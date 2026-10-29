-- Fase 5: importação das planilhas antigas (conferência e carga).

insert into public.avaliadores (nome, diretoria_id) values
  ('SIMONE PACHECO', (select id from public.diretorias where nome = 'DIRETORIA FINANCEIRA'));
insert into public.bairros (nome) values ('TIBERY');

-- A importação direta não fica exposta; a tela usa as funções que exigem administrador.
do $$ begin
  assert not has_table_privilege('anon', 'public.importacao_linhas', 'select'), 'área de carga fechada ao público';
  assert not has_function_privilege('authenticated', 'public.importacao_processar(text, boolean)', 'execute'), 'importação direta fechada';
  assert not has_function_privilege('authenticated', 'public.importacao_processar_linhas(bigint[], boolean)', 'execute'), 'blocos fechados';
  assert not has_function_privilege('anon', 'public.importacao_conferir(bigint[])', 'execute'), 'conferência fechada ao público';
  assert has_function_privilege('authenticated', 'public.importacao_conferir(bigint[])', 'execute'), 'tela confere';
end $$;

create procedure pg_temp.linha(n integer, extra jsonb) language sql as $$
  insert into public.importacao_linhas (lote, aba, linha, dados)
  values ('teste', 'set-2023.xlsx › SETEMBRO', n, jsonb_build_object(
    'n', n, 'situacao', 'RESPONDIDA', 'protocolo', (2023090000000 + n)::text, 'entrada', 'telefone',
    'tipo', 'Reclamacao', 'identificacao', 'IDENTIFICADA', 'cadastro', '2023-09-04', 'recebimento', '2023-09-04',
    'assunto', 'FALTA DE AGUA', 'descricao', 'Texto da manifestação.', 'diretoria', 'DIRETORIA FINANCEIRA',
    'avaliador', 'Simone Pacheco', 'encaminhado', '2023-09-04', 'resposta_data', '2023-09-08',
    'resposta', 'Resposta.', 'resolutiva', 'SIM') || extra);
$$;

-- 1: respondida no prazo; 2: arquivada; 3: reaberta e respondida de novo;
-- 4: em tratamento com bairro e avaliador novos; 5 a 8: erros; 9: sem resolutividade (aviso);
-- 10: prorrogada e respondida.
call pg_temp.linha(1, '{"bairro": "tibery", "cep": "38405142"}');
call pg_temp.linha(2, '{"resolutiva": null, "arquivamento": "Perda de objeto"}');
call pg_temp.linha(3, '{"reab_pedido": "2023-09-12", "reab_texto": "Não resolveu.", "reab_aceita": "SIM",
  "reab_data": "2023-09-12", "reab_resposta_data": "2023-09-15", "reab_resposta": "Resolvido.", "resolutiva": "NÃO"}');
call pg_temp.linha(4, '{"situacao": "EM TRATAMENTO", "resposta_data": null, "resposta": null, "resolutiva": null,
  "bairro": "Jardim Novo", "avaliador": "Fulano Antigo", "cep": "0"}');
call pg_temp.linha(5, '{"assunto": "ASSUNTO INEXISTENTE"}');
call pg_temp.linha(6, '{"cadastro": "31/02/2023"}');
call pg_temp.linha(7, '{"protocolo": "0", "falabr": "00000.0000.000000-00"}');
call pg_temp.linha(8, '{"situacao": "AGUARDANDO COMPLEMENTAÇÃO", "resposta_data": null}');
call pg_temp.linha(9, '{"resolutiva": null}');
call pg_temp.linha(10, '{"situacao": "RESPONDIDA", "prazo_prorrogacao": "2023-09-18", "resposta_data": "2023-09-15"}');

-- Conferência: não grava nada e aponta os erros de cada linha.
do $$
declare r record;
begin
  select * into r from public.importacao_processar('teste');
  assert r.linhas = 10 and r.sem_erro = 6 and r.com_erro = 4 and r.importadas = 0, format('conferência: %s', r);
  assert (select count(*) from public.manifestacoes) = 0, 'conferência não grava manifestações';
  assert (select count(*) from public.bairros where nome = 'JARDIM NOVO') = 0, 'conferência não grava bairro';
  assert (select erros[1] from public.importacao_linhas where linha = 5) like 'Assunto não encontrado%', 'assunto inexistente';
  assert (select erros[1] from public.importacao_linhas where linha = 6) = 'Data de cadastro inválida: "31/02/2023"', 'data inválida';
  assert (select erros[1] from public.importacao_linhas where linha = 7) = 'Sem protocolo MG-OUV nem Fala.BR', 'sem protocolo';
  assert (select erros[1] from public.importacao_linhas where linha = 8) like 'Aguardando complementação%', 'complementação à mão';
  assert (select erros from public.importacao_linhas where linha = 9) = '{}'
    and (select avisos[1] from public.importacao_linhas where linha = 9) like 'Sem a resolutividade%', 'sem resolutividade é aviso';
  assert (select avisos from public.importacao_linhas where linha = 4)
    = array['CEP ignorado por formato inválido: "0"', 'Bairro novo cadastrado: JARDIM NOVO', 'Avaliador cadastrado como inativo: FULANO ANTIGO'],
    'avisos da linha 4';
end $$;

-- Importação das linhas sem erro.
do $$
declare
  r record;
  m public.manifestacoes;
begin
  select * into r from public.importacao_processar('teste', true);
  assert r.importadas = 6 and r.com_erro = 4, format('importação: %s', r);

  select * into m from public.manifestacoes where protocolo_mgouv = '2023090000001';
  assert m.situacao = 'respondida' and m.resolutiva and not m.arquivada, 'linha 1 respondida';
  assert m.numero = '2023/0001' and m.dia_zero = '2023-09-04' and m.cep = '38405-142', 'linha 1 número, dia 0 e CEP';
  assert m.bairro_id = (select id from public.bairros where nome = 'TIBERY'), 'bairro existente';
  assert m.importada_de = 'set-2023.xlsx › SETEMBRO, nº 1 (linha 1)', 'origem';
  assert (select respondido_em from public.ciclos where manifestacao_id = m.id) = '2023-09-08', 'resposta';
  assert (select count(*) from public.encaminhamentos where manifestacao_id = m.id and atual) = 1, 'encaminhamento';

  select * into m from public.manifestacoes where protocolo_mgouv = '2023090000002';
  assert m.arquivada and m.resolutiva is null
    and m.motivo_arquivamento_id = (select id from public.motivos_arquivamento where nome = 'PERDA DE OBJETO'), 'linha 2 arquivada';

  select * into m from public.manifestacoes where protocolo_mgouv = '2023090000003';
  assert m.situacao = 'respondida' and m.resolutiva = false, 'linha 3 respondida após reabertura';
  assert (select count(*) from public.ciclos where manifestacao_id = m.id) = 2, 'linha 3 com dois ciclos';
  assert (select aceito from public.pedidos_reabertura where manifestacao_id = m.id), 'pedido aceito';
  assert (select respondido_em from public.ciclos where manifestacao_id = m.id and numero = 1) = '2023-09-15', 'resposta à reabertura';

  select * into m from public.manifestacoes where protocolo_mgouv = '2023090000004';
  assert m.situacao = 'em_tratamento' and m.cep is null, 'linha 4 em tratamento';
  assert (select nome from public.bairros where id = m.bairro_id) = 'JARDIM NOVO', 'bairro novo';
  assert not (select av.ativo from public.encaminhamentos e join public.avaliadores av on av.id = e.avaliador_id
              where e.manifestacao_id = m.id), 'avaliador antigo inativo';

  -- Respondida depois dos 5 dias úteis com prazo prorrogado na planilha: ciclo prorrogado.
  assert (select prorrogado from public.ciclos c join public.manifestacoes x on x.id = c.manifestacao_id
          where x.protocolo_mgouv = '2023090000010'), 'linha 10 prorrogada';
  assert not (select prorrogado from public.ciclos c join public.manifestacoes x on x.id = c.manifestacao_id
              where x.protocolo_mgouv = '2023090000001'), 'linha 1 sem prorrogação';

  -- Rodar de novo não duplica: as importadas ficam de fora e as com erro continuam com erro.
  select * into r from public.importacao_processar('teste', true);
  assert r.linhas = 4 and r.importadas = 0, format('segunda rodada: %s', r);
  assert (select count(*) from public.manifestacoes) = 6, 'sem duplicar';
end $$;

-- Protocolo já cadastrado no sistema vira erro.
call pg_temp.linha(11, '{"protocolo": "2023090000001"}');
do $$
declare r record;
begin
  select * into r from public.importacao_processar('teste');
  assert (select erros[1] from public.importacao_linhas where linha = 11) = 'Protocolo MG-OUV 2023090000001 já está no sistema',
    'protocolo repetido';
end $$;

-- A mesma manifestação em duas linhas do lote: só a primeira entra.
call pg_temp.linha(12, '{"protocolo": "2023090000012"}');
call pg_temp.linha(13, '{"protocolo": "2023090000012"}');
do $$
declare r record;
begin
  select * into r from public.importacao_processar('teste');
  assert (select erros from public.importacao_linhas where linha = 12) = '{}', 'primeira linha sem erro';
  assert (select erros[1] from public.importacao_linhas where linha = 13)
    = 'Protocolo repetido no lote: já aparece em set-2023.xlsx › SETEMBRO, linha 12', 'linha repetida';
end $$;

-- Formatos antigos: "SOLUCIONADO", sem a coluna Identificação, "ENCAMINHADO PARA SIMONE", bairro N/A,
-- resumo nas observações.
call pg_temp.linha(14, '{"situacao": "Solucionado", "identificacao": null, "_sem_coluna": ["identificacao", "resolutiva"],
  "resolutiva": null, "avaliador": "ENCAMINHADO PARA SIMONE", "bairro": "N/A", "resumo": "Pede reparo."}');
-- Valores fora do cadastro resolvidos por equivalência.
call pg_temp.linha(15, '{"entrada": "PMU", "assunto": "TAXA DE LIXO", "diretoria": "Financeira"}');
-- Protocolo do Fala.BR na coluna NUP, identificação em branco e diretoria sem a pessoa encaminhada.
call pg_temp.linha(16, '{"protocolo": "02646.2024.001156-60", "identificacao": null, "avaliador": null}');

insert into auth.users (id) values ('00000000-0000-0000-0000-000000000051'), ('00000000-0000-0000-0000-000000000052');
insert into public.usuarios (id, nome, perfil) values
  ('00000000-0000-0000-0000-000000000051', 'Admin', 'administrador'),
  ('00000000-0000-0000-0000-000000000052', 'Ana Ouvidoria', 'ouvidoria');
grant usage on schema public to anon, authenticated;
grant select on all tables in schema public to authenticated;

-- A equipe da Ouvidoria não usa a tela de importação.
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000052';
do $$
declare falhou boolean := false;
begin
  assert (select count(*) from public.importacao_linhas) = 0, 'ouvidoria não vê a área de carga';
  begin perform public.importacao_conferir(array[1::bigint]);
  exception when others then falhou := true; end;
  assert falhou, 'ouvidoria não confere';
end $$;

-- O administrador confere, define as equivalências e importa pela tela.
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000051';
do $$
declare
  r record;
  ids bigint[];
  m public.manifestacoes;
begin
  ids := array(select public.importacao_ordem_lote('teste'));
  assert (select count(*) from public.importacao_linhas where lote = 'teste') = 16, 'admin vê a área de carga';
  select * into r from public.importacao_conferir(ids);
  assert (select erros from public.importacao_linhas where linha = 14) = '{}', format('linha 14: %s', (select erros from public.importacao_linhas where linha = 14));
  assert (select erros from public.importacao_linhas where linha = 15)
    = array['Entrada não encontrada no cadastro: "PMU"', 'Assunto não encontrado no cadastro: "TAXA DE LIXO"', 'Diretoria não encontrada no cadastro: "Financeira"'],
    format('linha 15: %s', (select erros from public.importacao_linhas where linha = 15));

  perform public.importacao_equivaler('canais', 'PMU');  -- cadastra como item novo
  perform public.importacao_equivaler('assuntos', 'taxa de lixo', (select id from public.assuntos where nome = 'TAXA DE COLETA DE LIXO'));
  perform public.importacao_equivaler('diretorias', 'FINANCEIRA', (select id from public.diretorias where nome = 'DIRETORIA FINANCEIRA'));

  select * into r from public.importacao_importar(array(select public.importacao_ordem_lote('teste')));
  assert r.importadas = 4, format('importação pela tela (linhas 12, 14, 15 e 16): %s', r);

  select * into m from public.manifestacoes where protocolo_mgouv = '2023090000014';
  assert m.situacao = 'respondida' and m.resolutiva is null, 'solucionado vira respondida';
  assert (select nome from public.identificacoes where id = m.identificacao_id) = 'NÃO INFORMADA', 'identificação não informada';
  assert m.bairro_id is null and m.observacoes = 'Resumo da planilha antiga: Pede reparo.', 'bairro N/A e resumo';
  assert (select av.nome from public.encaminhamentos e join public.avaliadores av on av.id = e.avaliador_id
          where e.manifestacao_id = m.id) = 'SIMONE PACHECO', 'avaliador pelo primeiro nome';

  select * into m from public.manifestacoes where protocolo_mgouv = '2023090000015';
  assert (select nome from public.canais where id = m.canal_id) = 'PMU', 'canal novo';
  assert (select nome from public.assuntos where id = m.assunto_id) = 'TAXA DE COLETA DE LIXO', 'assunto por equivalência';

  select * into m from public.manifestacoes where protocolo_falabr = '02646.2024.001156-60';
  assert m.protocolo_mgouv is null, 'Fala.BR na coluna NUP';
  assert (select nome from public.identificacoes where id = m.identificacao_id) = 'NÃO INFORMADA', 'identificação em branco';
  assert (select av.nome || av.ativo::text from public.encaminhamentos e join public.avaliadores av on av.id = e.avaliador_id
          where e.manifestacao_id = m.id) = 'NÃO INFORMADOfalse', 'avaliador não informado';
end $$;
reset role;
