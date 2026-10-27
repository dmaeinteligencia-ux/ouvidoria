<script setup lang="ts">
definePageMeta({ layout: 'vazio' })

const user = useSupabaseUser()
watch(user, () => {
  if (user.value) navigateTo('/')
}, { immediate: true })
</script>

<template>
  <p class="text-sm text-slate-600">Entrando…</p>
</template>
