-- Correções antes da implantação:
-- - texto do pedido de complementação enviado ao manifestante;
-- - mais de um avaliador por encaminhamento, inclusive de diretorias diferentes. Cada avaliador é
--   uma linha de encaminhamentos; as linhas atuais formam o encaminhamento vigente, e a manifestação
--   conta uma vez em cada diretoria envolvida.

-- ---------------------------------------------------------------------------
-- Complementação (RN10): o que foi pedido ao manifestante
-- ---------------------------------------------------------------------------

alter table public.complementacoes add column texto text;

drop function public.pedir_complementacao(bigint, public.origem_complementacao, date);

create function public.pedir_complementacao(
  p_manifestacao_id bigint,
  p_origem public.origem_complementacao,
  p_pedido_em date,
  p_texto text
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  m public.manifestacoes;
  c public.ciclos;
begin
  if not public.eh_equipe_ouvidoria() then
    raise exception 'Ação permitida só para a equipe da Ouvidoria';
  end if;
  select * into m from public.manifestacoes where id = p_manifestacao_id for update;
  if not found then
    raise exception 'Manifestação não encontrada';
  end if;
  c := public.ciclo_atual(m.id);

  if c.respondido_em is not null then
    raise exception 'A manifestação já está respondida';
  end if;
  if m.situacao = 'aguardando_complementacao' then
    raise exception 'Já há um pedido de complementação em aberto';
  end if;
  if p_pedido_em is null or p_pedido_em < (m.cadastrado_em at time zone 'America/Sao_Paulo')::date
     or p_pedido_em > public.hoje() then
    raise exception 'A data do pedido deve ficar entre o cadastro e hoje';
  end if;
  if nullif(trim(p_texto), '') is null then
    raise exception 'Informe o pedido de complementação enviado ao manifestante';
  end if;

  perform set_config('ouvidoria.acao', 'sim', true);
  insert into public.complementacoes (ciclo_id, origem, pedido_em, texto) values (c.id, p_origem, p_pedido_em, trim(p_texto));
  update public.manifestacoes set situacao = 'aguardando_complementacao' where id = m.id;
  perform set_config('ouvidoria.acao', '', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- Encaminhamento a vários avaliadores (RN14 / RN16)
-- ---------------------------------------------------------------------------

drop index public.encaminhamento_atual_unico;
create unique index encaminhamento_atual_unico on public.encaminhamentos (manifestacao_id, avaliador_id) where atual;

-- Um insert avulso continua substituindo o encaminhamento anterior; dentro de encaminhar(), a
-- substituição já foi feita e as linhas do mesmo envio ficam todas atuais.
create or replace function public.encaminhamento_antes_inserir()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  m record;
begin
  select man.situacao, (man.cadastrado_em at time zone 'America/Sao_Paulo')::date as cadastro
  into m
  from public.manifestacoes man
  where man.id = new.manifestacao_id;

  if m.situacao = 'respondida' then
    raise exception 'Manifestação respondida não pode ser encaminhada';
  end if;
  if new.enviado_em < m.cadastro or new.enviado_em > public.hoje() then
    raise exception 'A data do envio deve ficar entre o cadastro (%) e hoje', to_char(m.cadastro, 'DD/MM/YYYY');
  end if;

  if not exists (
    select 1 from public.avaliadores a
    where a.id = new.avaliador_id and a.diretoria_id = new.diretoria_id
  ) then
    raise exception 'O avaliador não pertence à diretoria escolhida';
  end if;

  if new.atual and coalesce(current_setting('ouvidoria.encaminhando', true), '') <> new.manifestacao_id::text then
    update public.encaminhamentos e
    set atual = false
    where e.manifestacao_id = new.manifestacao_id and e.atual;
  end if;
  return new;
end;
$$;

-- Registra o envio no MG-OUV a um ou mais avaliadores; a diretoria de cada linha é a do avaliador.
create function public.encaminhar(p_manifestacao_id bigint, p_enviado_em date, p_avaliadores smallint[])
returns void
language plpgsql
set search_path = ''
as $$
declare
  lista smallint[] := array(select distinct x from unnest(p_avaliadores) x where x is not null);
begin
  if not public.eh_equipe_ouvidoria() then
    raise exception 'Ação permitida só para a equipe da Ouvidoria';
  end if;
  perform 1 from public.manifestacoes where id = p_manifestacao_id for update;
  if not found then
    raise exception 'Manifestação não encontrada';
  end if;
  if cardinality(lista) = 0 then
    raise exception 'Escolha ao menos um avaliador';
  end if;
  if (select count(*) from public.avaliadores where id = any (lista) and ativo) <> cardinality(lista) then
    raise exception 'Avaliador não encontrado ou desativado';
  end if;

  update public.encaminhamentos set atual = false where manifestacao_id = p_manifestacao_id and atual;
  perform set_config('ouvidoria.encaminhando', p_manifestacao_id::text, true);
  insert into public.encaminhamentos (manifestacao_id, diretoria_id, avaliador_id, enviado_em)
  select p_manifestacao_id, a.diretoria_id, a.id, p_enviado_em
  from public.avaliadores a
  where a.id = any (lista)
  order by a.diretoria_id, a.nome;
  perform set_config('ouvidoria.encaminhando', '', true);
end;
$$;

revoke execute on function public.encaminhar(bigint, date, smallint[]) from public, anon;
grant execute on function public.encaminhar(bigint, date, smallint[]) to authenticated;

-- Lista de manifestações: diretorias e avaliadores do encaminhamento vigente, em listas.
drop view public.painel_manifestacoes;

create view public.painel_manifestacoes
with (security_invoker = true)
as
select
  m.id,
  m.numero,
  m.protocolo_mgouv,
  m.protocolo_falabr,
  m.situacao,
  m.arquivada,
  m.dia_zero,
  a.nome as assunto,
  ca.nome_painel as canal,
  m.logradouro,
  b.nome as bairro,
  c.numero as ciclo,
  cp.prazo,
  c.respondido_em,
  cp.no_prazo,
  case when m.situacao <> 'aguardando_complementacao' and c.respondido_em is null
       then public.dias_uteis_restantes(cp.prazo) end as dias_restantes,
  e.diretorias,
  e.avaliadores,
  m.ano,
  m.sequencial,
  m.cadastrado_em,
  m.assunto_id,
  m.canal_id,
  e.diretoria_ids,
  t.nome as tipo,
  m.numero_imovel,
  m.resolutiva
from public.manifestacoes m
join public.assuntos a on a.id = m.assunto_id
join public.canais ca on ca.id = m.canal_id
join public.tipos_manifestacao t on t.id = m.tipo_id
left join public.bairros b on b.id = m.bairro_id
join lateral (
  select ci.* from public.ciclos ci
  where ci.manifestacao_id = m.id
  order by ci.numero desc
  limit 1
) c on true
join public.ciclos_prazos cp on cp.id = c.id
left join lateral (
  select array_agg(distinct d.nome order by d.nome) as diretorias,
         array_agg(distinct en.diretoria_id) as diretoria_ids,
         array_agg(av.nome order by d.nome, av.nome) as avaliadores
  from public.encaminhamentos en
  join public.diretorias d on d.id = en.diretoria_id
  join public.avaliadores av on av.id = en.avaliador_id
  where en.manifestacao_id = m.id and en.atual
  having count(*) > 0
) e on true;

grant select on public.painel_manifestacoes to authenticated;

-- ---------------------------------------------------------------------------
-- Indicadores: o filtro de diretoria pega qualquer diretoria do encaminhamento vigente, sem
-- duplicar a manifestação. Extrato: diretorias e avaliadores separados por vírgula.
-- ---------------------------------------------------------------------------

create or replace function public.indicadores_calcular(
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
    select m.*
    from public.manifestacoes m
    where m.dia_zero between p_inicio and p_fim
      and (p_situacoes is null or m.situacao = any (p_situacoes))
      and (p_tipos is null or m.tipo_id = any (p_tipos))
      and (p_canais is null or m.canal_id = any (p_canais))
      and (p_identificacoes is null or m.identificacao_id = any (p_identificacoes))
      and (p_assuntos is null or m.assunto_id = any (p_assuntos))
      and (p_bairros is null or m.bairro_id = any (p_bairros))
      and (p_diretorias is null or exists (
            select 1 from public.encaminhamentos e
            where e.manifestacao_id = m.id and e.atual and e.diretoria_id = any (p_diretorias)))
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

create or replace function public.extrato_mensal(p_ano integer, p_mes integer)
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
          'diretoria', e.diretorias,
          'avaliador', e.avaliadores,
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
      left join lateral (
        select string_agg(distinct d.nome, ', ') as diretorias,
               string_agg(av.nome, ', ' order by d.nome, av.nome) as avaliadores,
               max(en.enviado_em) as enviado_em
        from public.encaminhamentos en
        join public.diretorias d on d.id = en.diretoria_id
        join public.avaliadores av on av.id = en.avaliador_id
        where en.manifestacao_id = m.id and en.atual
      ) e on true
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
