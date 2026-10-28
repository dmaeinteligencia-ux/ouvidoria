<script setup lang="ts">
// Extrato mensal em Excel, no formato da planilha da Ouvidoria (manifestações recebidas no mês).
import type { LinhaExtrato } from '~/utils/extrato'

const supabase = useSupabaseClient()
const { data: perfil } = await usePerfil()
const ehEquipe = computed(() => perfil.value?.perfil === 'administrador' || perfil.value?.perfil === 'ouvidoria')

const hoje = hojeBrasilia()
const ano = ref(Number(hoje.slice(0, 4)))
const numeroMes = ref(Number(hoje.slice(5, 7)))
const mes = computed(() => `${ano.value}-${String(numeroMes.value).padStart(2, '0')}`)
// Registros desde setembro de 2023 (início da planilha).
const anos = Array.from({ length: Number(hoje.slice(0, 4)) - 2022 }, (_, i) => 2023 + i).reverse()
const MESES = ['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro']

const { data: linhas, error, pending } = await useAsyncData('extrato', async () => {
  if (!ehEquipe.value) return []
  const { data, error } = await supabase.rpc('extrato_mensal', { p_ano: ano.value, p_mes: numeroMes.value })
  if (error) throw error
  return (data ?? []) as unknown as LinhaExtrato[]
}, { watch: [mes] })

const nomeMes = computed(() => `${MESES[numeroMes.value - 1]} de ${ano.value}`)

const resumo = computed(() => {
  const l = linhas.value ?? []
  return {
    total: l.length,
    respondidas: l.filter(x => x.situacao === 'respondida').length,
    arquivadas: l.filter(x => x.arquivada).length,
    emAberto: l.filter(x => x.situacao !== 'respondida').length,
  }
})

const gerando = ref(false)
const falha = ref('')
async function baixar() {
  falha.value = ''
  gerando.value = true
  try {
    const arquivo = await gerarExtrato(linhas.value ?? [], ano.value, numeroMes.value)
    const url = URL.createObjectURL(arquivo)
    const a = document.createElement('a')
    a.href = url
    a.download = `Extrato Ouvidoria DMAE ${mes.value}.xlsx`
    a.click()
    URL.revokeObjectURL(url)
  }
  catch (e) {
    falha.value = mensagemErro(e)
  }
  finally {
    gerando.value = false
  }
}
</script>

<template>
  <AvisoCaixa v-if="!ehEquipe" titulo="Acesso restrito" tipo="atencao">O extrato mensal é gerado pela equipe da Ouvidoria.</AvisoCaixa>
  <template v-else>
    <CabecalhoPagina titulo="Extrato mensal" subtitulo="Planilha no formato atual da Ouvidoria, com as manifestações recebidas no mês." />

    <section class="cartao grid gap-4 p-4 sm:max-w-[640px]">
      <div class="flex flex-wrap items-end gap-3">
        <CampoForm rotulo="Mês de recebimento">
          <select v-model="numeroMes" class="campo">
            <option v-for="(nome, i) in MESES" :key="nome" :value="i + 1">{{ nome }}</option>
          </select>
        </CampoForm>
        <CampoForm rotulo="Ano">
          <select v-model="ano" class="campo font-mono">
            <option v-for="a in anos" :key="a" :value="a">{{ a }}</option>
          </select>
        </CampoForm>
        <button class="btn btn-primario" :disabled="gerando || pending || !linhas?.length" @click="baixar">
          {{ gerando ? 'Gerando…' : 'Baixar Excel' }}
        </button>
      </div>

      <AvisoCaixa v-if="error" titulo="Não foi possível montar o extrato" tipo="erro">{{ mensagemErro(error) }}</AvisoCaixa>
      <AvisoCaixa v-else-if="falha" titulo="Não foi possível gerar o arquivo" tipo="erro">{{ falha }}</AvisoCaixa>
      <template v-else-if="!pending">
        <p v-if="!resumo.total" class="text-[0.84rem] text-neutral-500">Nenhuma manifestação recebida em {{ nomeMes.toLowerCase() }}.</p>
        <dl v-else class="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <div class="grid gap-0.5"><dt class="rotulo-caps">Recebidas</dt><dd class="font-display text-[1.4rem] font-extrabold">{{ resumo.total }}</dd></div>
          <div class="grid gap-0.5"><dt class="rotulo-caps">Respondidas</dt><dd class="font-display text-[1.4rem] font-extrabold">{{ resumo.respondidas }}</dd></div>
          <div class="grid gap-0.5"><dt class="rotulo-caps">Arquivadas</dt><dd class="font-display text-[1.4rem] font-extrabold">{{ resumo.arquivadas }}</dd></div>
          <div class="grid gap-0.5"><dt class="rotulo-caps">Em aberto</dt><dd class="font-display text-[1.4rem] font-extrabold">{{ resumo.emAberto }}</dd></div>
        </dl>
      </template>

      <p class="text-[0.76rem] text-neutral-500">
        As 35 colunas seguem a planilha. A planilha tem lugar para uma reabertura; as seguintes e os pedidos negados vão
        em Observações, junto com o nº da manifestação no sistema.
      </p>
    </section>
  </template>
</template>
