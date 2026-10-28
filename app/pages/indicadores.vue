<script setup lang="ts">
// Painel Gerencial: a Ouvidoria vê todas as diretorias; o diretor, só a própria (garantido no banco).
const { data: perfil } = await usePerfil()
const { data: listas } = await useListas()

const ehDiretor = computed(() => perfil.value?.perfil === 'diretor')
const podeVer = computed(() => !!perfil.value)
const diretoriaDoDiretor = computed(() => nomePorId(listas.value?.diretorias, perfil.value?.diretoria_id ?? null))

const opcoes = computed(() => ({
  tipos: listas.value?.tipos ?? [],
  canais: (listas.value?.canais ?? []).map(c => ({ id: c.id, nome: c.nome_painel })),
  identificacoes: listas.value?.identificacoes ?? [],
  assuntos: listas.value?.assuntos ?? [],
  bairros: listas.value?.bairros ?? [],
  diretorias: ehDiretor.value ? undefined : listas.value?.diretorias ?? [],
}))

const filtros = reactive(filtrosIniciais())
const { data: dados, error, pending } = await useIndicadores(filtros, true)
</script>

<template>
  <AvisoCaixa v-if="!podeVer" titulo="Acesso restrito" tipo="atencao">Seu login ainda não tem perfil no sistema.</AvisoCaixa>
  <template v-else>
    <CabecalhoPagina
      titulo="Painel Gerencial"
      :subtitulo="ehDiretor ? nomeDiretoriaCurto(diretoriaDoDiretor) : 'Todas as diretorias, ou as escolhidas no filtro'"
    >
      <template v-if="!ehDiretor" #acoes>
        <NuxtLink to="/painel" class="btn btn-fantasma btn-pequeno" target="_blank">Ver Painel Geral (público)</NuxtLink>
      </template>
    </CabecalhoPagina>
    <div class="grid items-start gap-3.5 lg:grid-cols-[260px_1fr]">
      <FiltrosPainel :filtros="filtros" :opcoes="opcoes" gerencial />
      <div class="min-w-0">
        <AvisoCaixa v-if="error" titulo="Não foi possível carregar os indicadores" tipo="erro">{{ mensagemErro(error) }}</AvisoCaixa>
        <PainelIndicadores v-else-if="dados" :dados="dados" :agrupar="filtros.agrupar" gerencial :class="{ 'opacity-60 transition-opacity': pending }" />
      </div>
    </div>
    <p class="text-[0.74rem] text-neutral-500">
      Período pela data de recebimento no DMAE; diretoria pelo encaminhamento atual. Prazo médio e cumprimento do prazo
      consideram a primeira resposta; arquivadas não entram no prazo médio nem na resolutividade.
    </p>
  </template>
</template>
