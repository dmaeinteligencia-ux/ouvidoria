import type { H3Event } from 'h3'
import { serverSupabaseClient, serverSupabaseServiceRole, serverSupabaseUser } from '#supabase/server'
import type { Database } from '~~/app/types/database.types'

export type PerfilUsuario = Database['public']['Enums']['perfil_usuario']
export const PERFIS: PerfilUsuario[] = ['administrador', 'ouvidoria', 'diretor']

// Só o administrador ativo gerencia usuários. As alterações em public.usuarios usam o cliente do
// próprio administrador (RLS e histórico); a chave secreta fica restrita às operações do Auth.
export async function exigirAdministrador(event: H3Event) {
  const claims = await serverSupabaseUser(event).catch(() => null)
  if (!claims?.sub) falha(401, 'Entre de novo no sistema.')
  const cliente = await serverSupabaseClient<Database>(event)
  const { data: admin, error } = await cliente.rpc('eh_administrador')
  if (error) falha(500, error.message)
  if (!admin) falha(403, 'Só o administrador gerencia usuários.')
  let auth
  try {
    auth = serverSupabaseServiceRole<Database>(event).auth.admin
  }
  catch {
    falha(500, 'Falta configurar a chave secreta do Supabase (NUXT_SUPABASE_SECRET_KEY) na Vercel.')
  }
  return { id: claims.sub as string, cliente, auth }
}

// Endereço do link entregue: /confirmar valida o código quando a pessoa clica em Continuar e segue
// para `proximo`; o middleware leva quem ainda não escolheu senha para /nova-senha.
export function enderecoRetorno(event: H3Event, proximo?: string): string {
  const volta = new URL('/confirmar', getRequestURL(event).origin)
  if (proximo) volta.searchParams.set('proximo', proximo)
  return volta.toString()
}

// Sem SMTP próprio, o sistema não manda e-mail: gera o link e o administrador o repassa à pessoa.
// O link aponta para /confirmar com o código (token_hash), e não para o /verify do Supabase: a
// prévia de link do WhatsApp, do Teams e dos filtros de e-mail abre o endereço antes da pessoa e
// gastaria o código de uso único. O código só é usado no clique em Continuar.
// Vale pelo tempo de "Email OTP Expiration" do Supabase (padrão 1 hora).
export async function gerarLink(
  auth: ReturnType<typeof serverSupabaseServiceRole>['auth']['admin'],
  params: { type: 'invite', email: string, data: Record<string, unknown>, redirectTo: string } | { type: 'recovery', email: string, redirectTo: string },
): Promise<{ link: string, userId: string }> {
  const { data, error } = params.type === 'invite'
    ? await auth.generateLink({ type: 'invite', email: params.email, options: { data: params.data, redirectTo: params.redirectTo } })
    : await auth.generateLink({ type: 'recovery', email: params.email, options: { redirectTo: params.redirectTo } })
  if (error) {
    if (/already|registered|exists/i.test(error.message)) falha(409, 'Já existe um usuário com esse e-mail.')
    falha(500, error.message)
  }
  const link = new URL(params.redirectTo)
  link.searchParams.set('codigo', data.properties.hashed_token)
  link.searchParams.set('tipo', params.type)
  return { link: link.toString(), userId: data.user.id }
}

export function falha(statusCode: number, message: string): never {
  throw createError({ statusCode, message })
}

// Avaliador (perfil diretor no banco) precisa de diretoria; os demais perfis não têm.
export function validarPerfil(perfil: unknown, diretoriaId: unknown): { perfil: PerfilUsuario, diretoria_id: number | null } {
  if (!PERFIS.includes(perfil as PerfilUsuario)) falha(400, 'Escolha o perfil.')
  if (perfil === 'diretor') {
    const d = Number(diretoriaId)
    if (!Number.isInteger(d) || d <= 0) falha(400, 'Escolha a diretoria do avaliador.')
    return { perfil: 'diretor', diretoria_id: d }
  }
  return { perfil: perfil as PerfilUsuario, diretoria_id: null }
}
