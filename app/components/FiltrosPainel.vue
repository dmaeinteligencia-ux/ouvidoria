<script setup lang="ts">
// Barra lateral de filtros dos painéis (CI nº 6660/2025). Assunto, bairro e diretoria só no Gerencial.
import type { FiltrosIndicadores } from '~/composables/useIndicadores'

interface Opcao { id: number, nome: string }
const props = defineProps<{
  filtros: FiltrosIndicadores
  opcoes: { tipos: Opcao[], canais: Opcao[], identificacoes: Opcao[], assuntos?: Opcao[], bairros?: Opcao[], diretorias?: Opcao[] }
  gerencial?: boolean
  primeiroRecebimento?: string | null
}>()

const config = useRuntimeConfig()
const linkManifestacao = config.public.linkRegistrarManifestacao as string
const linkOuvidoria = config.public.linkPaginaOuvidoria as string

const paraOpcoes = (lista: Opcao[] | undefined, exibir: (nome: string) => string = nomeExibicao) =>
  (lista ?? []).map(o => ({ valor: String(o.id), nome: exibir(o.nome) }))
const situacoes = SITUACOES.map(s => ({ valor: s.valor, nome: s.nome }))
const AGRUPAR = [{ valor: 'day', nome: 'Dia' }, { valor: 'month', nome: 'Mês' }, { valor: 'year', nome: 'Ano' }] as const

const hoje = hojeBrasilia()
function periodoRapido(tipo: 'ano' | 'mes' | '12m' | 'tudo') {
  const f = props.filtros
  f.fim = hoje
  if (tipo === 'ano') f.inicio = `${hoje.slice(0, 4)}-01-01`
  else if (tipo === 'mes') f.inicio = `${hoje.slice(0, 7)}-01`
  else if (tipo === '12m') f.inicio = `${Number(hoje.slice(0, 4)) - 1}-${hoje.slice(5, 7)}-01`
  else f.inicio = props.primeiroRecebimento ?? '2023-09-01'
  if (tipo === 'tudo' && f.agrupar === 'day') f.agrupar = 'month'
}

const algumFiltro = computed(() => {
  const f = props.filtros
  return [f.situacoes, f.tipos, f.canais, f.identificacoes, f.assuntos, f.bairros, f.diretorias].some(l => l.length)
})
function limpar() {
  const f = props.filtros
  f.situacoes = []; f.tipos = []; f.canais = []; f.identificacoes = []; f.assuntos = []; f.bairros = []; f.diretorias = []
}
</script>

<template>
  <aside class="grid content-start gap-3">
    <section class="cartao grid gap-3 p-3.5">
      <b class="cartao-titulo">Período</b>
      <div class="grid grid-cols-2 gap-2 lg:grid-cols-1">
        <label class="grid gap-1 text-[0.72rem] font-semibold text-neutral-600">
          De
          <input v-model="filtros.inicio" type="date" class="campo !h-9 font-mono text-[0.8rem]" :max="filtros.fim">
        </label>
        <label class="grid gap-1 text-[0.72rem] font-semibold text-neutral-600">
          Até
          <input v-model="filtros.fim" type="date" class="campo !h-9 font-mono text-[0.8rem]" :min="filtros.inicio" :max="hoje">
        </label>
      </div>
      <div class="flex flex-wrap gap-1.5">
        <button type="button" class="rounded-control border border-neutral-200 px-2 py-1 text-[0.74rem] text-neutral-700 hover:bg-neutral-25" @click="periodoRapido('mes')">Este mês</button>
        <button type="button" class="rounded-control border border-neutral-200 px-2 py-1 text-[0.74rem] text-neutral-700 hover:bg-neutral-25" @click="periodoRapido('ano')">Este ano</button>
        <button type="button" class="rounded-control border border-neutral-200 px-2 py-1 text-[0.74rem] text-neutral-700 hover:bg-neutral-25" @click="periodoRapido('12m')">12 meses</button>
        <button type="button" class="rounded-control border border-neutral-200 px-2 py-1 text-[0.74rem] text-neutral-700 hover:bg-neutral-25" @click="periodoRapido('tudo')">Tudo</button>
      </div>
      <div class="grid gap-1">
        <span class="text-[0.72rem] font-semibold text-neutral-600">Agrupar por</span>
        <div class="grid grid-cols-3 rounded-control border border-neutral-200 p-0.5" role="radiogroup" aria-label="Agrupar por">
          <label
            v-for="a in AGRUPAR"
            :key="a.valor"
            class="cursor-pointer rounded-[4px] py-1 text-center text-[0.78rem] focus-within:shadow-focus"
            :class="filtros.agrupar === a.valor ? 'bg-primary-700 font-semibold text-white' : 'text-neutral-700 hover:bg-neutral-25'"
          >
            <input v-model="filtros.agrupar" type="radio" name="agrupar" :value="a.valor" class="sr-only">{{ a.nome }}
          </label>
        </div>
      </div>
    </section>

    <section class="cartao grid gap-2 p-3.5">
      <div class="flex items-center justify-between">
        <b class="cartao-titulo">Filtros</b>
        <button v-if="algumFiltro" type="button" class="text-[0.74rem] font-semibold text-primary-700 hover:underline" @click="limpar">Limpar todos</button>
      </div>
      <FiltroMultiplo v-model="filtros.situacoes" rotulo="Situação" :opcoes="situacoes" />
      <FiltroMultiplo v-model="filtros.tipos" rotulo="Tipo" :opcoes="paraOpcoes(opcoes.tipos)" />
      <FiltroMultiplo v-model="filtros.canais" rotulo="Forma de entrada" :opcoes="paraOpcoes(opcoes.canais, (n: string) => n)" />
      <FiltroMultiplo v-model="filtros.identificacoes" rotulo="Identificação" :opcoes="paraOpcoes(opcoes.identificacoes)" />
      <template v-if="gerencial">
        <FiltroMultiplo v-model="filtros.assuntos" rotulo="Assunto" :opcoes="paraOpcoes(opcoes.assuntos)" />
        <FiltroMultiplo v-model="filtros.bairros" rotulo="Bairro" :opcoes="paraOpcoes(opcoes.bairros)" />
        <FiltroMultiplo v-if="opcoes.diretorias" v-model="filtros.diretorias" rotulo="Diretoria" :opcoes="paraOpcoes(opcoes.diretorias, nomeDiretoriaCurto)" />
      </template>
    </section>

    <div v-if="linkManifestacao || linkOuvidoria" class="grid gap-2">
      <a v-if="linkManifestacao" :href="linkManifestacao" target="_blank" rel="noopener" class="btn btn-primario">Registre uma manifestação</a>
      <a v-if="linkOuvidoria" :href="linkOuvidoria" target="_blank" rel="noopener" class="btn btn-secundario">Página da Ouvidoria do DMAE</a>
    </div>
  </aside>
</template>
