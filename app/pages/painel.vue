<script setup lang="ts">
// Painel Geral (público, sem login): só números agregados, lidos por funções do banco (CI nº 6660/2025).
definePageMeta({ layout: 'vazio' })
useHead({ title: 'Painel Geral · Ouvidoria DMAE' })

const supabase = useSupabaseClient()
interface Opcao { id: number, nome: string }

const { data: opcoes } = await useAsyncData('painel-opcoes', async () => {
  const { data, error } = await supabase.rpc('painel_opcoes')
  if (error) throw error
  return data as unknown as { tipos: Opcao[], canais: Opcao[], identificacoes: Opcao[], primeiro_recebimento: string | null }
})

const filtros = reactive(filtrosIniciais())
const { data: dados, error, pending } = await useIndicadores(filtros, false)
</script>

<template>
  <div class="min-h-screen bg-neutral-50 text-[14px] leading-[1.45]">
    <header class="bg-primary-700 text-white">
      <div class="flex h-topbar items-center gap-5 px-4 sm:px-[26px]">
        <img src="/logo-branca.png" alt="DMAE e Prefeitura de Uberlândia" class="h-[26px] w-auto">
        <span class="hidden border-l border-white/30 pl-5 font-display text-[0.95rem] font-bold sm:inline">Ouvidoria</span>
      </div>
      <div class="faixa-marca" />
    </header>

    <main class="mx-auto grid max-w-[1440px] gap-[18px] px-4 pb-10 pt-[22px] sm:px-[26px]">
      <CabecalhoPagina
        titulo="Painel Geral da Ouvidoria"
        subtitulo="Manifestações recebidas pela Ouvidoria do DMAE. Os números são atualizados a cada registro."
      />
      <div class="grid items-start gap-3.5 lg:grid-cols-[260px_1fr]">
        <FiltrosPainel :filtros="filtros" :opcoes="opcoes ?? { tipos: [], canais: [], identificacoes: [] }" :primeiro-recebimento="opcoes?.primeiro_recebimento" />
        <div class="relative min-w-0">
          <AvisoCaixa v-if="error" titulo="Não foi possível carregar os indicadores" tipo="erro">{{ mensagemErro(error) }}</AvisoCaixa>
          <PainelIndicadores v-else-if="dados" :dados="dados" :agrupar="filtros.agrupar" :class="{ 'opacity-60 transition-opacity': pending }" />
        </div>
      </div>
      <p class="text-[0.74rem] text-neutral-500">
        Período pela data de recebimento no DMAE. Prazo médio e cumprimento do prazo consideram a primeira resposta;
        manifestações arquivadas não entram no prazo médio nem na resolutividade.
      </p>
    </main>
  </div>
</template>
