// Datas no fuso de Brasília. O banco guarda timestamptz e date; as telas mostram dd/mm/aaaa.
const FUSO = 'America/Sao_Paulo'

export function hojeBrasilia(): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: FUSO }).format(new Date())
}

// "2026-10-28" → "28/10/2026" (ou "28/10" curto)
export function formatarData(data: string | null | undefined, curto = false): string {
  if (!data) return ''
  const [ano, mes, dia] = data.slice(0, 10).split('-')
  return curto ? `${dia}/${mes}` : `${dia}/${mes}/${ano}`
}

// timestamptz → "28/10/2026 17:42"
export function formatarDataHora(momento: string | null | undefined): string {
  if (!momento) return ''
  const partes = new Intl.DateTimeFormat('pt-BR', {
    timeZone: FUSO, day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit',
  }).format(new Date(momento))
  return partes.replace(',', '')
}

// timestamptz → valor de <input type="datetime-local"> no horário de Brasília
export function paraCampoDataHora(momento: string): string {
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-CA', {
    timeZone: FUSO, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(new Date(momento)).map(x => [x.type, x.value]))
  return `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}`
}

// Valor de <input type="datetime-local"> → timestamptz. Brasília está em UTC-3 o ano todo desde 2019.
export function deCampoDataHora(valor: string): string {
  return `${valor}:00-03:00`
}

export function agoraCampoDataHora(): string {
  return paraCampoDataHora(new Date().toISOString())
}

// Soma dias corridos a uma data "aaaa-mm-dd".
export function somarDias(data: string, dias: number): string {
  const d = new Date(`${data}T12:00:00Z`)
  d.setUTCDate(d.getUTCDate() + dias)
  return d.toISOString().slice(0, 10)
}

export function ehFimDeSemana(data: string): boolean {
  const dia = new Date(`${data}T12:00:00Z`).getUTCDay()
  return dia === 0 || dia === 6
}
