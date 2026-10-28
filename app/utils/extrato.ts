// Extrato mensal em Excel no formato da planilha "CONTROLE DE MANIFESTAÇÕES OUVIDORIA.xlsx":
// título, mês, cabeçalho na linha 5, linha de explicação na 6 e as manifestações a partir da 7.
export interface LinhaExtrato {
  numero: string
  situacao: string
  protocolo_mgouv: string | null
  canal: string
  protocolo_falabr: string | null
  tipo: string
  identificacao: string
  cadastrado_em: string
  recebido_em: string
  assunto: string
  logradouro: string | null
  numero_imovel: string | null
  complemento: string | null
  bairro: string | null
  cep: string | null
  descricao: string
  diretoria: string | null
  avaliador: string | null
  encaminhado_em: string | null
  prazo: string
  prazo_prorrogacao: string | null
  respondido_em: string | null
  tempo: number | null
  resposta: string | null
  resolutiva: boolean | null
  arquivada: boolean
  motivo_arquivamento: string | null
  reabertura_pedido_em: string | null
  reabertura_texto: string | null
  reabertura_aceita: boolean | null
  reaberta_em: string | null
  reabertura_prazo: string | null
  reabertura_prazo_prorrogacao: string | null
  reabertura_respondido_em: string | null
  reabertura_resposta: string | null
  observacoes: string
}

type Valor = string | number | Date | null
interface Coluna { titulo: string, ajuda: string, largura: number, tipo?: 'data' | 'datahora' | 'numero', valor: (l: LinhaExtrato, i: number) => Valor }

const NOMES_SITUACAO: Record<string, string> = {
  em_tratamento: 'EM TRATAMENTO',
  aguardando_complementacao: 'AGUARDANDO COMPLEMENTAÇÃO',
  prorrogada: 'PRORROGADA',
  vencida: 'VENCIDA',
  reaberta: 'REABERTA',
  respondida: 'RESPONDIDA',
}

const simNao = (v: boolean | null) => (v === null ? null : v ? 'SIM' : 'NÃO')
const maiusculas = (v: string | null) => (v ? v.toLocaleUpperCase('pt-BR') : null)

// Datas como datas do Excel (sem fuso): "2026-10-28" vira 28/10/2026.
function data(iso: string | null): Date | null {
  if (!iso) return null
  const [a, m, d] = iso.slice(0, 10).split('-').map(Number)
  return new Date(Date.UTC(a!, m! - 1, d!))
}
function dataHora(iso: string | null): Date | null {
  if (!iso) return null
  const p = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Sao_Paulo', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(new Date(iso))
  const v = (t: string) => Number(p.find(x => x.type === t)!.value)
  return new Date(Date.UTC(v('year'), v('month') - 1, v('day'), v('hour'), v('minute')))
}

const COLUNAS: Coluna[] = [
  { titulo: 'Nº', largura: 20.3, tipo: 'numero', ajuda: 'Número da manifestação no mês, em ordem crescente.', valor: (_, i) => i + 1 },
  { titulo: 'SITUAÇÃO ', largura: 22, ajuda: 'Situação da manifestação (aguardando complementação, em tratamento, prorrogada, reaberta respondida, vencida).', valor: l => NOMES_SITUACAO[l.situacao] ?? l.situacao },
  { titulo: 'PROTOCOLO', largura: 29.4, ajuda: 'Nº de protocolo gerado automaticamente pelo sistema MG-OUV. É uma sequência de 13 dígitos.', valor: l => l.protocolo_mgouv },
  { titulo: 'ENTRADA', largura: 18.4, ajuda: 'Canal de entrada (carta, e-mail, Fala.BR, MG-OUV, presencial, telefone).', valor: l => l.canal },
  { titulo: 'FALA.BR', largura: 29.4, ajuda: 'Nº de protocolo gerado automaticamente pelo sistema Fala.BR, no caso de manifestações encaminhadas pela Ouvidoria-Geral do Município. Formato de dados padrão.', valor: l => l.protocolo_falabr },
  { titulo: 'TIPO', largura: 20.1, ajuda: 'Tipo de manifestação (denúncia, elogio, solicitação, sugestão, reclamação).', valor: l => l.tipo },
  { titulo: 'IDENTIFICAÇÃO', largura: 18, ajuda: 'Identificação da manifestação (anônima, identificada, sigilosa).', valor: l => l.identificacao },
  { titulo: 'DATA DE CADASTRO PELO MANIFESTANTE', largura: 18.4, tipo: 'datahora', ajuda: 'Data em que o manifestante cadastra a manifestação.', valor: l => dataHora(l.cadastrado_em) },
  { titulo: 'DATA DE RECEBIMENTO PELO DMAE', largura: 32, tipo: 'data', ajuda: 'Data em que a Ouvidoria do DMAE recebe a manifestação, sempre considerando dias e horas úteis. Por exemplo: se a manifestação for cadastrada no sábado, ela será recebida pelo DMAE na segunda-feira.', valor: l => data(l.recebido_em) },
  { titulo: 'ASSUNTO', largura: 20.1, ajuda: 'Assunto da manifestação.', valor: l => l.assunto },
  { titulo: 'LOGRADOURO', largura: 18, ajuda: 'Logradouro do local do fato (alameda, avenida, praça, rua travessa, etc.).', valor: l => maiusculas(l.logradouro) },
  { titulo: 'NÚMERO', largura: 12, ajuda: 'Número do imóvel, se cabível.', valor: l => l.numero_imovel },
  { titulo: 'COMPLEMENTO', largura: 14, ajuda: 'Complemento do imóvel, se cabível.', valor: l => maiusculas(l.complemento) },
  { titulo: 'BAIRRO', largura: 18.7, ajuda: 'Bairro onde o imóvel ou a ocorrência estão localizados.', valor: l => l.bairro },
  { titulo: 'CEP', largura: 12, ajuda: 'CEP do logradouro.', valor: l => l.cep },
  { titulo: 'DESCRIÇÃO', largura: 30.7, ajuda: 'Texto da manifestação. É o relato apresentado pelo manifestante.', valor: l => l.descricao },
  { titulo: 'DIRETORIA ', largura: 30.6, ajuda: 'Diretoria responsável pelo tratamento da manifestação.', valor: l => l.diretoria },
  { titulo: 'PESSOA ENCAMINHADA', largura: 26, ajuda: 'Avaliar a quem a manifestação é enviada, sendo ele o responsável pelo tratamento.', valor: l => l.avaliador },
  { titulo: 'DATA ENCAMINHADA', largura: 19.4, tipo: 'data', ajuda: 'Data de encaminhamento da manifestação à diretoria e ao avaliador.', valor: l => data(l.encaminhado_em) },
  { titulo: 'TEMPO PARA RESPOSTA - 5 DIAS ÚTEIS', largura: 24.7, tipo: 'data', ajuda: 'Tempo de resposta à manifestação, de 5 dias úteis, contado da data de recebimento pelo DMAE (coluna I).', valor: l => data(l.prazo) },
  { titulo: 'TEMPO PARA RESPOSTA - PRORROGAÇÃO', largura: 18, tipo: 'data', ajuda: 'Tempo de resposta à manifestação, após pedido de prorrogação, de 10 dias úteis, contado da data de recebimento pelo DMAE (coluna I).', valor: l => data(l.prazo_prorrogacao) },
  { titulo: 'DATA DA RESPOSTA ', largura: 19, tipo: 'data', ajuda: 'Data de envio da resposta ao manifestante.', valor: l => data(l.respondido_em) },
  { titulo: 'TEMPO', largura: 21.6, tipo: 'numero', ajuda: 'Tempo total, em dias úteis, decorrido entre a data de recebimento da manifestação (coluna I) e a data da resposta (coluna V).', valor: l => l.tempo },
  { titulo: 'RESPOSTA', largura: 39.3, ajuda: 'Texto da resposta enviada ao manifestante.', valor: l => l.resposta },
  { titulo: 'RESOLUTIVIDADE', largura: 25, ajuda: 'Resolutividade da manifestação (sim, não).', valor: l => (l.arquivada ? null : simNao(l.resolutiva)) },
  { titulo: 'ARQUIVAMENTO', largura: 25, ajuda: 'Motivo do arquivamento da manifestação, se cabível (ausência de competência, encaminhado para outro órgão, insuficiência de dados, perda de objeto, registro em duplicidade).', valor: l => l.motivo_arquivamento },
  { titulo: 'DATA DO PEDIDO DE REABERTURA', largura: 28.3, tipo: 'data', ajuda: 'Data em que o manifestante solicita a reabertura da manifestação, em caso de insatisfação com a primeira resposta apresentada.', valor: l => data(dataHora(l.reabertura_pedido_em)?.toISOString() ?? null) },
  { titulo: 'DESCRIÇÃO DA REABERTURA', largura: 32.6, ajuda: 'Texto da reabertura da manifestação. É o relato apresentado pelo manifestante em caso de insatisfação com a primeira resposta.', valor: l => l.reabertura_texto },
  { titulo: 'ACEITAÇÃO DA REABERTURA', largura: 33, ajuda: 'Aceitação ou negativa do pedido de reabertura (sim, não).', valor: l => simNao(l.reabertura_aceita) },
  { titulo: 'DATA DA REABERTURA', largura: 32.9, tipo: 'data', ajuda: 'Data da reabertura da manifestação, em caso de aceitação, sempre considerando dias e horas úteis. Por exemplo: se a reabertura da manifestação for solicitada no sábado, a data da reabertura será a segunda-feira.', valor: l => data(l.reaberta_em) },
  { titulo: 'TEMPO PARA RESPOSTA À REABERTURA - 5 DIAS ÚTEIS', largura: 21.6, tipo: 'data', ajuda: 'Tempo de resposta à reabertura da manifestação, de 5 dias úteis, contado da data da reabertura (coluna AA).', valor: l => data(l.reabertura_prazo) },
  { titulo: 'TEMPO PARA RESPOSTA À REABERTURA - PRORROGAÇÃO', largura: 24.7, tipo: 'data', ajuda: 'Tempo de resposta à reabertura da manifestação, após pedido de prorrogação, de 10 dias úteis, contado da data da reabertura (coluna AA).', valor: l => data(l.reabertura_prazo_prorrogacao) },
  { titulo: 'DATA DA RESPOSTA À REABERTURA', largura: 17.4, tipo: 'data', ajuda: 'Data de envio da resposta à reabertura da manifestação.', valor: l => data(l.reabertura_respondido_em) },
  { titulo: 'RESPOSTA À REABERTURA', largura: 18.6, ajuda: 'Texto da resposta à reabertura da manifestação.', valor: l => l.reabertura_resposta },
  { titulo: 'OBSERVAÇÕES', largura: 23.6, ajuda: 'Observações gerais.', valor: l => [`Nº no sistema: ${l.numero}`, l.observacoes].filter(Boolean).join('\n') },
]

const MESES = ['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro']

export async function gerarExtrato(linhas: LinhaExtrato[], ano: number, mes: number): Promise<Blob> {
  const { default: ExcelJS } = await import('exceljs')
  const livro = new ExcelJS.Workbook()
  livro.creator = 'Sistema da Ouvidoria DMAE'
  const aba = livro.addWorksheet(MESES[mes - 1]!.toLocaleUpperCase('pt-BR'))
  const ultima = COLUNAS.length

  aba.columns = COLUNAS.map(c => ({ width: c.largura }))
  const borda = { style: 'thin' as const, color: { argb: 'FF000000' } }
  const bordas = { top: borda, left: borda, bottom: borda, right: borda }

  aba.mergeCells(1, 1, 1, ultima)
  const titulo = aba.getCell(1, 1)
  titulo.value = 'EXTRATO OUVIDORIA DMAE'
  titulo.font = { bold: true, size: 48, color: { argb: 'FFFFFFFF' } }
  titulo.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF203764' } }
  titulo.alignment = { vertical: 'middle', horizontal: 'left' }
  aba.getRow(1).height = 61.5

  aba.mergeCells(2, 1, 4, ultima)
  const mesCelula = aba.getCell(2, 1)
  mesCelula.value = `Mês de ${MESES[mes - 1]}/${ano}`
  mesCelula.font = { bold: true, size: 48, color: { argb: 'FF222B35' } }
  mesCelula.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFD9D9D9' } }
  mesCelula.alignment = { vertical: 'middle', horizontal: 'left' }

  const cabecalho = aba.getRow(5)
  cabecalho.height = 63
  const ajuda = aba.getRow(6)
  COLUNAS.forEach((c, i) => {
    const h = cabecalho.getCell(i + 1)
    h.value = c.titulo
    h.font = { bold: true, size: 12 }
    h.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFACB9CA' } }
    h.alignment = { vertical: 'middle', horizontal: 'center', wrapText: true }
    h.border = bordas
    const a = ajuda.getCell(i + 1)
    a.value = c.ajuda
    a.font = { size: 12 }
    a.alignment = { vertical: 'middle', horizontal: 'left', wrapText: true }
    a.border = bordas
  })

  linhas.forEach((l, n) => {
    const linha = aba.getRow(7 + n)
    COLUNAS.forEach((c, i) => {
      const celula = linha.getCell(i + 1)
      celula.value = c.valor(l, n)
      celula.font = { size: 12 }
      celula.alignment = { vertical: 'top', horizontal: 'left', wrapText: !c.tipo }
      celula.border = bordas
      if (c.tipo === 'data') celula.numFmt = 'dd/mm/yyyy'
      if (c.tipo === 'datahora') celula.numFmt = 'dd/mm/yyyy hh:mm'
    })
  })

  aba.autoFilter = { from: { row: 5, column: 1 }, to: { row: 6 + Math.max(linhas.length, 1), column: ultima } }
  aba.views = [{ state: 'frozen', ySplit: 6, xSplit: 0 }]

  const buffer = await livro.xlsx.writeBuffer()
  return new Blob([buffer], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' })
}
