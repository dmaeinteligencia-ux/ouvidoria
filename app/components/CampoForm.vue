<script setup lang="ts">
// Rótulo, campo, dica e erro no padrão do guia visual. "grupo" usa <fieldset> para radios.
defineProps<{ rotulo: string, obrigatorio?: boolean, erro?: string, dica?: string, grupo?: boolean }>()
</script>

<template>
  <component :is="grupo ? 'fieldset' : 'label'" class="grid content-start gap-1.5" :class="{ 'campo-com-erro': erro }">
    <component :is="grupo ? 'legend' : 'span'" class="campo-rotulo mb-1.5">
      {{ rotulo }}<i v-if="obrigatorio" class="ml-0.5 not-italic text-danger">*</i>
    </component>
    <slot />
    <span v-if="erro" class="text-[0.74rem] text-danger">{{ erro }}</span>
    <span v-else-if="dica" class="text-[0.74rem] text-neutral-500">{{ dica }}</span>
  </component>
</template>
