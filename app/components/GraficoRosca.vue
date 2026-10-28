<script setup lang="ts">
// Rosca com total no centro e legenda com quantidade e %. Ao passar o mouse (ou focar),
// o centro mostra a fatia.
export interface FatiaRosca { chave: string, nome: string, n: number, cor: string }

const props = defineProps<{ fatias: FatiaRosca[], rotuloCentro?: string, valorCentro?: string, vazio?: string }>()

const total = computed(() => props.fatias.reduce((s, f) => s + f.n, 0))
const visiveis = computed(() => props.fatias.filter(f => f.n > 0))
const ativa = ref<string | null>(null)

const R = 70
const C = 2 * Math.PI * R
const VAO = 2.5

const arcos = computed(() => {
  let acumulado = 0
  const so = visiveis.value.length === 1
  return visiveis.value.map((f) => {
    const tamanho = (f.n / total.value) * C
    const arco = { ...f, traco: `${Math.max(tamanho - (so ? 0 : VAO), 0.5)} ${C}`, deslocamento: -acumulado }
    acumulado += tamanho
    return arco
  })
})

const destaque = computed(() => visiveis.value.find(f => f.chave === ativa.value))
</script>

<template>
  <div v-if="!total" class="grid min-h-[180px] place-items-center px-4 text-center text-[0.82rem] text-neutral-500">{{ vazio ?? 'Nenhum dado no período.' }}</div>
  <div v-else class="grid items-center gap-4 px-4 py-4 sm:grid-cols-[180px_1fr]">
    <svg viewBox="0 0 180 180" class="mx-auto h-[180px] w-[180px]" role="img" :aria-label="`${rotuloCentro ?? 'Total'}: ${valorCentro ?? total}`">
      <g transform="rotate(-90 90 90)">
        <circle
          v-for="a in arcos"
          :key="a.chave"
          cx="90" cy="90" :r="R" fill="none"
          :stroke="a.cor" stroke-width="24"
          :stroke-dasharray="a.traco" :stroke-dashoffset="a.deslocamento"
          class="cursor-pointer transition-opacity"
          :class="{ 'opacity-40': ativa && ativa !== a.chave }"
          @mouseenter="ativa = a.chave" @mouseleave="ativa = null"
        />
      </g>
      <text x="90" y="86" text-anchor="middle" class="fill-neutral-900 font-display text-[26px] font-extrabold">
        {{ destaque ? formatarNumero(destaque.n) : (valorCentro ?? formatarNumero(total)) }}
      </text>
      <text x="90" y="106" text-anchor="middle" class="fill-neutral-500 text-[11px]">
        {{ destaque ? percentual(destaque.n, total) : (rotuloCentro ?? 'total') }}
      </text>
    </svg>
    <ul class="grid gap-1.5 text-[0.8rem]">
      <li
        v-for="f in fatias"
        :key="f.chave"
        tabindex="0"
        class="grid cursor-default grid-cols-[10px_1fr_auto_44px] items-center gap-2 rounded-[4px] px-1.5 py-1 outline-none focus-visible:shadow-focus"
        :class="{ 'bg-neutral-50': ativa === f.chave }"
        @mouseenter="ativa = f.chave" @mouseleave="ativa = null" @focus="ativa = f.chave" @blur="ativa = null"
      >
        <i class="h-2.5 w-2.5 rounded-full" :style="{ background: f.cor }" />
        <span class="truncate text-neutral-700">{{ f.nome }}</span>
        <span class="font-semibold tabular-nums text-neutral-900">{{ formatarNumero(f.n) }}</span>
        <span class="text-right tabular-nums text-neutral-500">{{ percentual(f.n, total) }}</span>
      </li>
    </ul>
  </div>
</template>
