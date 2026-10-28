<script setup lang="ts">
// Colunas de uma série só, com o valor no topo e quantidade e % ao passar o mouse.
export interface ItemGrafico { nome: string, n: number }

const props = defineProps<{ itens: ItemGrafico[], vazio?: string }>()

const total = computed(() => props.itens.reduce((s, i) => s + i.n, 0))
const maximo = computed(() => Math.max(1, ...props.itens.map(i => i.n)))
const ativo = ref<string | null>(null)
</script>

<template>
  <div v-if="!total" class="grid min-h-[180px] place-items-center px-4 text-center text-[0.82rem] text-neutral-500">{{ vazio ?? 'Nenhum dado no período.' }}</div>
  <div v-else class="px-4 pb-3 pt-5">
    <div class="flex h-[160px] items-end gap-1 border-b border-neutral-100">
      <div
        v-for="i in itens"
        :key="i.nome"
        tabindex="0"
        class="relative flex h-full min-w-0 flex-1 cursor-default flex-col items-center justify-end outline-none focus-visible:shadow-focus"
        @mouseenter="ativo = i.nome" @mouseleave="ativo = null" @focus="ativo = i.nome" @blur="ativo = null"
      >
        <span
          v-if="ativo === i.nome"
          class="pointer-events-none absolute bottom-full z-10 mb-1 whitespace-nowrap rounded-control bg-neutral-900 px-2 py-1 text-[0.72rem] text-white shadow-overlay"
        >{{ i.nome }}: {{ formatarNumero(i.n) }} ({{ percentual(i.n, total) }})</span>
        <span class="mb-1 text-[0.74rem] font-semibold tabular-nums text-neutral-800">{{ formatarNumero(i.n) }}</span>
        <i
          class="block w-full max-w-[24px] rounded-t-[4px] transition-opacity"
          :class="{ 'opacity-60': ativo && ativo !== i.nome }"
          :style="{ height: `${Math.max((i.n / maximo) * 120, i.n ? 2 : 0)}px`, background: COR_SERIE }"
        />
      </div>
    </div>
    <div class="mt-1.5 flex gap-1">
      <span v-for="i in itens" :key="i.nome" class="min-w-0 flex-1 text-center text-[0.7rem] leading-tight text-neutral-600 hyphens-auto [overflow-wrap:break-word]">{{ i.nome }}</span>
    </div>
  </div>
</template>
