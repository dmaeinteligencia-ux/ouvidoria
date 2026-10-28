-- Fase 5: importação das planilhas antigas (conferência e carga).

insert into public.avaliadores (nome, diretoria_id) values
  ('SIMONE PACHECO', (select id from public.diretorias where nome = 'DIRETORIA FINANCEIRA'));
insert into public.bairros (nome) values ('TIBERY');

-- A área de carga e as funções não ficam expostas aos usuários.
do $$ begin
  assert not has_table_privilege('authenticated', 'public.importacao_linhas', 'select'), 'área de carga fechada';
  assert not has_function_privilege('authenticated', 'public.importacao_processar(text, boolean)', 'execute'), 'importação fechada';
  assert not has_function_privilege('anon', 'public.importacao_processar(text, boolean)', 'execute'), 'importação fechada';
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
-- 4: em tratamento com bairro e avaliador novos; 5 a 9: erros; 10: prorrogada e respondida.
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
  assert r.linhas = 10 and r.sem_erro = 5 and r.com_erro = 5 and r.importadas = 0, format('conferência: %s', r);
  assert (select count(*) from public.manifestacoes) = 0, 'conferência não grava manifestações';
  assert (select count(*) from public.bairros where nome = 'JARDIM NOVO') = 0, 'conferência não grava bairro';
  assert (select erros[1] from public.importacao_linhas where linha = 5) like 'Assunto não encontrado%', 'assunto inexistente';
  assert (select erros[1] from public.importacao_linhas where linha = 6) = 'Data de cadastro inválida: "31/02/2023"', 'data inválida';
  assert (select erros[1] from public.importacao_linhas where linha = 7) = 'Sem protocolo MG-OUV nem Fala.BR', 'sem protocolo';
  assert (select erros[1] from public.importacao_linhas where linha = 8) like 'Aguardando complementação%', 'complementação à mão';
  assert (select erros[1] from public.importacao_linhas where linha = 9) like 'Respondida sem a resolutividade%', 'sem resolutividade';
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
  assert r.importadas = 5 and r.com_erro = 5, format('importação: %s', r);

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
  assert r.linhas = 5 and r.importadas = 0, format('segunda rodada: %s', r);
  assert (select count(*) from public.manifestacoes) = 5, 'sem duplicar';
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
