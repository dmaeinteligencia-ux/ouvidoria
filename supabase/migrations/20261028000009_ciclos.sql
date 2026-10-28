-- Fase 3: prorrogação (RN08), complementação (RN10, RN11), reabertura (RN20 a RN22)
-- e rotina que marca Vencida (RN13) e arquiva por falta de complementação (RN11).

-- Situação "em andamento" do ciclo atual: prorrogada, reaberta ou em tratamento.
create function public.situacao_em_andamento(c public.ciclos)
returns public.situacao_manifestacao
language sql
stable
set search_path = ''
as $$
  select case
    when c.prorrogado then 'prorrogada'::public.situacao_manifestacao
    when c.numero > 0 then 'reaberta'::public.situacao_manifestacao
    else 'em_tratamento'::public.situacao_manifestacao
  end;
$$;

create function public.ciclo_atual(p_manifestacao_id bigint)
returns public.ciclos
language sql
stable
set search_path = ''
as $$
  select c.* from public.ciclos c
  where c.manifestacao_id = p_manifestacao_id
  order by c.numero desc
  limit 1;
$$;

-- ---------------------------------------------------------------------------
-- RN24: complementações, pedidos de reabertura e novos ciclos só pelas ações.
-- ---------------------------------------------------------------------------

create function public.exigir_acao()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- O ciclo original é criado pelo gatilho do cadastro.
  if tg_table_name = 'ciclos' then
    if new.numero = 0 then
      return new;
    end if;
  end if;
  if not public.em_acao() then
    raise exception 'Use as ações da manifestação para registrar % (RN24)',
      case tg_table_name
        when 'complementacoes' then 'complementações'
        when 'pedidos_reabertura' then 'pedidos de reabertura'
        else 'reaberturas'
      end;
  end if;
  return new;
end;
$$;

create trigger exigir_acao before insert or update on public.complementacoes
for each row execute function public.exigir_acao();
create trigger exigir_acao before insert or update on public.pedidos_reabertura
for each row execute function public.exigir_acao();
create trigger exigir_acao before insert on public.ciclos
for each row execute function public.exigir_acao();

-- Corrigir a data do cadastro não mexe no dia 0 de um ciclo reiniciado por complementação.
create or replace function public.manifestacao_propagar_dia_zero()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.dia_zero is distinct from old.dia_zero then
    update public.ciclos c
    set dia_zero = new.dia_zero
    where c.manifestacao_id = new.id and c.numero = 0 and c.respondido_em is null
      and not exists (
        select 1 from public.complementacoes co
        where co.ciclo_id = c.id and co.complementado_em is not null);
  end if;
  return null;
end;
$$;

-- ---------------------------------------------------------------------------
-- Ações
-- ---------------------------------------------------------------------------

-- RN08: prorrogação pedida pelo avaliador, registrada até o dia do vencimento, uma por ciclo.
create function public.registrar_prorrogacao(p_manifestacao_id bigint, p_justificativa text)
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
    raise exception 'O prazo está suspenso aguardando complementação';
  end if;
  if c.prorrogado then
    raise exception 'Este ciclo já foi prorrogado; só cabe uma prorrogação por ciclo (RN08)';
  end if;
  if public.hoje() > public.prazo_ciclo(c.dia_zero, false) then
    raise exception 'A prorrogação deve ser registrada até o vencimento (%) (RN08)',
      to_char(public.prazo_ciclo(c.dia_zero, false), 'DD/MM/YYYY');
  end if;
  if nullif(trim(p_justificativa), '') is null then
    raise exception 'Informe a justificativa da prorrogação (RN08)';
  end if;

  perform set_config('ouvidoria.acao', 'sim', true);
  update public.ciclos
  set prorrogado = true, prorrogacao_justificativa = trim(p_justificativa), prorrogacao_registrada_em = now()
  where id = c.id;
  update public.manifestacoes set situacao = 'prorrogada' where id = m.id;
  perform set_config('ouvidoria.acao', '', true);
end;
$$;

-- RN10: pedido de complementação suspende o prazo.
create function public.pedir_complementacao(
  p_manifestacao_id bigint,
  p_origem public.origem_complementacao,
  p_pedido_em date
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

  perform set_config('ouvidoria.acao', 'sim', true);
  insert into public.complementacoes (ciclo_id, origem, pedido_em) values (c.id, p_origem, p_pedido_em);
  update public.manifestacoes set situacao = 'aguardando_complementacao' where id = m.id;
  perform set_config('ouvidoria.acao', '', true);
end;
$$;

-- RN10: a complementação chegou; a contagem recomeça com novo dia 0 (RN04).
create function public.registrar_complementacao(p_manifestacao_id bigint, p_complementado_em timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
declare
  m public.manifestacoes;
  c public.ciclos;
  co public.complementacoes;
begin
  if not public.eh_equipe_ouvidoria() then
    raise exception 'Ação permitida só para a equipe da Ouvidoria';
  end if;
  select * into m from public.manifestacoes where id = p_manifestacao_id for update;
  if not found then
    raise exception 'Manifestação não encontrada';
  end if;
  c := public.ciclo_atual(m.id);
  select * into co from public.complementacoes
  where ciclo_id = c.id and complementado_em is null and not arquivada_por_falta
  order by id desc limit 1;

  if m.situacao <> 'aguardando_complementacao' or co.id is null then
    raise exception 'Não há pedido de complementação em aberto';
  end if;
  if p_complementado_em is null
     or (p_complementado_em at time zone 'America/Sao_Paulo')::date < co.pedido_em
     or p_complementado_em > now() then
    raise exception 'A complementação deve ter chegado entre o pedido (%) e agora', to_char(co.pedido_em, 'DD/MM/YYYY');
  end if;
  if (p_complementado_em at time zone 'America/Sao_Paulo')::date > co.limite then
    raise exception 'O prazo de 10 dias corridos para a complementação terminou em % (RN11)', to_char(co.limite, 'DD/MM/YYYY');
  end if;

  perform set_config('ouvidoria.acao', 'sim', true);
  update public.complementacoes set complementado_em = p_complementado_em where id = co.id;
  -- Nova contagem: novo dia 0 e sem a prorrogação anterior.
  update public.ciclos
  set dia_zero = public.calcular_dia_zero(p_complementado_em),
      prorrogado = false, prorrogacao_justificativa = null, prorrogacao_registrada_em = null
  where id = c.id;
  select * into c from public.ciclos where id = c.id;
  update public.manifestacoes set situacao = public.situacao_em_andamento(c) where id = m.id;
  perform set_config('ouvidoria.acao', '', true);
end;
$$;

-- RN20: pedido de reabertura até 30 dias corridos após o envio da primeira resposta.
create function public.registrar_pedido_reabertura(
  p_manifestacao_id bigint,
  p_recebido_em timestamptz,
  p_texto text
)
returns bigint
language plpgsql
set search_path = ''
as $$
declare
  m public.manifestacoes;
  primeira date;
  novo bigint;
begin
  if not public.eh_equipe_ouvidoria() then
    raise exception 'Ação permitida só para a equipe da Ouvidoria';
  end if;
  select * into m from public.manifestacoes where id = p_manifestacao_id for update;
  if not found then
    raise exception 'Manifestação não encontrada';
  end if;
  if m.situacao <> 'respondida' then
    raise exception 'Só manifestação respondida pode ser reaberta';
  end if;
  if m.arquivada then
    raise exception 'Manifestação arquivada não pode ser reaberta';
  end if;
  if exists (select 1 from public.pedidos_reabertura p where p.manifestacao_id = m.id and p.aceito is null) then
    raise exception 'Já há um pedido de reabertura aguardando decisão';
  end if;

  select c.respondido_em into primeira from public.ciclos c where c.manifestacao_id = m.id and c.numero = 0;
  if p_recebido_em is null or p_recebido_em > now()
     or (p_recebido_em at time zone 'America/Sao_Paulo')::date < (select max(c.respondido_em) from public.ciclos c where c.manifestacao_id = m.id) then
    raise exception 'A data do pedido deve ficar entre a última resposta e agora';
  end if;
  if (p_recebido_em at time zone 'America/Sao_Paulo')::date > primeira + 30 then
    raise exception 'O prazo para pedir reabertura terminou em %: 30 dias corridos após a primeira resposta (RN20)',
      to_char(primeira + 30, 'DD/MM/YYYY');
  end if;
  if nullif(trim(p_texto), '') is null then
    raise exception 'Informe o texto do pedido de reabertura';
  end if;

  perform set_config('ouvidoria.acao', 'sim', true);
  insert into public.pedidos_reabertura (manifestacao_id, recebido_em, texto)
  values (m.id, p_recebido_em, trim(p_texto))
  returning id into novo;
  perform set_config('ouvidoria.acao', '', true);
  return novo;
end;
$$;

-- RN21 / RN22: aceito abre novo ciclo com dia 0 no recebimento do pedido; negado continua Respondida.
create function public.decidir_reabertura(p_pedido_id bigint, p_aceito boolean, p_justificativa text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  p public.pedidos_reabertura;
  m public.manifestacoes;
  novo_ciclo bigint;
begin
  if not public.eh_equipe_ouvidoria() then
    raise exception 'Ação permitida só para a equipe da Ouvidoria';
  end if;
  select * into p from public.pedidos_reabertura where id = p_pedido_id for update;
  if not found then
    raise exception 'Pedido de reabertura não encontrado';
  end if;
  if p.aceito is not null then
    raise exception 'Este pedido já foi decidido';
  end if;
  if p_aceito is null or nullif(trim(p_justificativa), '') is null then
    raise exception 'Informe a decisão e a justificativa (RN21)';
  end if;
  select * into m from public.manifestacoes where id = p.manifestacao_id for update;

  perform set_config('ouvidoria.acao', 'sim', true);
  if p_aceito then
    insert into public.ciclos (manifestacao_id, numero, dia_zero)
    select m.id, max(c.numero) + 1, public.calcular_dia_zero(p.recebido_em)
    from public.ciclos c where c.manifestacao_id = m.id
    returning id into novo_ciclo;
    update public.manifestacoes set situacao = 'reaberta', resolutiva = null where id = m.id;
  end if;
  update public.pedidos_reabertura
  set aceito = p_aceito, decidido_em = now(), justificativa_decisao = trim(p_justificativa), ciclo_id = novo_ciclo
  where id = p.id;
  perform set_config('ouvidoria.acao', '', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- Rotina do sistema (agendada; também pode ser chamada à mão).
-- RN11: sem complementação em 10 dias corridos → Respondida e Arquivada por insuficiência de dados.
-- RN13: prazo vigente terminou sem resposta → Vencida (e volta, se o dia 0 for corrigido).
-- ---------------------------------------------------------------------------

create function public.atualizar_situacoes()
returns table (arquivadas integer, vencidas integer, reabertas_do_prazo integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  motivo smallint := (select id from public.motivos_arquivamento where nome = 'INSUFICIÊNCIA DE DADOS');
  r record;
  n_arq integer := 0;
  n_venc integer := 0;
  n_volta integer := 0;
begin
  perform set_config('ouvidoria.acao', 'sim', true);

  for r in
    select co.id as complementacao_id, co.limite, c.id as ciclo_id, c.manifestacao_id
    from public.complementacoes co
    join public.ciclos c on c.id = co.ciclo_id
    join public.manifestacoes m on m.id = c.manifestacao_id
    where co.complementado_em is null and not co.arquivada_por_falta
      and m.situacao = 'aguardando_complementacao'
      and co.limite < public.hoje()
  loop
    update public.complementacoes set arquivada_por_falta = true where id = r.complementacao_id;
    update public.ciclos
    set respondido_em = r.limite + 1,
        resposta = 'Arquivada automaticamente: sem complementação em 10 dias corridos (RN11).'
    where id = r.ciclo_id;
    update public.manifestacoes
    set situacao = 'respondida', arquivada = true, motivo_arquivamento_id = motivo, resolutiva = null
    where id = r.manifestacao_id;
    n_arq := n_arq + 1;
  end loop;

  with alvo as (
    select m.id
    from public.manifestacoes m
    cross join lateral public.ciclo_atual(m.id) c
    where m.situacao in ('em_tratamento', 'prorrogada', 'reaberta')
      and c.respondido_em is null
      and public.prazo_ciclo(c.dia_zero, c.prorrogado) < public.hoje()
  )
  update public.manifestacoes m set situacao = 'vencida' from alvo where m.id = alvo.id;
  get diagnostics n_venc = row_count;

  with alvo as (
    select m.id, public.situacao_em_andamento(c) as situacao
    from public.manifestacoes m
    cross join lateral public.ciclo_atual(m.id) c
    where m.situacao = 'vencida'
      and c.respondido_em is null
      and public.prazo_ciclo(c.dia_zero, c.prorrogado) >= public.hoje()
  )
  update public.manifestacoes m set situacao = alvo.situacao from alvo where m.id = alvo.id;
  get diagnostics n_volta = row_count;

  perform set_config('ouvidoria.acao', '', true);
  return query select n_arq, n_venc, n_volta;
end;
$$;

revoke execute on function public.atualizar_situacoes() from public, anon, authenticated;

-- Respondida depois de vencida: registrar_resposta já aceita a situação Vencida.
-- Dia 0 corrigido numa manifestação vencida: a rotina devolve a situação na próxima execução.

-- Agenda a rotina de hora em hora quando o pg_cron existe (no Supabase); nos testes locais, não.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('ouvidoria-atualizar-situacoes', '5 * * * *', 'select public.atualizar_situacoes()');
  end if;
end;
$$;
