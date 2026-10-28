// Altera nome, perfil e diretoria, ou desativa/reativa. Desativado não entra no sistema (login
// bloqueado no Auth) e perde o acesso aos dados (perfil_atual exige ativo).
export default defineEventHandler(async (event) => {
  const { id: eu, cliente, auth } = await exigirAdministrador(event)
  const id = getRouterParam(event, 'id')!
  const corpo = await readBody<{ nome?: string, perfil?: string, diretoria_id?: number | null, ativo?: boolean }>(event)

  const { data: atual, error } = await cliente.from('usuarios').select('id, nome, perfil, diretoria_id, ativo').eq('id', id).maybeSingle()
  if (error) falha(500, error.message)
  if (!atual) falha(404, 'Usuário não encontrado.')

  const mudancas: { nome?: string, perfil?: PerfilUsuario, diretoria_id?: number | null, ativo?: boolean } = {}
  if (corpo.nome !== undefined) {
    const nome = corpo.nome.trim().replace(/\s+/g, ' ')
    if (!nome) falha(400, 'Informe o nome.')
    mudancas.nome = nome
  }
  if (corpo.perfil !== undefined) Object.assign(mudancas, validarPerfil(corpo.perfil, corpo.diretoria_id))
  if (corpo.ativo !== undefined) mudancas.ativo = corpo.ativo

  // O administrador não tira o próprio acesso, para o sistema nunca ficar sem administrador.
  const perdeAdmin = (mudancas.perfil && mudancas.perfil !== 'administrador') || mudancas.ativo === false
  if (id === eu && perdeAdmin) falha(400, 'Você não pode desativar nem mudar o perfil do seu próprio usuário. Peça a outro administrador.')

  const { error: erroUpdate } = await cliente.from('usuarios').update(mudancas).eq('id', id)
  if (erroUpdate) falha(500, erroUpdate.message)

  if (mudancas.ativo !== undefined && mudancas.ativo !== atual.ativo) {
    const { error: erroAuth } = await auth.updateUserById(id, { ban_duration: mudancas.ativo ? 'none' : '876000h' })
    if (erroAuth) {
      await cliente.from('usuarios').update({ ativo: atual.ativo }).eq('id', id)
      falha(500, erroAuth.message)
    }
  }
  return { ok: true }
})
