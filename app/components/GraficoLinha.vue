<script setup lang="ts">
import type { Agrupamento } from '~/utils/graficos'

// Linha de uma série ao longo dos períodos, com mira e valor ao passar o mouse.
// valor null = período sem dado (a linha se interrompe).
export interface PontoLinha { periodo: string, valor: number | null }

const props = defineProps<{ pontos: PontoLinha[], agrupar: Agrupamento, unidade?: string, decimal?: boolean, vazio?: string }>()

const caixa = ref<HTMLElement | null>(null)
const largura = ref(640)
const ALTURA = 200
const M = { topo: 14, dir: 14, base: 26, esq: 36 }

onMounted(() => {
  const obs = new ResizeObserver(([e]) => { if (e) largura.value = Math.max(260, e.contentRect.width) })
  if (caixa.value) obs.observe(caixa.value)
  onBeforeUnmount(() => obs.disconnect())
})

const temDado = computed(() => props.pontos.some(p => p.valor !== null && p.valor > 0))
const marcas = computed(() => marcasEixo(Math.max(0, ...props.pontos.map(p => p.valor ?? 0))))
const topo = computed(() => marcas.value.at(-1)!)
const passoX = computed(() => (largura.value - M.esq - M.dir) / Math.max(1, props.pontos.length - 1))
const x = (i: number) => M.esq + (props.pontos.length === 1 ? (largura.value - M.esq - M.dir) / 2 : i * passoX.value)
const y = (v: number) => M.topo + (1 - v / topo.value) * (ALTURA - M.topo - M.base)

// Trechos contínuos (sem períodos vazios no meio).
const trechos = computed(() => {
  const lista: { i: number, v: number }[][] = []
  let atual: { i: number, v: number }[] = []
  props.pontos.forEach((p, i) => {
    if (p.valor === null) { if (atual.length) lista.push(atual); atual = [] }
    else atual.push({ i, v: p.valor })
  })
  if (atual.length) lista.push(atual)
  return lista
})
const caminho = (t: { i: number, v: number }[]) => t.map((p, k) => `${k ? 'L' : 'M'}${x(p.i).toFixed(1)},${y(p.v).toFixed(1)}`).join(' ')
const area = (t: { i: number, v: number }[]) =>
  `${caminho(t)} L${x(t.at(-1)!.i).toFixed(1)},${y(0)} L${x(t[0]!.i).toFixed(1)},${y(0)} Z`

// Rótulos do eixo x sem encavalar: no máximo um a cada ~56px.
const saltoRotulo = computed(() => Math.max(1, Math.ceil(56 / Math.max(passoX.value, 1))))

const ativo = ref<number | null>(null)
function mover(ev: MouseEvent) {
  const svg = ev.currentTarget as SVGElement
  const r = svg.getBoundingClientRect()
  const px = ((ev.clientX - r.left) / r.width) * largura.value
  const i = props.pontos.length === 1 ? 0 : Math.round((px - M.esq) / passoX.value)
  ativo.value = Math.min(props.pontos.length - 1, Math.max(0, i))
}
const formatar = (v: number) => (props.decimal ? formatarDecimal(v) : formatarNumero(v))
const ultimo = computed(() => {
  for (let i = props.pontos.length - 1; i >= 0; i--) if (props.pontos[i]!.valor !== null) return i
  return -1
})
</script>

<template>
  <div ref="caixa" class="relative px-2 pb-2 pt-3">
    <div v-if="!temDado" class="grid min-h-[180px] place-items-center px-4 text-center text-[0.82rem] text-neutral-500">{{ vazio ?? 'Nenhum dado no período.' }}</div>
    <svg
      v-else
      :viewBox="`0 0 ${largura} ${ALTURA}`" :width="largura" :height="ALTURA"
      class="block max-w-full" role="img" aria-label="Gráfico de linha"
      @mousemove="mover" @mouseleave="ativo = null"
    >
      <g v-for="m in marcas" :key="m">
        <line :x1="M.esq" :x2="largura - M.dir" :y1="y(m)" :y2="y(m)" stroke="#E4E9F1" stroke-width="1" />
        <text :x="M.esq - 6" :y="y(m) + 3.5" text-anchor="end" class="fill-neutral-500 text-[10px] tabular-nums">{{ formatar(m) }}</text>
      </g>
      <template v-for="(p, i) in pontos" :key="p.periodo">
        <text v-if="i % saltoRotulo === 0" :x="x(i)" :y="ALTURA - 8" text-anchor="middle" class="fill-neutral-500 text-[10px]">{{ rotuloPeriodo(p.periodo, agrupar) }}</text>
      </template>
      <template v-for="(t, k) in trechos" :key="k">
        <path :d="area(t)" :fill="COR_SERIE" fill-opacity="0.1" />
        <path :d="caminho(t)" fill="none" :stroke="COR_SERIE" stroke-width="2" stroke-linejoin="round" stroke-linecap="round" />
        <circle v-if="t.length === 1" :cx="x(t[0]!.i)" :cy="y(t[0]!.v)" r="4" :fill="COR_SERIE" stroke="#fff" stroke-width="2" />
      </template>
      <template v-if="ultimo >= 0 && ativo === null">
        <circle :cx="x(ultimo)" :cy="y(pontos[ultimo]!.valor!)" r="4" :fill="COR_SERIE" stroke="#fff" stroke-width="2" />
        <text :x="x(ultimo)" :y="y(pontos[ultimo]!.valor!) - 9" :text-anchor="ultimo === pontos.length - 1 && pontos.length > 1 ? 'end' : 'middle'" class="fill-neutral-800 text-[11px] font-semibold tabular-nums">{{ formatar(pontos[ultimo]!.valor!) }}</text>
      </template>
      <g v-if="ativo !== null">
        <line :x1="x(ativo)" :x2="x(ativo)" :y1="M.topo" :y2="y(0)" stroke="#A9B4C5" stroke-width="1" />
        <circle v-if="pontos[ativo]!.valor !== null" :cx="x(ativo)" :cy="y(pontos[ativo]!.valor!)" r="4.5" :fill="COR_SERIE" stroke="#fff" stroke-width="2" />
      </g>
    </svg>
    <div
      v-if="ativo !== null && temDado"
      class="pointer-events-none absolute top-1 z-10 whitespace-nowrap rounded-control bg-neutral-900 px-2 py-1 text-[0.72rem] text-white shadow-overlay"
      :style="{ left: `${Math.min(Math.max(x(ativo) - 60, 0), largura - 140)}px` }"
    >
      {{ rotuloPeriodoLongo(pontos[ativo]!.periodo, agrupar) }}:
      <b>{{ pontos[ativo]!.valor === null ? 'sem dado' : `${formatar(pontos[ativo]!.valor!)}${unidade ? ` ${unidade}` : ''}` }}</b>
    </div>
  </div>
</template>
