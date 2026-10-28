-- Ações da Fase 2: correção do cadastro, resposta, arquivamento, duplicidade e histórico.

insert into auth.users (id) values ('00000000-0000-0000-0000-000000000011');
insert into public.usuarios (id, nome, perfil) values
  ('00000000-0000-0000-0000-000000000011', 'Ana Ouvidoria', 'ouvidoria');
insert into public.avaliadores (nome, diretoria_id)
values ('LUCAS ROCHA', (select id from public.diretorias where nome = 'DIRETORIA FINANCEIRA'));

grant usage on schema public to authenticated;
grant select, insert, update on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

do $$
declare
  m bigint;
  dup bigint;
  falhou boolean;
  motivo_dup smallint := (select id from public.motivos_arquivamento where nome = 'REGISTRO EM DUPLICIDADE');
begin
  insert into public.manifestacoes
    (protocolo_mgouv, canal_id, tipo_id, identificacao_id, cadastrado_em, assunto_id, logradouro, numero_imovel, descricao)
  values ('2025091500001', (select id from public.canais where nome = 'TELEFONE'),
          (select id from public.tipos_manifestacao where nome = 'RECLAMAÇÃO'),
          (select id from public.identificacoes where nome = 'IDENTIFICADA'),
          '2025-09-15 10:00-03', (select id from public.assuntos where nome = 'FALTA DE ÁGUA'),
          'Rua Mário Porto', '512', 'Sem água desde ontem.')
  returning id into m;
  assert (select dia_zero from public.manifestacoes where id = m) = '2025-09-15', 'dia 0 no próprio dia';

  -- RN04: nova data de cadastro recalcula o dia 0 e o ciclo original
  update public.manifestacoes set cadastrado_em = '2025-09-15 17:30-03' where id = m;
  assert (select dia_zero from public.manifestacoes where id = m) = '2025-09-16', 'dia 0 recalculado';
  assert (select dia_zero from public.ciclos where manifestacao_id = m) = '2025-09-16', 'ciclo acompanha o dia 0';

  -- RN04: correção manual com justificativa
  update public.manifestacoes
  set dia_zero = '2025-09-17', dia_zero_corrigido_justificativa = 'Recebida no MG-OUV só no dia 17'
  where id = m;
  assert (select prazo from public.ciclos_prazos where manifestacao_id = m) = '2025-09-24', 'prazo do dia 0 corrigido';

  -- RN24: situação não muda por edição direta
  falhou := false;
  begin
    update public.manifestacoes set situacao = 'respondida' where id = m;
  exception when raise_exception then falhou := true;
  end;
  assert falhou, 'situação não muda por edição direta';

  falhou := false;
  begin
    update public.ciclos set respondido_em = '2025-09-18', resposta = 'x' where manifestacao_id = m;
  exception when raise_exception then falhou := true;
  end;
  assert falhou, 'resposta não muda por edição direta';

  -- RN14: envio no futuro é recusado
  falhou := false;
  begin
    insert into public.encaminhamentos (manifestacao_id, diretoria_id, avaliador_id, enviado_em)
    select m, a.diretoria_id, a.id, public.hoje() + 1 from public.avaliadores a where a.nome = 'LUCAS ROCHA';
  exception when raise_exception then falhou := true;
  end;
  assert falhou, 'envio no futuro é recusado';

  insert into public.encaminhamentos (manifestacao_id, diretoria_id, avaliador_id, enviado_em)
  select m, a.diretoria_id, a.id, '2025-09-17' from public.avaliadores a where a.nome = 'LUCAS ROCHA';

  -- RN17: resolutividade obrigatória quando não arquivada
  falhou := false;
  begin
    perform public.registrar_resposta(m, '2025-09-19', 'Equipe religou o abastecimento.');
  exception when raise_exception then falhou := true;
  end;
  assert falhou, 'resposta sem resolutividade é recusada';

  -- Data da resposta antes do recebimento é recusada
  falhou := false;
  begin
    perform public.registrar_resposta(m, '2025-09-16', 'Texto', true);
  exception when raise_exception then falhou := true;
  end;
  assert falhou, 'resposta antes do dia 0 é recusada';

  perform public.registrar_resposta(m, '2025-09-26', 'Equipe religou o abastecimento.', true);
  assert (select situacao from public.manifestacoes where id = m) = 'respondida', 'situação Respondida';
  assert (select resolutiva from public.manifestacoes where id = m), 'resolutiva gravada';
  assert not (select no_prazo from public.ciclos_prazos where manifestacao_id = m), 'respondida fora do prazo (RN19)';

  -- Respondida não é encaminhada de novo
  falhou := false;
  begin
    insert into public.encaminhamentos (manifestacao_id, diretoria_id, avaliador_id, enviado_em)
    select m, a.diretoria_id, a.id, '2025-09-29' from public.avaliadores a where a.nome = 'LUCAS ROCHA';
  exception when raise_exception then falhou := true;
  end;
  assert falhou, 'respondida não é encaminhada';

  -- RN06: duplicidade por protocolo e por endereço e assunto
  assert (select count(*) from public.possiveis_duplicidades('2025091500001', null, null, null, null, now())) = 1,
    'duplicidade por protocolo';
  assert (select count(*) from public.possiveis_duplicidades(
            null, null, 'rua mario porto', '512',
            (select id from public.assuntos where nome = 'FALTA DE ÁGUA'), '2025-09-20 10:00-03')) = 1,
    'duplicidade por endereço e assunto';
  assert (select count(*) from public.possiveis_duplicidades(
            null, null, 'rua mario porto', '512',
            (select id from public.assuntos where nome = 'FALTA DE ÁGUA'), '2025-12-20 10:00-03')) = 0,
    'fora dos 30 dias não é duplicidade';

  -- RN18: duplicada registrada direto como arquivada, ligada à original
  insert into public.manifestacoes
    (protocolo_mgouv, canal_id, tipo_id, identificacao_id, cadastrado_em, assunto_id, logradouro, descricao)
  values ('2025091500002', (select id from public.canais where nome = 'TELEFONE'),
          (select id from public.tipos_manifestacao where nome = 'RECLAMAÇÃO'),
          (select id from public.identificacoes where nome = 'ANÔNIMA'),
          '2025-09-16 10:00-03', (select id from public.assuntos where nome = 'FALTA DE ÁGUA'),
          'Rua Mário Porto', 'Mesma falta de água.')
  returning id into dup;

  falhou := false;
  begin
    perform public.registrar_resposta(dup, '2025-09-16', 'Registro em duplicidade.', null, true, null);
  exception when raise_exception then falhou := true;
  end;
  assert falhou, 'arquivamento sem motivo é recusado';

  perform public.registrar_resposta(dup, '2025-09-16', 'Registro em duplicidade.', null, true, motivo_dup, m);
  assert (select arquivada and situacao = 'respondida' and duplicada_de = m and resolutiva is null
          from public.manifestacoes where id = dup), 'duplicada arquivada e ligada à original';

  -- RN18: arquivar depois de respondida
  falhou := false;
  begin
    perform public.arquivar_manifestacao(dup, motivo_dup);
  exception when raise_exception then falhou := true;
  end;
  assert falhou, 'não arquiva duas vezes';
  perform public.arquivar_manifestacao(m, (select id from public.motivos_arquivamento where nome = 'PERDA DE OBJETO'));
  assert (select arquivada and resolutiva is null from public.manifestacoes where id = m), 'arquivada depois da resposta';

  -- RN23: histórico com o nome de quem fez
  assert (select count(*) from public.historico_manifestacao(m) where usuario = 'Ana Ouvidoria') >= 5,
    'histórico legível da manifestação';
  assert (select count(*) from public.historico_manifestacao(m) where tabela = 'encaminhamentos') = 1,
    'encaminhamento no histórico';
end;
$$;

-- Diretor não vê histórico nem executa ações.
reset role;
insert into auth.users (id) values ('00000000-0000-0000-0000-000000000012');
insert into public.usuarios (id, nome, perfil, diretoria_id) values
  ('00000000-0000-0000-0000-000000000012', 'Diretor', 'diretor', (select id from public.diretorias where nome = 'DIRETORIA FINANCEIRA'));
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000012';
do $$
declare
  falhou boolean := false;
begin
  assert (select count(*) from public.historico_manifestacao(
    (select min(id) from public.historico where tabela = 'manifestacoes'))) = 0, 'diretor não lê o histórico';
  begin
    perform public.registrar_resposta(1, '2025-09-16', 'x', true);
  exception when raise_exception then falhou := true;
  end;
  assert falhou, 'diretor não responde';
end;
$$;
reset role;
