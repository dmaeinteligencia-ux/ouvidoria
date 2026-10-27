<script setup lang="ts">
// Barra lateral colorida + dias úteis restantes (guia visual: ok, atenção, hoje, vencida, suspenso).
const props = defineProps<{ diasRestantes: number | null, prazo: string | null, suspenso?: boolean }>()

const faixa = computed(() => {
  if (props.suspenso) return { cor: 'bg-neutral-400', texto: 'text-neutral-400', rotulo: 'Suspenso' }
  const d = props.diasRestantes
  if (d === null) return { cor: 'bg-neutral-400', texto: 'text-neutral-400', rotulo: 'Respondida' }
  if (d < 0) return { cor: 'bg-danger', texto: 'text-danger', rotulo: `${d} d.u.` }
  if (d === 0) return { cor: 'bg-due', texto: 'text-due', rotulo: 'Hoje' }
  if (d <= 2) return { cor: 'bg-warning', texto: 'text-warning', rotulo: `${d} d.u.` }
  return { cor: 'bg-success', texto: 'text-success', rotulo: `${d} d.u.` }
})

const data = computed(() => {
  if (props.suspenso) return 'aguarda cidadão'
  if (!props.prazo) return ''
  const [, mes, dia] = props.prazo.split('-')
  return `${dia}/${mes}`
})
</script>

<template>
  <span class="inline-grid grid-cols-[4px_auto] items-center gap-x-2 whitespace-nowrap">
    <span class="row-span-2 self-stretch rounded-sm" :class="faixa.cor" />
    <b class="font-mono text-[0.8rem] font-semibold leading-tight" :class="faixa.texto">{{ faixa.rotulo }}</b>
    <small class="text-[0.72rem] text-neutral-500">{{ data }}</small>
  </span>
</template>
