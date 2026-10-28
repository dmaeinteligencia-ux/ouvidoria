<script setup lang="ts">
definePageMeta({ layout: 'vazio' })

// Volta dos links enviados por e-mail (convite e nova senha). Esses links trazem a sessão no
// fragmento do endereço (#access_token=...), que o cliente do Supabase em modo PKCE não lê sozinho.
const supabase = useSupabaseClient()
const user = useSupabaseUser()
const route = useRoute()
const erro = ref('')
const proximo = computed(() => {
  const p = route.query.proximo
  return typeof p === 'string' && p.startsWith('/') && !p.startsWith('//') ? p : '/'
})

onMounted(async () => {
  const fragmento = new URLSearchParams(window.location.hash.slice(1))
  if (fragmento.get('error')) {
    erro.value = fragmento.get('error_code') === 'otp_expired'
      ? 'Este link expirou ou já foi usado. Peça ao administrador um novo envio.'
      : 'Não foi possível abrir o link. Peça ao administrador um novo envio.'
    return
  }
  const access = fragmento.get('access_token')
  const refresh = fragmento.get('refresh_token')
  if (access && refresh) {
    const { error } = await supabase.auth.setSession({ access_token: access, refresh_token: refresh })
    if (error) {
      erro.value = 'Não foi possível abrir o link. Peça ao administrador um novo envio.'
      return
    }
    history.replaceState(null, '', window.location.pathname + window.location.search)
  }
})

watch(user, () => {
  if (user.value) navigateTo(proximo.value)
}, { immediate: true })
</script>

<template>
  <div class="grid min-h-screen place-items-center p-6">
    <div v-if="erro" class="cartao grid max-w-[380px] gap-3 p-6">
      <p class="text-[0.9rem] text-danger">{{ erro }}</p>
      <NuxtLink to="/login" class="btn btn-secundario">Ir para a entrada</NuxtLink>
    </div>
    <p v-else class="text-[0.9rem] text-neutral-500">Entrando…</p>
  </div>
</template>
