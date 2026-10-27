-- RN04, RN07, RN08, RN09, RN12: dia 0, dias úteis e prazos.
-- Calendário de referência (2026): 31/10 sábado, 01/11 domingo, 02/11 Finados, 20/11 Consciência Negra.

do $$
begin
  -- RN04: corte às 17h (horário de Brasília)
  assert public.calcular_dia_zero('2026-10-27 00:30-03') = '2026-10-27', 'madrugada vale o próprio dia';
  assert public.calcular_dia_zero('2026-10-27 16:59-03') = '2026-10-27', 'até 16h59 vale o próprio dia';
  assert public.calcular_dia_zero('2026-10-27 17:00-03') = '2026-10-28', 'a partir das 17h vale o próximo dia útil';
  assert public.calcular_dia_zero('2026-10-27 20:30+00') = '2026-10-28', 'horário em UTC é convertido para Brasília';
  assert public.calcular_dia_zero('2026-10-30 18:00-03') = '2026-11-03', 'sexta após 17h pula fim de semana e Finados';
  assert public.calcular_dia_zero('2026-10-31 10:00-03') = '2026-11-03', 'sábado vale o próximo dia útil';
  assert public.calcular_dia_zero('2026-11-02 09:00-03') = '2026-11-03', 'feriado vale o próximo dia útil';

  -- RN07 / RN08: o dia seguinte ao dia 0 é o dia 1
  assert public.prazo_ciclo('2026-10-27', false) = '2026-11-04', 'prazo de 5 dias úteis';
  assert public.prazo_ciclo('2026-10-27', true) = '2026-11-11', 'prazo prorrogado de 10 dias úteis';
  assert public.prazo_ciclo('2026-11-16', false) = '2026-11-24', 'prazo pula o feriado de 20/11';

  -- RN12: tempo de resposta em dias úteis
  assert public.dias_uteis_entre('2026-10-27', '2026-10-27') = 0, 'resposta no dia 0 leva 0 dias';
  assert public.dias_uteis_entre('2026-10-27', '2026-11-04') = 5, 'resposta no último dia do prazo leva 5 dias';
  assert public.dias_uteis_entre('2026-10-30', '2026-11-03') = 1, 'fim de semana e feriado não contam';
end;
$$;
