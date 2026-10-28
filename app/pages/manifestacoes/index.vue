<script setup lang="ts">
import { SITUACOES, type Situacao } from '~/utils/situacao'

const supabase = useSupabaseClient()
const route = useRoute()
const router = useRouter()
const { data: perfil } = await usePerfil()
const { data: listas } = await useListas()

const POR_PAGINA = 25
const ABERTAS: Situacao[] = ['em_tratamento', 'aguardando_complementacao', 'prorrogada', 'vencida', 'reaberta']

interface Linha {
  id: number
  numero: string
  protocolo_mgouv: string | null
  protocolo_falabr: string | null
  situacao: Situacao
  arquivada: boolean
  assunto: string
  canal: string
  logradouro: string | null
  numero_imovel: string | null
  bairro: string | null
  prazo: string
  respondido_em: string | null
  dias_restantes: number | null
  diretoria: string | null
  avaliador: string | null
}

// Filtros ficam na URL, para o link poder ser compartilhado e o "voltar" do navegador funcionar.
function filtro(nome: string, padrao = '') {
  return computed<string>({
    get: () => (route.query[nome] as string | undefined) ?? padrao,
    set: (valor) => {
      const query = { ...route.query, [nome]: valor === padrao ? undefined : valor }
      delete query.pagina
      router.replace({ query })
    },
  })
}

const situacao = filtro('situacao', 'abertas')
const prazo = filtro('prazo')
const diretoria = filtro('diretoria')
const assunto = filtro('assunto')
const canal = filtro('canal')
const mes = filtro('mes')
const ordem = filtro('ordem', 'prazo')
const busca = filtro('busca')
const pagina = computed(() => Math.max(1, Number(route.query.pagina ?? 1) || 1))

const buscaDigitada = ref(busca.value)
watch(busca, v => (buscaDigitada.value = v))
function buscar() {
  busca.value = buscaDigitada.value.trim()
}

const opcoesSituacao = [
  { valor: 'abertas', nome: 'Em aberto' },
  { valor: 'todas', nome: 'Todas as situações' },
  { valor: 'respondidas', nome: 'Respondidas' },
  { valor: 'arquivadas', nome: 'Arquivadas' },
  ...SITUACOES.filter(s => s.valor !== 'respondida').map(s => ({ valor: s.valor, nome: s.nome })),
]
const opcoesPrazo = [
  { valor: 'vencidas', nome: 'Vencidas' },
  { valor: 'hoje', nome: 'Vencem hoje' },
  { valor: 'ate2', nome: 'Vencem em até 2 d.u.' },
  { valor: 'noprazo', nome: 'No prazo' },
]
const opcoesDe = (lista: { id: number, nome: string }[] | undefined, curto = false) =>
  (lista ?? []).map(i => ({ valor: String(i.id), nome: curto ? nomeDiretoriaCurto(i.nome) : nomeExibicao(i.nome) }))

const opcoesMes = computed(() => {
  const hoje = hojeBrasilia()
  const meses = []
  let [ano, m] = hoje.split('-').map(Number) as [number, number]
  for (let i = 0; i < 18; i++) {
    const valor = `${ano}-${String(m).padStart(2, '0')}`
    const nome = new Intl.DateTimeFormat('pt-BR', { month: 'short', year: 'numeric', timeZone: 'UTC' })
      .format(new Date(`${valor}-15T12:00:00Z`)).replace('. de ', '/').replace(' de ', '/')
    meses.push({ valor, nome: nome.charAt(0).toUpperCase() + nome.slice(1) })
    m--
    if (m === 0) { m = 12; ano-- }
  }
  return meses
})

const { data: resultado, pending, error } = await useAsyncData('lista-manifestacoes', async () => {
  let q = supabase
    .from('painel_manifestacoes')
    .select('id, numero, protocolo_mgouv, protocolo_falabr, situacao, arquivada, assunto, canal, logradouro, numero_imovel, bairro, prazo, respondido_em, dias_restantes, diretoria, avaliador', { count: 'exact' })

  if (situacao.value === 'abertas') q = q.in('situacao', ABERTAS)
  else if (situacao.value === 'respondidas') q = q.eq('situacao', 'respondida')
  else if (situacao.value === 'arquivadas') q = q.eq('arquivada', true)
  else if (situacao.value !== 'todas') q = q.eq('situacao', situacao.value as Situacao)

  if (prazo.value === 'vencidas') q = q.lt('dias_restantes', 0)
  else if (prazo.value === 'hoje') q = q.eq('dias_restantes', 0)
  else if (prazo.value === 'ate2') q = q.gte('dias_restantes', 0).lte('dias_restantes', 2)
  else if (prazo.value === 'noprazo') q = q.gt('dias_restantes', 2)

  if (diretoria.value) q = q.eq('diretoria_id', Number(diretoria.value))
  if (assunto.value) q = q.eq('assunto_id', Number(assunto.value))
  if (canal.value) q = q.eq('canal_id', Number(canal.value))
  if (mes.value) {
    const [a, m] = mes.value.split('-').map(Number) as [number, number]
    const fim = m === 12 ? `${a + 1}-01-01` : `${a}-${String(m + 1).padStart(2, '0')}-01`
    q = q.gte('dia_zero', `${mes.value}-01`).lt('dia_zero', fim)
  }

  // Busca por nº interno, protocolos, bairro ou logradouro (sem caracteres que quebram o filtro).
  const termo = busca.value.replace(/[,()*%\\]/g, ' ').trim()
  if (termo) {
    const t = `%${termo}%`
    q = q.or(`numero.ilike.${t},protocolo_mgouv.ilike.${t},protocolo_falabr.ilike.${t},bairro.ilike.${t},logradouro.ilike.${t},assunto.ilike.${t}`)
  }

  if (ordem.value === 'recentes') q = q.order('cadastrado_em', { ascending: false })
  else if (ordem.value === 'numero') q = q.order('ano', { ascending: false }).order('sequencial', { ascending: false })
  else q = q.order('dias_restantes', { ascending: true, nullsFirst: false }).order('prazo', { ascending: true })

  const inicio = (pagina.value - 1) * POR_PAGINA
  const { data, count, error } = await q.range(inicio, inicio + POR_PAGINA - 1)
  if (error) throw error
  return { linhas: (data ?? []) as Linha[], total: count ?? 0 }
}, { watch: [() => route.query] })

const total = computed(() => resultado.value?.total ?? 0)
const ultimaPagina = computed(() => Math.max(1, Math.ceil(total.value / POR_PAGINA)))
function irPara(p: number) {
  router.replace({ query: { ...route.query, pagina: p === 1 ? undefined : String(p) } })
}

const temFiltro = computed(() => Object.keys(route.query).some(k => !['pagina', 'ordem'].includes(k)))
function limpar() {
  router.replace({ query: ordem.value === 'prazo' ? {} : { ordem: ordem.value } })
}

const subtitulo = computed(() => {
  const n = total.value
  const rotulo = opcoesSituacao.find(o => o.valor === situacao.value)?.nome.toLowerCase()
  if (situacao.value === 'abertas') return `${n} em aberto`
  return `${n} ${n === 1 ? 'manifestação' : 'manifestações'} · ${rotulo}`
})

function local(l: Linha) {
  const rua = [l.logradouro && nomeExibicao(l.logradouro), l.numero_imovel].filter(Boolean).join(', ')
  return [rua, l.bairro && nomeExibicao(l.bairro)].filter(Boolean).join(' · ')
}
</script>

<template>
  <AvisoCaixa v-if="perfil?.perfil === 'diretor'" titulo="Acesso restrito" tipo="atencao">
    A lista de manifestações é usada só pela equipe da Ouvidoria.
  </AvisoCaixa>

  <template v-else>
    <CabecalhoPagina titulo="Manifestações" :subtitulo="subtitulo">
      <template #acoes>
        <button class="btn btn-fantasma btn-pequeno" disabled title="Disponível na Fase 4">Exportar Excel</button>
        <NuxtLink to="/manifestacoes/nova" class="btn btn-primario btn-pequeno">+ Nova manifestação</NuxtLink>
      </template>
    </CabecalhoPagina>

    <section class="cartao">
      <div class="flex flex-wrap items-center gap-2 border-b border-neutral-100 px-3.5 py-3">
        <form class="relative" role="search" @submit.prevent="buscar">
          <input
            v-model="buscaDigitada"
            type="search"
            placeholder="Nº, protocolo, bairro ou rua"
            class="w-[220px] rounded-control border border-neutral-200 bg-white py-1.5 pl-2.5 pr-7 text-[0.78rem] placeholder:text-neutral-400 focus:border-primary-500 focus:shadow-focus focus:outline-none"
            aria-label="Buscar manifestações"
            @search="buscar"
          >
        </form>
        <FiltroChip v-model="situacao" rotulo="Situação" :opcoes="opcoesSituacao" padrao="abertas" />
        <FiltroChip v-model="prazo" rotulo="Prazo" :opcoes="opcoesPrazo" />
        <FiltroChip v-model="diretoria" rotulo="Diretoria" :opcoes="opcoesDe(listas?.diretorias, true)" />
        <FiltroChip v-model="assunto" rotulo="Assunto" :opcoes="opcoesDe(listas?.assuntos)" />
        <FiltroChip v-model="canal" rotulo="Canal" :opcoes="(listas?.canais ?? []).map(c => ({ valor: String(c.id), nome: c.nome_painel }))" />
        <FiltroChip v-model="mes" rotulo="Mês" :opcoes="opcoesMes" todos="Qualquer mês" />
        <button v-if="temFiltro" class="text-[0.76rem] font-semibold text-primary-700 hover:underline" @click="limpar">Limpar filtros</button>

        <div class="ml-auto inline-flex overflow-hidden rounded-control border border-neutral-200" role="group" aria-label="Ordenar por">
          <button
            v-for="o in [{ v: 'prazo', n: 'Prazo' }, { v: 'recentes', n: 'Mais recentes' }, { v: 'numero', n: 'Nº' }]"
            :key="o.v"
            class="border-r border-neutral-200 px-2.5 py-1.5 text-[0.76rem] last:border-r-0"
            :class="ordem === o.v ? 'bg-primary-700 font-semibold text-white' : 'bg-white text-neutral-600 hover:bg-neutral-25'"
            :aria-pressed="ordem === o.v"
            @click="ordem = o.v"
          >
            {{ o.n }}
          </button>
        </div>
      </div>

      <div class="overflow-x-auto">
        <table class="lista min-w-[860px]">
          <thead>
            <tr><th>Nº / protocolo</th><th>Assunto e local</th><th>Canal</th><th>Diretoria · avaliador</th><th>Situação</th><th>Prazo</th></tr>
          </thead>
          <tbody :class="{ 'opacity-60': pending }">
            <tr
              v-for="l in resultado?.linhas"
              :key="l.id"
              class="cursor-pointer hover:bg-neutral-25"
              :class="{ '!bg-[#FFFAF9]': l.dias_restantes !== null && l.dias_restantes < 0 }"
              @click="navigateTo(`/manifestacoes/${l.id}`)"
            >
              <td>
                <NuxtLink :to="`/manifestacoes/${l.id}`" class="numero-interno hover:underline" @click.stop>{{ l.numero }}</NuxtLink>
                <div v-if="l.protocolo_mgouv" class="whitespace-nowrap font-mono text-[0.72rem] text-neutral-500">MG-OUV {{ l.protocolo_mgouv }}</div>
                <div v-if="l.protocolo_falabr" class="whitespace-nowrap font-mono text-[0.72rem] text-neutral-500">Fala.BR {{ l.protocolo_falabr }}</div>
              </td>
              <td>
                <div class="font-semibold text-neutral-900">{{ nomeExibicao(l.assunto) }}</div>
                <div class="text-[0.76rem] text-neutral-500">{{ local(l) || 'Sem endereço' }}</div>
              </td>
              <td class="text-neutral-700">{{ l.canal }}</td>
              <td>
                <template v-if="l.diretoria">
                  {{ nomeDiretoriaCurto(l.diretoria) }}
                  <div class="text-[0.76rem] text-neutral-500">{{ nomeExibicao(l.avaliador) }}</div>
                </template>
                <span v-else class="text-[0.76rem] text-neutral-500">Não encaminhada</span>
              </td>
              <td><SituacaoBadge :situacao="l.situacao" :arquivada="l.arquivada" /></td>
              <td><PrazoIndicador :dias-restantes="l.dias_restantes" :prazo="l.prazo" :respondido-em="l.respondido_em" :suspenso="l.situacao === 'aguardando_complementacao'" /></td>
            </tr>
            <tr v-if="!pending && !resultado?.linhas.length">
              <td colspan="6" class="py-8 text-center text-neutral-500">
                <template v-if="error">Não foi possível carregar a lista. Recarregue a página.</template>
                <template v-else-if="temFiltro">Nenhuma manifestação com esses filtros.</template>
                <template v-else>Nenhuma manifestação em aberto. <NuxtLink to="/manifestacoes/nova" class="font-semibold text-primary-700 hover:underline">Cadastrar a primeira</NuxtLink></template>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="flex items-center justify-between border-t border-neutral-100 px-3.5 py-2.5 text-[0.76rem] text-neutral-500">
        <span v-if="total">Mostrando {{ (pagina - 1) * POR_PAGINA + 1 }} a {{ Math.min(pagina * POR_PAGINA, total) }} de {{ total }}</span>
        <span v-else>Nenhum registro</span>
        <span class="flex gap-3">
          <button class="hover:text-primary-700 disabled:opacity-40" :disabled="pagina <= 1" @click="irPara(pagina - 1)">‹ Anterior</button>
          <button class="hover:text-primary-700 disabled:opacity-40" :disabled="pagina >= ultimaPagina" @click="irPara(pagina + 1)">Próxima ›</button>
        </span>
      </div>
    </section>
  </template>
</template>
