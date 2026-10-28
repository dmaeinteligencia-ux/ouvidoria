-- Fase 4: indicadores dos painéis, acesso por perfil e extrato mensal.

insert into auth.users (id) values
  ('00000000-0000-0000-0000-000000000031'),
  ('00000000-0000-0000-0000-000000000032');
insert into public.usuarios (id, nome, perfil, diretoria_id) values
  ('00000000-0000-0000-0000-000000000031', 'Ana Ouvidoria', 'ouvidoria', null),
  ('00000000-0000-0000-0000-000000000032', 'Diretor Financeiro', 'diretor',
   (select id from public.diretorias where nome = 'DIRETORIA FINANCEIRA'));
insert into public.avaliadores (nome, diretoria_id) values
  ('SIMONE PACHECO', (select id from public.diretorias where nome = 'DIRETORIA FINANCEIRA')),
  ('LUCAS ROCHA', (select id from public.diretorias where nome = 'DIRETORIA DO SISTEMA DE ABASTECIMENTO DE ÁGUA'));
insert into public.bairros (nome) values ('TIBERY'), ('BRASIL');

grant usage on schema public to anon, authenticated;
grant select, insert, update on all tables in schema public to authenticated;

-- A função interna não fica exposta; as dos painéis e do extrato, sim, cada uma ao seu público.
do $$ begin
  assert not has_function_privilege('anon', 'public.indicadores_calcular(date, date, text, public.situacao_manifestacao[], smallint[], smallint[], smallint[], smallint[], integer[], smallint[], boolean)', 'execute'), 'cálculo interno fechado';
  assert not has_function_privilege('authenticated', 'public.indicadores_calcular(date, date, text, public.situacao_manifestacao[], smallint[], smallint[], smallint[], smallint[], integer[], smallint[], boolean)', 'execute'), 'cálculo interno fechado';
  assert has_function_privilege('anon', 'public.painel_geral(date, date, text, public.situacao_manifestacao[], smallint[], smallint[], smallint[])', 'execute'), 'painel geral público';
  assert not has_function_privilege('anon', 'public.painel_gerencial(date, date, text, public.situacao_manifestacao[], smallint[], smallint[], smallint[], smallint[], integer[], smallint[])', 'execute'), 'gerencial exige login';
  assert not has_function_privilege('anon', 'public.extrato_mensal(integer, integer)', 'execute'), 'extrato exige login';
end $$;

-- Funções auxiliares e ações usadas só no preparo dos dados.
grant execute on function public.registrar_resposta(bigint, date, text, boolean, boolean, smallint, bigint) to authenticated;

create function pg_temp.nova(prot text, momento timestamptz, tipo text, canal text, bairro text) returns bigint
language sql as $$
  insert into public.manifestacoes (protocolo_mgouv, canal_id, tipo_id, identificacao_id, cadastrado_em, assunto_id, bairro_id, descricao)
  values (prot, (select id from public.canais where nome = canal),
          (select id from public.tipos_manifestacao where nome = tipo),
          (select id from public.identificacoes where nome = 'IDENTIFICADA'),
          momento, (select id from public.assuntos where nome = 'FALTA DE ÁGUA'),
          (select id from public.bairros where nome = bairro), 'Texto.')
  returning id;
$$;
create function pg_temp.enc(m bigint, avaliador text) returns void language sql as $$
  insert into public.encaminhamentos (manifestacao_id, diretoria_id, avaliador_id, enviado_em)
  select m, a.diretoria_id, a.id, (select dia_zero from public.manifestacoes where id = m) from public.avaliadores a where a.nome = avaliador;
$$;

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000031';

do $$
declare
  m bigint;
begin
  -- Setembro/2025: 3 manifestações. Outubro/2025: 1.
  m := pg_temp.nova('2025091500201', '2025-09-15 10:00-03', 'RECLAMAÇÃO', 'TELEFONE', 'TIBERY');
  perform pg_temp.enc(m, 'SIMONE PACHECO');
  perform public.registrar_resposta(m, '2025-09-18', 'Resolvido.', true);          -- 3 d.u., no prazo

  m := pg_temp.nova('2025091600202', '2025-09-16 10:00-03', 'RECLAMAÇÃO', 'MG-OUV', 'TIBERY');
  perform pg_temp.enc(m, 'LUCAS ROCHA');
  perform public.registrar_resposta(m, '2025-09-25', 'Atrasado.', false);         -- 7 d.u., fora do prazo

  m := pg_temp.nova('2025091700203', '2025-09-17 10:00-03', 'SOLICITAÇÃO', 'TELEFONE', null);
  perform public.registrar_resposta(m, '2025-09-17', 'Duplicada.', null, true,
    (select id from public.motivos_arquivamento where nome = 'REGISTRO EM DUPLICIDADE'));

  m := pg_temp.nova('2025100100204', '2025-10-01 10:00-03', 'ELOGIO', 'E-MAIL', 'BRASIL');
  perform pg_temp.enc(m, 'SIMONE PACHECO');
end $$;

-- Satisfação (campos opcionais) direto na tabela, como dado de exemplo.
reset role;
update public.manifestacoes set satisfacao_resposta = 'muito_satisfeito', satisfacao_ouvidoria = 'satisfeito'
where protocolo_mgouv = '2025091500201';
update public.manifestacoes set satisfacao_resposta = 'insatisfeito' where protocolo_mgouv = '2025091600202';

-- Painel Geral sem login
set role anon;
set request.jwt.claim.sub = '';
do $$
declare
  r jsonb := public.painel_geral('2025-09-01', '2025-10-31');
begin
  assert (r->>'total')::int = 4, 'total no período';
  assert jsonb_array_length(r->'evolucao') = 2, 'dois meses';
  assert (r->'evolucao'->0->>'n')::int = 3 and (r->'evolucao'->1->>'n')::int = 1, 'evolução mensal pelo dia 0';
  assert (r->>'prazo_medio')::numeric = 5.0, 'prazo médio só da primeira resposta, sem arquivadas';
  assert (r->'cumprimento'->>'no_prazo')::int = 1 and (r->'cumprimento'->>'fora_prazo')::int = 1, 'cumprimento';
  assert (r->'resolutividade'->>'resolutivas')::int = 1 and (r->'resolutividade'->>'respondidas')::int = 2, 'resolutividade sem arquivadas';
  assert (r->'arquivamento'->0->>'nome') = 'REGISTRO EM DUPLICIDADE', 'tipo de arquivamento';
  assert (select sum((s->>'n')::int) from jsonb_array_elements(r->'situacao') s) = 4, 'pizza de situação soma o total';
  assert jsonb_array_length(r->'satisfacao_resposta') = 2, 'satisfação com a resposta';
  assert not r ? 'assuntos' and not r ? 'bairros', 'público não vê assuntos nem bairros';
  assert (public.painel_geral('2025-09-01', '2025-10-31', 'month', array['em_tratamento']::public.situacao_manifestacao[])->>'total')::int = 1, 'filtro de situação';
  assert (public.painel_opcoes()->'canais') is not null, 'opções dos filtros';
end $$;

do $$
declare falhou boolean := false;
begin
  begin
    perform public.painel_gerencial('2025-09-01', '2025-10-31');
  exception when insufficient_privilege then falhou := true;
  end;
  assert falhou, 'anônimo não abre o Painel Gerencial';
end $$;

-- Diretor: só a própria diretoria, mesmo pedindo outra
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000032';
do $$
declare
  r jsonb := public.painel_gerencial('2025-09-01', '2025-10-31', 'month', null, null, null, null, null, null,
    array[(select id from public.diretorias where nome = 'DIRETORIA DO SISTEMA DE ABASTECIMENTO DE ÁGUA')]);
  falhou boolean := false;
begin
  assert (r->>'total')::int = 2, 'diretor vê só a Diretoria Financeira';
  assert (r->'bairros'->0->>'nome') in ('TIBERY', 'BRASIL'), 'bairros no gerencial';
  begin
    perform public.extrato_mensal(2025, 9);
  exception when raise_exception then falhou := true;
  end;
  assert falhou, 'diretor não gera o extrato';
end $$;

-- Ouvidoria: todas as diretorias, filtro por diretoria e extrato
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000031';
do $$
declare
  r jsonb := public.painel_gerencial('2025-09-01', '2025-10-31');
  e jsonb := public.extrato_mensal(2025, 9);
begin
  assert (r->>'total')::int = 4, 'ouvidoria vê tudo';
  assert (r->'assuntos'->0->>'n')::int = 4, 'principais assuntos';
  assert (r->>'sem_bairro')::int = 1, 'sem bairro contada à parte';
  assert (public.painel_gerencial('2025-09-01', '2025-10-31', 'year')->'evolucao'->0->>'n')::int = 4, 'agrupamento por ano';
  assert jsonb_array_length(e) = 3, 'extrato com as recebidas no mês';
  assert e->0->>'protocolo_mgouv' = '2025091500201' and (e->0->>'tempo')::int = 3, 'primeira linha com o tempo';
  assert e->0->>'prazo' = '2025-09-22', 'prazo de 5 dias úteis';
  assert e->0->>'avaliador' = 'SIMONE PACHECO', 'encaminhamento';
end $$;
reset role;
