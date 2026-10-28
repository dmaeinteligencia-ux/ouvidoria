// Lista os usuários do sistema com e-mail e último acesso (do Auth).
export default defineEventHandler(async (event) => {
  const { cliente, auth } = await exigirAdministrador(event)
  const { data: usuarios, error } = await cliente.from('usuarios').select('id, nome, perfil, diretoria_id, ativo').order('nome')
  if (error) falha(500, error.message)
  const { data: contas, error: erroAuth } = await auth.listUsers({ page: 1, perPage: 1000 })
  if (erroAuth) falha(500, erroAuth.message)
  const porId = new Map(contas.users.map(u => [u.id, u]))
  return (usuarios ?? []).map((u) => {
    const conta = porId.get(u.id)
    return {
      ...u,
      email: conta?.email ?? null,
      ultimo_acesso: conta?.last_sign_in_at ?? null,
      // Convite gerado e ainda sem senha escolhida.
      convite_pendente: conta?.user_metadata?.trocar_senha === true,
    }
  })
})
