-- Gatilhos de integridade, numeração e histórico.

-- Manifestação: dia 0 (RN04), protocolo Fala.BR (RN02) e número interno anual (RN03).
create function public.manifestacao_antes_inserir()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  calculado date := public.calcular_dia_zero(new.cadastrado_em);
begin
  if new.dia_zero is null then
    new.dia_zero := calculado;
  elsif new.dia_zero <> calculado and new.dia_zero_corrigido_justificativa is null then
    raise exception 'Dia 0 diferente do calculado (%) exige justificativa', calculado;
  end if;

  if new.protocolo_falabr is null
     and (select exigir.exige_protocolo_falabr from public.canais exigir where exigir.id = new.canal_id) then
    raise exception 'Canal Fala.BR exige o protocolo Fala.BR';
  end if;

  new.ano := extract(year from new.dia_zero);
  perform pg_advisory_xact_lock(hashtext('manifestacoes'), new.ano);
  select coalesce(max(m.sequencial), 0) + 1 into new.sequencial
  from public.manifestacoes m
  where m.ano = new.ano;

  return new;
end;
$$;

create trigger antes_inserir
before insert on public.manifestacoes
for each row execute function public.manifestacao_antes_inserir();

-- Toda manifestação nasce com o ciclo original (número 0).
create function public.manifestacao_criar_ciclo()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  insert into public.ciclos (manifestacao_id, numero, dia_zero)
  values (new.id, 0, new.dia_zero);
  return null;
end;
$$;

create trigger criar_ciclo_original
after insert on public.manifestacoes
for each row execute function public.manifestacao_criar_ciclo();

create function public.manifestacao_antes_atualizar()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.dia_zero is distinct from old.dia_zero
     and new.dia_zero_corrigido_justificativa is not distinct from old.dia_zero_corrigido_justificativa then
    raise exception 'Correção do dia 0 exige justificativa';
  end if;
  if new.ano <> old.ano or new.sequencial <> old.sequencial then
    raise exception 'O número interno não pode ser alterado';
  end if;
  new.atualizado_em := now();
  return new;
end;
$$;

create trigger antes_atualizar
before update on public.manifestacoes
for each row execute function public.manifestacao_antes_atualizar();

-- RN14 / RN16: avaliador da diretoria escolhida; o novo encaminhamento substitui o anterior.
create function public.encaminhamento_antes_inserir()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.avaliadores a
    where a.id = new.avaliador_id and a.diretoria_id = new.diretoria_id
  ) then
    raise exception 'O avaliador não pertence à diretoria escolhida';
  end if;

  if new.atual then
    update public.encaminhamentos e
    set atual = false
    where e.manifestacao_id = new.manifestacao_id and e.atual;
  end if;
  return new;
end;
$$;

create trigger antes_inserir
before insert on public.encaminhamentos
for each row execute function public.encaminhamento_antes_inserir();

-- RN23: histórico de inserções, alterações e exclusões.
create function public.registrar_historico()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.historico (tabela, registro_id, acao, dados_antigos, dados_novos)
  values (
    tg_table_name,
    coalesce(new.id, old.id),
    lower(tg_op),
    case when tg_op <> 'INSERT' then to_jsonb(old) end,
    case when tg_op <> 'DELETE' then to_jsonb(new) end
  );
  return null;
end;
$$;

create trigger historico after insert or update or delete on public.manifestacoes
for each row execute function public.registrar_historico();
create trigger historico after insert or update or delete on public.ciclos
for each row execute function public.registrar_historico();
create trigger historico after insert or update or delete on public.complementacoes
for each row execute function public.registrar_historico();
create trigger historico after insert or update or delete on public.encaminhamentos
for each row execute function public.registrar_historico();
create trigger historico after insert or update or delete on public.pedidos_reabertura
for each row execute function public.registrar_historico();
