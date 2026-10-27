<script setup lang="ts">
const supabase = useSupabaseClient()
const { data: perfil } = await usePerfil()

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
    <div v-if="!perfil" class="rounded-control bg-warning-soft p-4 text-sm text-warning">
      Seu login ainda não tem perfil no sistema. Peça ao administrador para cadastrá-lo.
    </div>

    <div v-else-if="perfil.perfil === 'diretor'" class="rounded-control bg-primary-50 p-4 text-sm text-primary-900">
      O Painel Gerencial da sua diretoria estará disponível aqui na Fase 4.
    </div>

    <template v-else>
      <h1 class="mb-4 font-display text-h1 font-bold">Manifestações por situação</h1>
      <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
        <div v-for="s in SITUACOES" :key="s.valor" class="rounded-panel bg-white p-4 shadow-sm">
          <span class="inline-block rounded-full px-2 py-0.5 text-caption" :class="s.classes">{{ s.nome }}</span>
          <p class="mt-2 font-display text-display text-primary-900">
            {{ contagens?.[s.valor] ?? 0 }}
          </p>
        </div>
      </div>
    </template>
  </div>
</template>
