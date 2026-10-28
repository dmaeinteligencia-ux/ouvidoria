// Listas de cadastro usadas nos formulários e filtros das manifestações.
export interface ItemLista { id: number, nome: string }
export interface Canal extends ItemLista { nome_painel: string, exige_protocolo_falabr: boolean }
export interface Avaliador extends ItemLista { diretoria_id: number }

export interface Listas {
  canais: Canal[]
  tipos: ItemLista[]
  identificacoes: ItemLista[]
  assuntos: ItemLista[]
  diretorias: ItemLista[]
  avaliadores: Avaliador[]
  motivos: ItemLista[]
  bairros: ItemLista[]
}

export function useListas() {
  const supabase = useSupabaseClient()

  return useAsyncData('listas', async (): Promise<Listas> => {
    type Tabela = 'canais' | 'tipos_manifestacao' | 'identificacoes' | 'assuntos' | 'diretorias' | 'avaliadores' | 'motivos_arquivamento' | 'bairros'
    const ativos = <T>(tabela: Tabela, colunas = 'id, nome') =>
      supabase.from(tabela).select(colunas).eq('ativo', true).order('nome').then(({ data, error }) => {
        if (error) throw error
        return (data ?? []) as T[]
      })
    const [canais, tipos, identificacoes, assuntos, diretorias, avaliadores, motivos, bairros] = await Promise.all([
      ativos<Canal>('canais', 'id, nome, nome_painel, exige_protocolo_falabr'),
      ativos<ItemLista>('tipos_manifestacao'),
      ativos<ItemLista>('identificacoes'),
      ativos<ItemLista>('assuntos'),
      ativos<ItemLista>('diretorias'),
      ativos<Avaliador>('avaliadores', 'id, nome, diretoria_id'),
      ativos<ItemLista>('motivos_arquivamento'),
      ativos<ItemLista>('bairros'),
    ])
    return { canais, tipos, identificacoes, assuntos, diretorias, avaliadores, motivos, bairros }
  })
}

export function nomePorId(lista: ItemLista[] | undefined, id: number | null | undefined): string {
  return lista?.find(i => i.id === id)?.nome ?? ''
}
