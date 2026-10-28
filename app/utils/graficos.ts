// Cores e formatos dos gráficos dos painéis (validados para daltonismo na ordem abaixo).
// As cores de texto das situações (tailwind) são escuras demais para preencher gráficos;
// aqui ficam tons próprios, um por situação, na ordem em que aparecem na rosca.
export const CORES_SITUACAO: Record<string, string> = {
  respondida: '#008300',
  em_tratamento: '#2A78D6',
  prorrogada: '#EDA100',
  aguardando_complementacao: '#6250D6',
  vencida: '#E34948',
  reaberta: '#1BAF7A',
}
export const ORDEM_SITUACAO = ['respondida', 'em_tratamento', 'prorrogada', 'aguardando_complementacao', 'vencida', 'reaberta']

// Uma série só: uma cor para todas as barras.
export const COR_SERIE = '#2A78D6'
export const COR_PRAZO = { no_prazo: '#008300', fora_prazo: '#E34948' }

// Satisfação: escala divergente, azul (satisfeito) ↔ vermelho (insatisfeito), cinza no meio.
export const NIVEIS_SATISFACAO = [
  { chave: 'muito_satisfeito', nome: 'Muito satisfeito', cor: '#1C5CAB' },
  { chave: 'satisfeito', nome: 'Satisfeito', cor: '#6DA7EC' },
  { chave: 'regular', nome: 'Regular', cor: '#B9B8B2' },
  { chave: 'insatisfeito', nome: 'Insatisfeito', cor: '#EC8F8E' },
  { chave: 'muito_insatisfeito', nome: 'Muito insatisfeito', cor: '#B8302F' },
]

const numero = new Intl.NumberFormat('pt-BR')
const decimal = new Intl.NumberFormat('pt-BR', { minimumFractionDigits: 1, maximumFractionDigits: 1 })

export function formatarNumero(n: number): string {
  return numero.format(n)
}

export function formatarDecimal(n: number): string {
  return decimal.format(n)
}

export function percentual(parte: number, total: number): string {
  if (!total) return '0%'
  const p = (parte / total) * 100
  return `${p >= 10 || Number.isInteger(p) ? Math.round(p) : decimal.format(p)}%`
}

export type Agrupamento = 'day' | 'month' | 'year'

const MESES = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez']

// Rótulo curto do período: "15/09", "set/25" ou "2025".
export function rotuloPeriodo(iso: string, agrupar: Agrupamento): string {
  const [a, m, d] = iso.slice(0, 10).split('-')
  if (agrupar === 'year') return a!
  if (agrupar === 'month') return `${MESES[Number(m) - 1]}/${a!.slice(2)}`
  return `${d}/${m}`
}

export function rotuloPeriodoLongo(iso: string, agrupar: Agrupamento): string {
  const [a, m, d] = iso.slice(0, 10).split('-')
  if (agrupar === 'year') return a!
  if (agrupar === 'month') return `${MESES[Number(m) - 1]} de ${a}`
  return `${d}/${m}/${a}`
}

// Marcas limpas no eixo: 0, 5, 10… até cobrir o máximo.
export function marcasEixo(maximo: number, quantas = 4): number[] {
  if (maximo <= 0) return [0, 1]
  const bruto = maximo / quantas
  const potencia = 10 ** Math.floor(Math.log10(bruto))
  const passo = [1, 2, 2.5, 5, 10].map(f => f * potencia).find(p => p >= bruto)!
  const marcas: number[] = []
  for (let v = 0; v < maximo + passo; v += passo) marcas.push(Number(v.toFixed(6)))
  return marcas
}
