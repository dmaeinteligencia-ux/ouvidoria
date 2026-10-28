-- Fase 4: indicadores do CI nº 6660/2025 (Painel Geral público e Painel Gerencial por diretoria)
-- e extrato mensal no formato da planilha.
--
-- Definições:
-- - Período: data de recebimento pelo DMAE (dia 0 original da manifestação).
-- - Diretoria: a do encaminhamento atual.
-- - Prazo médio e cumprimento do prazo: só a primeira resposta (ciclo original), sem as arquivadas;
--   reaberturas ficam num indicador separado.
-- - Resolutividade: resolutivas ÷ respondidas não arquivadas (RN18).

create function public.indicadores_calcular(
  p_inicio date,
  p_fim date,
  p_agrupar text,
  p_situacoes public.situacao_manifestacao[],
  p_tipos smallint[],
  p_canais smallint[],
  p_identificacoes smallint[],
  p_assuntos smallint[],
  p_bairros integer[],
  p_diretorias smallint[],
  p_gerencial boolean
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with base as (
    select m.*, e.diretoria_id
    from public.manifestacoes m
    left join public.encaminhamentos e on e.manifestacao_id = m.id and e.atual
    where m.dia_zero between p_inicio and p_fim
      and (p_situacoes is null or m.situacao = any (p_situacoes))
      and (p_tipos is null or m.tipo_id = any (p_tipos))
      and (p_canais is null or m.canal_id = any (p_canais))
      and (p_identificacoes is null or m.identificacao_id = any (p_identificacoes))
      and (p_assuntos is null or m.assunto_id = any (p_assuntos))
      and (p_bairros is null or m.bairro_id = any (p_bairros))
      and (p_diretorias is null or e.diretoria_id = any (p_diretorias))
  ),
  primeira as (
    select b.id, b.dia_zero as recebido, c.respondido_em,
           public.dias_uteis_entre(c.dia_zero, c.respondido_em) as tempo,
           c.respondido_em <= public.prazo_ciclo(c.dia_zero, c.prorrogado) as no_prazo
    from base b
    join public.ciclos c on c.manifestacao_id = b.id and c.numero = 0
    where c.respondido_em is not null and not b.arquivada
  ),
  periodos as (
    select date_trunc(p_agrupar, g)::date as periodo
    from generate_series(p_inicio, p_fim, ('1 ' || p_agrupar)::interval) g
    union
    select date_trunc(p_agrupar, p_fim)::date
  )
  select jsonb_build_object(
    'total', (select count(*) from base),
    'situacao', (
      select coalesce(jsonb_agg(jsonb_build_object('chave', s, 'n', n) order by n desc), '[]')
      from (select situacao::text as s, count(*) as n from base group by 1) t),
    'evolucao', (
      select jsonb_agg(jsonb_build_object('periodo', p.periodo,
               'n', (select count(*) from base b where date_trunc(p_agrupar, b.dia_zero)::date = p.periodo))
             order by p.periodo)
      from periodos p),
    'tipo', (
      select coalesce(jsonb_agg(jsonb_build_object('nome', t.nome, 'n', n) order by n desc, t.nome), '[]')
      from (select tipo_id, count(*) as n from base group by 1) x
      join public.tipos_manifestacao t on t.id = x.tipo_id),
    'canal', (
      select coalesce(jsonb_agg(jsonb_build_object('nome', t.nome_painel, 'n', n) order by n desc, t.nome_painel), '[]')
      from (select c.nome_painel, count(*) as n from base b join public.canais c on c.id = b.canal_id group by 1) t),
    'arquivamento', (
      select coalesce(jsonb_agg(jsonb_build_object('nome', mo.nome, 'n', n) order by n desc, mo.nome), '[]')
      from (select motivo_arquivamento_id, count(*) as n from base where arquivada group by 1) x
      join public.motivos_arquivamento mo on mo.id = x.motivo_arquivamento_id),
    'prazo_medio', (select round(avg(tempo), 1) from primeira),
    'respondidas_primeira', (select count(*) from primeira),
    'evolucao_prazo', (
      select jsonb_agg(jsonb_build_object('periodo', p.periodo,
               'media', (select round(avg(tempo), 1) from primeira f where date_trunc(p_agrupar, f.recebido)::date = p.periodo))
             order by p.periodo)
      from periodos p),
    'cumprimento', jsonb_build_object(
      'no_prazo', (select count(*) from primeira where no_prazo),
      'fora_prazo', (select count(*) from primeira where not no_prazo)),
    'resolutividade', jsonb_build_object(
      'resolutivas', (select count(*) from base where situacao = 'respondida' and not arquivada and resolutiva),
      'respondidas', (select count(*) from base where situacao = 'respondida' and not arquivada and resolutiva is not null)),
    'reaberturas', jsonb_build_object(
      'pedidos', (select count(*) from public.pedidos_reabertura p join base b on b.id = p.manifestacao_id),
      'aceitas', (select count(*) from public.pedidos_reabertura p join base b on b.id = p.manifestacao_id where p.aceito)),
    'satisfacao_resposta', (
      select coalesce(jsonb_agg(jsonb_build_object('chave', s, 'n', n)), '[]')
      from (select satisfacao_resposta::text as s, count(*) as n from base where satisfacao_resposta is not null group by 1) t),
    'satisfacao_ouvidoria', (
      select coalesce(jsonb_agg(jsonb_build_object('chave', s, 'n', n)), '[]')
      from (select satisfacao_ouvidoria::text as s, count(*) as n from base where satisfacao_ouvidoria is not null group by 1) t)
  )
  || case when p_gerencial then jsonb_build_object(
    'assuntos', (
      select coalesce(jsonb_agg(jsonb_build_object('nome', a.nome, 'n', n) order by n desc, a.nome), '[]')
      from (select assunto_id, count(*) as n from base group by 1 order by 2 desc limit 10) x
      join public.assuntos a on a.id = x.assunto_id),
    'bairros', (
      select coalesce(jsonb_agg(jsonb_build_object('nome', ba.nome, 'n', n) order by n desc, ba.nome), '[]')
      from (select bairro_id, count(*) as n from base where bairro_id is not null group by 1) x
      join public.bairros ba on ba.id = x.bairro_id),
    'sem_bairro', (select count(*) from base where bairro_id is null)
  ) else '{}'::jsonb end;
$$;

revoke execute on function public.indicadores_calcular(date, date, text, public.situacao_manifestacao[], smallint[], smallint[], smallint[], smallint[], integer[], smallint[], boolean)
  from public, anon, authenticated;

create function public.validar_periodo(p_inicio date, p_fim date, p_agrupar text)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_inicio is null or p_fim is null or p_fim < p_inicio then
    raise exception 'Informe um período válido';
  end if;
  if p_agrupar not in ('day', 'month', 'year') then
    raise exception 'Agrupamento deve ser por dia, mês ou ano';
  end if;
  if p_agrupar = 'day' and p_fim - p_inicio > 366 then
    raise exception 'Agrupamento por dia vale para períodos de até um ano';
  end if;
end;
$$;

-- Painel Geral: público, só números agregados e só os filtros do CI para o público.
create function public.painel_geral(
  p_inicio date,
  p_fim date,
  p_agrupar text default 'month',
  p_situacoes public.situacao_manifestacao[] default null,
  p_tipos smallint[] default null,
  p_canais smallint[] default null,
  p_identificacoes smallint[] default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.validar_periodo(p_inicio, p_fim, p_agrupar);
  return public.indicadores_calcular(p_inicio, p_fim, p_agrupar, p_situacoes, p_tipos, p_canais,
    p_identificacoes, null, null, null, false);
end;
$$;

-- Painel Gerencial: a equipe da Ouvidoria vê todas as diretorias; o diretor, só a própria.
create function public.painel_gerencial(
  p_inicio date,
  p_fim date,
  p_agrupar text default 'month',
  p_situacoes public.situacao_manifestacao[] default null,
  p_tipos smallint[] default null,
  p_canais smallint[] default null,
  p_identificacoes smallint[] default null,
  p_assuntos smallint[] default null,
  p_bairros integer[] default null,
  p_diretorias smallint[] default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  diretorias smallint[] := p_diretorias;
begin
  if public.perfil_atual() = 'diretor' then
    diretorias := array[(select u.diretoria_id from public.usuarios u where u.id = auth.uid())];
  elsif not public.eh_equipe_ouvidoria() then
    raise exception 'Painel Gerencial disponível só para a Ouvidoria e os diretores';
  end if;
  perform public.validar_periodo(p_inicio, p_fim, p_agrupar);
  return public.indicadores_calcular(p_inicio, p_fim, p_agrupar, p_situacoes, p_tipos, p_canais,
    p_identificacoes, p_assuntos, p_bairros, diretorias, true);
end;
$$;

-- Opções dos filtros do Painel Geral (o público não lê as tabelas de cadastro).
create function public.painel_opcoes()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'tipos', (select jsonb_agg(jsonb_build_object('id', id, 'nome', nome) order by nome) from public.tipos_manifestacao where ativo),
    'canais', (select jsonb_agg(jsonb_build_object('id', id, 'nome', nome_painel) order by nome_painel) from public.canais where ativo),
    'identificacoes', (select jsonb_agg(jsonb_build_object('id', id, 'nome', nome) order by nome) from public.identificacoes where ativo),
    'primeiro_recebimento', (select min(dia_zero) from public.manifestacoes)
  );
$$;

revoke execute on function public.painel_geral(date, date, text, public.situacao_manifestacao[], smallint[], smallint[], smallint[]) from public;
grant execute on function public.painel_geral(date, date, text, public.situacao_manifestacao[], smallint[], smallint[], smallint[]) to anon, authenticated;
revoke execute on function public.painel_opcoes() from public;
grant execute on function public.painel_opcoes() to anon, authenticated;
revoke execute on function public.painel_gerencial(date, date, text, public.situacao_manifestacao[], smallint[], smallint[], smallint[], smallint[], integer[], smallint[]) from public, anon;
grant execute on function public.painel_gerencial(date, date, text, public.situacao_manifestacao[], smallint[], smallint[], smallint[], smallint[], integer[], smallint[]) to authenticated;

-- ---------------------------------------------------------------------------
-- Extrato mensal: uma linha por manifestação recebida no mês, nas 35 colunas da planilha.
-- A planilha tem lugar para uma reabertura; as seguintes vão em Observações.
-- ---------------------------------------------------------------------------

create function public.extrato_mensal(p_ano integer, p_mes integer)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  inicio date;
begin
  if not public.eh_equipe_ouvidoria() then
    raise exception 'Extrato disponível só para a equipe da Ouvidoria';
  end if;
  if p_mes not between 1 and 12 then
    raise exception 'Mês inválido';
  end if;
  inicio := make_date(p_ano, p_mes, 1);

  return (
    select coalesce(jsonb_agg(linha order by ordem), '[]')
    from (
      select
        row_number() over (order by m.dia_zero, m.cadastrado_em, m.id) as ordem,
        jsonb_build_object(
          'numero', m.numero,
          'situacao', m.situacao,
          'protocolo_mgouv', m.protocolo_mgouv,
          'canal', ca.nome,
          'protocolo_falabr', m.protocolo_falabr,
          'tipo', t.nome,
          'identificacao', i.nome,
          'cadastrado_em', m.cadastrado_em,
          'recebido_em', m.dia_zero,
          'assunto', a.nome,
          'logradouro', m.logradouro,
          'numero_imovel', m.numero_imovel,
          'complemento', m.complemento,
          'bairro', ba.nome,
          'cep', m.cep,
          'descricao', m.descricao,
          'diretoria', d.nome,
          'avaliador', av.nome,
          'encaminhado_em', e.enviado_em,
          'prazo', public.prazo_ciclo(c0.dia_zero, false),
          'prazo_prorrogacao', case when c0.prorrogado then public.prazo_ciclo(c0.dia_zero, true) end,
          'respondido_em', c0.respondido_em,
          'tempo', case when c0.respondido_em is not null then public.dias_uteis_entre(c0.dia_zero, c0.respondido_em) end,
          'resposta', c0.resposta,
          'resolutiva', m.resolutiva,
          'arquivada', m.arquivada,
          'motivo_arquivamento', mo.nome,
          'reabertura_pedido_em', p1.recebido_em,
          'reabertura_texto', p1.texto,
          'reabertura_aceita', p1.aceito,
          'reaberta_em', c1.dia_zero,
          'reabertura_prazo', case when c1.id is not null then public.prazo_ciclo(c1.dia_zero, false) end,
          'reabertura_prazo_prorrogacao', case when c1.prorrogado then public.prazo_ciclo(c1.dia_zero, true) end,
          'reabertura_respondido_em', c1.respondido_em,
          'reabertura_resposta', c1.resposta,
          'observacoes', concat_ws(E'\n',
            m.observacoes,
            (select string_agg(format('Reabertura %s: recebida em %s, %s%s', c.numero, to_char(c.dia_zero, 'DD/MM/YYYY'),
                      coalesce('respondida em ' || to_char(c.respondido_em, 'DD/MM/YYYY'), 'sem resposta'),
                      coalesce(': ' || c.resposta, '')), E'\n' order by c.numero)
             from public.ciclos c where c.manifestacao_id = m.id and c.numero > 1),
            (select string_agg(format('Pedido de reabertura de %s negado: %s', to_char(p.recebido_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'),
                      p.justificativa_decisao), E'\n' order by p.recebido_em)
             from public.pedidos_reabertura p
             where p.manifestacao_id = m.id and p.aceito = false and p.id <> p1.id))
        ) as linha
      from public.manifestacoes m
      join public.canais ca on ca.id = m.canal_id
      join public.tipos_manifestacao t on t.id = m.tipo_id
      join public.identificacoes i on i.id = m.identificacao_id
      join public.assuntos a on a.id = m.assunto_id
      left join public.bairros ba on ba.id = m.bairro_id
      left join public.motivos_arquivamento mo on mo.id = m.motivo_arquivamento_id
      left join public.encaminhamentos e on e.manifestacao_id = m.id and e.atual
      left join public.diretorias d on d.id = e.diretoria_id
      left join public.avaliadores av on av.id = e.avaliador_id
      join public.ciclos c0 on c0.manifestacao_id = m.id and c0.numero = 0
      left join public.ciclos c1 on c1.manifestacao_id = m.id and c1.numero = 1
      left join lateral (
        select p.* from public.pedidos_reabertura p
        where p.manifestacao_id = m.id
        order by (p.ciclo_id is not distinct from c1.id) desc, p.recebido_em
        limit 1
      ) p1 on true
      where m.dia_zero >= inicio and m.dia_zero < (inicio + interval '1 month')::date
    ) x
  );
end;
$$;

revoke execute on function public.extrato_mensal(integer, integer) from public, anon;
grant execute on function public.extrato_mensal(integer, integer) to authenticated;
