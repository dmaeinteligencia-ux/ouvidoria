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

// Volta do link do e-mail: /confirmar abre a sessão (tokens no endereço) e segue para `proximo`;
// o middleware leva quem ainda não escolheu senha para /nova-senha.
export function enderecoRetorno(event: H3Event, proximo?: string): string {
  const volta = new URL('/confirmar', getRequestURL(event).origin)
  if (proximo) volta.searchParams.set('proximo', proximo)
  return volta.toString()
}

// Erros de envio de e-mail do Supabase Auth em linguagem da tela.
export function erroEmail(mensagem: string): never {
  if (/already|registered|exists/i.test(mensagem)) falha(409, 'Já existe um usuário com esse e-mail.')
  if (/not authorized|smtp|sending|rate limit/i.test(mensagem)) {
    falha(502, 'O Supabase não conseguiu enviar o e-mail. Confira o SMTP do DMAE em Authentication › Emails no Supabase (o envio padrão só entrega para a equipe do projeto e poucos por hora).')
  }
  falha(500, mensagem)
}

export function falha(statusCode: number, message: string): never {
  throw createError({ statusCode, message })
}

// Diretor precisa de diretoria; os demais perfis não têm.
export function validarPerfil(perfil: unknown, diretoriaId: unknown): { perfil: PerfilUsuario, diretoria_id: number | null } {
  if (!PERFIS.includes(perfil as PerfilUsuario)) falha(400, 'Escolha o perfil.')
  if (perfil === 'diretor') {
    const d = Number(diretoriaId)
    if (!Number.isInteger(d) || d <= 0) falha(400, 'Escolha a diretoria do diretor.')
    return { perfil: 'diretor', diretoria_id: d }
  }
  return { perfil: perfil as PerfilUsuario, diretoria_id: null }
}
