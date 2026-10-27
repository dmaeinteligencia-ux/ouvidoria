<script setup lang="ts">
import { SITUACOES, type Situacao } from '~/utils/situacao'

const props = defineProps<{ situacao: Situacao, arquivada?: boolean }>()
const info = computed(() => SITUACOES.find(s => s.valor === props.situacao))
</script>

<template>
  <span class="inline-flex items-center gap-1.5">
    <span
      class="inline-flex items-center gap-1.5 whitespace-nowrap rounded-full py-[5px] pl-2 pr-2.5 text-[0.78rem] font-semibold leading-none"
      :class="info?.classes"
    >
      <span class="h-[7px] w-[7px] rounded-full bg-current" />
      {{ info?.nome }}
    </span>
    <span
      v-if="arquivada"
      class="inline-flex items-center gap-1.5 whitespace-nowrap rounded-full bg-white py-[5px] pl-2 pr-2.5 text-[0.78rem] font-semibold leading-none text-status-arquivada ring-1 ring-inset ring-neutral-300"
    >
      <span class="h-[7px] w-[7px] rounded-full ring-[1.5px] ring-inset ring-current" />
      Arquivada
    </span>
  </span>
</template>
