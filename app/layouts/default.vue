<script setup lang="ts">
const supabase = useSupabaseClient()
const { data: perfil } = await usePerfil()
const { data: resumo } = await useResumoPainel()

async function sair() {
  await supabase.auth.signOut()
  await navigateTo('/login')
}
</script>

<template>
  <div class="grid min-h-screen grid-rows-[56px_1fr] bg-neutral-50 text-[14px] leading-[1.45]">
    <AppTopbar :perfil="perfil ?? null" @sair="sair" />
    <div class="flex min-w-0">
      <AppSidebar :perfil="perfil?.perfil ?? null" :contagens="resumo?.contagens" />
      <main class="grid min-w-0 flex-1 content-start gap-[18px] px-4 pb-7 pt-[22px] sm:px-[26px]">
        <slot />
      </main>
    </div>
  </div>
</template>
