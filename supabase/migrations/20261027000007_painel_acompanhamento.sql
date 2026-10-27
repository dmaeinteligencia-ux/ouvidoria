-- Visão do painel de acompanhamento da Ouvidoria: ciclo atual, prazo e dias úteis restantes.

-- Data de hoje no fuso de Brasília (o servidor roda em UTC).
create function public.hoje()
returns date
language sql
stable
set search_path = ''
as $$
  select (now() at time zone 'America/Sao_Paulo')::date;
$$;

-- Dias úteis de hoje até o prazo; negativo quando o prazo já passou.
create function public.dias_uteis_restantes(prazo date)
returns integer
language sql
stable
set search_path = ''
as $$
  select case
    when prazo >= public.hoje() then public.dias_uteis_entre(public.hoje(), prazo)
    else -public.dias_uteis_entre(prazo, public.hoje())
  end;
$$;

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
  -- Sem contagem enquanto aguarda complementação (RN10) ou depois de respondido.
  case when m.situacao <> 'aguardando_complementacao' and c.respondido_em is null
       then public.dias_uteis_restantes(cp.prazo) end as dias_restantes,
  d.nome as diretoria,
  av.nome as avaliador
from public.manifestacoes m
join public.assuntos a on a.id = m.assunto_id
join public.canais ca on ca.id = m.canal_id
left join public.bairros b on b.id = m.bairro_id
join lateral (
  select ci.* from public.ciclos ci
  where ci.manifestacao_id = m.id
  order by ci.numero desc
  limit 1
) c on true
join public.ciclos_prazos cp on cp.id = c.id
left join public.encaminhamentos e on e.manifestacao_id = m.id and e.atual
left join public.diretorias d on d.id = e.diretoria_id
left join public.avaliadores av on av.id = e.avaliador_id;
