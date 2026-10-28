-- Fase 3: prorrogação, complementação, reabertura e a rotina de Vencida / arquivamento automático.
-- O teste controla "hoje" pela configuração teste.hoje (só neste banco descartável).

create or replace function public.hoje()
returns date
language sql
stable
set search_path = ''
as $$
  select coalesce(nullif(current_setting('teste.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date);
$$;

insert into auth.users (id) values ('00000000-0000-0000-0000-000000000021');
insert into public.usuarios (id, nome, perfil) values ('00000000-0000-0000-0000-000000000021', 'Ana Ouvidoria', 'ouvidoria');

-- A rotina do sistema não fica exposta ao usuário logado.
do $$ begin
  assert not has_function_privilege('authenticated', 'public.atualizar_situacoes()', 'execute'), 'rotina fechada para usuários';
end $$;

grant usage on schema public to authenticated;
grant select, insert, update on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

create function pg_temp.nova(prot text, momento timestamptz) returns bigint
language sql as $$
  insert into public.manifestacoes (protocolo_mgouv, canal_id, tipo_id, identificacao_id, cadastrado_em, assunto_id, descricao)
  values (prot, (select id from public.canais where nome = 'TELEFONE'),
          (select id from public.tipos_manifestacao where nome = 'RECLAMAÇÃO'),
          (select id from public.identificacoes where nome = 'IDENTIFICADA'),
          momento, (select id from public.assuntos where nome = 'FALTA DE ÁGUA'), 'Texto.')
  returning id;
$$;

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000021';

do $$
declare
  m bigint;
  falhou boolean;
begin
  -- Cadastro em 15/09/2025 (segunda): dia 0 = 15/09, prazo = 22/09, prorrogação até 29/09.
  perform set_config('teste.hoje', '2025-09-22', false);
  m := pg_temp.nova('2025091500101', '2025-09-15 10:00-03');

  -- RN24: complementação não entra por inserção direta
  falhou := false;
  begin
    insert into public.complementacoes (ciclo_id, origem, pedido_em)
    select id, 'ouvidoria', '2025-09-16' from public.ciclos where manifestacao_id = m;
  exception when raise_exception then falhou := true;
  end;
  assert falhou, 'complementação direta é recusada';

  -- RN08: prorrogação no dia do vencimento, uma vez por ciclo
  perform public.registrar_prorrogacao(m, 'Avaliador aguarda equipe de campo.');
  assert (select situacao from public.manifestacoes where id = m) = 'prorrogada', 'situação Prorrogada';
  assert (select prazo from public.ciclos_prazos where manifestacao_id = m) = '2025-09-29', 'prazo de 10 d.u.';
  falhou := false;
  begin
    perform public.registrar_prorrogacao(m, 'De novo.');
  exception when raise_exception then falhou := true;
  end;
  assert falhou, 'segunda prorrogação é recusada';

  -- RN13: rotina marca Vencida depois do prazo prorrogado
  perform set_config('teste.hoje', '2025-09-29', false);
  reset role;
  perform public.atualizar_situacoes();
  set role authenticated;
  assert (select situacao from public.manifestacoes where id = m) = 'prorrogada', 'no último dia ainda não venceu';
  perform set_config('teste.hoje', '2025-09-30', false);
  reset role;
  assert (select vencidas from public.atualizar_situacoes()) = 1, 'uma manifestação vencida';
  set role authenticated;
  assert (select situacao from public.manifestacoes where id = m) = 'vencida', 'situação Vencida';

  -- Vencida ainda pode ser respondida (fora do prazo, RN19)
  perform public.registrar_resposta(m, '2025-09-30', 'Resposta atrasada.', true);
  assert not (select no_prazo from public.ciclos_prazos where manifestacao_id = m), 'fora do prazo';
end;
$$;

do $$
declare
  m bigint;
  falhou boolean;
begin
  -- RN08: prorrogação depois do vencimento é recusada
  perform set_config('teste.hoje', '2025-09-23', false);
  m := pg_temp.nova('2025091500102', '2025-09-15 10:00-03');
  falhou := false;
  begin
    perform public.registrar_prorrogacao(m, 'Tarde demais.');
  exception when raise_exception then falhou := true;
  end;
  assert falhou, 'prorrogação depois do vencimento é recusada';

  -- RN10: complementação suspende e recomeça a contagem com novo dia 0
  perform public.pedir_complementacao(m, 'diretoria', '2025-09-17', 'Informe o número do hidrômetro.');
  assert (select situacao from public.manifestacoes where id = m) = 'aguardando_complementacao', 'aguardando complementação';
  assert (select dias_restantes from public.painel_manifestacoes where id = m) is null, 'prazo suspenso';
  falhou := false;
  begin
    perform public.registrar_resposta(m, '2025-09-23', 'x', true);
  exception when raise_exception then falhou := true;
  end;
  assert falhou, 'não responde enquanto aguarda complementação';

  perform public.registrar_complementacao(m, '2025-09-23 17:30-03');
  assert (select situacao from public.manifestacoes where id = m) = 'em_tratamento', 'volta para Em tratamento';
  assert (select dia_zero from public.ciclos where manifestacao_id = m) = '2025-09-24', 'novo dia 0 com corte das 17h';
  assert (select prazo from public.ciclos_prazos where manifestacao_id = m) = '2025-10-01', 'novo prazo';
  assert (select dia_zero from public.manifestacoes where id = m) = '2025-09-15', 'recebimento original preservado';

  -- RN11: complementação depois de 10 dias corridos é recusada
  m := pg_temp.nova('2025091500103', '2025-09-15 10:00-03');
  perform public.pedir_complementacao(m, 'ouvidoria', '2025-09-15', 'Envie uma foto do local.');
  perform set_config('teste.hoje', '2025-09-26', false);
  falhou := false;
  begin
    perform public.registrar_complementacao(m, '2025-09-26 09:00-03');
  exception when raise_exception then falhou := true;
  end;
  assert falhou, 'complementação após o limite é recusada';
end;
$$;

-- RN11: rotina arquiva por insuficiência de dados
-- A rotina roda sem usuário logado (agendada no banco).
reset role;
set request.jwt.claim.sub = '';
set teste.hoje = '2025-09-26';
do $$ begin
  assert (select arquivadas from public.atualizar_situacoes()) = 1, 'uma arquivada por falta de complementação';
  assert (select arquivada and situacao = 'respondida' and resolutiva is null
          from public.manifestacoes where protocolo_mgouv = '2025091500103'), 'Respondida e Arquivada';
  assert (select mo.nome from public.manifestacoes m join public.motivos_arquivamento mo on mo.id = m.motivo_arquivamento_id
          where m.protocolo_mgouv = '2025091500103') = 'INSUFICIÊNCIA DE DADOS', 'motivo insuficiência de dados';
  assert (select respondido_em from public.ciclos c join public.manifestacoes m on m.id = c.manifestacao_id
          where m.protocolo_mgouv = '2025091500103') = '2025-09-26', 'resposta no dia seguinte ao limite';
  assert (select count(*) from public.historico h where h.tabela = 'manifestacoes' and h.usuario_id is null) >= 1,
    'rotina registra no histórico sem usuário';
end $$;

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000021';

do $$
declare
  m bigint;
  pedido bigint;
  falhou boolean;
begin
  -- Reabertura: primeira resposta em 19/09/2025
  perform set_config('teste.hoje', '2025-09-19', false);
  m := pg_temp.nova('2025091500104', '2025-09-15 10:00-03');
  perform public.registrar_resposta(m, '2025-09-19', 'Primeira resposta.', false);

  -- RN20: pedido depois de 30 dias corridos é recusado (limite 19/10/2025)
  perform set_config('teste.hoje', '2025-10-20', false);
  falhou := false;
  begin
    perform public.registrar_pedido_reabertura(m, '2025-10-20 10:00-03', 'Não resolveram.');
  exception when raise_exception then falhou := true;
  end;
  assert falhou, 'pedido após 30 dias é recusado';

  -- RN21: pedido aceito abre o ciclo 1 com dia 0 no recebimento (sexta 17h30 → segunda)
  pedido := public.registrar_pedido_reabertura(m, '2025-10-10 17:30-03', 'Não resolveram.');
  falhou := false;
  begin
    perform public.registrar_pedido_reabertura(m, '2025-10-10 18:00-03', 'Outro.');
  exception when raise_exception then falhou := true;
  end;
  assert falhou, 'um pedido pendente por vez';
  perform public.decidir_reabertura(pedido, true, 'Resposta não tratou o vazamento.');
  assert (select situacao from public.manifestacoes where id = m) = 'reaberta', 'situação Reaberta';
  assert (select count(*) from public.ciclos where manifestacao_id = m) = 2, 'ciclo 1 criado';
  assert (select dia_zero from public.ciclos where manifestacao_id = m and numero = 1) = '2025-10-13', 'dia 0 do ciclo 1';
  assert (select resposta from public.ciclos where manifestacao_id = m and numero = 0) = 'Primeira resposta.', 'resposta anterior preservada (RN22)';

  -- Resposta do ciclo 1 e prorrogação no ciclo reaberto
  perform set_config('teste.hoje', '2025-10-13', false);
  perform public.registrar_prorrogacao(m, 'Precisa de obra.');
  assert (select prazo from public.ciclos_prazos where manifestacao_id = m and numero = 1) = '2025-10-27', 'prazo 10 d.u. do ciclo 1';
  perform set_config('teste.hoje', '2025-10-15', false);
  perform public.registrar_resposta(m, '2025-10-14', 'Segunda resposta.', true);
  assert (select situacao from public.manifestacoes where id = m) = 'respondida', 'respondida no ciclo 1';

  -- Segunda reabertura ainda dentro dos 30 dias da primeira resposta; negada continua Respondida
  pedido := public.registrar_pedido_reabertura(m, '2025-10-15 11:00-03', 'De novo.');
  perform public.decidir_reabertura(pedido, false, 'Já atendida.');
  assert (select situacao from public.manifestacoes where id = m) = 'respondida', 'negada continua Respondida';
  assert (select count(*) from public.ciclos where manifestacao_id = m) = 2, 'negada não cria ciclo';

  -- Histórico com reabertura
  assert (select count(*) from public.historico_manifestacao(m) where tabela = 'pedidos_reabertura') >= 4,
    'pedidos e decisões no histórico';
end;
$$;
reset role;
