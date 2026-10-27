<script setup lang="ts">
defineProps<{ titulo: string, subtitulo?: string }>()
</script>

<template>
  <div class="flex flex-wrap items-end justify-between gap-4">
    <div>
      <h1 class="font-display text-[1.45rem] font-extrabold leading-tight text-neutral-900">{{ titulo }}</h1>
      <p v-if="subtitulo" class="mt-1 text-[0.82rem] text-neutral-500">{{ subtitulo }}</p>
    </div>
    <div class="flex gap-2">
      <slot name="acoes" />
    </div>
  </div>
</template>
