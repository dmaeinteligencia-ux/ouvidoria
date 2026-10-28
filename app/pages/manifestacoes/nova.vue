<script setup lang="ts">
const salvando = ref(false)

async function salvo(id: number) {
  refreshNuxtData('resumo-painel')
  clearNuxtData('lista-manifestacoes')
  await navigateTo(`/manifestacoes/${id}?novo=1`)
}
</script>

<template>
  <CabecalhoPagina titulo="Nova manifestação" subtitulo="Campos com * são obrigatórios (RN01). Nenhum dado pessoal do manifestante é guardado (RN05).">
    <template #acoes>
      <NuxtLink to="/manifestacoes" class="btn btn-fantasma btn-pequeno">Cancelar</NuxtLink>
      <button type="submit" form="form-manifestacao" class="btn btn-primario btn-pequeno" :disabled="salvando">
        {{ salvando ? 'Salvando…' : 'Salvar manifestação' }}
      </button>
    </template>
  </CabecalhoPagina>
  <FormManifestacao v-model:salvando="salvando" @salvo="salvo" />
</template>
