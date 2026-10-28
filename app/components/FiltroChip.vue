<script setup lang="ts">
// Filtro em forma de chip (guia visual): um <select> nativo, destacado quando foge do padrão.
// Com "padrao", o filtro sempre tem um valor da lista; sem ele, a opção vazia vale "todos".
const props = defineProps<{ rotulo: string, opcoes: { valor: string, nome: string }[], todos?: string, padrao?: string }>()
const modelo = defineModel<string>({ default: '' })
const ativo = computed(() => modelo.value !== (props.padrao ?? ''))
const nomeAtual = computed(() => props.opcoes.find(o => o.valor === modelo.value)?.nome)
</script>

<template>
  <label
    class="relative inline-flex items-center gap-1.5 rounded-control border px-2.5 py-1.5 text-[0.78rem] focus-within:shadow-focus"
    :class="ativo ? 'border-primary-300 bg-primary-50 font-semibold text-primary-800' : 'border-neutral-200 bg-white text-neutral-700 hover:bg-neutral-25'"
  >
    <span class="max-w-[220px] truncate">{{ nomeAtual ?? todos ?? rotulo }}</span>
    <svg class="h-3 w-3 shrink-0" viewBox="0 0 12 12" aria-hidden="true"><path d="M3 4.5 6 7.5 9 4.5" fill="none" stroke="currentColor" stroke-width="1.5" /></svg>
    <select v-model="modelo" class="absolute inset-0 cursor-pointer opacity-0" :aria-label="rotulo">
      <option v-if="padrao === undefined" value="">{{ todos ?? `${rotulo}: todos` }}</option>
      <option v-for="o in opcoes" :key="o.valor" :value="o.valor">{{ o.nome }}</option>
    </select>
  </label>
</template>
