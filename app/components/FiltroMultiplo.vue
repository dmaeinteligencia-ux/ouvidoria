<script setup lang="ts">
// Filtro de vários valores: resumo ("Todos", "Reclamação", "3 selecionados") que abre uma lista de caixas.
// Lista vazia = todos. Com busca para listas longas (assuntos, bairros).
const props = defineProps<{ rotulo: string, opcoes: { valor: string, nome: string }[] }>()
const modelo = defineModel<string[]>({ default: () => [] })
const busca = ref('')

const resumo = computed(() => {
  if (!modelo.value.length) return 'Todos'
  if (modelo.value.length === 1) return props.opcoes.find(o => o.valor === modelo.value[0])?.nome ?? '1 selecionado'
  return `${modelo.value.length} selecionados`
})
const filtradas = computed(() => {
  const termo = normalizar(busca.value)
  return termo ? props.opcoes.filter(o => normalizar(o.nome).includes(termo)) : props.opcoes
})
function normalizar(t: string) {
  return t.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase()
}
function alternar(valor: string) {
  modelo.value = modelo.value.includes(valor) ? modelo.value.filter(v => v !== valor) : [...modelo.value, valor]
}
</script>

<template>
  <details class="group rounded-control border bg-white" :class="modelo.length ? 'border-primary-300' : 'border-neutral-200'">
    <summary class="flex cursor-pointer list-none items-center justify-between gap-2 px-2.5 py-2 text-[0.8rem] focus-visible:shadow-focus [&::-webkit-details-marker]:hidden">
      <span class="grid min-w-0">
        <span class="text-[0.68rem] font-semibold uppercase tracking-[0.08em] text-neutral-500">{{ rotulo }}</span>
        <span class="truncate" :class="modelo.length ? 'font-semibold text-primary-800' : 'text-neutral-700'">{{ resumo }}</span>
      </span>
      <svg class="h-3 w-3 shrink-0 transition-transform group-open:rotate-180" viewBox="0 0 12 12" aria-hidden="true"><path d="M3 4.5 6 7.5 9 4.5" fill="none" stroke="currentColor" stroke-width="1.5" /></svg>
    </summary>
    <div class="grid gap-1 border-t border-neutral-100 px-2 pb-2 pt-1.5">
      <input v-if="opcoes.length > 12" v-model="busca" type="search" class="campo !h-8 !py-1 text-[0.78rem]" :placeholder="`Buscar ${rotulo.toLowerCase()}`" :aria-label="`Buscar ${rotulo.toLowerCase()}`">
      <button v-if="modelo.length" type="button" class="justify-self-start px-1 text-[0.74rem] font-semibold text-primary-700 hover:underline" @click="modelo = []">Limpar</button>
      <div class="grid max-h-[220px] gap-0.5 overflow-y-auto">
        <label v-for="o in filtradas" :key="o.valor" class="flex cursor-pointer items-start gap-2 rounded-[4px] px-1 py-1 text-[0.8rem] text-neutral-700 hover:bg-neutral-25">
          <input type="checkbox" class="mt-0.5 h-3.5 w-3.5 shrink-0 accent-primary-700" :checked="modelo.includes(o.valor)" @change="alternar(o.valor)">
          <span>{{ o.nome }}</span>
        </label>
        <span v-if="!filtradas.length" class="px-1 py-1 text-[0.76rem] text-neutral-500">Nada encontrado.</span>
      </div>
    </div>
  </details>
</template>
