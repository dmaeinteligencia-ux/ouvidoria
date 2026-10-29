// Leitura das planilhas mensais antigas para a tela Importar planilha. O formato mudou várias vezes
// entre 2024 e 2026 (colunas novas, nomes diferentes, endereço em uma ou quatro colunas), então as
// colunas são achadas pelo nome do cabeçalho, e não pela posição.
import type { Cell, Worksheet } from 'exceljs'

export interface LinhaLida {
  aba: string
  linha: number
  dados: Record<string, unknown>
}

export interface AbaLida {
  aba: string
  linhas: number
  ignorada?: string
}

// Campos que valem como data (vão para o banco como AAAA-MM-DD).
const DATAS = new Set(['cadastro', 'recebimento', 'encaminhado', 'prazo', 'prazo_prorrogacao', 'resposta_data',
  'reab_pedido', 'reab_prazo', 'reab_resposta_data'])

// Colunas que nem todo formato tem; sem elas, o banco aplica a regra do histórico.
const OPCIONAIS = ['identificacao', 'resolutiva']

export function normalizarCabecalho(texto: string): string {
  return texto.normalize('NFD').replace(/[̀-ͯ]/g, '').toUpperCase().replace(/\s+/g, ' ').trim()
}

// Nome da coluna → campo da área de carga. Depois de "DATA DA REABERTURA", as colunas repetidas
// (ASSUNTO, DATA DA RESPOSTA, prazo) são as da reabertura.
export function campoDaColuna(cabecalho: string, depoisDaReabertura: boolean): string | null {
  const c = normalizarCabecalho(cabecalho)
  if (!c) return null
  if (c === 'LINHA') return 'n'
  if (c === 'NUP') return 'protocolo'
  if (c === 'FALA.BR' || c === 'FALABR') return 'falabr'
  if (c === 'SITUACAO') return 'situacao'
  if (c === 'ENTRADA') return 'entrada'
  if (c === 'TIPO') return 'tipo'
  if (c === 'IDENTIFICACAO') return 'identificacao'
  if (c.startsWith('DATA DE CADASTRO')) return 'cadastro'
  if (c.startsWith('DATA RECEBIDA') || c.startsWith('DATA DE RECEBIMENTO')) return 'recebimento'
  if (c === 'SINTOMA') return 'assunto'
  if (c === 'ENDERECO' || c === 'LOGRADOURO') return 'logradouro'
  if (c === 'NUMERO') return 'numero'
  if (c === 'COMPLEMENTO') return 'complemento'
  if (c === 'BAIRRO') return 'bairro'
  if (c === 'CEP') return 'cep'
  if (c === 'DESCRICAO') return 'descricao'
  if (c === 'ASSUNTO') return depoisDaReabertura ? 'reab_texto' : 'descricao'
  if (c === 'RESUMO') return 'resumo'
  if (c === 'DIRETORIA') return 'diretoria'
  if (c === 'PESSOA ENCAMINHADA') return 'avaliador'
  if (c === 'DATA ENCAMINHADA') return 'encaminhado'
  if (c.startsWith('TEMPO PARA RESPOSTA')) {
    if (c.includes('PRORROGACAO')) return depoisDaReabertura ? 'reab_prazo_prorrogacao' : 'prazo_prorrogacao'
    return depoisDaReabertura ? 'reab_prazo' : 'prazo'
  }
  if (c.startsWith('DATA DA RESPOSTA')) return depoisDaReabertura ? 'reab_resposta_data' : 'resposta_data'
  if (c === 'RESPOSTA') return 'resposta'
  if (c === 'RESOLUTIVIDADE') return 'resolutiva'
  if (c === 'ARQUIVAMENTO') return 'arquivamento'
  if (c === 'DATA DA REABERTURA') return 'reab_pedido'
  if (c === 'SEGUNDA RESPOSTA') return 'reab_resposta'
  if (c.startsWith('OBSERVAC')) return 'observacoes'
  return null
}

export function mapearCabecalho(celulas: string[]): (string | null)[] {
  let depois = false
  const usados = new Set<string>()
  return celulas.map((texto) => {
    const campo = campoDaColuna(texto, depois)
    if (campo === 'reab_pedido') depois = true
    // Coluna repetida fora do padrão: vale a primeira.
    if (!campo || usados.has(campo)) return null
    usados.add(campo)
    return campo
  })
}

function iso(d: Date): string {
  // O exceljs entrega as datas da planilha em UTC.
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`
}

function textoDaCelula(v: Cell['value']): unknown {
  if (v === null || v === undefined) return null
  if (v instanceof Date) return v
  if (typeof v === 'object') {
    if ('result' in v) return textoDaCelula(v.result as Cell['value'])
    if ('richText' in v) return v.richText.map(t => t.text).join('')
    if ('text' in v) return v.text
    if ('error' in v) return null
    return null
  }
  return v
}

export function valorDoCampo(campo: string, bruto: Cell['value']): string | null {
  const v = textoDaCelula(bruto)
  if (v === null || v === undefined) return null
  if (v instanceof Date) return iso(v)
  if (typeof v === 'number') {
    if (DATAS.has(campo) && v > 20000 && v < 80000) {
      // Data guardada como número de série do Excel.
      return iso(new Date(Math.round((v - 25569) * 86400000)))
    }
    return String(v)
  }
  const texto = String(v).trim()
  if (!texto) return null
  if (DATAS.has(campo)) {
    // "00/00/0000" é o marcador de data vazia das planilhas.
    if (/^[0/\s:-]+$/.test(texto)) return null
    const achado = texto.match(/^(\d{1,2})\/(\d{1,2})\/(\d{2}|\d{4})$/)
    if (achado) {
      const [, dia, mes, ano] = achado
      const a = ano!.length === 2 ? `20${ano}` : ano
      return `${a}-${mes!.padStart(2, '0')}-${dia!.padStart(2, '0')}`
    }
  }
  return texto
}

const ESSENCIAIS = ['protocolo', 'falabr', 'descricao', 'assunto', 'situacao']

export function lerAba(aba: Worksheet, arquivo: string): { linhas: LinhaLida[], resumo: AbaLida } {
  const nome = `${arquivo} › ${aba.name}`
  let cabecalho = 0
  for (let i = 1; i <= Math.min(15, aba.rowCount); i++) {
    const valores = aba.getRow(i).values as Cell['value'][]
    if (valores.some(v => typeof v === 'string' && normalizarCabecalho(v) === 'NUP')) {
      cabecalho = i
      break
    }
  }
  if (!cabecalho) return { linhas: [], resumo: { aba: nome, linhas: 0, ignorada: 'sem a coluna NUP no cabeçalho' } }

  const textos: string[] = []
  aba.getRow(cabecalho).eachCell({ includeEmpty: true }, (celula, col) => {
    textos[col] = String(textoDaCelula(celula.value) ?? '')
  })
  const campos = mapearCabecalho(Array.from(textos, t => t ?? ''))
  const presentes = new Set(campos.filter(Boolean))
  const semColuna = OPCIONAIS.filter(c => !presentes.has(c))
  // Sem a coluna LINHA, o número de ordem fica na coluna logo antes da primeira coluna reconhecida.
  const colunaNumero = presentes.has('n') ? -1 : campos.findIndex(c => c) - 1

  const linhas: LinhaLida[] = []
  for (let i = cabecalho + 1; i <= aba.rowCount; i++) {
    const linha = aba.getRow(i)
    const dados: Record<string, unknown> = {}
    campos.forEach((campo, col) => {
      if (!campo) return
      const valor = valorDoCampo(campo, linha.getCell(col).value)
      if (valor !== null) dados[campo] = valor
    })
    if (!ESSENCIAIS.some(c => dados[c] !== undefined)) continue
    if (colunaNumero > 0 && dados.n === undefined) {
      const n = textoDaCelula(linha.getCell(colunaNumero).value)
      if (typeof n === 'number') dados.n = String(n)
    }
    // Data de reabertura na planilha antiga quer dizer reabertura aceita nesse dia.
    if (dados.reab_pedido) {
      dados.reab_data = dados.reab_pedido
      dados.reab_aceita = 'SIM'
    }
    if (semColuna.length) dados._sem_coluna = semColuna
    linhas.push({ aba: nome, linha: i, dados })
  }
  return { linhas, resumo: { aba: nome, linhas: linhas.length } }
}

export async function lerPlanilha(arquivo: File): Promise<{ linhas: LinhaLida[], abas: AbaLida[] }> {
  const { default: ExcelJS } = await import('exceljs')
  const livro = new ExcelJS.Workbook()
  await livro.xlsx.load(await arquivo.arrayBuffer())
  const linhas: LinhaLida[] = []
  const abas: AbaLida[] = []
  livro.eachSheet((aba) => {
    const r = lerAba(aba, arquivo.name)
    linhas.push(...r.linhas)
    abas.push(r.resumo)
  })
  return { linhas, abas }
}

// Erros de valor fora do cadastro, que a tela resolve com uma equivalência.
export const CADASTROS = {
  'Entrada': { tabela: 'canais', lista: 'canais' },
  'Tipo': { tabela: 'tipos_manifestacao', lista: 'tipos' },
  'Identificação': { tabela: 'identificacoes', lista: 'identificacoes' },
  'Assunto': { tabela: 'assuntos', lista: 'assuntos' },
  'Diretoria': { tabela: 'diretorias', lista: 'diretorias' },
  'Motivo de arquivamento': { tabela: 'motivos_arquivamento', lista: 'motivos' },
} as const
export type RotuloCadastro = keyof typeof CADASTROS

export function valorForaDoCadastro(erro: string): { rotulo: RotuloCadastro, valor: string } | null {
  const achado = erro.match(/^(Entrada|Tipo|Identificação|Assunto|Diretoria|Motivo de arquivamento) não encontrad[ao](?: no cadastro)?: "(.*)"$/)
  return achado ? { rotulo: achado[1] as RotuloCadastro, valor: achado[2]! } : null
}

export const jaNoSistema = (erro: string) => /já está no sistema$/.test(erro)
