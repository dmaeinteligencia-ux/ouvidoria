// Cadastra o perfil e manda o convite por e-mail; no link a pessoa escolhe a própria senha.
export default defineEventHandler(async (event) => {
  const { cliente, auth } = await exigirAdministrador(event)
  const corpo = await readBody<{ nome?: string, email?: string, perfil?: string, diretoria_id?: number | null }>(event)
  const nome = (corpo.nome ?? '').trim().replace(/\s+/g, ' ')
  const email = (corpo.email ?? '').trim().toLowerCase()
  if (!nome) falha(400, 'Informe o nome.')
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) falha(400, 'Informe um e-mail válido.')
  const perfil = validarPerfil(corpo.perfil, corpo.diretoria_id)

  // O convite a um e-mail já cadastrado reaproveitaria a conta existente; recusa antes.
  const { data: contas, error: erroLista } = await auth.listUsers({ page: 1, perPage: 1000 })
  if (erroLista) falha(500, erroLista.message)
  if (contas.users.some(u => u.email?.toLowerCase() === email)) falha(409, 'Já existe um usuário com esse e-mail.')

  const { data, error } = await auth.inviteUserByEmail(email, {
    data: { nome, trocar_senha: true }, redirectTo: enderecoRetorno(event),
  })
  if (error) erroEmail(error.message)
  const { error: erroPerfil } = await cliente.from('usuarios').insert({ id: data.user.id, nome, ...perfil })
  if (erroPerfil) {
    await auth.deleteUser(data.user.id)
    falha(500, erroPerfil.message)
  }
  return { id: data.user.id, email }
})
