<script setup lang="ts">
const supabase = useSupabaseClient()
const route = useRoute()
const router = useRouter()

const abas = [
  { id: 'diretorias', nome: 'Diretorias e avaliadores' },
  { id: 'assuntos', nome: 'Assuntos' },
  { id: 'canais', nome: 'Canais' },
  { id: 'motivos_arquivamento', nome: 'Motivos de arquivamento' },
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

interface Linha { colunas: string[] }

const cabecalhos: Record<Aba, string[]> = {
  diretorias: ['Diretoria', 'Avaliadores'],
  assuntos: ['Assunto'],
  canais: ['Canal', 'Nome no painel'],
  motivos_arquivamento: ['Motivo'],
  feriados: ['Data', 'Descrição', 'Tipo'],
}

const { data: linhas, pending } = await useAsyncData('cadastro', async (): Promise<Linha[]> => {
  switch (aba.value) {
    case 'diretorias': {
      const { data, error } = await supabase.from('diretorias').select('nome, avaliadores(nome)').order('nome')
      if (error) throw error
      return (data as { nome: string, avaliadores: { nome: string }[] }[]).map(d => ({
        colunas: [nomeExibicao(d.nome), d.avaliadores.map(a => nomeExibicao(a.nome)).join(', ') || '—'],
      }))
    }
    case 'canais': {
      const { data, error } = await supabase.from('canais').select('nome, nome_painel').order('nome')
      if (error) throw error
      return (data as { nome: string, nome_painel: string }[]).map(c => ({ colunas: [nomeExibicao(c.nome), c.nome_painel] }))
    }
    case 'feriados': {
      const { data, error } = await supabase.from('feriados').select('data, descricao, tipo')
        .gte('data', `${new Date().getFullYear()}-01-01`).order('data')
      if (error) throw error
      return (data as { data: string, descricao: string, tipo: string }[]).map((f) => {
        const [ano, mes, dia] = f.data.split('-')
        return { colunas: [`${dia}/${mes}/${ano}`, f.descricao, tiposFeriado[f.tipo] ?? f.tipo] }
      })
    }
    default: {
      const { data, error } = await supabase.from(aba.value).select('nome').order('nome')
      if (error) throw error
      return (data as { nome: string }[]).map(r => ({ colunas: [nomeExibicao(r.nome)] }))
    }
  }
}, { watch: [aba] })
</script>

<template>
  <CabecalhoPagina titulo="Cadastros" subtitulo="Listas usadas no registro das manifestações. Alterações pelo administrador chegam na próxima fase." />

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
    <p v-if="pending" class="px-4 py-6 text-[0.84rem] text-neutral-500">Carregando…</p>
    <table v-else class="lista">
      <thead>
        <tr><th v-for="c in cabecalhos[aba]" :key="c">{{ c }}</th></tr>
      </thead>
      <tbody>
        <tr v-for="(linha, i) in linhas" :key="i">
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
        </tr>
        <tr v-if="!linhas?.length">
          <td :colspan="cabecalhos[aba].length" class="text-neutral-500">Nenhum registro.</td>
        </tr>
      </tbody>
    </table>
    <div class="flex justify-between border-t border-neutral-100 px-3.5 py-2.5 text-[0.76rem] text-neutral-500">
      <span>{{ linhas?.length ?? 0 }} registros</span>
      <span v-if="aba === 'feriados'">Ano atual e seguintes</span>
    </div>
  </section>
</template>
