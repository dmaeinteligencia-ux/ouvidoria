<script setup lang="ts">
definePageMeta({ layout: 'vazio' })

const supabase = useSupabaseClient()
const email = ref('')
const senha = ref('')
const erro = ref('')
const enviando = ref(false)

async function entrar() {
  erro.value = ''
  enviando.value = true
  const { error } = await supabase.auth.signInWithPassword({ email: email.value, password: senha.value })
  enviando.value = false
  if (error) {
    erro.value = 'E-mail ou senha inválidos.'
    return
  }
  await navigateTo('/')
}
</script>

<template>
  <form class="w-full max-w-sm space-y-4 rounded-panel bg-white p-6 shadow" @submit.prevent="entrar">
    <h1 class="font-display text-h1 font-bold text-primary">Ouvidoria DMAE</h1>
    <label class="block text-sm">
      E-mail institucional
      <input v-model="email" type="email" required autocomplete="username" class="campo mt-1">
    </label>
    <label class="block text-sm">
      Senha
      <input v-model="senha" type="password" required autocomplete="current-password" class="campo mt-1">
    </label>
    <p v-if="erro" class="text-sm text-danger">{{ erro }}</p>
    <button type="submit" class="botao w-full" :disabled="enviando">Entrar</button>
  </form>
</template>
