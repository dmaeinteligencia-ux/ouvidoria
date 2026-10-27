-- Perfis e políticas de acesso (RLS).
-- Administrador e Ouvidoria operam o sistema; Diretor verá só o Painel Gerencial
-- da própria diretoria (por funções agregadas, na Fase 4); o público não acessa tabelas.

create function public.perfil_atual()
returns public.perfil_usuario
language sql
stable
security definer
set search_path = ''
as $$
  select u.perfil from public.usuarios u where u.id = auth.uid() and u.ativo;
$$;

create function public.eh_equipe_ouvidoria()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(public.perfil_atual() in ('administrador', 'ouvidoria'), false);
$$;

create function public.eh_administrador()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(public.perfil_atual() = 'administrador', false);
$$;

-- Cadastros: leitura por qualquer usuário logado; escrita só pelo administrador.
do $$
declare
  t text;
begin
  foreach t in array array[
    'canais', 'tipos_manifestacao', 'identificacoes', 'assuntos', 'diretorias',
    'avaliadores', 'motivos_arquivamento', 'bairros', 'feriados'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy leitura on public.%I for select to authenticated using (true)', t);
    execute format(
      'create policy escrita_admin on public.%I for all to authenticated
         using (public.eh_administrador()) with check (public.eh_administrador())', t);
  end loop;
end;
$$;

-- A Ouvidoria pode incluir bairros novos ao cadastrar uma manifestação.
create policy inclusao_ouvidoria on public.bairros
for insert to authenticated with check (public.eh_equipe_ouvidoria());

-- Usuários: cada um vê o próprio registro; o administrador gerencia todos.
alter table public.usuarios enable row level security;
create policy proprio on public.usuarios
for select to authenticated using (id = auth.uid() or public.eh_administrador());
create policy gestao_admin on public.usuarios
for all to authenticated
using (public.eh_administrador()) with check (public.eh_administrador());

-- Manifestações e etapas: só a equipe da Ouvidoria. Sem política de exclusão (RN23).
do $$
declare
  t text;
begin
  foreach t in array array[
    'manifestacoes', 'ciclos', 'complementacoes', 'encaminhamentos', 'pedidos_reabertura'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy leitura_ouvidoria on public.%I for select to authenticated
         using (public.eh_equipe_ouvidoria())', t);
    execute format(
      'create policy inclusao_ouvidoria on public.%I for insert to authenticated
         with check (public.eh_equipe_ouvidoria())', t);
    execute format(
      'create policy alteracao_ouvidoria on public.%I for update to authenticated
         using (public.eh_equipe_ouvidoria()) with check (public.eh_equipe_ouvidoria())', t);
  end loop;
end;
$$;

-- Histórico: só leitura pela equipe; gravação apenas pelo gatilho.
alter table public.historico enable row level security;
create policy leitura_ouvidoria on public.historico
for select to authenticated using (public.eh_equipe_ouvidoria());
