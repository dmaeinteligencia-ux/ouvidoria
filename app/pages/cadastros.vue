<script setup lang="ts">
const supabase = useSupabaseClient()

const abas = [
  { id: 'diretorias', nome: 'Diretorias' },
  { id: 'avaliadores', nome: 'Avaliadores' },
  { id: 'assuntos', nome: 'Assuntos' },
  { id: 'canais', nome: 'Canais' },
  { id: 'motivos_arquivamento', nome: 'Motivos de arquivamento' },
  { id: 'feriados', nome: 'Feriados' },
] as const

type Aba = typeof abas[number]['id']
const aba = ref<Aba>('diretorias')

const consultas: Record<Aba, () => PromiseLike<{ data: unknown[] | null, error: unknown }>> = {
  diretorias: () => supabase.from('diretorias').select('nome').order('nome'),
  avaliadores: () => supabase.from('avaliadores').select('nome, diretorias(nome)').order('nome'),
  assuntos: () => supabase.from('assuntos').select('nome').order('nome'),
  canais: () => supabase.from('canais').select('nome, nome_painel').order('nome'),
  motivos_arquivamento: () => supabase.from('motivos_arquivamento').select('nome').order('nome'),
  feriados: () => supabase.from('feriados').select('data, descricao, tipo').order('data'),
}

const { data: linhas, pending } = await useAsyncData('cadastro', async () => {
  const { data, error } = await consultas[aba.value]()
  if (error) throw error
  return (data ?? []) as Record<string, unknown>[]
}, { watch: [aba] })

function texto(linha: Record<string, unknown>): string {
  if (aba.value === 'avaliadores') {
    const diretoria = (linha.diretorias as { nome: string } | null)?.nome ?? ''
    return `${linha.nome} · ${diretoria}`
  }
  if (aba.value === 'feriados') {
    const [ano, mes, dia] = String(linha.data).split('-')
    return `${dia}/${mes}/${ano} · ${linha.descricao}`
  }
  if (aba.value === 'canais') return `${linha.nome} (no painel: ${linha.nome_painel})`
  return String(linha.nome)
}
</script>

<template>
  <div>
    <h1 class="mb-4 text-xl font-semibold">Cadastros</h1>
    <div class="mb-4 flex flex-wrap gap-2">
      <button
        v-for="a in abas"
        :key="a.id"
        class="rounded-full px-3 py-1 text-sm"
        :class="aba === a.id ? 'bg-dmae-600 text-white' : 'bg-white text-slate-700 shadow-sm'"
        @click="aba = a.id"
      >
        {{ a.nome }}
      </button>
    </div>
    <p v-if="pending" class="text-sm text-slate-500">Carregando…</p>
    <ul v-else class="divide-y divide-slate-100 rounded-lg bg-white shadow-sm">
      <li v-for="(linha, i) in linhas" :key="i" class="px-4 py-2 text-sm">{{ texto(linha) }}</li>
      <li v-if="!linhas?.length" class="px-4 py-2 text-sm text-slate-500">Nenhum registro.</li>
    </ul>
  </div>
</template>
