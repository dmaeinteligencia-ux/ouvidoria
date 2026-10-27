<script setup lang="ts">
const supabase = useSupabaseClient()
const { data: perfil } = await usePerfil()

const nomesPerfil: Record<string, string> = {
  administrador: 'Administrador',
  ouvidoria: 'Ouvidoria',
  diretor: 'Diretor',
}

async function sair() {
  await supabase.auth.signOut()
  await navigateTo('/login')
}
</script>

<template>
  <div class="min-h-screen bg-neutral-50 text-neutral-900">
    <header class="bg-primary text-white">
      <div class="mx-auto flex max-w-6xl items-center justify-between px-4 py-3">
        <NuxtLink to="/" class="font-display text-h2 font-bold">Ouvidoria DMAE</NuxtLink>
        <nav v-if="perfil" class="flex items-center gap-4 text-sm">
          <NuxtLink to="/" class="hover:text-primary-100">Início</NuxtLink>
          <NuxtLink to="/cadastros" class="hover:text-primary-100">Cadastros</NuxtLink>
          <span class="text-primary-100">{{ perfil.nome }} · {{ nomesPerfil[perfil.perfil] }}</span>
          <button class="text-white hover:text-primary-100" @click="sair">Sair</button>
        </nav>
      </div>
    </header>
    <main class="mx-auto max-w-6xl px-4 py-6">
      <slot />
    </main>
  </div>
</template>
