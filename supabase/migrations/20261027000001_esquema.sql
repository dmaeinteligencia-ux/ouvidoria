-- Esquema do controle interno da Ouvidoria do DMAE.
-- Regras de negócio citadas como RNxx: ver o documento "Sistema da Ouvidoria DMAE: plano e regras de negócio".

-- ---------------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------------

create type public.situacao_manifestacao as enum (
  'aguardando_complementacao',
  'em_tratamento',
  'prorrogada',
  'vencida',
  'respondida',
  'reaberta'
);

create type public.perfil_usuario as enum ('administrador', 'ouvidoria', 'diretor');

create type public.nivel_satisfacao as enum (
  'muito_satisfeito',
  'satisfeito',
  'regular',
  'insatisfeito',
  'muito_insatisfeito'
);

create type public.tipo_feriado as enum ('nacional', 'estadual', 'municipal', 'ponto_facultativo');

create type public.origem_complementacao as enum ('ouvidoria', 'diretoria');

-- ---------------------------------------------------------------------------
-- Cadastros (aba CAMPOS da planilha)
-- ---------------------------------------------------------------------------

create table public.canais (
  id smallint generated always as identity primary key,
  nome text not null unique,
  nome_painel text not null,          -- nome usado nos painéis (CI nº 6660/2025)
  exige_protocolo_falabr boolean not null default false,
  ativo boolean not null default true
);

create table public.tipos_manifestacao (
  id smallint generated always as identity primary key,
  nome text not null unique,
  ativo boolean not null default true
);

create table public.identificacoes (
  id smallint generated always as identity primary key,
  nome text not null unique,
  ativo boolean not null default true
);

create table public.assuntos (
  id smallint generated always as identity primary key,
  nome text not null unique,
  ativo boolean not null default true
);

create table public.diretorias (
  id smallint generated always as identity primary key,
  nome text not null unique,
  ativo boolean not null default true
);

-- RN15: cada avaliador pertence a uma única diretoria; avaliadores não têm login.
create table public.avaliadores (
  id smallint generated always as identity primary key,
  nome text not null,
  diretoria_id smallint not null references public.diretorias (id),
  ativo boolean not null default true,
  unique (nome, diretoria_id)
);

create table public.motivos_arquivamento (
  id smallint generated always as identity primary key,
  nome text not null unique,
  ativo boolean not null default true
);

create table public.bairros (
  id integer generated always as identity primary key,
  nome text not null unique,
  ativo boolean not null default true
);

-- RN09: dias não úteis além de sábados e domingos.
create table public.feriados (
  data date primary key,
  descricao text not null,
  tipo public.tipo_feriado not null
);

-- ---------------------------------------------------------------------------
-- Usuários e perfis
-- ---------------------------------------------------------------------------

create table public.usuarios (
  id uuid primary key references auth.users (id) on delete cascade,
  nome text not null,
  perfil public.perfil_usuario not null,
  diretoria_id smallint references public.diretorias (id),
  ativo boolean not null default true,
  -- O diretor só enxerga a própria diretoria no Painel Gerencial.
  constraint diretor_tem_diretoria check (perfil <> 'diretor' or diretoria_id is not null)
);

-- ---------------------------------------------------------------------------
-- Manifestações
-- ---------------------------------------------------------------------------

create table public.manifestacoes (
  id bigint generated always as identity primary key,
  ano smallint not null,
  sequencial integer not null,
  numero text generated always as (ano::text || '/' || lpad(sequencial::text, 4, '0')) stored,
  protocolo_mgouv text unique,
  protocolo_falabr text unique,
  canal_id smallint not null references public.canais (id),
  tipo_id smallint not null references public.tipos_manifestacao (id),
  identificacao_id smallint not null references public.identificacoes (id),
  cadastrado_em timestamptz not null,               -- data e hora do cadastro pelo manifestante
  dia_zero date not null,                           -- RN04: recebimento pelo DMAE
  dia_zero_corrigido_justificativa text,
  assunto_id smallint not null references public.assuntos (id),
  logradouro text,
  numero_imovel text,
  complemento text,
  bairro_id integer references public.bairros (id),
  cep text,
  descricao text not null,
  situacao public.situacao_manifestacao not null default 'em_tratamento',
  resolutiva boolean,
  arquivada boolean not null default false,
  motivo_arquivamento_id smallint references public.motivos_arquivamento (id),
  duplicada_de bigint references public.manifestacoes (id),
  satisfacao_resposta public.nivel_satisfacao,
  satisfacao_ouvidoria public.nivel_satisfacao,
  observacoes text,
  criado_em timestamptz not null default now(),
  criado_por uuid references auth.users (id) default auth.uid(),
  atualizado_em timestamptz not null default now(),
  unique (ano, sequencial),
  -- RN02
  constraint tem_protocolo check (protocolo_mgouv is not null or protocolo_falabr is not null),
  constraint protocolo_mgouv_formato check (protocolo_mgouv ~ '^\d{13}$'),
  constraint protocolo_falabr_formato check (protocolo_falabr ~ '^\d{5}\.\d{4}\.\d{6}-\d{2}$'),
  constraint cep_formato check (cep ~ '^\d{5}-\d{3}$'),
  -- RN18
  constraint arquivada_tem_motivo check (not arquivada or motivo_arquivamento_id is not null),
  constraint motivo_so_se_arquivada check (arquivada or motivo_arquivamento_id is null),
  constraint arquivada_e_respondida check (not arquivada or situacao = 'respondida')
);

create index manifestacoes_dia_zero_idx on public.manifestacoes (dia_zero);
create index manifestacoes_situacao_idx on public.manifestacoes (situacao);

-- Ciclo de resposta: número 0 = original; 1, 2, ... = reaberturas (RN22).
create table public.ciclos (
  id bigint generated always as identity primary key,
  manifestacao_id bigint not null references public.manifestacoes (id) on delete cascade,
  numero smallint not null check (numero >= 0),
  dia_zero date not null,
  prorrogado boolean not null default false,
  prorrogacao_registrada_em timestamptz,
  prorrogacao_justificativa text,
  respondido_em date,
  resposta text,
  criado_em timestamptz not null default now(),
  unique (manifestacao_id, numero),
  constraint prorrogacao_justificada check (not prorrogado or prorrogacao_justificativa is not null),
  constraint resposta_completa check ((respondido_em is null) = (resposta is null))
);

-- RN10 / RN11
create table public.complementacoes (
  id bigint generated always as identity primary key,
  ciclo_id bigint not null references public.ciclos (id) on delete cascade,
  origem public.origem_complementacao not null,
  pedido_em date not null,
  limite date generated always as (pedido_em + 10) stored,   -- 10 dias corridos
  complementado_em timestamptz,
  arquivada_por_falta boolean not null default false,
  criado_em timestamptz not null default now(),
  constraint encerramento_unico check (not (arquivada_por_falta and complementado_em is not null))
);

-- RN14 / RN16: tramitação real acontece no MG-OUV; aqui só o registro.
create table public.encaminhamentos (
  id bigint generated always as identity primary key,
  manifestacao_id bigint not null references public.manifestacoes (id) on delete cascade,
  diretoria_id smallint not null references public.diretorias (id),
  avaliador_id smallint not null references public.avaliadores (id),
  enviado_em date not null,
  atual boolean not null default true,
  criado_em timestamptz not null default now()
);

create unique index encaminhamento_atual_unico on public.encaminhamentos (manifestacao_id) where atual;

-- RN20 / RN21
create table public.pedidos_reabertura (
  id bigint generated always as identity primary key,
  manifestacao_id bigint not null references public.manifestacoes (id) on delete cascade,
  recebido_em timestamptz not null,
  texto text not null,
  aceito boolean,
  decidido_em timestamptz,
  justificativa_decisao text,
  ciclo_id bigint references public.ciclos (id),
  criado_em timestamptz not null default now(),
  constraint decisao_completa check ((aceito is null) = (decidido_em is null)),
  constraint aceito_gera_ciclo check (aceito is not true or ciclo_id is not null)
);

-- RN23: histórico de todas as alterações.
create table public.historico (
  id bigint generated always as identity primary key,
  tabela text not null,
  registro_id bigint not null,
  acao text not null,
  dados_antigos jsonb,
  dados_novos jsonb,
  usuario_id uuid default auth.uid(),
  em timestamptz not null default now()
);

create index historico_registro_idx on public.historico (tabela, registro_id);
