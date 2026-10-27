<script setup lang="ts">
defineProps<{ rotulo: string, valor: string | number, detalhe?: string, destaque?: 'atencao' | 'vencida' }>()
</script>

<template>
  <div
    class="cartao grid gap-1 px-4 py-3.5"
    :class="{
      'shadow-[inset_0_3px_0_theme(colors.due.DEFAULT)]': destaque === 'atencao',
      'shadow-[inset_0_3px_0_theme(colors.danger.DEFAULT)]': destaque === 'vencida',
    }"
  >
    <span class="text-[0.78rem] font-medium text-neutral-500">{{ rotulo }}</span>
    <span
      class="font-display text-[1.9rem] font-extrabold leading-none tabular-nums"
      :class="{ 'text-due': destaque === 'atencao', 'text-danger': destaque === 'vencida' }"
    >{{ valor }}</span>
    <span v-if="detalhe" class="text-[0.74rem] text-neutral-500">{{ detalhe }}</span>
  </div>
</template>
