-- Dias úteis, dia 0 e prazos (RN04, RN07, RN08, RN09, RN12).
-- Todas as datas são do fuso de Brasília; o corte do dia útil é às 17h.

create function public.eh_dia_util(d date)
returns boolean
language sql
stable
set search_path = ''
as $$
  select extract(isodow from d) < 6
     and not exists (select 1 from public.feriados f where f.data = d);
$$;

-- Primeiro dia útil igual ou posterior a d.
create function public.proximo_dia_util(d date)
returns date
language plpgsql
stable
set search_path = ''
as $$
begin
  while not public.eh_dia_util(d) loop
    d := d + 1;
  end loop;
  return d;
end;
$$;

-- RN04: cadastro em dia útil até 16h59 vale o próprio dia; das 17h às 23h59,
-- ou em sábado, domingo ou feriado, vale o próximo dia útil.
create function public.calcular_dia_zero(momento timestamptz)
returns date
language plpgsql
stable
set search_path = ''
as $$
declare
  local_ timestamp := momento at time zone 'America/Sao_Paulo';
  d date := local_::date;
begin
  if local_::time >= time '17:00' then
    d := d + 1;
  end if;
  return public.proximo_dia_util(d);
end;
$$;

-- O n-ésimo dia útil depois de inicio (inicio é o dia 0; o seguinte útil é o dia 1).
create function public.somar_dias_uteis(inicio date, n integer)
returns date
language plpgsql
stable
set search_path = ''
as $$
declare
  d date := inicio;
  contados integer := 0;
begin
  while contados < n loop
    d := d + 1;
    if public.eh_dia_util(d) then
      contados := contados + 1;
    end if;
  end loop;
  return d;
end;
$$;

-- Dias úteis no intervalo (inicio, fim]. Resposta no próprio dia 0 = 0 dias.
create function public.dias_uteis_entre(inicio date, fim date)
returns integer
language sql
stable
set search_path = ''
as $$
  select count(*)::integer
  from generate_series(inicio + 1, fim, interval '1 day') as g(dia)
  where fim > inicio and public.eh_dia_util(g.dia::date);
$$;

-- RN07 / RN08 / RN21: 5 dias úteis, ou 10 se prorrogado, contados do dia 0 do ciclo.
create function public.prazo_ciclo(dia_zero date, prorrogado boolean)
returns date
language sql
stable
set search_path = ''
as $$
  select public.somar_dias_uteis(dia_zero, case when prorrogado then 10 else 5 end);
$$;

-- Prazo, tempo e cumprimento de cada ciclo (RN12, RN19).
create view public.ciclos_prazos
with (security_invoker = true)
as
select
  c.id,
  c.manifestacao_id,
  c.numero,
  c.dia_zero,
  c.prorrogado,
  public.prazo_ciclo(c.dia_zero, c.prorrogado) as prazo,
  c.respondido_em,
  case when c.respondido_em is not null
       then public.dias_uteis_entre(c.dia_zero, c.respondido_em) end as tempo_dias_uteis,
  case when c.respondido_em is not null
       then c.respondido_em <= public.prazo_ciclo(c.dia_zero, c.prorrogado) end as no_prazo
from public.ciclos c;
