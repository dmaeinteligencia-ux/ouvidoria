<script setup lang="ts">
const { data: perfil } = await usePerfil()
// O diretor só usa o Painel Gerencial da própria diretoria.
if (perfil.value?.perfil === 'diretor') await navigateTo('/indicadores', { replace: true })
const { data: resumo } = await useResumoPainel()

const hoje = new Date()
const dataExtenso = new Intl.DateTimeFormat('pt-BR', {
  weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', timeZone: 'America/Sao_Paulo',
}).format(hoje)
const subtitulo = dataExtenso.charAt(0).toUpperCase() + dataExtenso.slice(1)
const nomeMes = new Intl.DateTimeFormat('pt-BR', { month: 'long', year: 'numeric', timeZone: 'America/Sao_Paulo' }).format(hoje)

const maiorCarga = computed(() => Math.max(1, ...(resumo.value?.cargaPorDiretoria ?? []).map(c => c.total)))
</script>

<template>
  <div v-if="!perfil" class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 rounded-control border border-[#F3D58A] bg-[#FFF8E6] px-3.5 py-3 text-[0.86rem] text-neutral-800">
    <span class="row-span-2 grid h-5 w-5 place-items-center rounded-full bg-warning text-[0.75rem] font-bold text-white">!</span>
    <b class="font-semibold">Seu login ainda não tem perfil no sistema</b>
    <span>Peça ao administrador para cadastrá-lo.</span>
  </div>

  <template v-else>
    <CabecalhoPagina titulo="Painel" :subtitulo="subtitulo">
      <template #acoes>
        <NuxtLink to="/extrato" class="btn btn-secundario btn-pequeno">Extrato do mês</NuxtLink>
        <NuxtLink to="/manifestacoes/nova" class="btn btn-primario btn-pequeno">+ Nova manifestação</NuxtLink>
      </template>
    </CabecalhoPagina>

    <div class="grid grid-cols-2 gap-3 xl:grid-cols-4">
      <KpiCartao rotulo="Em aberto" :valor="resumo?.contagens.abertas ?? 0" :detalhe="`${resumo?.registradasNoMes ?? 0} registradas este mês`" />
      <KpiCartao rotulo="Vencem em até 2 d.u." :valor="resumo?.atencao ?? 0" :detalhe="`${resumo?.vencemHoje ?? 0} vencem hoje`" destaque="atencao" />
      <KpiCartao rotulo="Vencidas" :valor="resumo?.vencidas ?? 0" detalhe="sem resposta após o prazo" destaque="vencida" />
      <KpiCartao
        rotulo="Respondidas no prazo (mês)"
        :valor="resumo?.percentualNoPrazo === null || resumo?.percentualNoPrazo === undefined ? '–' : `${resumo.percentualNoPrazo}%`"
        :detalhe="resumo?.tempoMedio ? `tempo médio ${resumo.tempoMedio.toFixed(1).replace('.', ',')} d.u.` : 'nenhuma resposta no mês'"
      />
    </div>

    <div class="grid gap-3 xl:grid-cols-[1.35fr_1fr]">
      <section class="cartao">
        <div class="cartao-topo"><b class="cartao-titulo">Em aberto por diretoria</b><span class="cartao-nota">{{ nomeMes }}</span></div>
        <div v-if="resumo?.cargaPorDiretoria.length" class="grid gap-2.5 px-4 pb-4 pt-3">
          <div v-for="c in resumo.cargaPorDiretoria" :key="c.diretoria" class="grid grid-cols-[minmax(0,210px)_1fr_34px] items-center gap-2.5 text-[0.8rem]">
            <span class="truncate" :title="c.diretoria">{{ nomeDiretoriaCurto(c.diretoria) }}</span>
            <span class="flex h-3 overflow-hidden rounded-[3px] bg-neutral-50">
              <i class="block h-full bg-primary-700" :style="{ width: `${(c.noPrazo / maiorCarga) * 100}%` }" />
              <i class="block h-full bg-due" :style="{ width: `${(c.atencao / maiorCarga) * 100}%` }" />
              <i class="block h-full bg-danger" :style="{ width: `${(c.vencidas / maiorCarga) * 100}%` }" />
            </span>
            <span class="text-right font-mono text-[0.78rem] font-medium text-neutral-700">{{ c.total }}</span>
          </div>
        </div>
        <p v-else class="px-4 py-6 text-[0.84rem] text-neutral-500">Nenhuma manifestação em aberto.</p>
        <div class="flex gap-3.5 px-4 pb-3.5 text-[0.72rem] text-neutral-500">
          <span class="flex items-center gap-1.5"><i class="h-[9px] w-[9px] rounded-sm bg-primary-700" />No prazo</span>
          <span class="flex items-center gap-1.5"><i class="h-[9px] w-[9px] rounded-sm bg-due" />Vence em até 2 d.u.</span>
          <span class="flex items-center gap-1.5"><i class="h-[9px] w-[9px] rounded-sm bg-danger" />Vencida</span>
        </div>
      </section>

      <section class="cartao">
        <div class="cartao-topo"><b class="cartao-titulo">Precisam de ação hoje</b><span class="cartao-nota">por prazo</span></div>
        <table v-if="resumo?.urgentes.length" class="lista">
          <tbody>
            <tr v-for="m in resumo.urgentes" :key="m.id" class="cursor-pointer hover:bg-neutral-25" :class="{ '!bg-[#FFFAF9]': m.dias_restantes! < 0 }" @click="navigateTo(`/manifestacoes/${m.id}`)">
              <td>
                <NuxtLink :to="`/manifestacoes/${m.id}`" class="numero-interno hover:underline" @click.stop>{{ m.numero }}</NuxtLink>
                <div class="font-semibold text-neutral-900">{{ nomeExibicao(m.assunto) }}</div>
              </td>
              <td class="text-right"><PrazoIndicador :dias-restantes="m.dias_restantes" :prazo="m.prazo" /></td>
            </tr>
          </tbody>
        </table>
        <p v-else class="px-4 py-6 text-[0.84rem] text-neutral-500">Nada vence nos próximos 2 dias úteis.</p>
      </section>
    </div>
  </template>
</template>
