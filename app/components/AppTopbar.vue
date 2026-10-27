<script setup lang="ts">
import type { UsuarioSistema } from '~/composables/usePerfil'

const props = defineProps<{ perfil: UsuarioSistema | null }>()
const emit = defineEmits<{ sair: [] }>()

const nomesPerfil: Record<string, string> = {
  administrador: 'Administrador',
  ouvidoria: 'Ouvidoria',
  diretor: 'Diretor',
}

const iniciais = computed(() => {
  const partes = (props.perfil?.nome ?? '').trim().split(/\s+/).filter(Boolean)
  return ((partes[0]?.[0] ?? '') + (partes.length > 1 ? partes.at(-1)![0] : '')).toUpperCase()
})
</script>

<template>
  <header class="flex h-topbar items-center gap-5 bg-primary-700 px-5 text-white">
    <NuxtLink to="/" class="flex items-center gap-5">
      <img src="/logo-branca.png" alt="DMAE e Prefeitura de Uberlândia" class="h-[26px] w-auto">
      <span class="border-l border-white/30 pl-5 font-display text-[0.95rem] font-bold tracking-[0.01em]">Ouvidoria</span>
    </NuxtLink>
    <span class="flex-1" />
    <div
      class="hidden w-[260px] rounded-control bg-white/[0.12] px-3 py-2 text-[0.82rem] text-primary-100 md:block"
      title="Busca disponível na Fase 2"
    >
      Buscar por nº, protocolo ou bairro
    </div>
    <div v-if="perfil" class="flex items-center gap-2.5 text-[0.82rem]">
      <span class="grid h-[30px] w-[30px] place-items-center rounded-full bg-primary-100 text-[0.75rem] font-bold text-primary-800">
        {{ iniciais }}
      </span>
      <span class="hidden sm:inline">{{ perfil.nome }} · {{ nomesPerfil[perfil.perfil] }}</span>
      <button class="ml-2 rounded-control px-2 py-1 text-primary-100 hover:bg-white/10 hover:text-white" @click="emit('sair')">
        Sair
      </button>
    </div>
  </header>
</template>
