<script setup lang="ts">
import type { EventoHistorico } from '~/components/LinhaDoTempo.vue'
import type { Situacao } from '~/utils/situacao'

const supabase = useSupabaseClient()
const route = useRoute()
const id = Number(route.params.id)
const { data: perfil } = await usePerfil()
const { data: listas } = await useListas()

interface Detalhe {
  id: number
  numero: string
  protocolo_mgouv: string | null
  protocolo_falabr: string | null
  situacao: Situacao
  arquivada: boolean
  resolutiva: boolean | null
  cadastrado_em: string
  dia_zero: string
  dia_zero_corrigido_justificativa: string | null
  logradouro: string | null
  numero_imovel: string | null
  complemento: string | null
  cep: string | null
  descricao: string
  observacoes: string | null
  canal: { nome_painel: string }
  tipo: { nome: string }
  identificacao: { nome: string }
  assunto: { nome: string }
  bairro: { nome: string } | null
  motivo: { nome: string } | null
  original: { id: number, numero: string } | null
}
interface Ciclo {
  id: number
  numero: number
  dia_zero: string
  prorrogado: boolean
  prazo: string
  respondido_em: string | null
  no_prazo: boolean | null
}
interface Encaminhamento { diretoria_id: number, avaliador_id: number, enviado_em: string }

const { data, refresh, error } = await useAsyncData(`manifestacao-${id}`, async () => {
  const [m, ciclos, enc, painel, historico] = await Promise.all([
    supabase.from('manifestacoes').select(`
      id, numero, protocolo_mgouv, protocolo_falabr, situacao, arquivada, resolutiva, cadastrado_em, dia_zero,
      dia_zero_corrigido_justificativa, logradouro, numero_imovel, complemento, cep, descricao, observacoes,
      canal:canais(nome_painel), tipo:tipos_manifestacao(nome), identificacao:identificacoes(nome),
      assunto:assuntos(nome), bairro:bairros(nome), motivo:motivos_arquivamento(nome),
      original:duplicada_de(id, numero)`).eq('id', id).maybeSingle(),
    supabase.from('ciclos_prazos').select('id, numero, dia_zero, prorrogado, prazo, respondido_em, no_prazo').eq('manifestacao_id', id).order('numero'),
    supabase.from('encaminhamentos').select('diretoria_id, avaliador_id, enviado_em').eq('manifestacao_id', id).eq('atual', true).maybeSingle(),
    supabase.from('painel_manifestacoes').select('dias_restantes').eq('id', id).maybeSingle(),
    supabase.rpc('historico_manifestacao', { p_manifestacao_id: id }),
  ])
  for (const r of [m, ciclos, enc, painel, historico]) if (r.error) throw r.error
  if (!m.data) return null

  const ciclo = (ciclos.data as Ciclo[]).at(-1)!
  const { data: feriados } = await supabase.from('feriados').select('data')
    .gt('data', ciclo.dia_zero).lte('data', somarDias(ciclo.dia_zero, 40))

  return {
    m: m.data as unknown as Detalhe,
    ciclo,
    encaminhamento: enc.data as Encaminhamento | null,
    diasRestantes: (painel.data as { dias_restantes: number | null } | null)?.dias_restantes ?? null,
    historico: (historico.data ?? []) as EventoHistorico[],
    feriados: ((feriados ?? []) as { data: string }[]).map(f => f.data),
  }
})

const m = computed(() => data.value?.m)
const respondida = computed(() => m.value?.situacao === 'respondida')
const suspensa = computed(() => m.value?.situacao === 'aguardando_complementacao')
const ehEquipe = computed(() => perfil.value?.perfil === 'administrador' || perfil.value?.perfil === 'ouvidoria')

// Painel de ação aberto na coluna da direita.
type Acao = 'encaminhar' | 'responder' | 'arquivar' | null
const acao = ref<Acao>(null)
const falha = ref('')
const salvando = ref(false)
const sucesso = ref(route.query.novo ? 'Manifestação registrada.' : '')

function abrir(a: Acao) {
  acao.value = a
  falha.value = ''
  sucesso.value = ''
}

async function executar(trabalho: () => PromiseLike<{ error: unknown }>, mensagem: string) {
  salvando.value = true
  falha.value = ''
  const { error } = await trabalho()
  salvando.value = false
  if (error) {
    falha.value = mensagemErro(error)
    return
  }
  acao.value = null
  sucesso.value = mensagem
  refreshNuxtData('resumo-painel')
  clearNuxtData('lista-manifestacoes')
  await refresh()
}

// Encaminhar (RN14 / RN16)
const enc = reactive({ diretoria_id: null as number | null, avaliador_id: null as number | null, enviado_em: hojeBrasilia() })
const avaliadoresDaDiretoria = computed(() => (listas.value?.avaliadores ?? []).filter(a => a.diretoria_id === enc.diretoria_id))
watch(() => enc.diretoria_id, () => {
  enc.avaliador_id = avaliadoresDaDiretoria.value.length === 1 ? avaliadoresDaDiretoria.value[0]!.id : null
})
function encaminhar() {
  if (!enc.diretoria_id || !enc.avaliador_id || !enc.enviado_em) {
    falha.value = 'Escolha a diretoria, o avaliador e a data do envio.'
    return
  }
  return executar(
    () => supabase.from('encaminhamentos').insert({
      manifestacao_id: id, diretoria_id: enc.diretoria_id!, avaliador_id: enc.avaliador_id!, enviado_em: enc.enviado_em,
    }),
    data.value?.encaminhamento ? 'Reencaminhamento registrado. O prazo não muda (RN16).' : 'Encaminhamento registrado.',
  )
}

// Responder (RN17) e arquivar (RN18)
const MOTIVO_DUPLICIDADE = 'REGISTRO EM DUPLICIDADE'
const resp = reactive({
  respondido_em: hojeBrasilia(),
  resposta: '',
  resolutiva: null as boolean | null,
  arquivar: false,
  motivo_id: null as number | null,
  original: '',
})
const motivoEhDuplicidade = computed(() => nomePorId(listas.value?.motivos, resp.motivo_id) === MOTIVO_DUPLICIDADE)

async function idDaOriginal(): Promise<number | null | false> {
  if (!motivoEhDuplicidade.value || !resp.original.trim()) return null
  const { data: achada } = await supabase.from('manifestacoes').select('id').eq('numero', resp.original.trim()).maybeSingle()
  if (!achada) {
    falha.value = `Não há manifestação com o nº ${resp.original.trim()}. Use o formato 2026/0001.`
    return false
  }
  return (achada as { id: number }).id
}

async function responder() {
  if (!resp.respondido_em || !resp.resposta.trim()) {
    falha.value = 'Informe a data e o texto da resposta (RN17).'
    return
  }
  if (!resp.arquivar && resp.resolutiva === null) {
    falha.value = 'Informe se a resposta foi resolutiva (RN17).'
    return
  }
  if (resp.arquivar && !resp.motivo_id) {
    falha.value = 'Escolha o motivo do arquivamento (RN18).'
    return
  }
  const original = await idDaOriginal()
  if (original === false) return
  return executar(() => supabase.rpc('registrar_resposta', {
    p_manifestacao_id: id,
    p_respondido_em: resp.respondido_em,
    p_resposta: resp.resposta,
    p_resolutiva: resp.arquivar ? null : resp.resolutiva,
    p_arquivar: resp.arquivar,
    p_motivo_arquivamento_id: resp.arquivar ? resp.motivo_id : null,
    p_duplicada_de: original,
  }), resp.arquivar ? 'Resposta registrada e manifestação arquivada.' : 'Resposta registrada.')
}

async function arquivar() {
  if (!resp.motivo_id) {
    falha.value = 'Escolha o motivo do arquivamento (RN18).'
    return
  }
  const original = await idDaOriginal()
  if (original === false) return
  return executar(() => supabase.rpc('arquivar_manifestacao', {
    p_manifestacao_id: id,
    p_motivo_arquivamento_id: resp.motivo_id!,
    p_duplicada_de: original,
  }), 'Manifestação arquivada.')
}

const endereco = computed(() => {
  if (!m.value) return ''
  const rua = [m.value.logradouro && nomeExibicao(m.value.logradouro), m.value.numero_imovel, m.value.complemento].filter(Boolean).join(', ')
  return [rua, m.value.bairro && nomeExibicao(m.value.bairro.nome)].filter(Boolean).join(' · ')
})

const encaminhadoA = computed(() => {
  const e = data.value?.encaminhamento
  if (!e) return null
  return {
    diretoria: nomeExibicao(nomePorId(listas.value?.diretorias, e.diretoria_id)),
    avaliador: nomeExibicao(nomePorId(listas.value?.avaliadores, e.avaliador_id)),
    enviado_em: e.enviado_em,
  }
})

const opcoes = (lista: { id: number, nome: string }[] | undefined) => (lista ?? []).map(i => ({ id: i.id, nome: nomeExibicao(i.nome) }))
</script>

<template>
  <AvisoCaixa v-if="!ehEquipe" titulo="Acesso restrito" tipo="atencao">As manifestações são consultadas só pela equipe da Ouvidoria.</AvisoCaixa>
  <AvisoCaixa v-else-if="error" titulo="Não foi possível carregar a manifestação" tipo="erro">Recarregue a página.</AvisoCaixa>
  <AvisoCaixa v-else-if="!m || !data" titulo="Manifestação não encontrada" tipo="atencao">
    <NuxtLink to="/manifestacoes" class="font-semibold text-primary-700 hover:underline">Voltar para a lista</NuxtLink>
  </AvisoCaixa>

  <template v-else>
    <nav class="text-[0.78rem] text-neutral-500">
      <NuxtLink to="/manifestacoes" class="hover:text-primary-700 hover:underline">Manifestações</NuxtLink> / <span class="font-mono">{{ m.numero }}</span>
    </nav>

    <div class="grid items-start gap-3.5 xl:grid-cols-[1fr_300px]">
      <article class="cartao">
        <header class="grid gap-3 px-5 py-[18px]">
          <div class="flex flex-wrap items-center gap-2.5">
            <span class="font-mono text-[0.9rem] font-medium text-primary-700">{{ m.numero }}</span>
            <SituacaoBadge :situacao="m.situacao" :arquivada="m.arquivada" />
            <PrazoIndicador :dias-restantes="data.diasRestantes" :prazo="data.ciclo.prazo" :respondido-em="data.ciclo.respondido_em" :suspenso="suspensa" />
          </div>
          <h1 class="font-display text-[1.3rem] font-extrabold leading-tight text-neutral-900">{{ nomeExibicao(m.assunto.nome) }}</h1>
        </header>

        <dl class="grid grid-cols-2 gap-x-[18px] gap-y-3 border-t border-neutral-100 px-5 py-3.5 md:grid-cols-4">
          <div v-if="m.protocolo_mgouv" class="grid min-w-0 gap-[3px]"><dt class="rotulo-caps">MG-OUV</dt><dd class="font-mono text-[0.8rem]">{{ m.protocolo_mgouv }}</dd></div>
          <div v-if="m.protocolo_falabr" class="grid min-w-0 gap-[3px]"><dt class="rotulo-caps">Fala.BR</dt><dd class="font-mono text-[0.8rem]">{{ m.protocolo_falabr }}</dd></div>
          <div class="grid min-w-0 gap-[3px]"><dt class="rotulo-caps">Canal</dt><dd class="text-[0.84rem] font-medium">{{ m.canal.nome_painel }}</dd></div>
          <div class="grid min-w-0 gap-[3px]"><dt class="rotulo-caps">Tipo</dt><dd class="text-[0.84rem] font-medium">{{ nomeExibicao(m.tipo.nome) }}</dd></div>
          <div class="grid min-w-0 gap-[3px]"><dt class="rotulo-caps">Identificação</dt><dd class="text-[0.84rem] font-medium">{{ nomeExibicao(m.identificacao.nome) }}</dd></div>
          <div class="grid min-w-0 gap-[3px]"><dt class="rotulo-caps">Cadastro</dt><dd class="font-mono text-[0.8rem]">{{ formatarDataHora(m.cadastrado_em) }}</dd></div>
          <div class="grid min-w-0 gap-[3px]">
            <dt class="rotulo-caps">Recebimento DMAE</dt>
            <dd class="font-mono text-[0.8rem]" :title="m.dia_zero_corrigido_justificativa ?? undefined">
              {{ formatarData(m.dia_zero) }}<span v-if="m.dia_zero_corrigido_justificativa" class="ml-1 font-sans text-[0.7rem] text-warning">corrigido</span>
            </dd>
          </div>
          <div class="col-span-2 grid min-w-0 gap-[3px]"><dt class="rotulo-caps">Endereço</dt><dd class="text-[0.84rem] font-medium [overflow-wrap:anywhere]">{{ endereco || 'Não informado' }}</dd></div>
          <div v-if="m.cep" class="grid min-w-0 gap-[3px]"><dt class="rotulo-caps">CEP</dt><dd class="font-mono text-[0.8rem]">{{ m.cep }}</dd></div>
          <div class="col-span-2 grid min-w-0 gap-[3px]">
            <dt class="rotulo-caps">Encaminhamento</dt>
            <dd class="text-[0.84rem] font-medium">
              <template v-if="encaminhadoA">{{ encaminhadoA.diretoria }} · {{ encaminhadoA.avaliador }} <span class="font-mono text-[0.76rem] text-neutral-500">({{ formatarData(encaminhadoA.enviado_em, true) }})</span></template>
              <span v-else class="text-neutral-500">Não encaminhada</span>
            </dd>
          </div>
          <div v-if="respondida" class="grid min-w-0 gap-[3px]">
            <dt class="rotulo-caps">Resolutiva</dt>
            <dd class="text-[0.84rem] font-medium">{{ m.arquivada ? 'Não se aplica' : m.resolutiva ? 'Sim' : 'Não' }}</dd>
          </div>
          <div v-if="m.arquivada" class="grid min-w-0 gap-[3px]">
            <dt class="rotulo-caps">Motivo do arquivamento</dt>
            <dd class="text-[0.84rem] font-medium">
              {{ nomeExibicao(m.motivo?.nome) }}
              <NuxtLink v-if="m.original" :to="`/manifestacoes/${m.original.id}`" class="font-mono text-[0.78rem] text-primary-700 hover:underline">de {{ m.original.numero }}</NuxtLink>
            </dd>
          </div>
        </dl>

        <p class="whitespace-pre-line border-t border-neutral-100 px-5 pb-[18px] pt-3.5 text-[0.86rem] text-neutral-700">{{ m.descricao }}</p>
        <p v-if="m.observacoes" class="whitespace-pre-line border-t border-dashed border-neutral-100 px-5 py-3 text-[0.8rem] text-neutral-600">
          <b class="rotulo-caps mr-1.5">Observações internas</b>{{ m.observacoes }}
        </p>

        <div class="flex gap-1.5 border-t border-neutral-100 px-5 pt-3">
          <span class="rounded-control border border-primary-700 bg-primary-50 px-2.5 py-1.5 text-[0.76rem] font-semibold text-primary-700">Ciclo original</span>
          <span class="rounded-control border border-dashed border-neutral-200 px-2.5 py-1.5 text-[0.76rem] text-neutral-400">Sem reaberturas</span>
        </div>
        <LinhaDoTempo :historico="data.historico" :listas="listas" />
      </article>

      <aside class="grid gap-3">
        <AvisoCaixa v-if="sucesso" :titulo="sucesso" tipo="sucesso" />

        <MedidorDiasUteis
          :dia-zero="data.ciclo.dia_zero"
          :prazo="data.ciclo.prazo"
          :prorrogado="data.ciclo.prorrogado"
          :respondido-em="data.ciclo.respondido_em"
          :dias-restantes="data.diasRestantes"
          :suspenso="suspensa"
          :feriados="data.feriados"
        />

        <!-- Ações permitidas para a situação atual (RN24) -->
        <div v-if="!acao" class="cartao grid gap-2 p-4">
          <template v-if="!respondida">
            <button class="btn" :class="encaminhadoA ? 'btn-primario' : 'btn-secundario'" :disabled="suspensa" @click="abrir('responder')">Registrar resposta</button>
            <button class="btn" :class="encaminhadoA ? 'btn-fantasma' : 'btn-primario'" @click="abrir('encaminhar')">{{ encaminhadoA ? 'Reencaminhar' : 'Encaminhar' }}</button>
            <button class="btn btn-secundario" disabled title="Disponível na Fase 3">Prorrogar para 10 d.u.</button>
          </template>
          <button v-else-if="!m.arquivada" class="btn btn-perigo" @click="abrir('arquivar')">Arquivar</button>
          <NuxtLink :to="`/manifestacoes/${id}/editar`" class="btn btn-fantasma">Corrigir dados</NuxtLink>
        </div>

        <form v-else-if="acao === 'encaminhar'" class="cartao grid gap-3 p-4" @submit.prevent="encaminhar">
          <b class="cartao-titulo">{{ encaminhadoA ? 'Reencaminhar' : 'Encaminhar' }}</b>
          <p class="text-[0.76rem] text-neutral-500">A tramitação acontece no MG-OUV; aqui fica o registro (RN14).{{ encaminhadoA ? ' O prazo não reinicia (RN16).' : '' }}</p>
          <CampoForm rotulo="Diretoria" obrigatorio>
            <select v-model="enc.diretoria_id" class="campo">
              <option :value="null" disabled>Escolha</option>
              <option v-for="d in opcoes(listas?.diretorias)" :key="d.id" :value="d.id">{{ d.nome }}</option>
            </select>
          </CampoForm>
          <CampoForm rotulo="Avaliador" obrigatorio>
            <select v-model="enc.avaliador_id" class="campo" :disabled="!avaliadoresDaDiretoria.length">
              <option :value="null" disabled>{{ enc.diretoria_id && !avaliadoresDaDiretoria.length ? 'Nenhum avaliador cadastrado' : 'Escolha' }}</option>
              <option v-for="a in opcoes(avaliadoresDaDiretoria)" :key="a.id" :value="a.id">{{ a.nome }}</option>
            </select>
          </CampoForm>
          <p v-if="enc.diretoria_id && !avaliadoresDaDiretoria.length" class="text-[0.74rem] text-warning">
            Cadastre o avaliador desta diretoria em <NuxtLink to="/cadastros?aba=diretorias" class="font-semibold underline">Cadastros</NuxtLink>.
          </p>
          <CampoForm rotulo="Data do envio no MG-OUV" obrigatorio>
            <input v-model="enc.enviado_em" type="date" class="campo font-mono" :max="hojeBrasilia()">
          </CampoForm>
          <AvisoCaixa v-if="falha" titulo="Não foi salvo" tipo="erro">{{ falha }}</AvisoCaixa>
          <div class="flex justify-end gap-2">
            <button type="button" class="btn btn-fantasma btn-pequeno" @click="abrir(null)">Cancelar</button>
            <button class="btn btn-primario btn-pequeno" :disabled="salvando">{{ salvando ? 'Salvando…' : 'Registrar envio' }}</button>
          </div>
        </form>

        <form v-else-if="acao === 'responder' || acao === 'arquivar'" class="cartao grid gap-3 p-4" @submit.prevent="acao === 'responder' ? responder() : arquivar()">
          <b class="cartao-titulo">{{ acao === 'responder' ? 'Registrar resposta' : 'Arquivar manifestação' }}</b>
          <template v-if="acao === 'responder'">
            <CampoForm rotulo="Data do envio da resposta" obrigatorio>
              <input v-model="resp.respondido_em" type="date" class="campo font-mono" :min="data.ciclo.dia_zero" :max="hojeBrasilia()">
            </CampoForm>
            <CampoForm rotulo="Resposta enviada ao manifestante" obrigatorio>
              <textarea v-model="resp.resposta" class="campo min-h-[110px] leading-[1.45]" rows="5" />
            </CampoForm>
            <label class="flex items-center gap-2 text-[0.82rem] font-semibold text-neutral-800">
              <input v-model="resp.arquivar" type="checkbox" class="h-4 w-4 accent-primary-700"> Arquivada
            </label>
            <CampoForm v-if="!resp.arquivar" rotulo="Resolutiva?" obrigatorio grupo>
              <div class="flex gap-2">
                <label
                  v-for="o in [{ v: true, n: 'Sim' }, { v: false, n: 'Não' }]"
                  :key="o.n"
                  class="flex-1 cursor-pointer rounded-control border py-2 text-center text-[0.8rem] focus-within:shadow-focus"
                  :class="resp.resolutiva === o.v ? 'border-primary-700 bg-primary-50 font-semibold text-primary-800' : 'border-neutral-200 bg-white text-neutral-700'"
                >
                  <input v-model="resp.resolutiva" type="radio" name="resolutiva" :value="o.v" class="sr-only">{{ o.n }}
                </label>
              </div>
            </CampoForm>
          </template>
          <template v-if="acao === 'arquivar' || resp.arquivar">
            <CampoForm rotulo="Motivo do arquivamento" obrigatorio>
              <select v-model="resp.motivo_id" class="campo">
                <option :value="null" disabled>Escolha</option>
                <option v-for="mo in opcoes(listas?.motivos)" :key="mo.id" :value="mo.id">{{ mo.nome }}</option>
              </select>
            </CampoForm>
            <CampoForm v-if="motivoEhDuplicidade" rotulo="Nº da manifestação original" dica="Ex.: 2026/0131. Liga as duas no histórico (RN06).">
              <input v-model="resp.original" class="campo font-mono" placeholder="2026/0000">
            </CampoForm>
            <p class="text-[0.74rem] text-neutral-500">Arquivada fica Respondida e não entra no cálculo de resolutividade (RN18).</p>
          </template>
          <AvisoCaixa v-if="falha" titulo="Não foi salvo" tipo="erro">{{ falha }}</AvisoCaixa>
          <div class="flex justify-end gap-2">
            <button type="button" class="btn btn-fantasma btn-pequeno" @click="abrir(null)">Cancelar</button>
            <button class="btn btn-pequeno" :class="acao === 'arquivar' ? 'btn-perigo' : 'btn-primario'" :disabled="salvando">
              {{ salvando ? 'Salvando…' : acao === 'arquivar' ? 'Arquivar' : 'Registrar resposta' }}
            </button>
          </div>
        </form>

        <AvisoCaixa v-if="!respondida && data.diasRestantes !== null && data.diasRestantes < 0" :titulo="`Prazo vencido há ${-data.diasRestantes} ${data.diasRestantes === -1 ? 'dia útil' : 'dias úteis'}`" tipo="erro">
          Registre a resposta assim que ela for enviada.
        </AvisoCaixa>
      </aside>
    </div>
  </template>
</template>
