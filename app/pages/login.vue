<script setup lang="ts">
definePageMeta({ layout: 'vazio' })

const supabase = useSupabaseClient()
const email = ref('')
const senha = ref('')
const erro = ref('')
const aviso = ref('')
const enviando = ref(false)

async function entrar() {
  erro.value = ''
  aviso.value = ''
  enviando.value = true
  const { error } = await supabase.auth.signInWithPassword({ email: email.value, password: senha.value })
  enviando.value = false
  if (error) {
    erro.value = 'E-mail ou senha inválidos.'
    return
  }
  await navigateTo('/')
}

async function esqueciSenha() {
  erro.value = ''
  aviso.value = ''
  if (!email.value) {
    erro.value = 'Informe seu e-mail para receber o link de nova senha.'
    return
  }
  const { error } = await supabase.auth.resetPasswordForEmail(email.value, {
    redirectTo: `${window.location.origin}/nova-senha`,
  })
  if (error) erro.value = 'Não foi possível enviar o e-mail agora. Tente de novo em instantes.'
  else aviso.value = 'Se o e-mail estiver cadastrado, você vai receber o link em instantes.'
}
</script>

<template>
  <div class="grid min-h-screen lg:grid-cols-[1.1fr_1fr]">
    <div class="relative grid content-between gap-10 overflow-hidden bg-primary-700 p-8 text-white sm:p-10">
      <img src="/logo-branca.png" alt="DMAE, Departamento Municipal de Água e Esgoto, e Prefeitura de Uberlândia" class="h-10 w-auto max-w-full self-start justify-self-start">
      <div>
        <h1 class="max-w-[12ch] font-display text-[2.4rem] font-extrabold leading-[1.05]">Ouvidoria do DMAE</h1>
        <p class="mt-3 max-w-[38ch] text-[0.95rem] text-primary-100">
          Registro, encaminhamento e acompanhamento das manifestações até a resposta ao cidadão.
        </p>
      </div>
      <small class="text-[0.75rem] text-primary-200">Acesso restrito a servidores do DMAE.</small>
      <svg class="pointer-events-none absolute -bottom-10 -right-[60px] w-[460px] opacity-[0.16]" viewBox="0 0 400 200" aria-hidden="true">
        <g fill="none" stroke="#fff" stroke-width="2">
          <path d="M0 60 Q50 30 100 60 T200 60 T300 60 T400 60" />
          <path d="M0 100 Q50 70 100 100 T200 100 T300 100 T400 100" />
          <path d="M0 140 Q50 110 100 140 T200 140 T300 140 T400 140" />
          <path d="M0 180 Q50 150 100 180 T200 180 T300 180 T400 180" />
        </g>
      </svg>
      <div class="faixa-marca absolute inset-x-0 bottom-0" aria-hidden="true" />
    </div>

    <div class="grid place-items-center bg-white p-8 sm:p-10">
      <form class="grid w-full max-w-[340px] gap-4" @submit.prevent="entrar">
        <div>
          <h2 class="font-display text-[1.5rem] font-extrabold leading-tight">Entrar</h2>
          <p class="text-[0.85rem] text-neutral-500">Use seu e-mail institucional.</p>
        </div>
        <label class="grid gap-1.5">
          <span class="campo-rotulo">E-mail</span>
          <input v-model="email" type="email" required autocomplete="username" class="campo">
        </label>
        <label class="grid gap-1.5">
          <span class="campo-rotulo">Senha</span>
          <input v-model="senha" type="password" required autocomplete="current-password" class="campo">
        </label>
        <p v-if="erro" class="text-[0.8rem] text-danger">{{ erro }}</p>
        <p v-if="aviso" class="text-[0.8rem] text-success">{{ aviso }}</p>
        <button type="submit" class="btn btn-primario py-3" :disabled="enviando">
          {{ enviando ? 'Entrando…' : 'Entrar' }}
        </button>
        <button type="button" class="text-center text-[0.82rem] text-primary-700 hover:underline" @click="esqueciSenha">
          Esqueci minha senha
        </button>
      </form>
    </div>
  </div>
</template>
