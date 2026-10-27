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
  <div class="min-h-screen bg-slate-50 text-slate-900">
    <header class="border-b border-slate-200 bg-white">
      <div class="mx-auto flex max-w-6xl items-center justify-between px-4 py-3">
        <NuxtLink to="/" class="font-semibold text-dmae-900">Ouvidoria DMAE</NuxtLink>
        <nav v-if="perfil" class="flex items-center gap-4 text-sm">
          <NuxtLink to="/" class="hover:text-dmae-600">Início</NuxtLink>
          <NuxtLink to="/cadastros" class="hover:text-dmae-600">Cadastros</NuxtLink>
          <span class="text-slate-500">{{ perfil.nome }} · {{ nomesPerfil[perfil.perfil] }}</span>
          <button class="text-slate-600 hover:text-dmae-600" @click="sair">Sair</button>
        </nav>
      </div>
    </header>
    <main class="mx-auto max-w-6xl px-4 py-6">
      <slot />
    </main>
  </div>
</template>
