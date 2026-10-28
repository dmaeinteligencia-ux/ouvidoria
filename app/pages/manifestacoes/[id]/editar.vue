<script setup lang="ts">
import type { Manifestacao } from '~/components/FormManifestacao.vue'

const supabase = useSupabaseClient()
const route = useRoute()
const id = Number(route.params.id)
const salvando = ref(false)

const { data: manifestacao } = await useAsyncData(`manifestacao-editar-${id}`, async () => {
  const { data, error } = await supabase.from('manifestacoes').select('*').eq('id', id).maybeSingle()
  if (error) throw error
  return data as Manifestacao | null
})

async function salvo() {
  refreshNuxtData('resumo-painel')
  clearNuxtData(['lista-manifestacoes', `manifestacao-${id}`])
  await navigateTo(`/manifestacoes/${id}`)
}
</script>

<template>
  <AvisoCaixa v-if="!manifestacao" titulo="Manifestação não encontrada" tipo="atencao">
    <NuxtLink to="/manifestacoes" class="font-semibold text-primary-700 hover:underline">Voltar para a lista</NuxtLink>
  </AvisoCaixa>
  <template v-else>
    <CabecalhoPagina :titulo="`Corrigir ${manifestacao.numero}`" subtitulo="Cada alteração fica no histórico com seu nome, a data e os valores antigo e novo (RN23).">
      <template #acoes>
        <NuxtLink :to="`/manifestacoes/${id}`" class="btn btn-fantasma btn-pequeno">Cancelar</NuxtLink>
        <button type="submit" form="form-manifestacao" class="btn btn-primario btn-pequeno" :disabled="salvando">
          {{ salvando ? 'Salvando…' : 'Salvar correções' }}
        </button>
      </template>
    </CabecalhoPagina>
    <FormManifestacao v-model:salvando="salvando" :inicial="manifestacao" @salvo="salvo" />
  </template>
</template>
