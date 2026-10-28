-- Cadastro, numeração, ciclo original, encaminhamento, histórico e acesso por perfil.

insert into auth.users (id) values
  ('00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-000000000002');

insert into public.usuarios (id, nome, perfil, diretoria_id) values
  ('00000000-0000-0000-0000-000000000001', 'Equipe Ouvidoria', 'ouvidoria', null),
  ('00000000-0000-0000-0000-000000000002', 'Diretor Financeiro', 'diretor',
   (select id from public.diretorias where nome = 'DIRETORIA FINANCEIRA'));

insert into public.avaliadores (nome, diretoria_id)
values ('SIMONE PACHECO', (select id from public.diretorias where nome = 'DIRETORIA FINANCEIRA'));

grant usage on schema public to authenticated;
grant select, insert, update on all tables in schema public to authenticated;

create function pg_temp.nova(protocolo text, momento timestamptz) returns bigint
language sql as $$
  insert into public.manifestacoes
    (protocolo_mgouv, canal_id, tipo_id, identificacao_id, cadastrado_em, assunto_id, descricao)
  values (
    protocolo,
    (select id from public.canais where nome = 'TELEFONE'),
    (select id from public.tipos_manifestacao where nome = 'RECLAMAÇÃO'),
    (select id from public.identificacoes where nome = 'IDENTIFICADA'),
    momento,
    (select id from public.assuntos where nome = 'FALTA DE ÁGUA'),
    'Texto da manifestação.'
  )
  returning id;
$$;

do $$
declare
  m1 bigint;
  m2 bigint;
  falhou boolean;
begin
  -- RN03 / RN04: número anual sequencial e dia 0 calculado
  m1 := pg_temp.nova('1234567890123', '2025-09-15 18:00-03');
  m2 := pg_temp.nova('1234567890124', '2025-09-16 09:00-03');
  assert (select numero from public.manifestacoes where id = m1) = '2025/0001', 'primeiro número do ano';
  assert (select numero from public.manifestacoes where id = m2) = '2025/0002', 'segundo número do ano';
  assert (select dia_zero from public.manifestacoes where id = m1) = '2025-09-16', 'dia 0 calculado com corte';
  assert (select count(*) from public.ciclos where manifestacao_id = m1 and numero = 0) = 1, 'ciclo original criado';
  assert (select prazo from public.ciclos_prazos where manifestacao_id = m1) = '2025-09-23', 'prazo do ciclo original';

  -- RN02: formato do protocolo MG-OUV
  falhou := false;
  begin
    perform pg_temp.nova('123', '2025-09-15 10:00-03');
  exception when check_violation then falhou := true;
  end;
  assert falhou, 'protocolo MG-OUV precisa de 13 dígitos';

  -- RN02: canal Fala.BR exige protocolo Fala.BR
  falhou := false;
  begin
    insert into public.manifestacoes
      (protocolo_mgouv, canal_id, tipo_id, identificacao_id, cadastrado_em, assunto_id, descricao)
    values ('1234567890125', (select id from public.canais where nome = 'FALA.BR'),
            1, 1, '2025-09-15 10:00-03', 1, 'x');
  exception when raise_exception then falhou := true;
  end;
  assert falhou, 'Fala.BR sem protocolo Fala.BR é recusado';

  -- RN04: dia 0 diferente do calculado exige justificativa
  falhou := false;
  begin
    update public.manifestacoes set dia_zero = '2025-09-18' where id = m1;
  exception when raise_exception then falhou := true;
  end;
  assert falhou, 'correção do dia 0 sem justificativa é recusada';

  -- RN18: arquivada exige motivo e situação Respondida
  falhou := false;
  begin
    update public.manifestacoes set arquivada = true where id = m1;
  exception when check_violation or raise_exception then falhou := true;
  end;
  assert falhou, 'arquivada sem motivo é recusada';

  -- RN14: avaliador precisa pertencer à diretoria
  falhou := false;
  begin
    insert into public.encaminhamentos (manifestacao_id, diretoria_id, avaliador_id, enviado_em)
    values (m1, (select id from public.diretorias where nome = 'DIRETORIA ADMINISTRATIVA'),
            (select id from public.avaliadores where nome = 'SIMONE PACHECO'), '2025-09-16');
  exception when raise_exception then falhou := true;
  end;
  assert falhou, 'avaliador de outra diretoria é recusado';

  -- RN16: novo encaminhamento substitui o anterior
  insert into public.encaminhamentos (manifestacao_id, diretoria_id, avaliador_id, enviado_em)
  select m1, a.diretoria_id, a.id, '2025-09-16' from public.avaliadores a where a.nome = 'SIMONE PACHECO';
  insert into public.encaminhamentos (manifestacao_id, diretoria_id, avaliador_id, enviado_em)
  select m1, a.diretoria_id, a.id, '2025-09-17' from public.avaliadores a where a.nome = 'SIMONE PACHECO';
  assert (select count(*) from public.encaminhamentos where manifestacao_id = m1) = 2, 'dois encaminhamentos guardados';
  assert (select count(*) from public.encaminhamentos where manifestacao_id = m1 and atual) = 1, 'só um atual';

  -- RN23: histórico registrado
  assert (select count(*) from public.historico where tabela = 'manifestacoes' and registro_id = m1) >= 1,
    'histórico da manifestação';
end;
$$;

-- Acesso: a Ouvidoria vê as manifestações; o diretor não vê as tabelas.
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
do $$ begin
  assert (select count(*) from public.manifestacoes) = 2, 'Ouvidoria vê as manifestações';
end $$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
do $$ begin
  assert (select count(*) from public.manifestacoes) = 0, 'diretor não lê a tabela de manifestações';
  assert (select count(*) from public.assuntos) > 0, 'diretor lê os cadastros';
end $$;
reset role;
