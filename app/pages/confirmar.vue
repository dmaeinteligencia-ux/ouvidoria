<script setup lang="ts">
definePageMeta({ layout: 'vazio' })

const user = useSupabaseUser()
watch(user, () => {
  if (user.value) navigateTo('/')
}, { immediate: true })
</script>

<template>
  <div class="grid min-h-screen place-items-center">
    <p class="text-[0.9rem] text-neutral-500">Entrando…</p>
  </div>
</template>
