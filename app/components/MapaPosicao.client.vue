<script setup lang="ts">
// Marca a posição de um bairro com um clique no mapa. Os bairros já marcados aparecem em cinza,
// para servir de referência.
import type { Map as MapaLeaflet, CircleMarker } from 'leaflet'

const props = defineProps<{ bairro: PosicaoBairro, outros: PosicaoBairro[], salvando?: boolean }>()
const emit = defineEmits<{ salvar: [posicao: { latitude: number, longitude: number } | null], cancelar: [] }>()

const ponto = ref<{ latitude: number, longitude: number } | null>(
  props.bairro.latitude == null ? null : { latitude: Number(props.bairro.latitude), longitude: Number(props.bairro.longitude) })
const mudou = computed(() => ponto.value?.latitude !== (props.bairro.latitude == null ? undefined : Number(props.bairro.latitude))
  || ponto.value?.longitude !== (props.bairro.longitude == null ? undefined : Number(props.bairro.longitude)))

const elemento = ref<HTMLElement | null>(null)
let mapa: MapaLeaflet | null = null
let marcador: CircleMarker | null = null

const escapar = (t: string) => t.replace(/[&<>"']/g, c => `&#${c.charCodeAt(0)};`)
const arredondar = (n: number) => Math.round(n * 1e6) / 1e6

// Componente .client: o template só aparece no tique seguinte ao onMounted.
onMounted(async () => {
  await nextTick()
  if (!elemento.value) return
  const { L, mapa: m } = await criarMapa(elemento.value)
  mapa = m
  for (const b of props.outros) {
    if (b.id === props.bairro.id || b.latitude == null) continue
    L.circleMarker([Number(b.latitude), Number(b.longitude)], { radius: 5, color: '#ffffff', weight: 1, fillColor: '#6b7280', fillOpacity: 0.8 })
      .bindTooltip(escapar(nomeExibicao(b.nome)), { direction: 'top' })
      .addTo(mapa)
  }
  const desenhar = () => {
    if (!ponto.value) return
    const pos: [number, number] = [ponto.value.latitude, ponto.value.longitude]
    if (marcador) marcador.setLatLng(pos)
    else marcador = L.circleMarker(pos, { radius: 9, color: '#ffffff', weight: 2, fillColor: '#004790', fillOpacity: 1 }).addTo(mapa!)
  }
  if (ponto.value) {
    mapa.setView([ponto.value.latitude, ponto.value.longitude], 14)
    desenhar()
  }
  mapa.on('click', (e) => {
    const limites = L.latLngBounds(LIMITES_MUNICIPIO)
    if (!limites.contains(e.latlng)) return
    ponto.value = { latitude: arredondar(e.latlng.lat), longitude: arredondar(e.latlng.lng) }
    desenhar()
  })
})
onBeforeUnmount(() => mapa?.remove())
</script>

<template>
  <div class="grid gap-3 border-b border-neutral-100 bg-neutral-25 px-3.5 py-3">
    <div class="flex flex-wrap items-baseline justify-between gap-2">
      <b class="text-[0.9rem] text-neutral-900">Posição de {{ nomeExibicao(bairro.nome) }}</b>
      <span class="text-[0.76rem] text-neutral-500">Clique no mapa, no centro do bairro.</span>
    </div>
    <div ref="elemento" class="h-[360px] w-full cursor-crosshair rounded-control bg-neutral-50 ring-1 ring-inset ring-neutral-100" />
    <div class="flex flex-wrap items-center gap-2">
      <span class="mr-auto font-mono text-[0.76rem] text-neutral-600">
        {{ ponto ? `${ponto.latitude.toFixed(6)}, ${ponto.longitude.toFixed(6)}` : 'Sem posição' }}
      </span>
      <button v-if="bairro.latitude != null" type="button" class="btn btn-secundario" :disabled="salvando" @click="emit('salvar', null)">Remover posição</button>
      <button type="button" class="btn btn-secundario" :disabled="salvando" @click="emit('cancelar')">Cancelar</button>
      <button type="button" class="btn btn-primario" :disabled="salvando || !ponto || !mudou" @click="emit('salvar', ponto)">Salvar posição</button>
    </div>
  </div>
</template>
