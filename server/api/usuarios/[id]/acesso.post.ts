// Quem ainda não aceitou o convite recebe outro; quem já tem senha recebe o link de nova senha.
export default defineEventHandler(async (event) => {
  const { auth } = await exigirAdministrador(event)
  const id = getRouterParam(event, 'id')!
  const { data: conta, error } = await auth.getUserById(id)
  if (error || !conta.user?.email) falha(404, 'Usuário não encontrado.')
  const { email, user_metadata: dados } = conta.user

  if (dados?.trocar_senha === true && !conta.user.last_sign_in_at) {
    const { error: erroConvite } = await auth.inviteUserByEmail(email, { data: dados, redirectTo: enderecoRetorno(event) })
    if (erroConvite) erroEmail(erroConvite.message)
    return { tipo: 'convite', email }
  }
  // Pedido direto à API do Auth, sem PKCE: o link precisa funcionar no navegador de quem recebe,
  // não no do administrador.
  const { url, key } = useRuntimeConfig(event).public.supabase
  try {
    await $fetch(`${url}/auth/v1/recover`, {
      method: 'POST',
      query: { redirect_to: enderecoRetorno(event, '/nova-senha') },
      headers: { apikey: key },
      body: { email },
    })
  }
  catch (e) {
    const corpo = (e as { data?: { msg?: string, message?: string } }).data
    erroEmail(corpo?.msg ?? corpo?.message ?? String(e))
  }
  return { tipo: 'senha', email }
})
