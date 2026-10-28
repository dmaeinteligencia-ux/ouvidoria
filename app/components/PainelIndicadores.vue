<script setup lang="ts">
// Área central dos painéis: os módulos do CI nº 6660/2025. Assuntos, bairros e mapa só no Gerencial.
import type { Indicadores } from '~/composables/useIndicadores'
import type { Agrupamento } from '~/utils/graficos'
import type { FatiaRosca } from './GraficoRosca.vue'

const props = defineProps<{ dados: Indicadores, agrupar: Agrupamento, gerencial?: boolean }>()

const nomeSituacao = (chave: string) => SITUACOES.find(s => s.valor === chave)?.nome ?? chave
const situacao = computed<FatiaRosca[]>(() => ORDEM_SITUACAO.map(chave => ({
  chave,
  nome: nomeSituacao(chave),
  n: props.dados.situacao.find(s => s.chave === chave)?.n ?? 0,
  cor: CORES_SITUACAO[chave]!,
})).filter(f => f.n > 0))

const exibir = (lista: { nome: string, n: number }[]) => lista.map(i => ({ nome: nomeExibicao(i.nome), n: i.n }))

const cumprimento = computed<FatiaRosca[]>(() => [
  { chave: 'no_prazo', nome: 'No prazo', n: props.dados.cumprimento.no_prazo, cor: COR_PRAZO.no_prazo },
  { chave: 'fora_prazo', nome: 'Fora do prazo', n: props.dados.cumprimento.fora_prazo, cor: COR_PRAZO.fora_prazo },
])
const totalCumprimento = computed(() => props.dados.cumprimento.no_prazo + props.dados.cumprimento.fora_prazo)
const pctNoPrazo = computed(() => (totalCumprimento.value ? percentual(props.dados.cumprimento.no_prazo, totalCumprimento.value) : '–'))

const resolutividade = computed(() => {
  const r = props.dados.resolutividade
  return r.respondidas ? percentual(r.resolutivas, r.respondidas) : '–'
})

function satisfacao(lista: { chave: string, n: number }[]) {
  const fatias = NIVEIS_SATISFACAO.map(n => ({ ...n, n: lista.find(l => l.chave === n.chave)?.n ?? 0 }))
  const total = fatias.reduce((s, f) => s + f.n, 0)
  const positivos = fatias.filter(f => f.chave === 'muito_satisfeito' || f.chave === 'satisfeito').reduce((s, f) => s + f.n, 0)
  return { fatias, total, media: total ? percentual(positivos, total) : '–' }
}
const satResposta = computed(() => satisfacao(props.dados.satisfacao_resposta))
const satOuvidoria = computed(() => satisfacao(props.dados.satisfacao_ouvidoria))

const evolucao = computed(() => props.dados.evolucao.map(p => ({ periodo: p.periodo, valor: p.n })))
const evolucaoPrazo = computed(() => props.dados.evolucao_prazo.map(p => ({ periodo: p.periodo, valor: p.media })))
const nomeAgrupar = computed(() => ({ day: 'por dia', month: 'por mês', year: 'por ano' })[props.agrupar])
</script>

<template>
  <div class="grid min-w-0 content-start gap-3">
    <div class="grid grid-cols-2 gap-3 xl:grid-cols-4">
      <KpiCartao
        rotulo="Manifestações recebidas"
        :valor="formatarNumero(dados.total)"
        :detalhe="dados.reaberturas.aceitas ? `${formatarNumero(dados.reaberturas.aceitas)} ${dados.reaberturas.aceitas === 1 ? 'reabertura aceita' : 'reaberturas aceitas'}` : 'no período'"
      />
      <KpiCartao
        rotulo="Prazo médio de resposta"
        :valor="dados.prazo_medio === null ? '–' : `${formatarDecimal(dados.prazo_medio)} d.u.`"
        :detalhe="`${formatarNumero(dados.respondidas_primeira)} primeiras respostas`"
      />
      <KpiCartao rotulo="Respondidas no prazo" :valor="pctNoPrazo" :detalhe="`de ${formatarNumero(totalCumprimento)} respondidas`" />
      <KpiCartao rotulo="Resolutividade" :valor="resolutividade" :detalhe="`${formatarNumero(dados.resolutividade.resolutivas)} de ${formatarNumero(dados.resolutividade.respondidas)} não arquivadas`" />
    </div>

    <div class="grid gap-3 2xl:grid-cols-2">
      <section class="cartao">
        <div class="cartao-topo"><b class="cartao-titulo">Situação</b><span class="cartao-nota">quantidade e %</span></div>
        <GraficoRosca :fatias="situacao" rotulo-centro="manifestações" />
      </section>
      <section class="cartao">
        <div class="cartao-topo"><b class="cartao-titulo">Evolução das manifestações</b><span class="cartao-nota">recebidas {{ nomeAgrupar }}</span></div>
        <GraficoLinha :pontos="evolucao" :agrupar="agrupar" unidade="manifestações" />
      </section>
    </div>

    <div class="grid gap-3 lg:grid-cols-2">
      <section class="cartao">
        <div class="cartao-topo"><b class="cartao-titulo">Tipo de manifestação</b></div>
        <GraficoColunas :itens="exibir(dados.tipo)" />
      </section>
      <section class="cartao">
        <div class="cartao-topo"><b class="cartao-titulo">Formas de entrada</b></div>
        <GraficoColunas :itens="dados.canal" />
      </section>
    </div>

    <div v-if="gerencial" class="grid gap-3 lg:grid-cols-2">
      <section class="cartao">
        <div class="cartao-topo"><b class="cartao-titulo">Principais assuntos</b><span class="cartao-nota">10 mais frequentes</span></div>
        <GraficoBarras :itens="exibir(dados.assuntos ?? [])" :total="dados.total" />
      </section>
      <section class="cartao">
        <div class="cartao-topo">
          <b class="cartao-titulo">Principais bairros</b>
          <span class="cartao-nota">10 mais frequentes{{ dados.sem_bairro ? ` · ${formatarNumero(dados.sem_bairro)} sem bairro` : '' }}</span>
        </div>
        <GraficoBarras :itens="exibir((dados.bairros ?? []).slice(0, 10))" :total="dados.total" />
      </section>
    </div>

    <section v-if="gerencial" class="cartao">
      <div class="cartao-topo"><b class="cartao-titulo">Mapa de calor por bairro</b></div>
      <p class="px-4 py-5 text-[0.82rem] text-neutral-500">
        O mapa entra quando o contorno dos bairros de Uberlândia (GeoJSON, KML ou shapefile) for enviado.
        Até lá, a quantidade por bairro está em "Principais bairros".
      </p>
    </section>

    <div class="grid gap-3 lg:grid-cols-2">
      <section class="cartao">
        <div class="cartao-topo"><b class="cartao-titulo">Tipo de arquivamento</b><span class="cartao-nota">entre as arquivadas</span></div>
        <GraficoColunas :itens="exibir(dados.arquivamento)" vazio="Nenhuma manifestação arquivada no período." />
      </section>
      <section class="cartao">
        <div class="cartao-topo"><b class="cartao-titulo">Cumprimento do prazo</b><span class="cartao-nota">primeira resposta</span></div>
        <GraficoRosca :fatias="cumprimento" :valor-centro="pctNoPrazo" rotulo-centro="no prazo" vazio="Nenhuma manifestação respondida no período." />
      </section>
    </div>

    <section class="cartao">
      <div class="cartao-topo"><b class="cartao-titulo">Evolução do prazo médio</b><span class="cartao-nota">dias úteis {{ nomeAgrupar }}, pelo recebimento</span></div>
      <GraficoLinha :pontos="evolucaoPrazo" :agrupar="agrupar" unidade="d.u." decimal vazio="Nenhuma manifestação respondida no período." />
    </section>

    <div class="grid gap-3 lg:grid-cols-2">
      <section v-for="s in [{ titulo: 'Satisfação com a resposta', d: satResposta }, { titulo: 'Satisfação com a Ouvidoria', d: satOuvidoria }]" :key="s.titulo" class="cartao">
        <div class="cartao-topo">
          <b class="cartao-titulo">{{ s.titulo }}</b>
          <span class="cartao-nota">satisfação média <b class="font-semibold text-neutral-800">{{ s.d.media }}</b></span>
        </div>
        <GraficoRosca :fatias="s.d.fatias" rotulo-centro="respostas" vazio="Nenhuma resposta da pesquisa de satisfação no período." />
      </section>
    </div>
  </div>
</template>
