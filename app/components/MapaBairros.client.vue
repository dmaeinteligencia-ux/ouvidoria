<script setup lang="ts">
// Mapa de bolhas por bairro (Painel Gerencial): cada bairro é um ponto marcado em Cadastros, com
// área proporcional à quantidade de manifestações. Fica no lugar do mapa de calor até chegar o
// contorno oficial dos bairros.
import type { Map as MapaLeaflet, LayerGroup } from 'leaflet'
import type { ItemGrafico } from './GraficoColunas.vue'

const props = defineProps<{ itens: ItemGrafico[], total: number }>()

const supabase = useSupabaseClient()
const { data: perfil } = usePerfil()
const ehAdmin = computed(() => perfil.value?.perfil === 'administrador')

const { data: posicoes } = useAsyncData('posicoes-bairros', async () => {
  const { data, error } = await supabase.from('bairros').select('id, nome, latitude, longitude').not('latitude', 'is', null)
  if (error) throw error
  return (data ?? []) as PosicaoBairro[]
})

const noMapa = computed(() => {
  const porNome = new Map((posicoes.value ?? []).map(p => [p.nome, p]))
  return props.itens.flatMap((i) => {
    const p = porNome.get(i.nome)
    return p ? [{ ...i, lat: Number(p.latitude), lng: Number(p.longitude) }] : []
  })
})
const foraDoMapa = computed(() => {
  const marcados = new Set(noMapa.value.map(i => i.nome))
  const lista = props.itens.filter(i => !marcados.has(i.nome))
  return { bairros: lista.length, n: lista.reduce((s, i) => s + i.n, 0) }
})
const maximo = computed(() => Math.max(0, ...noMapa.value.map(i => i.n)))
// Legenda com três tamanhos de referência, a partir do maior bairro.
const legenda = computed(() => {
  const m = maximo.value
  if (!m) return []
  return [...new Set([m, Math.round(m / 4), Math.max(1, Math.round(m / 16))])].filter(n => n > 0)
})

const elemento = ref<HTMLElement | null>(null)
let mapa: MapaLeaflet | null = null
let camada: LayerGroup | null = null
let L: Awaited<ReturnType<typeof carregarLeaflet>> | null = null
let enquadrado = false

const escapar = (t: string) => t.replace(/[&<>"']/g, c => `&#${c.charCodeAt(0)};`)

function desenhar() {
  if (!mapa || !L || !camada) return
  camada.clearLayers()
  // Maiores primeiro, para as bolhas pequenas ficarem por cima e continuarem clicáveis.
  for (const i of [...noMapa.value].sort((a, b) => b.n - a.n)) {
    L.circleMarker([i.lat, i.lng], {
      radius: raioBolha(i.n, maximo.value),
      color: '#ffffff',
      weight: 1,
      fillColor: COR_SERIE,
      fillOpacity: 0.6,
    })
      .bindTooltip(`<b>${escapar(nomeExibicao(i.nome))}</b><br>${formatarNumero(i.n)} (${percentual(i.n, props.total)})`, { direction: 'top' })
      .on('mouseover', e => e.target.setStyle({ fillOpacity: 0.85 }))
      .on('mouseout', e => e.target.setStyle({ fillOpacity: 0.6 }))
      .addTo(camada)
  }
  // Enquadra os bairros na primeira vez; depois mantém o zoom de quem está olhando.
  if (!enquadrado && noMapa.value.length > 1) {
    mapa.fitBounds(L.latLngBounds(noMapa.value.map(i => [i.lat, i.lng] as [number, number])).pad(0.15), { maxZoom: 14 })
    enquadrado = true
  }
}

// Componente .client: o template só aparece no tique seguinte ao onMounted.
onMounted(async () => {
  await nextTick()
  if (!elemento.value) return
  const criado = await criarMapa(elemento.value)
  L = criado.L
  mapa = criado.mapa
  camada = L.layerGroup().addTo(mapa)
  desenhar()
})
onBeforeUnmount(() => mapa?.remove())
watch(noMapa, desenhar)
</script>

<template>
  <div>
    <div ref="elemento" class="h-[380px] w-full bg-neutral-50" role="img" :aria-label="`Mapa com ${noMapa.length} bairros marcados; a lista completa está em Principais bairros.`" />
    <div class="flex flex-wrap items-center justify-between gap-x-6 gap-y-2 border-t border-neutral-100 px-4 py-2.5 text-[0.76rem] text-neutral-600">
      <div v-if="legenda.length" class="flex items-center gap-3" aria-hidden="true">
        <span>Manifestações</span>
        <span v-for="n in legenda" :key="n" class="flex items-center gap-1.5">
          <i class="block rounded-full border border-white" :style="{ width: `${raioBolha(n, maximo) * 2}px`, height: `${raioBolha(n, maximo) * 2}px`, background: COR_SERIE, opacity: 0.6 }" />
          <span class="tabular-nums">{{ formatarNumero(n) }}</span>
        </span>
      </div>
      <span v-else>Nenhum bairro do período está marcado no mapa.</span>
      <span v-if="foraDoMapa.bairros">
        {{ formatarNumero(foraDoMapa.bairros) }} {{ foraDoMapa.bairros === 1 ? 'bairro sem posição fica' : 'bairros sem posição ficam' }}
        fora do mapa ({{ formatarNumero(foraDoMapa.n) }} {{ foraDoMapa.n === 1 ? 'manifestação' : 'manifestações' }}).
        <NuxtLink v-if="ehAdmin" to="/cadastros?aba=bairros" class="font-semibold text-primary-700 hover:underline">Marcar em Cadastros</NuxtLink>
      </span>
    </div>
  </div>
</template>
