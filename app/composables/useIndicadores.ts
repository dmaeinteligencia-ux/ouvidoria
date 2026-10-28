import type { Agrupamento } from '~/utils/graficos'
import type { Situacao } from '~/utils/situacao'

// Filtros e dados dos painéis do CI nº 6660/2025. O período é o recebimento pelo DMAE (dia 0).
export interface FiltrosIndicadores {
  inicio: string
  fim: string
  agrupar: Agrupamento
  situacoes: string[]
  tipos: string[]
  canais: string[]
  identificacoes: string[]
  assuntos: string[]
  bairros: string[]
  diretorias: string[]
}

export interface Contagem { nome: string, n: number }
export interface ContagemChave { chave: string, n: number }

export interface Indicadores {
  total: number
  situacao: ContagemChave[]
  evolucao: { periodo: string, n: number }[]
  tipo: Contagem[]
  canal: Contagem[]
  arquivamento: Contagem[]
  prazo_medio: number | null
  respondidas_primeira: number
  evolucao_prazo: { periodo: string, media: number | null }[]
  cumprimento: { no_prazo: number, fora_prazo: number }
  resolutividade: { resolutivas: number, respondidas: number }
  reaberturas: { pedidos: number, aceitas: number }
  satisfacao_resposta: ContagemChave[]
  satisfacao_ouvidoria: ContagemChave[]
  // Só no Painel Gerencial
  assuntos?: Contagem[]
  bairros?: Contagem[]
  sem_bairro?: number
}

export function filtrosIniciais(): FiltrosIndicadores {
  const hoje = hojeBrasilia()
  return {
    inicio: `${hoje.slice(0, 4)}-01-01`,
    fim: hoje,
    agrupar: 'month',
    situacoes: [], tipos: [], canais: [], identificacoes: [], assuntos: [], bairros: [], diretorias: [],
  }
}

const lista = (v: string[]) => (v.length ? v.map(Number) : null)

export function useIndicadores(filtros: FiltrosIndicadores, gerencial: boolean) {
  const supabase = useSupabaseClient()
  return useAsyncData(gerencial ? 'painel-gerencial' : 'painel-geral', async () => {
    const comuns = {
      p_inicio: filtros.inicio,
      p_fim: filtros.fim,
      p_agrupar: filtros.agrupar,
      p_situacoes: filtros.situacoes.length ? filtros.situacoes as Situacao[] : null,
      p_tipos: lista(filtros.tipos),
      p_canais: lista(filtros.canais),
      p_identificacoes: lista(filtros.identificacoes),
    }
    const { data, error } = gerencial
      ? await supabase.rpc('painel_gerencial', {
          ...comuns,
          p_assuntos: lista(filtros.assuntos),
          p_bairros: lista(filtros.bairros),
          p_diretorias: lista(filtros.diretorias),
        })
      : await supabase.rpc('painel_geral', comuns)
    if (error) throw error
    return data as unknown as Indicadores
  }, { watch: [filtros] })
}
