import type { Situacao } from '~/utils/situacao'

export interface LinhaPainel {
  id: number
  numero: string
  assunto: string
  situacao: Situacao
  arquivada: boolean
  prazo: string | null
  dias_restantes: number | null
  diretoria: string | null
  dia_zero: string
}

export interface CargaDiretoria {
  diretoria: string
  noPrazo: number
  atencao: number
  vencidas: number
  total: number
}

const ABERTAS: Situacao[] = ['em_tratamento', 'aguardando_complementacao', 'prorrogada', 'vencida', 'reaberta']

function hojeBrasilia(): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(new Date())
}

// Números do painel da Ouvidoria, lidos da visão painel_manifestacoes (RLS: só a equipe).
export function useResumoPainel() {
  const supabase = useSupabaseClient()
  const { data: perfil } = useNuxtData<{ perfil: string } | null>('perfil')

  return useAsyncData('resumo-painel', async () => {
    const equipe = perfil.value?.perfil === 'administrador' || perfil.value?.perfil === 'ouvidoria'
    if (!equipe) return null

    const mes = hojeBrasilia().slice(0, 7)
    const [linhasResp, respostasResp] = await Promise.all([
      supabase
        .from('painel_manifestacoes')
        .select('id, numero, assunto, situacao, arquivada, prazo, dias_restantes, diretoria, dia_zero'),
      supabase
        .from('ciclos_prazos')
        .select('no_prazo, tempo_dias_uteis')
        .eq('numero', 0)
        .gte('respondido_em', `${mes}-01`)
        .lte('respondido_em', `${mes}-31`),
    ])
    if (linhasResp.error) throw linhasResp.error
    if (respostasResp.error) throw respostasResp.error

    const linhas = (linhasResp.data ?? []) as LinhaPainel[]
    const abertas = linhas.filter(l => ABERTAS.includes(l.situacao))
    const contando = abertas.filter(l => l.dias_restantes !== null)
    const vencidas = contando.filter(l => l.dias_restantes! < 0)
    const atencao = contando.filter(l => l.dias_restantes! >= 0 && l.dias_restantes! <= 2)

    const porDiretoria = new Map<string, CargaDiretoria>()
    for (const l of abertas) {
      const nome = l.diretoria ?? 'Não encaminhada'
      const c = porDiretoria.get(nome) ?? { diretoria: nome, noPrazo: 0, atencao: 0, vencidas: 0, total: 0 }
      c.total++
      if (l.dias_restantes !== null && l.dias_restantes < 0) c.vencidas++
      else if (l.dias_restantes !== null && l.dias_restantes <= 2) c.atencao++
      else c.noPrazo++
      porDiretoria.set(nome, c)
    }

    const respostas = (respostasResp.data ?? []) as { no_prazo: boolean, tempo_dias_uteis: number }[]
    const noPrazo = respostas.filter(r => r.no_prazo).length
    const tempoMedio = respostas.length
      ? respostas.reduce((s, r) => s + r.tempo_dias_uteis, 0) / respostas.length
      : null

    return {
      contagens: {
        abertas: abertas.length,
        vencidas: vencidas.length,
        reabertas: abertas.filter(l => l.situacao === 'reaberta').length,
      },
      registradasNoMes: linhas.filter(l => l.dia_zero.startsWith(mes)).length,
      atencao: atencao.length,
      vencemHoje: atencao.filter(l => l.dias_restantes === 0).length,
      vencidas: vencidas.length,
      percentualNoPrazo: respostas.length ? Math.round((noPrazo / respostas.length) * 100) : null,
      tempoMedio,
      cargaPorDiretoria: [...porDiretoria.values()].sort((a, b) => b.total - a.total),
      urgentes: contando
        .filter(l => l.dias_restantes! <= 2)
        .sort((a, b) => a.dias_restantes! - b.dias_restantes!)
        .slice(0, 6),
    }
  }, { watch: [perfil] })
}
