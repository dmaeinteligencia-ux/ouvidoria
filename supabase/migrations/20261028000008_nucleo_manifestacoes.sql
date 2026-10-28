-- Fase 2: ações sobre a manifestação (encaminhar, responder, arquivar), correções de cadastro,
-- aviso de duplicidade e histórico legível.

-- ---------------------------------------------------------------------------
-- RN24: situação, resposta e arquivamento só mudam pelas ações abaixo.
-- As funções de ação marcam a transação com ouvidoria.acao = 'sim'.
-- ---------------------------------------------------------------------------

create function public.em_acao()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(current_setting('ouvidoria.acao', true), '') = 'sim';
$$;

create or replace function public.manifestacao_antes_atualizar()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  calculado date := public.calcular_dia_zero(new.cadastrado_em);
begin
  if new.ano <> old.ano or new.sequencial <> old.sequencial then
    raise exception 'O número interno não pode ser alterado';
  end if;

  if (new.situacao is distinct from old.situacao
      or new.arquivada is distinct from old.arquivada
      or new.motivo_arquivamento_id is distinct from old.motivo_arquivamento_id
      or new.resolutiva is distinct from old.resolutiva)
     and not public.em_acao() then
    raise exception 'Situação, resolutividade e arquivamento mudam só pelas ações da manifestação (RN24)';
  end if;

  -- RN04: nova data de cadastro recalcula o dia 0, salvo correção manual justificada.
  if new.dia_zero is not distinct from old.dia_zero then
    if new.cadastrado_em is distinct from old.cadastrado_em and old.dia_zero_corrigido_justificativa is null then
      new.dia_zero := calculado;
    end if;
  elsif new.dia_zero = calculado then
    new.dia_zero_corrigido_justificativa := null;
  elsif new.dia_zero_corrigido_justificativa is null
     or new.dia_zero_corrigido_justificativa is not distinct from old.dia_zero_corrigido_justificativa then
    raise exception 'Correção do dia 0 exige justificativa';
  end if;

  new.atualizado_em := now();
  return new;
end;
$$;

-- O ciclo original acompanha o dia 0 corrigido enquanto não houver resposta.
create function public.manifestacao_propagar_dia_zero()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.dia_zero is distinct from old.dia_zero then
    update public.ciclos c
    set dia_zero = new.dia_zero
    where c.manifestacao_id = new.id and c.numero = 0 and c.respondido_em is null;
  end if;
  return null;
end;
$$;

create trigger propagar_dia_zero
after update on public.manifestacoes
for each row execute function public.manifestacao_propagar_dia_zero();

create function public.ciclo_antes_atualizar()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (new.respondido_em is distinct from old.respondido_em
      or new.resposta is distinct from old.resposta
      or new.prorrogado is distinct from old.prorrogado)
     and not public.em_acao() then
    raise exception 'Resposta e prorrogação mudam só pelas ações da manifestação (RN24)';
  end if;
  return new;
end;
$$;

create trigger antes_atualizar
before update on public.ciclos
for each row execute function public.ciclo_antes_atualizar();

-- RN14 / RN16: só encaminha o que ainda não foi respondido; data do envio entre o cadastro e hoje.
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

  if new.atual then
    update public.encaminhamentos e
    set atual = false
    where e.manifestacao_id = new.manifestacao_id and e.atual;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Ações
-- ---------------------------------------------------------------------------

-- RN17 / RN18: registra a resposta do ciclo atual; arquivada dispensa a resolutividade.
create function public.registrar_resposta(
  p_manifestacao_id bigint,
  p_respondido_em date,
  p_resposta text,
  p_resolutiva boolean default null,
  p_arquivar boolean default false,
  p_motivo_arquivamento_id smallint default null,
  p_duplicada_de bigint default null
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
  if m.situacao = 'respondida' then
    raise exception 'A manifestação já está respondida';
  end if;
  if m.situacao = 'aguardando_complementacao' then
    raise exception 'A manifestação aguarda complementação do manifestante';
  end if;

  select * into c from public.ciclos
  where manifestacao_id = m.id order by numero desc limit 1;

  if p_respondido_em is null or nullif(trim(p_resposta), '') is null then
    raise exception 'Informe a data e o texto da resposta (RN17)';
  end if;
  if p_respondido_em < c.dia_zero or p_respondido_em > public.hoje() then
    raise exception 'A data da resposta deve ficar entre o recebimento (%) e hoje', to_char(c.dia_zero, 'DD/MM/YYYY');
  end if;
  if not p_arquivar and p_resolutiva is null then
    raise exception 'Informe se a resposta foi resolutiva (RN17)';
  end if;
  if p_arquivar and p_motivo_arquivamento_id is null then
    raise exception 'Escolha o motivo do arquivamento (RN18)';
  end if;
  if p_duplicada_de = m.id then
    raise exception 'A manifestação não pode ser duplicada dela mesma';
  end if;

  perform set_config('ouvidoria.acao', 'sim', true);

  update public.ciclos
  set respondido_em = p_respondido_em, resposta = trim(p_resposta)
  where id = c.id;

  update public.manifestacoes
  set situacao = 'respondida',
      resolutiva = case when p_arquivar then null else p_resolutiva end,
      arquivada = coalesce(p_arquivar, false),
      motivo_arquivamento_id = case when p_arquivar then p_motivo_arquivamento_id end,
      duplicada_de = case when p_arquivar then p_duplicada_de else duplicada_de end
  where id = m.id;

  perform set_config('ouvidoria.acao', '', true);
end;
$$;

-- RN18: arquiva uma manifestação já respondida.
create function public.arquivar_manifestacao(
  p_manifestacao_id bigint,
  p_motivo_arquivamento_id smallint,
  p_duplicada_de bigint default null
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  m public.manifestacoes;
begin
  if not public.eh_equipe_ouvidoria() then
    raise exception 'Ação permitida só para a equipe da Ouvidoria';
  end if;

  select * into m from public.manifestacoes where id = p_manifestacao_id for update;
  if not found then
    raise exception 'Manifestação não encontrada';
  end if;
  if m.situacao <> 'respondida' then
    raise exception 'Registre a resposta antes de arquivar (RN18)';
  end if;
  if m.arquivada then
    raise exception 'A manifestação já está arquivada';
  end if;
  if p_motivo_arquivamento_id is null then
    raise exception 'Escolha o motivo do arquivamento (RN18)';
  end if;
  if p_duplicada_de = m.id then
    raise exception 'A manifestação não pode ser duplicada dela mesma';
  end if;

  perform set_config('ouvidoria.acao', 'sim', true);
  update public.manifestacoes
  set arquivada = true,
      resolutiva = null,
      motivo_arquivamento_id = p_motivo_arquivamento_id,
      duplicada_de = coalesce(p_duplicada_de, duplicada_de)
  where id = m.id;
  perform set_config('ouvidoria.acao', '', true);
end;
$$;

-- RN04: prévia do dia 0 e dos prazos na tela de cadastro.
create function public.previa_prazos(p_cadastrado_em timestamptz)
returns table (dia_zero date, prazo date, prazo_prorrogado date)
language sql
stable
set search_path = ''
as $$
  select z.d, public.prazo_ciclo(z.d, false), public.prazo_ciclo(z.d, true)
  from (select public.calcular_dia_zero(p_cadastrado_em) as d) z;
$$;

-- ---------------------------------------------------------------------------
-- RN06: possível duplicidade (mesmo protocolo, ou mesmo endereço e assunto em 30 dias).
-- ---------------------------------------------------------------------------

create function public.normalizar_texto(t text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(regexp_replace(
    translate(lower(coalesce(t, '')),
      'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc'),
    '[^a-z0-9]+', '', 'g'), '');
$$;

create function public.possiveis_duplicidades(
  p_protocolo_mgouv text,
  p_protocolo_falabr text,
  p_logradouro text,
  p_numero_imovel text,
  p_assunto_id smallint,
  p_referencia timestamptz,
  p_ignorar_id bigint default null
)
returns table (id bigint, numero text, assunto text, dia_zero date, motivo text)
language sql
stable
set search_path = ''
as $$
  select m.id, m.numero, a.nome, m.dia_zero,
    case
      when m.protocolo_mgouv = p_protocolo_mgouv then 'mesmo protocolo MG-OUV'
      when m.protocolo_falabr = p_protocolo_falabr then 'mesmo protocolo Fala.BR'
      else 'mesmo endereço e assunto'
    end
  from public.manifestacoes m
  join public.assuntos a on a.id = m.assunto_id
  where m.id is distinct from p_ignorar_id
    and (
      m.protocolo_mgouv = p_protocolo_mgouv
      or m.protocolo_falabr = p_protocolo_falabr
      or (
        m.assunto_id = p_assunto_id
        and public.normalizar_texto(p_logradouro) is not null
        and public.normalizar_texto(m.logradouro) = public.normalizar_texto(p_logradouro)
        and (public.normalizar_texto(p_numero_imovel) is null
             or public.normalizar_texto(m.numero_imovel) is not distinct from public.normalizar_texto(p_numero_imovel))
        and m.cadastrado_em between p_referencia - interval '30 days' and p_referencia + interval '30 days'
      )
    )
  order by m.cadastrado_em desc
  limit 5;
$$;

-- ---------------------------------------------------------------------------
-- RN23: histórico com o nome de quem fez (a tabela de usuários é restrita por RLS).
-- ---------------------------------------------------------------------------

create function public.historico_manifestacao(p_manifestacao_id bigint)
returns table (
  id bigint,
  em timestamptz,
  tabela text,
  acao text,
  usuario text,
  dados_antigos jsonb,
  dados_novos jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select h.id, h.em, h.tabela, h.acao, u.nome, h.dados_antigos, h.dados_novos
  from public.historico h
  left join public.usuarios u on u.id = h.usuario_id
  where public.eh_equipe_ouvidoria()
    and (
      (h.tabela = 'manifestacoes' and h.registro_id = p_manifestacao_id)
      or (h.tabela in ('ciclos', 'encaminhamentos', 'complementacoes', 'pedidos_reabertura')
          and coalesce(h.dados_novos, h.dados_antigos) ->> 'manifestacao_id' = p_manifestacao_id::text)
      or (h.tabela = 'complementacoes'
          and (coalesce(h.dados_novos, h.dados_antigos) ->> 'ciclo_id')::bigint in (
            select c.id from public.ciclos c where c.manifestacao_id = p_manifestacao_id))
    )
  order by h.em, h.id;
$$;

revoke execute on function public.historico_manifestacao(bigint) from public, anon;
grant execute on function public.historico_manifestacao(bigint) to authenticated;

create index historico_manifestacao_idx on public.historico (((coalesce(dados_novos, dados_antigos) ->> 'manifestacao_id')));

-- ---------------------------------------------------------------------------
-- Lista de manifestações: a visão do painel ganha os campos de filtro.
-- ---------------------------------------------------------------------------

create or replace view public.painel_manifestacoes
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
  d.nome as diretoria,
  av.nome as avaliador,
  m.ano,
  m.sequencial,
  m.cadastrado_em,
  m.assunto_id,
  m.canal_id,
  e.diretoria_id,
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
left join public.encaminhamentos e on e.manifestacao_id = m.id and e.atual
left join public.diretorias d on d.id = e.diretoria_id
left join public.avaliadores av on av.id = e.avaliador_id;
