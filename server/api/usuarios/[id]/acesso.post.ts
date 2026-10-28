// Novo link de acesso: para quem ainda não aceitou o convite (o middleware leva a /nova-senha) ou
// para quem precisa de outra senha.
export default defineEventHandler(async (event) => {
  const { auth } = await exigirAdministrador(event)
  const id = getRouterParam(event, 'id')!
  const { data: conta, error } = await auth.getUserById(id)
  if (error || !conta.user?.email) falha(404, 'Usuário não encontrado.')
  const { email } = conta.user
  const pendente = conta.user.user_metadata?.trocar_senha === true
  const { link } = await gerarLink(auth, {
    type: 'recovery', email, redirectTo: enderecoRetorno(event, pendente ? undefined : '/nova-senha'),
  })
  return { tipo: pendente ? 'convite' : 'senha', email, link }
})
