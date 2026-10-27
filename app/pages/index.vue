<script setup lang="ts">
const supabase = useSupabaseClient()
const { data: perfil } = await usePerfil()

const situacoes = [
  { valor: 'em_tratamento', nome: 'Em tratamento' },
  { valor: 'aguardando_complementacao', nome: 'Aguardando complementação' },
  { valor: 'prorrogada', nome: 'Prorrogada' },
  { valor: 'vencida', nome: 'Vencida' },
  { valor: 'reaberta', nome: 'Reaberta' },
  { valor: 'respondida', nome: 'Respondida' },
] as const

const equipe = computed(() => perfil.value?.perfil === 'administrador' || perfil.value?.perfil === 'ouvidoria')

const { data: contagens } = await useAsyncData('contagens', async () => {
  if (!equipe.value) return {}
  const { data, error } = await supabase.from('manifestacoes').select('situacao')
  if (error) throw error
  const total: Record<string, number> = {}
  for (const linha of data as { situacao: string }[]) {
    total[linha.situacao] = (total[linha.situacao] ?? 0) + 1
  }
  return total
}, { watch: [equipe] })
</script>

<template>
  <div>
    <div v-if="!perfil" class="rounded-md bg-amber-50 p-4 text-sm text-amber-900">
      Seu login ainda não tem perfil no sistema. Peça ao administrador para cadastrá-lo.
    </div>

    <div v-else-if="perfil.perfil === 'diretor'" class="rounded-md bg-dmae-50 p-4 text-sm text-dmae-900">
      O Painel Gerencial da sua diretoria estará disponível aqui na Fase 4.
    </div>

    <template v-else>
      <h1 class="mb-4 text-xl font-semibold">Manifestações por situação</h1>
      <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
        <div v-for="s in situacoes" :key="s.valor" class="rounded-lg bg-white p-4 shadow-sm">
          <p class="text-xs text-slate-500">{{ s.nome }}</p>
          <p class="mt-1 text-2xl font-semibold" :class="s.valor === 'vencida' ? 'text-red-600' : 'text-dmae-900'">
            {{ contagens?.[s.valor] ?? 0 }}
          </p>
        </div>
      </div>
    </template>
  </div>
</template>
