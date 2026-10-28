<script setup lang="ts">
// Avisos do guia visual: vencido/erro, atenção, informação e sucesso.
const props = withDefaults(defineProps<{ titulo: string, tipo?: 'erro' | 'atencao' | 'info' | 'sucesso' }>(), { tipo: 'info' })

const estilos = {
  erro: { caixa: 'border-[#F4B4AC] bg-danger-soft', icone: 'bg-danger', simbolo: '!' },
  atencao: { caixa: 'border-[#F3D58A] bg-[#FFF8E6]', icone: 'bg-warning', simbolo: '!' },
  info: { caixa: 'border-primary-200 bg-primary-50', icone: 'bg-primary-700', simbolo: 'i' },
  sucesso: { caixa: 'border-[#A8DDB7] bg-success-soft', icone: 'bg-success', simbolo: '✓' },
}
const estilo = computed(() => estilos[props.tipo])
</script>

<template>
  <div class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 rounded-control border px-3.5 py-3 text-[0.84rem] text-neutral-800" :class="estilo.caixa" role="status">
    <span class="row-span-2 grid h-5 w-5 place-items-center rounded-full text-[0.75rem] font-bold text-white" :class="estilo.icone">{{ estilo.simbolo }}</span>
    <b class="font-semibold">{{ titulo }}</b>
    <span v-if="$slots.default"><slot /></span>
  </div>
</template>
