-- Encaminhamento a vários avaliadores (de diretorias diferentes) e texto do pedido de complementação.

insert into auth.users (id) values ('00000000-0000-0000-0000-000000000041');
insert into public.usuarios (id, nome, perfil) values ('00000000-0000-0000-0000-000000000041', 'Ana Ouvidoria', 'ouvidoria');
insert into public.avaliadores (nome, diretoria_id) values
  ('SIMONE PACHECO', (select id from public.diretorias where nome = 'DIRETORIA FINANCEIRA')),
  ('LUCAS ROCHA', (select id from public.diretorias where nome = 'DIRETORIA DO SISTEMA DE ABASTECIMENTO DE ÁGUA')),
  ('MARIA SOUZA', (select id from public.diretorias where nome = 'DIRETORIA DO SISTEMA DE ABASTECIMENTO DE ÁGUA'));
insert into public.avaliadores (nome, diretoria_id, ativo) values
  ('JOSÉ ANTIGO', (select id from public.diretorias where nome = 'DIRETORIA FINANCEIRA'), false);

grant usage on schema public to authenticated;
grant select, insert, update on all tables in schema public to authenticated;

create function pg_temp.av(nome text) returns smallint language sql as $$ select id from public.avaliadores where avaliadores.nome = av.nome $$;

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000041';

do $$
declare
  m bigint;
  falhou boolean;
  r jsonb;
  financeira smallint := (select id from public.diretorias where nome = 'DIRETORIA FINANCEIRA');
  agua smallint := (select id from public.diretorias where nome = 'DIRETORIA DO SISTEMA DE ABASTECIMENTO DE ÁGUA');
begin
  insert into public.manifestacoes (protocolo_mgouv, canal_id, tipo_id, identificacao_id, cadastrado_em, assunto_id, descricao)
  values ('2025091500301', (select id from public.canais where nome = 'TELEFONE'),
          (select id from public.tipos_manifestacao where nome = 'RECLAMAÇÃO'),
          (select id from public.identificacoes where nome = 'IDENTIFICADA'),
          '2025-09-15 10:00-03', (select id from public.assuntos where nome = 'FALTA DE ÁGUA'), 'Texto.')
  returning id into m;

  -- Vários avaliadores, de diretorias diferentes, no mesmo envio
  perform public.encaminhar(m, '2025-09-16', array[pg_temp.av('SIMONE PACHECO'), pg_temp.av('LUCAS ROCHA'), pg_temp.av('MARIA SOUZA'), pg_temp.av('LUCAS ROCHA')]);
  assert (select count(*) from public.encaminhamentos where manifestacao_id = m and atual) = 3, 'três avaliadores atuais, sem repetir';
  assert (select count(*) from public.painel_manifestacoes where id = m) = 1, 'uma linha por manifestação na lista';
  assert (select cardinality(diretorias) from public.painel_manifestacoes where id = m) = 2, 'duas diretorias';
  assert (select cardinality(avaliadores) from public.painel_manifestacoes where id = m) = 3, 'três avaliadores';
  assert (select diretoria_ids @> array[financeira, agua] from public.painel_manifestacoes where id = m), 'ids das diretorias';

  -- Indicadores: conta uma vez, mesmo filtrando as duas diretorias
  r := public.painel_gerencial('2025-09-01', '2025-09-30', 'month', null, null, null, null, null, null, array[financeira, agua]);
  assert (r->>'total')::int = 1, 'conta uma vez no filtro com as duas diretorias';
  r := public.painel_gerencial('2025-09-01', '2025-09-30', 'month', null, null, null, null, null, null, array[financeira]);
  assert (r->>'total')::int = 1, 'aparece no filtro de cada diretoria';

  -- Extrato: uma linha, diretorias e avaliadores juntos
  r := public.extrato_mensal(2025, 9);
  assert jsonb_array_length(r) = 1, 'extrato com uma linha';
  assert r->0->>'diretoria' = 'DIRETORIA DO SISTEMA DE ABASTECIMENTO DE ÁGUA, DIRETORIA FINANCEIRA', r->0->>'diretoria';
  assert r->0->>'avaliador' = 'LUCAS ROCHA, MARIA SOUZA, SIMONE PACHECO', r->0->>'avaliador';

  -- Reencaminhar substitui todo o envio anterior
  perform public.encaminhar(m, '2025-09-17', array[pg_temp.av('SIMONE PACHECO')]);
  assert (select count(*) from public.encaminhamentos where manifestacao_id = m and atual) = 1, 'reencaminhamento substitui';
  assert (select count(*) from public.encaminhamentos where manifestacao_id = m) = 4, 'histórico guardado';

  -- Lista vazia e avaliador desativado são recusados
  falhou := false;
  begin perform public.encaminhar(m, '2025-09-17', array[]::smallint[]);
  exception when raise_exception then falhou := true; end;
  assert falhou, 'sem avaliador é recusado';
  falhou := false;
  begin perform public.encaminhar(m, '2025-09-17', array[pg_temp.av('JOSÉ ANTIGO')]);
  exception when raise_exception then falhou := true; end;
  assert falhou, 'avaliador desativado é recusado';

  -- Pedido de complementação exige o texto enviado ao manifestante
  falhou := false;
  begin perform public.pedir_complementacao(m, 'ouvidoria', '2025-09-17', '  ');
  exception when raise_exception then falhou := true; end;
  assert falhou, 'pedido sem texto é recusado';
  perform public.pedir_complementacao(m, 'ouvidoria', '2025-09-17', ' Informe o número da casa. ');
  assert (select texto from public.complementacoes co join public.ciclos c on c.id = co.ciclo_id where c.manifestacao_id = m)
    = 'Informe o número da casa.', 'texto guardado';
end;
$$;
reset role;
