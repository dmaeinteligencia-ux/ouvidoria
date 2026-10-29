<script setup lang="ts">
// Linha do tempo montada a partir do histórico (RN23), mais recente primeiro.
export interface EventoHistorico {
  id: number
  em: string
  tabela: string
  acao: string
  usuario: string | null
  dados_antigos: Record<string, unknown> | null
  dados_novos: Record<string, unknown> | null
}

// inicio/fim: limita aos registros de um ciclo pela ordem do histórico (id; fim exclusivo).
const props = defineProps<{ historico: EventoHistorico[], listas: Listas | null | undefined, inicio?: number, fim?: number }>()

const CAMPOS: Record<string, string> = {
  protocolo_mgouv: 'protocolo MG-OUV',
  protocolo_falabr: 'protocolo Fala.BR',
  canal_id: 'canal',
  tipo_id: 'tipo',
  identificacao_id: 'identificação',
  cadastrado_em: 'data do cadastro',
  dia_zero: 'recebimento',
  assunto_id: 'assunto',
  logradouro: 'logradouro',
  numero_imovel: 'número',
  complemento: 'complemento',
  bairro_id: 'bairro',
  cep: 'CEP',
  descricao: 'descrição',
  observacoes: 'observações',
}

// cor: classes de borda e texto do marcador (tokens do tailwind.config)
interface Evento { id: number, titulo: string, detalhe: string, texto?: string, cor: string }

const eventos = computed<Evento[]>(() => {
  const l = props.listas
  const lista: Evento[] = []
  const envios = new Map<string, { evento: Evento, detalheSemAvaliador: string, prefixo: string, destinos: Map<string, string[]> }>()
  const doCiclo = props.historico.filter(h => (props.inicio === undefined || h.id >= props.inicio) && (props.fim === undefined || h.id < props.fim))
  for (const h of doCiclo) {
    const novo = (h.dados_novos ?? {}) as Record<string, any>
    const antigo = (h.dados_antigos ?? {}) as Record<string, any>
    const quem = `${formatarDataHora(h.em)} · ${h.usuario ?? 'sistema'}`

    if (h.tabela === 'manifestacoes' && h.acao === 'insert') {
      const cadastroDia = paraCampoDataHora(novo.cadastrado_em).slice(0, 10)
      const ajuste = novo.dia_zero !== cadastroDia
        ? ` · recebimento em ${formatarData(novo.dia_zero)} (cadastro em ${formatarDataHora(novo.cadastrado_em)})`
        : ''
      lista.push({ id: h.id, titulo: 'Registrada', detalhe: quem + ajuste, cor: 'border-neutral-300 text-neutral-300', texto: novo.dia_zero_corrigido_justificativa ? `Recebimento corrigido: ${novo.dia_zero_corrigido_justificativa}` : undefined })
    }
    else if (h.tabela === 'manifestacoes' && h.acao === 'update') {
      if (novo.situacao === 'vencida' && antigo.situacao !== 'vencida') {
        lista.push({ id: h.id + 0.25, titulo: 'Prazo vencido sem resposta', detalhe: quem, cor: 'border-danger text-danger' })
      }
      if (novo.arquivada && !antigo.arquivada) {
        const motivo = nomeExibicao(nomePorId(l?.motivos, novo.motivo_arquivamento_id))
        lista.push({ id: h.id, titulo: 'Arquivada', detalhe: `${quem} · ${motivo}`, cor: 'border-status-arquivada text-status-arquivada' })
      }
      const alterados = Object.keys(CAMPOS).filter(c => JSON.stringify(novo[c]) !== JSON.stringify(antigo[c]))
      if (alterados.length) {
        lista.push({
          id: h.id + 0.5,
          titulo: `Dados corrigidos: ${alterados.map(c => CAMPOS[c]).join(', ')}`,
          detalhe: quem,
          texto: alterados.includes('dia_zero')
            ? `Recebimento de ${formatarData(antigo.dia_zero)} para ${formatarData(novo.dia_zero)}${novo.dia_zero_corrigido_justificativa ? `. Justificativa: ${novo.dia_zero_corrigido_justificativa}` : ' (recalculado pela data do cadastro)'}`
            : undefined,
          cor: 'border-warning text-warning',
        })
      }
    }
    else if (h.tabela === 'encaminhamentos' && h.acao === 'insert') {
      // Os avaliadores de um mesmo envio são gravados juntos (mesmo momento) e viram um só evento.
      const diretoria = nomeExibicao(nomePorId(l?.diretorias, novo.diretoria_id)) || 'diretoria'
      const avaliador = nomeExibicao(nomePorId(l?.avaliadores, novo.avaliador_id)) || 'avaliador'
      const envio = envios.get(h.em)
      if (envio) {
        envio.destinos.set(diretoria, [...(envio.destinos.get(diretoria) ?? []), avaliador])
        envio.evento.titulo = `${envio.prefixo} ${[...envio.destinos.keys()].map(d => `à ${d}`).join(' e ')}`
        envio.evento.detalhe = envio.detalheSemAvaliador
        envio.evento.texto = [...envio.destinos].map(([d, av]) => `${d}: ${av.join(', ')}`).join('\n')
        continue
      }
      const anteriores = lista.some(e => e.titulo.startsWith('Encaminhada') || e.titulo.startsWith('Reencaminhada'))
      const evento: Evento = {
        id: h.id,
        titulo: `${anteriores ? 'Reencaminhada' : 'Encaminhada'} à ${diretoria}`,
        detalhe: `envio em ${formatarData(novo.enviado_em)} · avaliador ${avaliador} · registrado ${quem}`,
        cor: 'border-primary-700 text-primary-700',
      }
      envios.set(h.em, { evento, detalheSemAvaliador: `envio em ${formatarData(novo.enviado_em)} · registrado ${quem}`, prefixo: anteriores ? 'Reencaminhada' : 'Encaminhada', destinos: new Map([[diretoria, [avaliador]]]) })
      lista.push(evento)
    }
    else if (h.tabela === 'ciclos' && h.acao === 'insert' && novo.numero > 0) {
      lista.push({
        id: h.id,
        titulo: `Reaberta: ciclo ${novo.numero}`,
        detalhe: `novo recebimento em ${formatarData(novo.dia_zero)} · ${quem}`,
        cor: 'border-status-reaberta text-status-reaberta',
      })
    }
    else if (h.tabela === 'ciclos' && h.acao === 'update' && novo.prorrogado && !antigo.prorrogado) {
      lista.push({
        id: h.id,
        titulo: 'Prazo prorrogado para 10 dias úteis',
        detalhe: quem,
        texto: novo.prorrogacao_justificativa,
        cor: 'border-status-prorrogada text-status-prorrogada',
      })
    }
    else if (h.tabela === 'complementacoes' && h.acao === 'insert') {
      lista.push({
        id: h.id,
        titulo: `Complementação pedida ${novo.origem === 'diretoria' ? 'pela diretoria' : 'pela Ouvidoria'}`,
        detalhe: `pedido em ${formatarData(novo.pedido_em)} · prazo suspenso até a resposta do manifestante, limite ${formatarData(novo.limite)} · ${quem}`,
        texto: novo.texto ?? undefined,
        cor: 'border-status-complementacao text-status-complementacao',
      })
    }
    else if (h.tabela === 'complementacoes' && h.acao === 'update' && novo.complementado_em && !antigo.complementado_em) {
      lista.push({
        id: h.id,
        titulo: `Complementação recebida em ${formatarDataHora(novo.complementado_em)}`,
        detalhe: `a contagem do prazo recomeça · ${quem}`,
        cor: 'border-status-complementacao text-status-complementacao',
      })
    }
    else if (h.tabela === 'complementacoes' && h.acao === 'update' && novo.arquivada_por_falta && !antigo.arquivada_por_falta) {
      lista.push({
        id: h.id,
        titulo: 'Sem complementação em 10 dias corridos',
        detalhe: quem,
        cor: 'border-status-arquivada text-status-arquivada',
      })
    }
    else if (h.tabela === 'pedidos_reabertura' && h.acao === 'insert') {
      lista.push({
        id: h.id,
        titulo: `Pedido de reabertura recebido em ${formatarDataHora(novo.recebido_em)}`,
        detalhe: `registrado ${quem}`,
        texto: novo.texto,
        cor: 'border-status-reaberta text-status-reaberta',
      })
    }
    else if (h.tabela === 'pedidos_reabertura' && h.acao === 'update' && novo.aceito !== null && antigo.aceito === null) {
      lista.push({
        id: h.id,
        titulo: novo.aceito ? 'Reabertura aceita' : 'Reabertura negada',
        detalhe: quem,
        texto: novo.justificativa_decisao,
        cor: novo.aceito ? 'border-status-reaberta text-status-reaberta' : 'border-neutral-400 text-neutral-400',
      })
    }
    else if (h.tabela === 'ciclos' && h.acao === 'update' && novo.respondido_em && !antigo.respondido_em) {
      lista.push({
        id: h.id,
        titulo: `Resposta enviada em ${formatarData(novo.respondido_em)}`,
        detalhe: `registrada ${quem}`,
        texto: novo.resposta,
        cor: 'border-status-respondida text-status-respondida',
      })
    }
  }
  return lista.reverse()
})
</script>

<template>
  <ol class="grid px-5 pb-4 pt-1.5">
    <li v-for="(e, i) in eventos" :key="e.id" class="relative grid grid-cols-[22px_1fr] gap-2.5 py-2.5">
      <span v-if="i < eventos.length - 1" class="absolute bottom-[-10px] left-[10px] top-7 w-0.5 bg-neutral-100" />
      <span class="grid h-[22px] w-[22px] place-items-center rounded-full border-2 bg-white" :class="e.cor">
        <span class="h-2 w-2 rounded-full bg-current" />
      </span>
      <div class="text-[0.84rem]">
        <b class="font-semibold">{{ e.titulo }}</b>
        <small class="block text-[0.74rem] text-neutral-500">{{ e.detalhe }}</small>
        <div v-if="e.texto" class="mt-1.5 whitespace-pre-line rounded-control border border-neutral-100 bg-neutral-25 px-2.5 py-2 text-[0.8rem] text-neutral-700">{{ e.texto }}</div>
      </div>
    </li>
    <li v-if="!eventos.length" class="py-3 text-[0.84rem] text-neutral-500">Sem registros no histórico.</li>
  </ol>
</template>
