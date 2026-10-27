<script setup lang="ts">
definePageMeta({ layout: 'vazio' })

const supabase = useSupabaseClient()
const user = useSupabaseUser()
const senha = ref('')
const confirmacao = ref('')
const erro = ref('')
const salvando = ref(false)

async function salvar() {
  erro.value = ''
  if (senha.value.length < 8) {
    erro.value = 'A senha precisa ter pelo menos 8 caracteres.'
    return
  }
  if (senha.value !== confirmacao.value) {
    erro.value = 'As duas senhas não conferem.'
    return
  }
  salvando.value = true
  const { error } = await supabase.auth.updateUser({ password: senha.value })
  salvando.value = false
  if (error) {
    erro.value = 'Não foi possível salvar. Peça um novo link na tela de entrada.'
    return
  }
  await navigateTo('/')
}
</script>

<template>
  <div class="grid min-h-screen place-items-center bg-neutral-50 p-6">
    <form class="cartao grid w-full max-w-[380px] gap-4 p-6" @submit.prevent="salvar">
      <img src="/logo-preta.png" alt="DMAE e Prefeitura de Uberlândia" class="h-7 w-auto self-start justify-self-start">
      <div>
        <h1 class="font-display text-[1.5rem] font-extrabold leading-tight">Nova senha</h1>
        <p class="text-[0.85rem] text-neutral-500">
          {{ user ? 'Escolha a nova senha de acesso.' : 'Abra esta página pelo link enviado ao seu e-mail.' }}
        </p>
      </div>
      <label class="grid gap-1.5">
        <span class="campo-rotulo">Nova senha</span>
        <input v-model="senha" type="password" required autocomplete="new-password" class="campo">
      </label>
      <label class="grid gap-1.5">
        <span class="campo-rotulo">Repita a senha</span>
        <input v-model="confirmacao" type="password" required autocomplete="new-password" class="campo">
      </label>
      <p v-if="erro" class="text-[0.8rem] text-danger">{{ erro }}</p>
      <button type="submit" class="btn btn-primario py-3" :disabled="salvando || !user">Salvar senha</button>
    </form>
  </div>
</template>
