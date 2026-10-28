<script setup lang="ts">
import type { Database } from '~/types/database.types'

type Insercao = Database['public']['Tables']['manifestacoes']['Insert']
type Alteracao = Database['public']['Tables']['manifestacoes']['Update']

// Formulário de cadastro e correção da manifestação (RN01, RN02, RN04, RN06), em blocos na ordem da planilha.
export interface Manifestacao {
  id: number
  numero: string
  protocolo_mgouv: string | null
  protocolo_falabr: string | null
  canal_id: number
  tipo_id: number
  identificacao_id: number
  cadastrado_em: string
  dia_zero: string
  dia_zero_corrigido_justificativa: string | null
  assunto_id: number
  logradouro: string | null
  numero_imovel: string | null
  complemento: string | null
  bairro_id: number | null
  cep: string | null
  descricao: string
  observacoes: string | null
}

const props = defineProps<{ inicial?: Manifestacao | null }>()
const emit = defineEmits<{ salvo: [id: number] }>()
// O botão de salvar fica no cabeçalho da página e envia este formulário pelo atributo form="form-manifestacao".
const salvando = defineModel<boolean>('salvando', { default: false })

const supabase = useSupabaseClient()
const { data: listas, refresh: recarregarListas } = await useListas()
const editando = computed(() => !!props.inicial)

const f = reactive({
  canal_id: props.inicial?.canal_id ?? null as number | null,
  protocolo_mgouv: props.inicial?.protocolo_mgouv ?? '',
  protocolo_falabr: props.inicial?.protocolo_falabr ?? '',
  tipo_id: props.inicial?.tipo_id ?? null as number | null,
  identificacao_id: props.inicial?.identificacao_id ?? null as number | null,
  cadastrado_em: props.inicial ? paraCampoDataHora(props.inicial.cadastrado_em) : '',
  assunto_id: props.inicial?.assunto_id ?? null as number | null,
  logradouro: props.inicial?.logradouro ?? '',
  numero_imovel: props.inicial?.numero_imovel ?? '',
  complemento: props.inicial?.complemento ?? '',
  bairro: nomeExibicao(nomePorId(listas.value?.bairros, props.inicial?.bairro_id)),
  cep: props.inicial?.cep ?? '',
  descricao: props.inicial?.descricao ?? '',
  observacoes: props.inicial?.observacoes ?? '',
  corrigirDiaZero: !!props.inicial?.dia_zero_corrigido_justificativa,
  dia_zero: props.inicial?.dia_zero ?? '',
  justificativa: props.inicial?.dia_zero_corrigido_justificativa ?? '',
})

const canal = computed(() => listas.value?.canais.find(c => c.id === f.canal_id))
const exigeFalabr = computed(() => !!canal.value?.exige_protocolo_falabr)

// Máscaras simples: só dígitos no MG-OUV; Fala.BR e CEP com pontuação automática.
function soDigitos(v: string, max: number) {
  return v.replace(/\D/g, '').slice(0, max)
}
watch(() => f.protocolo_mgouv, v => (f.protocolo_mgouv = soDigitos(v, 13)))
watch(() => f.protocolo_falabr, (v) => {
  const d = soDigitos(v, 17)
  const partes = [d.slice(0, 5), d.slice(5, 9), d.slice(9, 15), d.slice(15, 17)]
  let r = partes[0]!
  if (d.length > 5) r += `.${partes[1]}`
  if (d.length > 9) r += `.${partes[2]}`
  if (d.length > 15) r += `-${partes[3]}`
  f.protocolo_falabr = r
})
watch(() => f.cep, (v) => {
  const d = soDigitos(v, 8)
  f.cep = d.length > 5 ? `${d.slice(0, 5)}-${d.slice(5)}` : d
})

const erros = computed(() => {
  const e: Record<string, string> = {}
  if (!f.canal_id) e.canal_id = 'Escolha o canal.'
  if (!f.tipo_id) e.tipo_id = 'Escolha o tipo.'
  if (!f.identificacao_id) e.identificacao_id = 'Escolha a identificação.'
  if (!f.cadastrado_em) e.cadastrado_em = 'Informe a data e a hora do cadastro.'
  else if (f.cadastrado_em > agoraCampoDataHora()) e.cadastrado_em = 'A data do cadastro não pode estar no futuro.'
  if (!f.assunto_id) e.assunto_id = 'Escolha o assunto.'
  if (!f.descricao.trim()) e.descricao = 'Descreva a manifestação.'
  if (f.protocolo_mgouv && f.protocolo_mgouv.length !== 13) e.protocolo_mgouv = 'O protocolo MG-OUV tem 13 dígitos.'
  if (f.protocolo_falabr && !/^\d{5}\.\d{4}\.\d{6}-\d{2}$/.test(f.protocolo_falabr)) e.protocolo_falabr = 'Formato esperado: 00000.0000.000000-00.'
  if (exigeFalabr.value && !f.protocolo_falabr) e.protocolo_falabr = 'Obrigatório para o canal Fala.BR.'
  if (!f.protocolo_mgouv && !f.protocolo_falabr && !e.protocolo_falabr) e.protocolo_mgouv = 'Informe pelo menos um protocolo.'
  if (f.cep && !/^\d{5}-\d{3}$/.test(f.cep)) e.cep = 'Formato esperado: 00000-000.'
  if (f.corrigirDiaZero && !f.dia_zero) e.dia_zero = 'Informe a data de recebimento.'
  if (f.corrigirDiaZero && f.dia_zero !== previa.value?.dia_zero && !f.justificativa.trim()) e.justificativa = 'Explique por que o recebimento é diferente do calculado.'
  return e
})
const tentouSalvar = ref(false)
const erro = (campo: string) => (tentouSalvar.value ? erros.value[campo] : undefined)

// RN04: prévia do dia 0 e dos prazos calculados pelo banco.
const previa = ref<{ dia_zero: string, prazo: string, prazo_prorrogado: string } | null>(null)
watch(() => f.cadastrado_em, async (valor) => {
  if (!valor) {
    previa.value = null
    return
  }
  const { data } = await supabase.rpc('previa_prazos', { p_cadastrado_em: deCampoDataHora(valor) })
  previa.value = (data as typeof previa.value[] | null)?.[0] ?? null
}, { immediate: true })

const diaZeroEfetivo = computed(() => (f.corrigirDiaZero && f.dia_zero ? f.dia_zero : previa.value?.dia_zero))
const motivoCorte = computed(() => {
  if (!f.cadastrado_em || !previa.value) return ''
  const data = f.cadastrado_em.slice(0, 10)
  const hora = f.cadastrado_em.slice(11, 16)
  if (previa.value.dia_zero === data) return 'Cadastro em dia útil antes das 17h: o recebimento é no mesmo dia (RN04).'
  if (hora >= '17:00' && !ehFimDeSemana(data)) return `Cadastro às ${hora}, depois do horário útil: o recebimento passa para o próximo dia útil (RN04).`
  return 'Cadastro em dia não útil: o recebimento passa para o próximo dia útil (RN04).'
})

// RN06: aviso de possível duplicidade antes de salvar.
const duplicidades = ref<{ id: number, numero: string, assunto: string, dia_zero: string, motivo: string }[]>([])
async function verificarDuplicidade() {
  if (!f.protocolo_mgouv && !f.protocolo_falabr && !(f.logradouro && f.assunto_id)) {
    duplicidades.value = []
    return
  }
  const { data } = await supabase.rpc('possiveis_duplicidades', {
    p_protocolo_mgouv: f.protocolo_mgouv || null,
    p_protocolo_falabr: f.protocolo_falabr || null,
    p_logradouro: f.logradouro || null,
    p_numero_imovel: f.numero_imovel || null,
    p_assunto_id: f.assunto_id,
    p_referencia: f.cadastrado_em ? deCampoDataHora(f.cadastrado_em) : new Date().toISOString(),
    p_ignorar_id: props.inicial?.id ?? null,
  })
  duplicidades.value = (data ?? []) as typeof duplicidades.value
}
watch(() => [f.assunto_id, f.protocolo_mgouv.length === 13, f.protocolo_falabr.length === 20], verificarDuplicidade, { immediate: true })

const falha = ref('')

async function idDoBairro(): Promise<number | null> {
  const nome = f.bairro.trim()
  if (!nome) return null
  const alvo = nome.toLocaleUpperCase('pt-BR')
  const existente = listas.value?.bairros.find(b => b.nome.toLocaleUpperCase('pt-BR') === alvo)
  if (existente) return existente.id
  const { data, error } = await supabase.from('bairros').insert({ nome: alvo }).select('id').single()
  if (error) throw error
  await recarregarListas()
  return (data as { id: number }).id
}

async function salvar() {
  tentouSalvar.value = true
  falha.value = ''
  if (Object.keys(erros.value).length) return
  salvando.value = true
  try {
    const dados: Alteracao = {
      canal_id: f.canal_id!,
      protocolo_mgouv: f.protocolo_mgouv || null,
      protocolo_falabr: f.protocolo_falabr || null,
      tipo_id: f.tipo_id!,
      identificacao_id: f.identificacao_id!,
      cadastrado_em: deCampoDataHora(f.cadastrado_em),
      assunto_id: f.assunto_id!,
      logradouro: f.logradouro.trim() || null,
      numero_imovel: f.numero_imovel.trim() || null,
      complemento: f.complemento.trim() || null,
      bairro_id: await idDoBairro(),
      cep: f.cep || null,
      descricao: f.descricao.trim(),
      observacoes: f.observacoes.trim() || null,
    }
    if (f.corrigirDiaZero && f.dia_zero !== previa.value?.dia_zero) {
      dados.dia_zero = f.dia_zero
      dados.dia_zero_corrigido_justificativa = f.justificativa.trim()
    }
    else if (editando.value) {
      // Sem correção manual, o banco recalcula o dia 0 a partir da data do cadastro.
      dados.dia_zero = previa.value?.dia_zero
      dados.dia_zero_corrigido_justificativa = null
    }

    const consulta = editando.value
      ? supabase.from('manifestacoes').update(dados).eq('id', props.inicial!.id).select('id').single()
      : supabase.from('manifestacoes').insert(dados as Insercao).select('id').single()
    const { data, error } = await consulta
    if (error) throw error
    emit('salvo', (data as { id: number }).id)
  }
  catch (e) {
    falha.value = mensagemErro(e)
  }
  finally {
    salvando.value = false
  }
}

const opcoes = (lista: { id: number, nome: string }[] | undefined) => (lista ?? []).map(i => ({ id: i.id, nome: nomeExibicao(i.nome) }))
</script>

<template>
  <form id="form-manifestacao" class="grid items-start gap-3.5 xl:grid-cols-[1fr_280px]" novalidate @submit.prevent="salvar">
    <div class="cartao">
      <fieldset class="grid gap-3.5 px-5 pb-5 pt-4">
        <legend class="contents"><h2 class="font-display text-[0.9rem] font-bold text-neutral-900">Identificação <span class="ml-1 font-mono text-[0.68rem] font-medium text-neutral-500">bloco 1</span></h2></legend>
        <div class="grid gap-3 md:grid-cols-3">
          <CampoForm rotulo="Canal de entrada" obrigatorio :erro="erro('canal_id')">
            <select v-model="f.canal_id" class="campo">
              <option :value="null" disabled>Escolha</option>
              <option v-for="c in listas?.canais" :key="c.id" :value="c.id">{{ nomeExibicao(c.nome) }}</option>
            </select>
          </CampoForm>
          <CampoForm rotulo="Protocolo MG-OUV" :obrigatorio="!exigeFalabr" :erro="erro('protocolo_mgouv')" dica="13 dígitos, sem pontos.">
            <input v-model="f.protocolo_mgouv" class="campo font-mono" inputmode="numeric" autocomplete="off" @blur="verificarDuplicidade">
          </CampoForm>
          <CampoForm rotulo="Protocolo Fala.BR" :obrigatorio="exigeFalabr" :erro="erro('protocolo_falabr')" dica="00000.0000.000000-00">
            <input v-model="f.protocolo_falabr" class="campo font-mono" inputmode="numeric" autocomplete="off" @blur="verificarDuplicidade">
          </CampoForm>
        </div>
        <div class="grid gap-3 md:grid-cols-[1fr_2fr]">
          <CampoForm rotulo="Tipo" obrigatorio :erro="erro('tipo_id')">
            <select v-model="f.tipo_id" class="campo">
              <option :value="null" disabled>Escolha</option>
              <option v-for="t in opcoes(listas?.tipos)" :key="t.id" :value="t.id">{{ t.nome }}</option>
            </select>
          </CampoForm>
          <CampoForm rotulo="Identificação" obrigatorio :erro="erro('identificacao_id')" grupo>
            <div class="flex gap-2">
              <label
                v-for="i in opcoes(listas?.identificacoes)"
                :key="i.id"
                class="flex-1 cursor-pointer rounded-control border px-1.5 py-[9px] text-center text-[0.8rem] focus-within:shadow-focus"
                :class="f.identificacao_id === i.id ? 'border-primary-700 bg-primary-50 font-semibold text-primary-800' : 'border-neutral-200 bg-white text-neutral-700'"
              >
                <input v-model="f.identificacao_id" type="radio" name="identificacao" :value="i.id" class="sr-only">
                {{ i.nome }}
              </label>
            </div>
          </CampoForm>
        </div>
      </fieldset>

      <fieldset class="grid gap-3.5 border-t border-neutral-100 px-5 pb-5 pt-4">
        <legend class="contents"><h2 class="font-display text-[0.9rem] font-bold text-neutral-900">Conteúdo e local <span class="ml-1 font-mono text-[0.68rem] font-medium text-neutral-500">bloco 2</span></h2></legend>
        <div class="grid gap-3 md:grid-cols-2">
          <CampoForm rotulo="Data de cadastro pelo manifestante" obrigatorio :erro="erro('cadastrado_em')">
            <input v-model="f.cadastrado_em" type="datetime-local" class="campo font-mono" :max="agoraCampoDataHora()">
          </CampoForm>
          <CampoForm rotulo="Assunto" obrigatorio :erro="erro('assunto_id')">
            <select v-model="f.assunto_id" class="campo">
              <option :value="null" disabled>Escolha</option>
              <option v-for="a in opcoes(listas?.assuntos)" :key="a.id" :value="a.id">{{ a.nome }}</option>
            </select>
          </CampoForm>
        </div>
        <div class="grid gap-3 md:grid-cols-[2fr_0.8fr_1.4fr_1fr]">
          <CampoForm rotulo="Logradouro">
            <input v-model="f.logradouro" class="campo" autocomplete="off" @blur="verificarDuplicidade">
          </CampoForm>
          <CampoForm rotulo="Número">
            <input v-model="f.numero_imovel" class="campo font-mono" autocomplete="off" @blur="verificarDuplicidade">
          </CampoForm>
          <CampoForm rotulo="Bairro" dica="Escolha da lista ou digite um novo.">
            <input v-model="f.bairro" class="campo" list="lista-bairros" autocomplete="off">
            <datalist id="lista-bairros">
              <option v-for="b in listas?.bairros" :key="b.id" :value="nomeExibicao(b.nome)" />
            </datalist>
          </CampoForm>
          <CampoForm rotulo="CEP" :erro="erro('cep')">
            <input v-model="f.cep" class="campo font-mono" inputmode="numeric" placeholder="00000-000" autocomplete="off">
          </CampoForm>
        </div>
        <CampoForm rotulo="Complemento">
          <input v-model="f.complemento" class="campo" autocomplete="off">
        </CampoForm>
        <CampoForm rotulo="Descrição" obrigatorio :erro="erro('descricao')">
          <textarea v-model="f.descricao" class="campo min-h-[96px] leading-[1.45]" rows="4" />
        </CampoForm>
        <CampoForm rotulo="Observações internas" dica="Não aparecem para o manifestante.">
          <textarea v-model="f.observacoes" class="campo min-h-[64px] leading-[1.45]" rows="2" />
        </CampoForm>
      </fieldset>
    </div>

    <div class="grid gap-3">
      <div class="cartao grid gap-3 p-4 text-[0.82rem]">
        <span class="rotulo-caps">Calculado pelo sistema</span>
        <div class="flex justify-between gap-2.5 border-b border-dashed border-neutral-200 pb-2">
          <span class="text-neutral-500">Nº interno</span><b class="font-mono text-[0.8rem] font-medium">{{ inicial?.numero ?? 'gerado ao salvar' }}</b>
        </div>
        <div class="flex justify-between gap-2.5 border-b border-dashed border-neutral-200 pb-2">
          <span class="text-neutral-500">Recebimento DMAE</span><b class="font-mono text-[0.8rem] font-medium">{{ formatarData(diaZeroEfetivo) || '—' }}</b>
        </div>
        <template v-if="!f.corrigirDiaZero || f.dia_zero === previa?.dia_zero">
          <div class="flex justify-between gap-2.5 border-b border-dashed border-neutral-200 pb-2">
            <span class="text-neutral-500">Prazo 5 d.u.</span><b class="font-mono text-[0.8rem] font-medium">{{ formatarData(previa?.prazo) || '—' }}</b>
          </div>
          <div class="flex justify-between gap-2.5">
            <span class="text-neutral-500">Prorrogação 10 d.u.</span><b class="font-mono text-[0.8rem] font-medium">{{ formatarData(previa?.prazo_prorrogado) || '—' }}</b>
          </div>
        </template>
        <span v-if="motivoCorte" class="text-[0.74rem] text-neutral-500">{{ motivoCorte }}</span>

        <label class="flex items-center gap-2 border-t border-neutral-100 pt-3 text-[0.8rem] text-neutral-700">
          <input v-model="f.corrigirDiaZero" type="checkbox" class="h-4 w-4 accent-primary-700">
          Corrigir o recebimento
        </label>
        <template v-if="f.corrigirDiaZero">
          <CampoForm rotulo="Recebimento corrigido" obrigatorio :erro="erro('dia_zero')">
            <input v-model="f.dia_zero" type="date" class="campo font-mono">
          </CampoForm>
          <CampoForm rotulo="Justificativa" obrigatorio :erro="erro('justificativa')" dica="Fica registrada no histórico (RN04).">
            <textarea v-model="f.justificativa" class="campo min-h-[64px]" rows="2" />
          </CampoForm>
        </template>
      </div>

      <AvisoCaixa v-for="d in duplicidades" :key="d.id" titulo="Possível duplicidade" tipo="atencao">
        <NuxtLink :to="`/manifestacoes/${d.id}`" target="_blank" class="font-mono font-medium text-primary-700 hover:underline">{{ d.numero }}</NuxtLink>,
        {{ nomeExibicao(d.assunto) }}, {{ d.motivo }}, recebida em {{ formatarData(d.dia_zero) }} (RN06).
      </AvisoCaixa>

      <AvisoCaixa v-if="falha" titulo="Não foi salvo" tipo="erro">{{ falha }}</AvisoCaixa>
      <AvisoCaixa v-else-if="tentouSalvar && Object.keys(erros).length" titulo="Confira os campos destacados" tipo="erro" />
    </div>
  </form>
</template>
