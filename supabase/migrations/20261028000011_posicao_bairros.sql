-- Posição de cada bairro, usada no mapa de bolhas do Painel Gerencial.
-- Enquanto o contorno oficial dos bairros não chega, cada bairro é um ponto marcado pelo administrador.
-- O limite cobre o município de Uberlândia, com os distritos.
alter table public.bairros
  add column latitude numeric(9, 6),
  add column longitude numeric(9, 6),
  add constraint bairros_posicao_completa check ((latitude is null) = (longitude is null)),
  add constraint bairros_posicao_no_municipio check (
    latitude is null or (latitude between -19.60 and -18.40 and longitude between -48.95 and -47.60));
