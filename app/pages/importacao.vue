<script setup lang="ts">
import type { ItemLista } from '~/composables/useListas'
import { CADASTROS, jaNoSistema, lerPlanilha, valorForaDoCadastro, type AbaLida, type LinhaLida, type RotuloCadastro } from '~/utils/importacao'

// Importação das planilhas mensais antigas (só o administrador). O arquivo é lido no navegador e as
// linhas vão para a área de carga do banco, que confere cada uma sem gravar nada; o administrador
// resolve os valores fora do cadastro e importa as linhas sem erro. As que têm erro ficam no lote:
// corrigidas na planilha, basta enviar o arquivo de novo (as já importadas são reconhecidas).
const supabase = useSupabaseClient()
const { data: perfil } = await usePerfil()
const ehAdmin = computed(() => perfil.value?.perfil === 'administrador')
const { data: listas, refresh: recarregarListas } = await useListas()

interface LinhaCarga { id: number, aba: string, linha: number, protocolo: string | null, erros: string[], avisos: string[], importada: boolean }

const BLOCO = 40
const mensagem = ref<{ tipo: 'erro' | 'sucesso' | 'atencao', texto: string } | null>(null)
const progresso = ref<{ texto: string, feito: number, total: number } | null>(null)
const ocupado = computed(() => progresso.value !== null)

// 1. Leitura dos arquivos
const lidas = ref<LinhaLida[]>([])
const abasLidas = ref<AbaLida[]>([])
const arquivos = ref<string[]>([])
async function escolher(evento: Event) {
  const entrada = evento.target as HTMLInputElement
  const escolhidos = Array.from(entrada.files ?? [])
  if (!escolhidos.length) return
  mensagem.value = null
  lidas.value = []
  abasLidas.value = []
  arquivos.value = escolhidos.map(f => f.name)
  try {
    progresso.value = { texto: 'Lendo as planilhas…', feito: 0, total: escolhidos.length }
    for (const arquivo of escolhidos) {
      const r = await lerPlanilha(arquivo)
      lidas.value.push(...r.linhas)
      abasLidas.value.push(...r.abas)
      progresso.value.feito++
    }
  }
  catch {
    mensagem.value = { tipo: 'erro', texto: 'Não foi possível ler o arquivo. Confira se é um .xlsx sem senha.' }
  }
  finally {
    progresso.value = null
    entrada.value = ''
  }
}

// 2. Envio para a área de carga e conferência
const lote = ref<string | null>(null)
const carga = ref<LinhaCarga[]>([])

async function enviar() {
  if (!lidas.value.length) return
  mensagem.value = null
  const nome = `${arquivos.value.join(', ')} · ${new Date().toLocaleString('pt-BR')}`
  try {
    progresso.value = { texto: 'Enviando as linhas…', feito: 0, total: lidas.value.length }
    for (let i = 0; i < lidas.value.length; i += 200) {
      const bloco = lidas.value.slice(i, i + 200).map(l => ({ lote: nome, aba: l.aba, linha: l.linha, dados: l.dados as never }))
      const { error } = await supabase.from('importacao_linhas').insert(bloco)
      if (error) throw error
      progresso.value.feito += bloco.length
    }
    lote.value = nome
    lidas.value = []
    abasLidas.value = []
    await conferir()
  }
  catch (e) {
    progresso.value = null
    mensagem.value = { tipo: 'erro', texto: mensagemErro(e) }
  }
}

async function emBlocos(funcao: 'importacao_conferir' | 'importacao_importar', texto: string) {
  const { data: ordem, error } = await supabase.rpc('importacao_ordem_lote', { p_lote: lote.value! })
  if (error) throw error
  const ids = (ordem ?? []) as number[]
  let importadas = 0
  progresso.value = { texto, feito: 0, total: ids.length }
  for (let i = 0; i < ids.length; i += BLOCO) {
    const { data, error: e } = await supabase.rpc(funcao, { p_ids: ids.slice(i, i + BLOCO) })
    if (e) throw e
    importadas += (data as { importadas: number }[] | null)?.[0]?.importadas ?? 0
    progresso.value.feito = Math.min(ids.length, i + BLOCO)
  }
  return importadas
}

async function carregarLote() {
  const linhas: LinhaCarga[] = []
  for (let de = 0; ; de += 1000) {
    const { data, error } = await supabase.from('importacao_linhas')
      .select('id, aba, linha, protocolo:dados->>protocolo, falabr:dados->>falabr, erros, avisos, importada_em')
      .eq('lote', lote.value!).order('id').range(de, de + 999)
    if (error) throw error
    for (const l of data ?? []) {
      linhas.push({ id: l.id, aba: l.aba, linha: l.linha, protocolo: (l.protocolo ?? l.falabr) as string | null,
        erros: l.erros, avisos: l.avisos, importada: !!l.importada_em })
    }
    if ((data ?? []).length < 1000) break
  }
  carga.value = linhas
}

async function conferir() {
  mensagem.value = null
  try {
    await emBlocos('importacao_conferir', 'Conferindo as linhas…')
    await carregarLote()
  }
  catch (e) {
    mensagem.value = { tipo: 'erro', texto: mensagemErro(e) }
  }
  finally {
    progresso.value = null
  }
}

// Resumo do lote
const pendentes = computed(() => carga.value.filter(l => !l.importada))
const prontas = computed(() => pendentes.value.filter(l => !l.erros.length))
const jaImportadas = computed(() => pendentes.value.filter(l => l.erros.length && l.erros.every(jaNoSistema)))
const comErro = computed(() => pendentes.value.filter(l => l.erros.length && !l.erros.every(jaNoSistema)))
const importadasNoLote = computed(() => carga.value.filter(l => l.importada).length)

// Valores fora do cadastro, agrupados: uma escolha resolve todas as linhas com o mesmo valor.
interface Fora { chave: string, rotulo: RotuloCadastro, valor: string, linhas: number }
const foraDoCadastro = computed<Fora[]>(() => {
  const grupos = new Map<string, Fora>()
  for (const l of comErro.value) {
    for (const e of l.erros) {
      const f = valorForaDoCadastro(e)
      if (!f) continue
      const chave = `${f.rotulo}|${f.valor.trim().toUpperCase()}`
      const g = grupos.get(chave) ?? { chave, ...f, linhas: 0 }
      g.linhas++
      grupos.set(chave, g)
    }
  }
  return [...grupos.values()].sort((a, b) => a.rotulo.localeCompare(b.rotulo) || b.linhas - a.linhas)
})
const NOVO = -1
const escolhas = reactive<Record<string, number | null>>({})
const opcoes = (rotulo: RotuloCadastro): ItemLista[] => (listas.value?.[CADASTROS[rotulo].lista] ?? []) as ItemLista[]

async function salvarEquivalencias() {
  const definidas = foraDoCadastro.value.filter(f => escolhas[f.chave] != null)
  if (!definidas.length) return
  mensagem.value = null
  try {
    progresso.value = { texto: 'Salvando as equivalências…', feito: 0, total: definidas.length }
    for (const f of definidas) {
      const alvo = escolhas[f.chave]
      const { error } = await supabase.rpc('importacao_equivaler', {
        p_tabela: CADASTROS[f.rotulo].tabela, p_valor: f.valor, ...(alvo === NOVO ? {} : { p_alvo_id: alvo! }),
      })
      if (error) throw error
      delete escolhas[f.chave]
      progresso.value.feito++
    }
    await recarregarListas()
    await conferir()
  }
  catch (e) {
    progresso.value = null
    mensagem.value = { tipo: 'erro', texto: mensagemErro(e) }
  }
}

// Outros problemas, agrupados pela mensagem (sem o valor entre aspas).
const outrosProblemas = computed(() => {
  const grupos = new Map<string, LinhaCarga[]>()
  for (const l of comErro.value) {
    for (const e of l.erros) {
      if (valorForaDoCadastro(e) || jaNoSistema(e)) continue
      const tipo = e.replace(/:\s*"[\s\S]*"$/, '').replace(/já aparece em [\s\S]*/, 'já aparece em outra linha')
      grupos.set(tipo, [...(grupos.get(tipo) ?? []), l])
    }
  }
  return [...grupos.entries()].map(([tipo, linhas]) => ({ tipo, linhas })).sort((a, b) => b.linhas.length - a.linhas.length)
})
const avisos = computed(() => {
  const grupos = new Map<string, number>()
  for (const l of prontas.value) {
    for (const a of l.avisos) {
      const tipo = a.replace(/:\s*.*$/, '')
      grupos.set(tipo, (grupos.get(tipo) ?? 0) + 1)
    }
  }
  return [...grupos.entries()].sort((a, b) => b[1] - a[1])
})

// 3. Importação
async function importar() {
  if (!prontas.value.length) return
  if (!confirm(`Importar ${prontas.value.length} manifestações? Elas entram no sistema como registros definitivos.`)) return
  mensagem.value = null
  try {
    const n = await emBlocos('importacao_importar', 'Importando…')
    await carregarLote()
    mensagem.value = { tipo: 'sucesso', texto: `${n} manifestações importadas.` }
  }
  catch (e) {
    mensagem.value = { tipo: 'erro', texto: mensagemErro(e) }
  }
  finally {
    progresso.value = null
  }
}

async function descartar() {
  if (!confirm('Descartar as linhas deste envio que não foram importadas? As já importadas continuam no sistema.')) return
  const { error } = await supabase.from('importacao_linhas').delete().eq('lote', lote.value!).is('importada_em', null)
  if (error) {
    mensagem.value = { tipo: 'erro', texto: mensagemErro(error) }
    return
  }
  lote.value = null
  carga.value = []
}

// Envios anteriores com linhas pendentes, para continuar depois.
const { data: anteriores, refresh: recarregarAnteriores } = await useAsyncData('importacao-lotes', async () => {
  if (!ehAdmin.value) return []
  const { data, error } = await supabase.from('importacao_linhas').select('lote').is('importada_em', null).limit(5000)
  if (error) throw error
  return [...new Set((data ?? []).map(l => l.lote))]
}, { server: false })
async function continuar(nome: string) {
  lote.value = nome
  try {
    await carregarLote()
  }
  catch (e) {
    mensagem.value = { tipo: 'erro', texto: mensagemErro(e) }
  }
}
watch(lote, () => recarregarAnteriores())
</script>

<template>
  <CabecalhoPagina titulo="Importar planilha" subtitulo="Planilhas mensais antigas da Ouvidoria. Só o administrador vê esta tela." />

  <AvisoCaixa v-if="!ehAdmin" titulo="Acesso restrito" tipo="atencao">Só o administrador importa planilhas.</AvisoCaixa>

  <template v-else>
    <AvisoCaixa v-if="mensagem" :titulo="mensagem.texto" :tipo="mensagem.tipo" />

    <section v-if="progresso" class="cartao px-4 py-3" role="status">
      <div class="flex items-center justify-between text-[0.84rem]">
        <b class="font-semibold">{{ progresso.texto }}</b>
        <span class="font-mono text-neutral-500">{{ progresso.feito }} de {{ progresso.total }}</span>
      </div>
      <div class="mt-2 h-1.5 overflow-hidden rounded-full bg-neutral-100">
        <div class="h-full bg-primary-600 transition-all" :style="{ width: `${progresso.total ? (100 * progresso.feito) / progresso.total : 0}%` }" />
      </div>
    </section>

    <!-- Escolha dos arquivos -->
    <section v-if="!lote" class="cartao">
      <div class="cartao-topo"><b class="cartao-titulo">1. Escolha as planilhas</b></div>
      <div class="grid gap-3 px-3.5 py-3">
        <p class="text-[0.84rem] text-neutral-600">
          Arquivos .xlsx sem senha, com uma aba por mês. As colunas são reconhecidas pelo nome do cabeçalho, em qualquer um dos formatos usados desde 2024.
          Pode escolher vários arquivos de uma vez.
        </p>
        <label class="btn btn-secundario w-fit cursor-pointer" :class="{ 'pointer-events-none opacity-60': ocupado }">
          Escolher arquivos
          <input type="file" accept=".xlsx" multiple class="sr-only" :disabled="ocupado" @change="escolher">
        </label>

        <div v-if="abasLidas.length" class="grid gap-3">
          <table class="lista">
            <thead><tr><th>Arquivo e aba</th><th class="text-right">Manifestações</th></tr></thead>
            <tbody>
              <tr v-for="a in abasLidas" :key="a.aba">
                <td>{{ a.aba }}</td>
                <td class="text-right font-mono">
                  <span v-if="a.ignorada" class="font-sans text-[0.78rem] text-neutral-500">Ignorada: {{ a.ignorada }}</span>
                  <template v-else>{{ a.linhas }}</template>
                </td>
              </tr>
            </tbody>
          </table>
          <div class="flex flex-wrap items-center justify-between gap-3 border-t border-neutral-100 pt-3">
            <p class="text-[0.84rem]"><b>{{ lidas.length }}</b> manifestações encontradas. Nada é gravado no sistema antes da sua confirmação.</p>
            <button class="btn btn-primario" :disabled="ocupado || !lidas.length" @click="enviar">Enviar e conferir</button>
          </div>
        </div>
      </div>
    </section>

    <section v-if="!lote && anteriores?.length" class="cartao">
      <div class="cartao-topo"><b class="cartao-titulo">Envios com linhas pendentes</b></div>
      <ul class="divide-y divide-neutral-100">
        <li v-for="nome in anteriores" :key="nome" class="flex items-center justify-between gap-3 px-3.5 py-2.5 text-[0.84rem]">
          <span class="min-w-0 truncate">{{ nome }}</span>
          <button class="btn btn-secundario btn-pequeno" :disabled="ocupado" @click="continuar(nome)">Continuar</button>
        </li>
      </ul>
    </section>

    <!-- Resultado da conferência -->
    <template v-if="lote && !progresso">
      <section class="cartao">
        <div class="cartao-topo flex items-center justify-between gap-3">
          <b class="cartao-titulo">2. Conferência</b>
          <span class="truncate text-[0.76rem] text-neutral-500">{{ lote }}</span>
        </div>
        <div class="grid grid-cols-2 gap-3 px-3.5 py-3 sm:grid-cols-4">
          <KpiCartao rotulo="Prontas para importar" :valor="prontas.length" />
          <KpiCartao rotulo="Com problema" :valor="comErro.length" />
          <KpiCartao rotulo="Já estavam no sistema" :valor="jaImportadas.length" />
          <KpiCartao rotulo="Importadas neste envio" :valor="importadasNoLote" />
        </div>
        <div class="flex flex-wrap items-center justify-between gap-3 border-t border-neutral-100 px-3.5 py-3">
          <p class="text-[0.8rem] text-neutral-600">As linhas com problema ficam de fora. Corrija na planilha e envie o arquivo de novo, ou resolva abaixo os valores fora do cadastro.</p>
          <div class="flex gap-2">
            <button class="btn btn-secundario" :disabled="ocupado" @click="descartar">Descartar envio</button>
            <button class="btn btn-primario" :disabled="ocupado || !prontas.length" @click="importar">Importar {{ prontas.length }} manifestações</button>
          </div>
        </div>
      </section>

      <section v-if="foraDoCadastro.length" class="cartao overflow-x-auto">
        <div class="cartao-topo"><b class="cartao-titulo">Valores fora do cadastro</b></div>
        <p class="px-3.5 pt-3 text-[0.8rem] text-neutral-600">
          Escolha a qual item do cadastro cada valor da planilha corresponde. A escolha vale para todas as linhas e para os próximos envios.
          "Cadastrar como novo" cria o item inativo, só para o histórico.
        </p>
        <table class="lista">
          <thead><tr><th>Campo</th><th>Valor na planilha</th><th class="text-right">Linhas</th><th>Corresponde a</th></tr></thead>
          <tbody>
            <tr v-for="f in foraDoCadastro" :key="f.chave">
              <td>{{ f.rotulo }}</td>
              <td class="font-semibold">{{ f.valor }}</td>
              <td class="text-right font-mono">{{ f.linhas }}</td>
              <td>
                <select v-model="escolhas[f.chave]" class="campo min-w-[240px]" :aria-label="`Equivalência de ${f.valor}`">
                  <option :value="undefined">Escolha</option>
                  <option v-for="o in opcoes(f.rotulo)" :key="o.id" :value="o.id">{{ nomeExibicao(o.nome) }}</option>
                  <option :value="NOVO">Cadastrar como novo: {{ f.valor.toUpperCase() }}</option>
                </select>
              </td>
            </tr>
          </tbody>
        </table>
        <div class="flex justify-end border-t border-neutral-100 px-3.5 py-3">
          <button class="btn btn-primario" :disabled="ocupado || !foraDoCadastro.some(f => escolhas[f.chave] != null)" @click="salvarEquivalencias">
            Salvar e conferir de novo
          </button>
        </div>
      </section>

      <section v-if="outrosProblemas.length" class="cartao">
        <div class="cartao-topo"><b class="cartao-titulo">Outros problemas</b></div>
        <details v-for="g in outrosProblemas" :key="g.tipo" class="border-b border-neutral-100 px-3.5 py-2.5 last:border-0">
          <summary class="cursor-pointer text-[0.84rem]"><b>{{ g.tipo }}</b> <span class="text-neutral-500">· {{ g.linhas.length }} linhas</span></summary>
          <ul class="mt-2 grid gap-1 text-[0.78rem] text-neutral-600">
            <li v-for="l in g.linhas.slice(0, 100)" :key="l.id">
              {{ l.aba }}, linha {{ l.linha }}<span v-if="l.protocolo" class="font-mono"> · {{ l.protocolo }}</span>:
              {{ l.erros.filter(e => !valorForaDoCadastro(e)).map(e => e.length > 160 ? `${e.slice(0, 160)}…` : e).join('; ') }}
            </li>
            <li v-if="g.linhas.length > 100" class="text-neutral-500">e mais {{ g.linhas.length - 100 }} linhas.</li>
          </ul>
        </details>
      </section>

      <section v-if="avisos.length" class="cartao">
        <div class="cartao-topo"><b class="cartao-titulo">Avisos das linhas prontas</b></div>
        <ul class="grid gap-1 px-3.5 py-3 text-[0.8rem] text-neutral-600">
          <li v-for="[tipo, n] in avisos" :key="tipo">{{ tipo }}: <b class="font-mono">{{ n }}</b></li>
        </ul>
      </section>

      <button class="btn btn-secundario w-fit" :disabled="ocupado" @click="lote = null; carga = []">Enviar outra planilha</button>
    </template>
  </template>
</template>
