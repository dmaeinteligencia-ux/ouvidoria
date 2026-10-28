<script setup lang="ts">
definePageMeta({ layout: 'vazio' })

// Entrada pelos links de convite e de nova senha gerados na tela Usuários. O link traz o código de
// uso único (?codigo=...&tipo=invite|recovery), que só é validado quando a pessoa clica em
// Continuar: a prévia de link do WhatsApp, do Teams e dos filtros de e-mail abre o endereço antes
// e, se o código fosse usado ao abrir, o link chegaria já gasto.
// Links antigos, que passavam pelo /verify do Supabase, trazem a sessão no fragmento
// (#access_token=...), que o cliente do Supabase em modo PKCE não lê sozinho.
const supabase = useSupabaseClient()
const user = useSupabaseUser()
const route = useRoute()
const erro = ref('')
const entrando = ref(false)
const proximo = computed(() => {
  const p = route.query.proximo
  return typeof p === 'string' && p.startsWith('/') && !p.startsWith('//') ? p : '/'
})
const codigo = typeof route.query.codigo === 'string' ? route.query.codigo : ''
const tipo = route.query.tipo === 'invite' ? 'invite' : 'recovery'
const aguardandoClique = ref(!!codigo)

const LINK_GASTO = 'Este link expirou ou já foi usado. Peça ao administrador um novo link.'
const FALHOU = 'Não foi possível abrir o link. Peça ao administrador um novo link.'

async function continuar() {
  entrando.value = true
  erro.value = ''
  const { error } = await supabase.auth.verifyOtp({ token_hash: codigo, type: tipo })
  entrando.value = false
  if (error) {
    erro.value = /expired|invalid|not found/i.test(error.message) ? LINK_GASTO : FALHOU
    return
  }
  aguardandoClique.value = false
}

onMounted(async () => {
  if (codigo) return
  const fragmento = new URLSearchParams(window.location.hash.slice(1))
  if (fragmento.get('error')) {
    erro.value = fragmento.get('error_code') === 'otp_expired' ? LINK_GASTO : FALHOU
    return
  }
  const access = fragmento.get('access_token')
  const refresh = fragmento.get('refresh_token')
  if (access && refresh) {
    const { error } = await supabase.auth.setSession({ access_token: access, refresh_token: refresh })
    if (error) {
      erro.value = FALHOU
      return
    }
    history.replaceState(null, '', window.location.pathname + window.location.search)
  }
})

watch([user, aguardandoClique], () => {
  if (user.value && !aguardandoClique.value) navigateTo(proximo.value, { replace: true })
}, { immediate: true })
</script>

<template>
  <div class="grid min-h-screen place-items-center bg-neutral-50 p-6">
    <div v-if="codigo && aguardandoClique" class="cartao grid w-full max-w-[380px] gap-4 p-6">
      <img src="/logo-preta.png" alt="DMAE e Prefeitura de Uberlândia" class="h-7 w-auto self-start justify-self-start">
      <div>
        <h1 class="font-display text-[1.5rem] font-extrabold leading-tight">Sistema da Ouvidoria</h1>
        <p class="text-[0.85rem] text-neutral-500">
          {{ tipo === 'invite' ? 'Você recebeu um convite de acesso. Clique em Continuar para escolher a sua senha.' : 'Clique em Continuar para escolher a nova senha.' }}
        </p>
      </div>
      <p v-if="erro" class="text-[0.8rem] text-danger">{{ erro }}</p>
      <button v-if="!erro" type="button" class="btn btn-primario py-3" :disabled="entrando" @click="continuar">{{ entrando ? 'Entrando…' : 'Continuar' }}</button>
      <NuxtLink v-else to="/login" class="btn btn-secundario">Ir para a entrada</NuxtLink>
    </div>
    <div v-else-if="erro" class="cartao grid max-w-[380px] gap-3 p-6">
      <p class="text-[0.9rem] text-danger">{{ erro }}</p>
      <NuxtLink to="/login" class="btn btn-secundario">Ir para a entrada</NuxtLink>
    </div>
    <p v-else class="text-[0.9rem] text-neutral-500">Entrando…</p>
  </div>
</template>
