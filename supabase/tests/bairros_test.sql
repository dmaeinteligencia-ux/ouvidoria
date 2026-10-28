-- Posição dos bairros no mapa do Painel Gerencial: só o administrador marca, e só dentro do município.

insert into auth.users (id) values
  ('00000000-0000-0000-0000-000000000041'),
  ('00000000-0000-0000-0000-000000000042');
insert into public.usuarios (id, nome, perfil, diretoria_id) values
  ('00000000-0000-0000-0000-000000000041', 'Admin', 'administrador', null),
  ('00000000-0000-0000-0000-000000000042', 'Ana Ouvidoria', 'ouvidoria', null);
insert into public.bairros (nome) values ('TIBERY'), ('BRASIL');

grant usage on schema public to anon, authenticated;
grant select, insert, update on all tables in schema public to authenticated;

-- Latitude sem longitude, ou um ponto fora de Uberlândia, não entram.
do $$
declare falhou boolean;
begin
  falhou := false;
  begin update public.bairros set latitude = -18.92 where nome = 'TIBERY';
  exception when check_violation then falhou := true; end;
  assert falhou, 'posição incompleta recusada';

  falhou := false;
  begin update public.bairros set latitude = -23.55, longitude = -46.63 where nome = 'TIBERY';
  exception when check_violation then falhou := true; end;
  assert falhou, 'posição fora do município recusada';
end $$;

-- A equipe da Ouvidoria não altera a posição (a política de escrita é do administrador).
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000042';
update public.bairros set latitude = -18.93, longitude = -48.24 where nome = 'TIBERY';
reset role;
do $$ begin
  assert (select latitude from public.bairros where nome = 'TIBERY') is null, 'ouvidoria não marca posição';
end $$;

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000041';
update public.bairros set latitude = -18.93, longitude = -48.24 where nome = 'TIBERY';
update public.bairros set latitude = null, longitude = null where nome = 'BRASIL';
reset role;
do $$ begin
  assert (select latitude from public.bairros where nome = 'TIBERY') = -18.93, 'administrador marca posição';
end $$;
