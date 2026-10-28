<script setup lang="ts">
const supabase = useSupabaseClient()
const route = useRoute()
const router = useRouter()

const abas = [
  { id: 'diretorias', nome: 'Diretorias e avaliadores' },
  { id: 'assuntos', nome: 'Assuntos' },
  { id: 'canais', nome: 'Canais' },
  { id: 'motivos_arquivamento', nome: 'Motivos de arquivamento' },
  { id: 'bairros', nome: 'Bairros' },
  { id: 'feriados', nome: 'Feriados' },
] as const

type Aba = typeof abas[number]['id']
const aba = computed<Aba>(() => {
  const pedida = route.query.aba as Aba
  return abas.some(a => a.id === pedida) ? pedida : 'diretorias'
})

function trocar(id: Aba) {
  router.replace({ query: { aba: id } })
}

const tiposFeriado: Record<string, string> = {
  nacional: 'Nacional',
  estadual: 'Estadual',
  municipal: 'Municipal',
  ponto_facultativo: 'Ponto facultativo',
}

type TipoFeriado = 'nacional' | 'estadual' | 'municipal' | 'ponto_facultativo'
interface Feriado { data: string, descricao: string, tipo: TipoFeriado }
interface Linha { colunas: string[], avaliadores?: { id: number, nome: string }[], bairro?: PosicaoBairro, feriado?: Feriado }

const cabecalhos: Record<Aba, string[]> = {
  diretorias: ['Diretoria', 'Avaliadores'],
  assuntos: ['Assunto'],
  canais: ['Canal', 'Nome no painel'],
  motivos_arquivamento: ['Motivo'],
  bairros: ['Bairro', 'Posição no mapa'],
  feriados: ['Data', 'Descrição', 'Tipo'],
}

const { data: linhas, pending } = await useAsyncData('cadastro', async (): Promise<Linha[]> => {
  switch (aba.value) {
    case 'diretorias': {
      const { data, error } = await supabase.from('diretorias').select('nome, avaliadores(id, nome)')
        .eq('avaliadores.ativo', true).order('nome')
      if (error) throw error
      return (data as { nome: string, avaliadores: { id: number, nome: string }[] }[]).map(d => ({
        colunas: [nomeExibicao(d.nome), d.avaliadores.map(a => nomeExibicao(a.nome)).join(', ') || '—'],
        avaliadores: d.avaliadores.map(a => ({ id: a.id, nome: nomeExibicao(a.nome) })),
      }))
    }
    case 'canais': {
      const { data, error } = await supabase.from('canais').select('nome, nome_painel').order('nome')
      if (error) throw error
      return (data as { nome: string, nome_painel: string }[]).map(c => ({ colunas: [nomeExibicao(c.nome), c.nome_painel] }))
    }
    case 'bairros': {
      const { data, error } = await supabase.from('bairros').select('id, nome, latitude, longitude').order('nome')
      if (error) throw error
      return (data as PosicaoBairro[]).map(b => ({
        colunas: [nomeExibicao(b.nome), b.latitude == null ? 'Sem posição' : 'Marcada'],
        bairro: b,
      }))
    }
    case 'feriados': {
      const { data, error } = await supabase.from('feriados').select('data, descricao, tipo')
        .gte('data', `${new Date().getFullYear()}-01-01`).order('data')
      if (error) throw error
      return (data as Feriado[]).map(f => ({ colunas: [formatarData(f.data), f.descricao, tiposFeriado[f.tipo] ?? f.tipo], feriado: f }))
    }
    default: {
      const { data, error } = await supabase.from(aba.value).select('nome').order('nome')
      if (error) throw error
      return (data as { nome: string }[]).map(r => ({ colunas: [nomeExibicao(r.nome)] }))
    }
  }
}, { watch: [aba] })

// RN15: avaliadores cadastrados à mão pelo administrador, cada um em uma diretoria.
const { data: perfil } = await usePerfil()
const ehAdmin = computed(() => perfil.value?.perfil === 'administrador')
const { data: listas, refresh: recarregarListas } = await useListas()

// Nomes da aba CAMPOS da planilha, sugeridos ao digitar.
const NOMES_PLANILHA = ['ARTHUR', 'CLEYTON', 'FÁBIO', 'GUILHERME', 'HUGO', 'IRENE', 'JULIANA DEGANE', 'LEOCÁDIO', 'LUCAS JOSÉ',
  'LUCAS ROCHA', 'LUIZ HENRIQUE', 'MARIA DO ROSÁRIO', 'REJANE', 'RODRIGO', 'SIMONE PACHECO', 'VANUZA', 'VINÍCIUS']

const novo = reactive({ nome: '', diretoria_id: null as number | null })
const mensagem = ref<{ tipo: 'erro' | 'sucesso', texto: string } | null>(null)
const salvando = ref(false)

async function depoisDeAlterar(texto: string) {
  mensagem.value = { tipo: 'sucesso', texto }
  await Promise.all([refreshNuxtData('cadastro'), recarregarListas()])
}

async function adicionarAvaliador() {
  mensagem.value = null
  const nome = novo.nome.trim().toLocaleUpperCase('pt-BR')
  if (!nome || !novo.diretoria_id) {
    mensagem.value = { tipo: 'erro', texto: 'Informe o nome e a diretoria do avaliador.' }
    return
  }
  salvando.value = true
  // Um avaliador desativado com o mesmo nome e diretoria volta a ficar ativo.
  const { error } = await supabase.from('avaliadores')
    .upsert({ nome, diretoria_id: novo.diretoria_id, ativo: true }, { onConflict: 'nome,diretoria_id' })
  salvando.value = false
  if (error) {
    mensagem.value = { tipo: 'erro', texto: mensagemErro(error) }
    return
  }
  const diretoria = nomeExibicao(nomePorId(listas.value?.diretorias, novo.diretoria_id))
  novo.nome = ''
  await depoisDeAlterar(`${nomeExibicao(nome)} cadastrado em ${diretoria}.`)
}

// Posição do bairro no mapa do Painel Gerencial, marcada pelo administrador.
const editando = ref<PosicaoBairro | null>(null)
const bairrosMarcados = computed(() => (linhas.value ?? []).flatMap(l => (l.bairro?.latitude != null ? [l.bairro] : [])))
watch(aba, () => { editando.value = null })

// Bairro cadastrado direto aqui, já abrindo o mapa para marcar a posição.
const novoBairro = ref('')
async function adicionarBairro() {
  mensagem.value = null
  const nome = novoBairro.value.trim().replace(/\s+/g, ' ').toLocaleUpperCase('pt-BR')
  if (!nome) {
    mensagem.value = { tipo: 'erro', texto: 'Informe o nome do bairro.' }
    return
  }
  const existente = linhas.value?.find(l => l.bairro?.nome.toLocaleUpperCase('pt-BR') === nome)?.bairro
  if (existente) {
    novoBairro.value = ''
    editando.value = existente
    return
  }
  salvando.value = true
  const { data, error } = await supabase.from('bairros').insert({ nome }).select('id, nome, latitude, longitude').single()
  salvando.value = false
  if (error) {
    mensagem.value = { tipo: 'erro', texto: mensagemErro(error) }
    return
  }
  novoBairro.value = ''
  await depoisDeAlterar(`${nomeExibicao(nome)} cadastrado. Marque a posição no mapa.`)
  editando.value = data as PosicaoBairro
}

// Correção do nome pelo administrador; as manifestações seguem ligadas ao bairro pelo id.
const nomeBairro = ref('')
watch(editando, (b) => { nomeBairro.value = b ? nomeExibicao(b.nome) : '' })
async function renomearBairro() {
  const b = editando.value
  if (!b) return
  mensagem.value = null
  const nome = nomeBairro.value.trim().replace(/\s+/g, ' ').toLocaleUpperCase('pt-BR')
  if (!nome || nome === b.nome) return
  salvando.value = true
  const { error } = await supabase.from('bairros').update({ nome }).eq('id', b.id)
  salvando.value = false
  if (error) {
    mensagem.value = { tipo: 'erro', texto: mensagemErro(error) }
    return
  }
  const antigo = nomeExibicao(b.nome)
  editando.value = { ...b, nome }
  await depoisDeAlterar(`${antigo} agora se chama ${nomeExibicao(nome)}.`)
  await refreshNuxtData('posicoes-bairros')
}

async function salvarPosicao(posicao: { latitude: number, longitude: number } | null) {
  const b = editando.value
  if (!b) return
  mensagem.value = null
  salvando.value = true
  const { error } = await supabase.from('bairros')
    .update({ latitude: posicao?.latitude ?? null, longitude: posicao?.longitude ?? null }).eq('id', b.id)
  salvando.value = false
  if (error) {
    mensagem.value = { tipo: 'erro', texto: mensagemErro(error) }
    return
  }
  editando.value = null
  await depoisDeAlterar(posicao ? `Posição de ${nomeExibicao(b.nome)} salva.` : `Posição de ${nomeExibicao(b.nome)} removida.`)
  await refreshNuxtData('posicoes-bairros')
}

// RN09: feriados e pontos facultativos entram na contagem de dias úteis. Os prazos em aberto são
// recalculados na hora; a situação Vencida se ajusta na rotina de hora em hora.
const novoFeriado = reactive({ data: '', descricao: '', tipo: 'municipal' as TipoFeriado })
async function adicionarFeriado() {
  mensagem.value = null
  const descricao = novoFeriado.descricao.trim().replace(/\s+/g, ' ')
  if (!novoFeriado.data || !descricao) {
    mensagem.value = { tipo: 'erro', texto: 'Informe a data e a descrição do feriado.' }
    return
  }
  salvando.value = true
  const { error } = await supabase.from('feriados').insert({ data: novoFeriado.data, descricao, tipo: novoFeriado.tipo })
  salvando.value = false
  if (error) {
    mensagem.value = { tipo: 'erro', texto: mensagemErro(error) }
    return
  }
  const data = novoFeriado.data
  Object.assign(novoFeriado, { data: '', descricao: '' })
  await depoisDeAlterar(`Feriado de ${formatarData(data)} cadastrado. Os prazos já contam com ele.`)
}
async function excluirFeriado(f: Feriado) {
  if (!confirm(`Excluir o feriado de ${formatarData(f.data)} (${f.descricao})? Os prazos que passam por essa data serão recalculados.`)) return
  mensagem.value = null
  const { error } = await supabase.from('feriados').delete().eq('data', f.data)
  if (error) mensagem.value = { tipo: 'erro', texto: mensagemErro(error) }
  else await depoisDeAlterar(`Feriado de ${formatarData(f.data)} excluído.`)
}

async function desativarAvaliador(a: { id: number, nome: string }) {
  if (!confirm(`Desativar ${a.nome}? Ele deixa de aparecer nos encaminhamentos; o histórico continua.`)) return
  const { error } = await supabase.from('avaliadores').update({ ativo: false }).eq('id', a.id)
  if (error) mensagem.value = { tipo: 'erro', texto: mensagemErro(error) }
  else await depoisDeAlterar(`${a.nome} desativado.`)
}
</script>

<template>
  <CabecalhoPagina titulo="Cadastros" subtitulo="Listas usadas no registro das manifestações. O administrador cadastra os avaliadores de cada diretoria." />

  <section class="cartao">
    <div class="flex flex-wrap gap-2 border-b border-neutral-100 px-3.5 py-3">
      <button
        v-for="a in abas"
        :key="a.id"
        class="inline-flex items-center rounded-control border px-2.5 py-1.5 text-[0.78rem]"
        :class="aba === a.id
          ? 'border-primary-300 bg-primary-50 font-semibold text-primary-800'
          : 'border-neutral-200 bg-white text-neutral-700 hover:bg-neutral-25'"
        @click="trocar(a.id)"
      >
        {{ a.nome }}
      </button>
    </div>
    <form v-if="aba === 'diretorias' && ehAdmin" class="flex flex-wrap items-end gap-3 border-b border-neutral-100 bg-neutral-25 px-3.5 py-3" @submit.prevent="adicionarAvaliador">
      <CampoForm rotulo="Novo avaliador" class="w-[220px]">
        <input v-model="novo.nome" class="campo" list="nomes-planilha" autocomplete="off">
        <datalist id="nomes-planilha"><option v-for="n in NOMES_PLANILHA" :key="n" :value="nomeExibicao(n)" /></datalist>
      </CampoForm>
      <CampoForm rotulo="Diretoria" class="min-w-[260px] flex-1">
        <select v-model="novo.diretoria_id" class="campo">
          <option :value="null" disabled>Escolha</option>
          <option v-for="d in listas?.diretorias" :key="d.id" :value="d.id">{{ nomeExibicao(d.nome) }}</option>
        </select>
      </CampoForm>
      <button class="btn btn-primario" :disabled="salvando">Adicionar avaliador</button>
    </form>
    <p v-if="aba === 'bairros'" class="border-b border-neutral-100 px-3.5 py-2.5 text-[0.8rem] text-neutral-600">
      Cada bairro marcado aparece como uma bolha no mapa do Painel Gerencial. Os bairros também entram quando são digitados numa manifestação.
    </p>
    <form v-if="aba === 'bairros' && ehAdmin" class="flex flex-wrap items-end gap-3 border-b border-neutral-100 bg-neutral-25 px-3.5 py-3" @submit.prevent="adicionarBairro">
      <CampoForm rotulo="Novo bairro" class="w-[280px]">
        <input v-model="novoBairro" class="campo" autocomplete="off">
      </CampoForm>
      <button class="btn btn-primario" :disabled="salvando">Adicionar e marcar no mapa</button>
    </form>
    <form v-if="aba === 'bairros' && editando" class="flex flex-wrap items-end gap-3 bg-neutral-25 px-3.5 pt-3" @submit.prevent="renomearBairro">
      <CampoForm rotulo="Nome do bairro" class="w-[280px]">
        <input v-model="nomeBairro" class="campo" autocomplete="off">
      </CampoForm>
      <button
        class="btn btn-secundario"
        :disabled="salvando || !nomeBairro.trim() || nomeBairro.trim().replace(/\s+/g, ' ').toLocaleUpperCase('pt-BR') === editando.nome"
      >
        Renomear
      </button>
    </form>
    <MapaPosicao
      v-if="aba === 'bairros' && editando"
      :key="editando.id"
      :bairro="editando"
      :outros="bairrosMarcados"
      :salvando="salvando"
      @salvar="salvarPosicao"
      @cancelar="editando = null"
    />
    <form v-if="aba === 'feriados' && ehAdmin" class="flex flex-wrap items-end gap-3 border-b border-neutral-100 bg-neutral-25 px-3.5 py-3" @submit.prevent="adicionarFeriado">
      <CampoForm rotulo="Data" obrigatorio>
        <input v-model="novoFeriado.data" type="date" class="campo font-mono">
      </CampoForm>
      <CampoForm rotulo="Descrição" obrigatorio class="w-[280px]">
        <input v-model="novoFeriado.descricao" class="campo" autocomplete="off" placeholder="Ex.: Aniversário de Uberlândia">
      </CampoForm>
      <CampoForm rotulo="Tipo" obrigatorio>
        <select v-model="novoFeriado.tipo" class="campo">
          <option v-for="(nome, valor) in tiposFeriado" :key="valor" :value="valor">{{ nome }}</option>
        </select>
      </CampoForm>
      <button class="btn btn-primario" :disabled="salvando">Adicionar feriado</button>
    </form>
    <AvisoCaixa v-if="mensagem && (aba === 'diretorias' || aba === 'bairros' || aba === 'feriados')" class="mx-3.5 mt-3" :titulo="mensagem.texto" :tipo="mensagem.tipo" />
    <p v-if="pending" class="px-4 py-6 text-[0.84rem] text-neutral-500">Carregando…</p>
    <table v-else class="lista">
      <thead>
        <tr><th v-for="c in cabecalhos[aba]" :key="c">{{ c }}</th></tr>
      </thead>
      <tbody>
        <tr v-for="(linha, i) in linhas" :key="i">
          <template v-if="aba === 'diretorias'">
            <td class="font-semibold text-neutral-900">{{ linha.colunas[0] }}</td>
            <td>
              <span v-if="!linha.avaliadores?.length" class="text-[0.8rem] text-warning">Sem avaliador: não dá para encaminhar</span>
              <span class="flex flex-wrap gap-1.5">
                <span v-for="a in linha.avaliadores" :key="a.id" class="inline-flex items-center gap-1 rounded-full bg-neutral-50 py-1 pl-2.5 pr-1.5 text-[0.78rem] text-neutral-700 ring-1 ring-inset ring-neutral-100">
                  {{ a.nome }}
                  <button v-if="ehAdmin" class="grid h-4 w-4 place-items-center rounded-full text-neutral-400 hover:bg-danger-soft hover:text-danger" :aria-label="`Desativar ${a.nome}`" @click="desativarAvaliador(a)">×</button>
                </span>
              </span>
            </td>
          </template>
          <template v-else-if="aba === 'bairros' && linha.bairro">
            <td class="font-semibold text-neutral-900">{{ linha.colunas[0] }}</td>
            <td>
              <span class="flex flex-wrap items-center gap-3">
                <span :class="linha.bairro.latitude == null ? 'text-warning' : 'text-neutral-600'">{{ linha.colunas[1] }}</span>
                <button
                  v-if="ehAdmin"
                  type="button"
                  class="text-[0.78rem] font-semibold text-primary-700 hover:underline"
                  @click="editando = linha.bairro"
                >
                  {{ linha.bairro.latitude == null ? 'Marcar no mapa' : 'Editar' }}
                </button>
              </span>
            </td>
          </template>
          <template v-else-if="aba === 'feriados' && linha.feriado">
            <td class="font-mono !font-medium text-primary-700">{{ linha.colunas[0] }}</td>
            <td class="text-neutral-600">{{ linha.colunas[1] }}</td>
            <td class="text-neutral-600">
              <span class="flex flex-wrap items-center justify-between gap-3">
                {{ linha.colunas[2] }}
                <button v-if="ehAdmin" type="button" class="text-[0.78rem] font-semibold text-danger hover:underline" @click="excluirFeriado(linha.feriado)">Excluir</button>
              </span>
            </td>
          </template>
          <template v-else>
            <td
              v-for="(valor, j) in linha.colunas"
              :key="j"
              :class="[
                j === 0 ? 'font-semibold text-neutral-900' : 'text-neutral-600',
                aba === 'feriados' && j === 0 ? 'font-mono !font-medium text-primary-700' : '',
              ]"
            >
              {{ valor }}
            </td>
          </template>
        </tr>
        <tr v-if="!linhas?.length">
          <td :colspan="cabecalhos[aba].length" class="text-neutral-500">Nenhum registro.</td>
        </tr>
      </tbody>
    </table>
    <div class="flex justify-between border-t border-neutral-100 px-3.5 py-2.5 text-[0.76rem] text-neutral-500">
      <span>{{ linhas?.length ?? 0 }} registros</span>
      <span v-if="aba === 'feriados'">Ano atual e seguintes</span>
      <span v-if="aba === 'bairros'">{{ bairrosMarcados.length }} com posição</span>
    </div>
  </section>
</template>
