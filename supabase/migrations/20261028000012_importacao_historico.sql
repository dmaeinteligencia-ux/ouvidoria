-- Fase 5: importação das planilhas mensais desde setembro de 2023.
-- O script scripts/importar_planilha.py lê cada aba (layout das 35 colunas) e grava uma linha por
-- manifestação em importacao_linhas. importacao_processar confere o lote (simulação, que desfaz tudo)
-- ou importa de fato; cada linha guarda os erros encontrados ou a manifestação criada.
-- Nada disso fica exposto aos usuários: a carga é feita pela equipe técnica direto no banco.

alter table public.manifestacoes add column importada_de text;
comment on column public.manifestacoes.importada_de is 'Origem na planilha antiga (aba e nº), quando veio da importação.';

create table public.importacao_linhas (
  id bigint generated always as identity primary key,
  lote text not null,
  aba text not null,
  linha integer not null,
  dados jsonb not null,
  erros text[] not null default '{}',
  avisos text[] not null default '{}',
  manifestacao_id bigint references public.manifestacoes (id),
  conferida_em timestamptz,
  importada_em timestamptz,
  unique (lote, aba, linha)
);

alter table public.importacao_linhas enable row level security;
revoke all on public.importacao_linhas from anon, authenticated;

-- Busca num cadastro pelo nome, sem diferença de acento, caixa ou pontuação.
create function public.importacao_buscar(p_tabela text, p_nome text)
returns integer
language plpgsql
stable
set search_path = ''
as $$
declare
  achado integer;
begin
  if public.normalizar_texto(p_nome) is null then
    return null;
  end if;
  execute format('select id from public.%I where public.normalizar_texto(nome) = public.normalizar_texto($1) order by ativo desc, id limit 1', p_tabela)
  into achado using p_nome;
  return achado;
end;
$$;

-- Data (ou data e hora) da planilha; nula se vazia. Data inválida vira erro com o nome da coluna.
create function public.importacao_data(d jsonb, campo text, rotulo text, inout erros text[], out valor timestamp)
language plpgsql
stable
set search_path = ''
as $$
begin
  valor := null;
  if nullif(trim(d->>campo), '') is null then
    return;
  end if;
  begin
    valor := (d->>campo)::timestamp;
  exception when others then
    erros := erros || format('%s inválida: "%s"', rotulo, d->>campo);
  end;
end;
$$;

-- Importa uma linha. Erro de regra ou de restrição do banco interrompe só esta linha.
create function public.importacao_linha(l public.importacao_linhas)
returns table (r_erros text[], r_avisos text[], r_manifestacao bigint)
language plpgsql
set search_path = ''
as $$
declare
  d jsonb := l.dados;
  e text[] := '{}';
  a text[] := '{}';
  v_canal integer; v_tipo integer; v_identificacao integer; v_assunto integer; v_bairro integer;
  v_diretoria integer; v_avaliador integer; v_motivo integer;
  v_cadastro timestamp; v_recebimento timestamp; v_encaminhado timestamp; v_respondido timestamp;
  v_reab_pedido timestamp; v_reab_data timestamp; v_reab_respondido timestamp;
  v_situacao public.situacao_manifestacao;
  v_resolutiva boolean;
  v_reab_aceita boolean;
  v_prorrogado boolean;
  v_mgouv text; v_falabr text; v_cep text;
  v_m bigint; v_c0 bigint; v_c1 bigint; v_dz date; v_dz_calc date;
  t text;
begin
  -- Cadastros
  v_situacao := case public.normalizar_texto(d->>'situacao')
    when 'respondida' then 'respondida'
    when 'emtratamento' then 'em_tratamento'
    when 'prorrogada' then 'prorrogada'
    when 'vencida' then 'vencida'
    when 'reaberta' then 'reaberta'
    when 'aguardandocomplementacao' then 'aguardando_complementacao'
  end;
  if v_situacao is null then
    e := e || format('Situação não reconhecida: "%s"', coalesce(d->>'situacao', ''));
  elsif v_situacao = 'aguardando_complementacao' then
    e := e || 'Aguardando complementação: registre esta manifestação à mão, com a data do pedido de complementação'::text;
  end if;

  v_canal := public.importacao_buscar('canais', d->>'entrada');
  if v_canal is null then e := e || format('Entrada não encontrada no cadastro: "%s"', coalesce(d->>'entrada', '')); end if;
  v_tipo := public.importacao_buscar('tipos_manifestacao', d->>'tipo');
  if v_tipo is null then e := e || format('Tipo não encontrado no cadastro: "%s"', coalesce(d->>'tipo', '')); end if;
  v_identificacao := public.importacao_buscar('identificacoes', d->>'identificacao');
  if v_identificacao is null then e := e || format('Identificação não encontrada no cadastro: "%s"', coalesce(d->>'identificacao', '')); end if;
  v_assunto := public.importacao_buscar('assuntos', d->>'assunto');
  if v_assunto is null then e := e || format('Assunto não encontrado no cadastro: "%s"', coalesce(d->>'assunto', '')); end if;

  if public.normalizar_texto(d->>'arquivamento') is not null then
    v_motivo := public.importacao_buscar('motivos_arquivamento', d->>'arquivamento');
    if v_motivo is null then e := e || format('Motivo de arquivamento não encontrado: "%s"', d->>'arquivamento'); end if;
  end if;

  if public.normalizar_texto(d->>'diretoria') is not null then
    v_diretoria := public.importacao_buscar('diretorias', d->>'diretoria');
    if v_diretoria is null then
      e := e || format('Diretoria não encontrada no cadastro: "%s"', d->>'diretoria');
    elsif public.normalizar_texto(d->>'avaliador') is null then
      e := e || 'Diretoria sem a pessoa encaminhada'::text;
    else
      select av.id into v_avaliador from public.avaliadores av
      where av.diretoria_id = v_diretoria and public.normalizar_texto(av.nome) = public.normalizar_texto(d->>'avaliador')
      order by av.ativo desc limit 1;
    end if;
  end if;

  -- Protocolos (o Excel tira os zeros à esquerda do MG-OUV) e CEP
  v_mgouv := nullif(regexp_replace(coalesce(d->>'protocolo', ''), '\D', '', 'g'), '');
  if v_mgouv ~ '^0+$' then v_mgouv := null; end if;
  if v_mgouv is not null and length(v_mgouv) < 13 then v_mgouv := lpad(v_mgouv, 13, '0'); end if;
  v_falabr := nullif(trim(coalesce(d->>'falabr', '')), '');
  if v_falabr ~ '^[0.\-]+$' then v_falabr := null; end if;
  if v_mgouv is null and v_falabr is null then e := e || 'Sem protocolo MG-OUV nem Fala.BR'::text; end if;
  if v_mgouv is not null and v_mgouv !~ '^\d{13}$' then e := e || format('Protocolo MG-OUV com formato inválido: "%s"', d->>'protocolo'); end if;
  if v_falabr is not null and v_falabr !~ '^\d{5}\.\d{4}\.\d{6}-\d{2}$' then e := e || format('Protocolo Fala.BR com formato inválido: "%s"', v_falabr); end if;
  if v_mgouv is not null and exists (select 1 from public.manifestacoes x where x.protocolo_mgouv = v_mgouv) then
    e := e || format('Protocolo MG-OUV %s já está no sistema', v_mgouv);
  end if;
  if v_falabr is not null and exists (select 1 from public.manifestacoes x where x.protocolo_falabr = v_falabr) then
    e := e || format('Protocolo Fala.BR %s já está no sistema', v_falabr);
  end if;

  -- Mesma manifestação lançada duas vezes nas planilhas: só a primeira linha entra.
  select format('Protocolo repetido no lote: já aparece em %s, linha %s', o.aba, o.linha) into t
  from public.importacao_linhas o
  where o.lote = l.lote and o.id < l.id
    and ((v_mgouv is not null and lpad(regexp_replace(coalesce(o.dados->>'protocolo', ''), '\D', '', 'g'), 13, '0') = v_mgouv)
      or (v_falabr is not null and trim(o.dados->>'falabr') = v_falabr))
  order by o.id limit 1;
  if t is not null then e := e || t; end if;

  v_cep := nullif(regexp_replace(coalesce(d->>'cep', ''), '\D', '', 'g'), '');
  if v_cep is not null then
    if length(v_cep) = 8 and v_cep !~ '^0+$' then
      v_cep := substr(v_cep, 1, 5) || '-' || substr(v_cep, 6);
    else
      a := a || format('CEP ignorado por formato inválido: "%s"', d->>'cep');
      v_cep := null;
    end if;
  end if;

  if nullif(trim(d->>'descricao'), '') is null then e := e || 'Sem descrição'::text; end if;

  -- Datas
  select x.erros, x.valor into e, v_cadastro from public.importacao_data(d, 'cadastro', 'Data de cadastro', e) x;
  select x.erros, x.valor into e, v_recebimento from public.importacao_data(d, 'recebimento', 'Data de recebimento', e) x;
  select x.erros, x.valor into e, v_encaminhado from public.importacao_data(d, 'encaminhado', 'Data de encaminhamento', e) x;
  select x.erros, x.valor into e, v_respondido from public.importacao_data(d, 'resposta_data', 'Data da resposta', e) x;
  select x.erros, x.valor into e, v_reab_pedido from public.importacao_data(d, 'reab_pedido', 'Data do pedido de reabertura', e) x;
  select x.erros, x.valor into e, v_reab_data from public.importacao_data(d, 'reab_data', 'Data da reabertura', e) x;
  select x.erros, x.valor into e, v_reab_respondido from public.importacao_data(d, 'reab_resposta_data', 'Data da resposta à reabertura', e) x;

  if v_cadastro is null and v_recebimento is null
     and nullif(trim(d->>'cadastro'), '') is null and nullif(trim(d->>'recebimento'), '') is null then
    e := e || 'Sem data de cadastro nem de recebimento'::text;
  end if;
  v_cadastro := coalesce(v_cadastro, v_recebimento);
  if v_respondido is not null and v_recebimento is not null and v_respondido::date < v_recebimento::date then
    e := e || 'Data da resposta anterior ao recebimento'::text;
  end if;
  if v_reab_respondido is not null and v_reab_pedido is not null and v_reab_respondido::date < v_reab_pedido::date then
    e := e || 'Data da resposta à reabertura anterior ao pedido'::text;
  end if;

  -- Resposta, resolutividade, reabertura e arquivamento
  v_resolutiva := case public.normalizar_texto(d->>'resolutiva') when 'sim' then true when 'nao' then false end;
  v_reab_aceita := case public.normalizar_texto(d->>'reab_aceita') when 'sim' then true when 'nao' then false end;

  if v_reab_pedido is null and (v_reab_aceita is not null or v_reab_respondido is not null) then
    e := e || 'Reabertura sem a data do pedido'::text;
  end if;
  if v_reab_pedido is not null and v_respondido is null then
    e := e || 'Pedido de reabertura sem a primeira resposta'::text;
  end if;
  if v_reab_respondido is not null and v_reab_aceita is not true then
    e := e || 'Resposta à reabertura sem a reabertura aceita'::text;
  end if;

  if v_situacao = 'respondida' then
    if v_respondido is null then e := e || 'Respondida sem a data da resposta'::text; end if;
    if v_reab_aceita and v_reab_respondido is null then e := e || 'Reabertura aceita sem a data da resposta à reabertura'::text; end if;
    if v_motivo is null and v_resolutiva is null then e := e || 'Respondida sem a resolutividade (sim ou não)'::text; end if;
  elsif v_situacao is not null then
    if v_motivo is not null then e := e || 'Arquivamento em manifestação que não está Respondida'::text; end if;
    if v_situacao = 'reaberta' then
      if v_reab_aceita is not true then e := e || 'Reaberta sem pedido de reabertura aceito'::text; end if;
    elsif v_respondido is not null then
      e := e || format('Situação "%s", mas a planilha tem data de resposta', d->>'situacao');
    end if;
    if v_reab_respondido is not null then
      e := e || format('Situação "%s", mas a planilha tem resposta à reabertura', d->>'situacao');
    end if;
  end if;

  -- A coluna do prazo prorrogado pode vir preenchida por fórmula em todas as linhas: só vale como
  -- prorrogação quando a situação é Prorrogada ou a resposta saiu depois dos 5 dias úteis.
  v_prorrogado := v_situacao = 'prorrogada'
    or coalesce(nullif(trim(d->>'prazo_prorrogacao'), '') is not null and v_respondido is not null
        and v_respondido::date > public.prazo_ciclo(coalesce(v_recebimento::date, public.calcular_dia_zero(v_cadastro at time zone 'America/Sao_Paulo')), false), false);

  if coalesce(array_length(e, 1), 0) > 0 then
    return query select e, a, null::bigint;
    return;
  end if;

  -- Bairro novo entra no cadastro, como no registro pela tela.
  if public.normalizar_texto(d->>'bairro') is not null then
    v_bairro := public.importacao_buscar('bairros', d->>'bairro');
    if v_bairro is null then
      insert into public.bairros (nome) values (upper(trim(regexp_replace(d->>'bairro', '\s+', ' ', 'g'))))
      returning id into v_bairro;
      a := a || format('Bairro novo cadastrado: %s', upper(trim(d->>'bairro')));
    end if;
  end if;

  -- Avaliador antigo que não está mais no cadastro entra desativado.
  if v_diretoria is not null and v_avaliador is null then
    insert into public.avaliadores (nome, diretoria_id, ativo)
    values (upper(trim(regexp_replace(d->>'avaliador', '\s+', ' ', 'g'))), v_diretoria, false)
    returning id into v_avaliador;
    a := a || format('Avaliador cadastrado como inativo: %s', upper(trim(d->>'avaliador')));
  end if;

  perform set_config('ouvidoria.acao', 'sim', true);

  -- A planilha só tem a data do cadastro: sem hora, conta como cadastro no início do dia.
  v_dz_calc := public.calcular_dia_zero(v_cadastro at time zone 'America/Sao_Paulo');
  v_dz := coalesce(v_recebimento::date, v_dz_calc);
  insert into public.manifestacoes (
    protocolo_mgouv, protocolo_falabr, canal_id, tipo_id, identificacao_id, cadastrado_em, dia_zero,
    dia_zero_corrigido_justificativa, assunto_id, logradouro, numero_imovel, complemento, bairro_id, cep,
    descricao, observacoes, importada_de)
  values (
    v_mgouv, v_falabr, v_canal, v_tipo, v_identificacao, v_cadastro at time zone 'America/Sao_Paulo', v_dz,
    case when v_dz <> v_dz_calc then 'Data de recebimento informada na planilha antiga' end,
    v_assunto, nullif(trim(d->>'logradouro'), ''), nullif(nullif(trim(d->>'numero'), ''), '0'),
    nullif(trim(d->>'complemento'), ''), v_bairro, v_cep, trim(d->>'descricao'),
    nullif(trim(d->>'observacoes'), ''), format('%s, nº %s (linha %s)', l.aba, coalesce(d->>'n', '?'), l.linha))
  returning id into v_m;

  select c.id into v_c0 from public.ciclos c where c.manifestacao_id = v_m and c.numero = 0;

  if v_diretoria is not null then
    insert into public.encaminhamentos (manifestacao_id, diretoria_id, avaliador_id, enviado_em)
    values (v_m, v_diretoria, v_avaliador, greatest(coalesce(v_encaminhado::date, v_dz), (v_cadastro)::date));
  end if;

  update public.ciclos c
  set prorrogado = v_prorrogado,
      prorrogacao_justificativa = case when v_prorrogado then 'Prorrogação registrada na planilha antiga' end,
      respondido_em = v_respondido::date,
      resposta = case when v_respondido is not null
        then coalesce(nullif(trim(d->>'resposta'), ''), '(Resposta não transcrita na planilha antiga.)') end
  where c.id = v_c0;

  if v_reab_pedido is not null then
    if v_reab_aceita then
      insert into public.ciclos (manifestacao_id, numero, dia_zero, respondido_em, resposta)
      values (v_m, 1, coalesce(v_reab_data::date, public.calcular_dia_zero(v_reab_pedido at time zone 'America/Sao_Paulo')),
              v_reab_respondido::date,
              case when v_reab_respondido is not null
                then coalesce(nullif(trim(d->>'reab_resposta'), ''), '(Resposta não transcrita na planilha antiga.)') end)
      returning id into v_c1;
    end if;
    insert into public.pedidos_reabertura (manifestacao_id, recebido_em, texto, aceito, decidido_em, justificativa_decisao, ciclo_id)
    values (v_m, v_reab_pedido at time zone 'America/Sao_Paulo',
            coalesce(nullif(trim(d->>'reab_texto'), ''), '(Pedido não transcrito na planilha antiga.)'),
            v_reab_aceita,
            case when v_reab_aceita is not null then coalesce(v_reab_data, v_reab_pedido) at time zone 'America/Sao_Paulo' end,
            case when v_reab_aceita is not null then 'Decisão registrada na planilha antiga' end,
            v_c1);
    if v_reab_aceita is null then
      a := a || 'Pedido de reabertura sem decisão na planilha: fica aguardando decisão'::text;
    end if;
  end if;

  update public.manifestacoes m
  set situacao = v_situacao,
      resolutiva = case when v_motivo is null and v_situacao = 'respondida' then v_resolutiva end,
      arquivada = v_motivo is not null,
      motivo_arquivamento_id = v_motivo
  where m.id = v_m;

  perform set_config('ouvidoria.acao', '', true);
  return query select e, a, v_m;
end;
$$;

-- Confere (p_importar = false, desfaz tudo) ou importa (true) as linhas ainda não importadas do lote.
-- Linhas em ordem de recebimento, para a numeração interna seguir a ordem da planilha.
create function public.importacao_processar(p_lote text, p_importar boolean default false)
returns table (linhas integer, sem_erro integer, com_erro integer, importadas integer)
language plpgsql
set search_path = ''
as $$
declare
  l public.importacao_linhas;
  r record;
  n integer := 0; ok integer := 0; ruim integer := 0; feitas integer := 0;
begin
  for l in
    select * from public.importacao_linhas il
    where il.lote = p_lote and il.importada_em is null
    order by il.dados->>'recebimento' nulls last, il.dados->>'cadastro', il.aba, il.linha
  loop
    n := n + 1;
    begin
      select * into r from public.importacao_linha(l);
      update public.importacao_linhas il
      set erros = r.r_erros, avisos = r.r_avisos, conferida_em = now(),
          manifestacao_id = case when p_importar then r.r_manifestacao end,
          importada_em = case when p_importar and r.r_manifestacao is not null then now() end
      where il.id = l.id;
      if r.r_manifestacao is null then
        ruim := ruim + 1;
      else
        ok := ok + 1;
        if p_importar then feitas := feitas + 1; end if;
      end if;
      if not p_importar and r.r_manifestacao is not null then
        -- Simulação: desfaz a linha e guarda só o resultado da conferência.
        raise exception using errcode = 'OUV01', message = array_to_string(r.r_avisos, '|');
      end if;
    exception
      when sqlstate 'OUV01' then
        update public.importacao_linhas il
        set erros = '{}', avisos = coalesce(string_to_array(nullif(sqlerrm, ''), '|'), '{}'), conferida_em = now()
        where il.id = l.id;
      when others then
        ruim := ruim + 1;
        update public.importacao_linhas il
        set erros = array[sqlerrm], avisos = '{}', conferida_em = now()
        where il.id = l.id;
    end;
  end loop;
  return query select n, ok, ruim, feitas;
end;
$$;

revoke execute on function public.importacao_buscar(text, text) from public, anon, authenticated;
revoke execute on function public.importacao_data(jsonb, text, text, text[]) from public, anon, authenticated;
revoke execute on function public.importacao_linha(public.importacao_linhas) from public, anon, authenticated;
revoke execute on function public.importacao_processar(text, boolean) from public, anon, authenticated;
