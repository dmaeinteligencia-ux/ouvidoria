export type Perfil = 'administrador' | 'ouvidoria' | 'diretor'

export interface UsuarioSistema {
  id: string
  nome: string
  perfil: Perfil
  diretoria_id: number | null
}

// Perfil do usuário logado, lido da tabela public.usuarios. O administrador enxerga todos os
// usuários (RLS), por isso o filtro pelo id do login.
export function usePerfil() {
  const supabase = useSupabaseClient()
  const user = useSupabaseUser()

  return useAsyncData('perfil', async () => {
    if (!user.value?.sub) return null
    const { data, error } = await supabase
      .from('usuarios')
      .select('id, nome, perfil, diretoria_id')
      .eq('id', user.value.sub)
      .eq('ativo', true)
      .maybeSingle()
    if (error) throw error
    return data as UsuarioSistema | null
  }, { watch: [user] })
}
