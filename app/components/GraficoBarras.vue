<script setup lang="ts">
// Barras horizontais (ranking): nome, barra e valor na ponta; % ao passar o mouse.
import type { ItemGrafico } from './GraficoColunas.vue'

const props = defineProps<{ itens: ItemGrafico[], total?: number, vazio?: string }>()

const soma = computed(() => props.total ?? props.itens.reduce((s, i) => s + i.n, 0))
const maximo = computed(() => Math.max(1, ...props.itens.map(i => i.n)))
</script>

<template>
  <div v-if="!itens.length" class="grid min-h-[180px] place-items-center px-4 text-center text-[0.82rem] text-neutral-500">{{ vazio ?? 'Nenhum dado no período.' }}</div>
  <ol v-else class="grid gap-2 px-4 py-4 text-[0.8rem]">
    <li
      v-for="i in itens"
      :key="i.nome"
      class="grid grid-cols-[minmax(0,170px)_1fr] items-center gap-2.5"
      :title="`${i.nome}: ${formatarNumero(i.n)} (${percentual(i.n, soma)})`"
    >
      <span class="truncate text-neutral-700">{{ i.nome }}</span>
      <span class="flex items-center gap-2">
        <i class="block h-3 rounded-r-[4px]" :style="{ width: `calc((100% - 70px) * ${i.n / maximo})`, minWidth: '2px', background: COR_SERIE }" />
        <span class="whitespace-nowrap tabular-nums"><b class="font-semibold text-neutral-900">{{ formatarNumero(i.n) }}</b> <span class="text-neutral-500">{{ percentual(i.n, soma) }}</span></span>
      </span>
    </li>
  </ol>
</template>
