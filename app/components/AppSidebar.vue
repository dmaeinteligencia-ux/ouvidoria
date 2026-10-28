<script setup lang="ts">
import type { Perfil } from '~/composables/usePerfil'

const props = defineProps<{ perfil: Perfil | null, contagens?: { abertas?: number, vencidas?: number, reabertas?: number } }>()
const route = useRoute()

interface Item {
  rotulo: string
  para?: string            // sem destino = disponível numa próxima fase
  contador?: number
  alerta?: boolean
}

const grupos = computed<{ titulo?: string, itens: Item[] }[]>(() => {
  const operacao: Item[] = [
    { rotulo: 'Painel', para: '/' },
    { rotulo: 'Manifestações', para: '/manifestacoes', contador: props.contagens?.abertas },
    { rotulo: 'Vencidas', para: '/manifestacoes?prazo=vencidas', contador: props.contagens?.vencidas, alerta: true },
    { rotulo: 'Reaberturas', contador: props.contagens?.reabertas },
  ]
  if (props.perfil === 'diretor') return [{ itens: [{ rotulo: 'Painel', para: '/' }] }]
  return [
    { itens: operacao },
    { titulo: 'Relatórios', itens: [{ rotulo: 'Extrato mensal' }, { rotulo: 'Indicadores' }] },
    {
      titulo: 'Cadastros',
      itens: [
        { rotulo: 'Assuntos', para: '/cadastros?aba=assuntos' },
        { rotulo: 'Diretorias e avaliadores', para: '/cadastros?aba=diretorias' },
        { rotulo: 'Feriados', para: '/cadastros?aba=feriados' },
      ],
    },
  ]
})

// Item ativo: mesmo caminho e mesmos parâmetros; vence o que tiver mais parâmetros em comum.
// Dentro de uma manifestação, "Manifestações" fica ativo.
const PADROES: Record<string, string> = { aba: 'diretorias' }

function pontos(item: Item): number {
  if (!item.para) return -1
  const [caminho, busca] = item.para.split('?')
  const noCaminho = route.path === caminho || (caminho !== '/' && route.path.startsWith(`${caminho}/`))
  if (!noCaminho) return -1
  let total = 0
  for (const [chave, valor] of new URLSearchParams(busca)) {
    if ((route.query[chave] ?? PADROES[chave]) !== valor) return -1
    total++
  }
  return total
}

const itemAtivo = computed(() => {
  let melhor: Item | null = null
  for (const item of grupos.value.flatMap(g => g.itens)) {
    if (pontos(item) > (melhor ? pontos(melhor) : -1)) melhor = item
  }
  return melhor
})

function ativo(item: Item) {
  return itemAtivo.value === item
}
</script>

<template>
  <aside class="hidden w-sidebar shrink-0 border-r border-neutral-100 bg-white px-2.5 py-4 lg:block">
    <nav class="grid content-start gap-0.5">
      <template v-for="(grupo, g) in grupos" :key="g">
        <span
          v-if="grupo.titulo"
          class="px-2.5 pb-1.5 pt-3.5 text-[0.68rem] font-semibold uppercase tracking-[0.1em] text-neutral-400"
        >{{ grupo.titulo }}</span>
        <template v-for="item in grupo.itens" :key="item.rotulo">
          <NuxtLink
            v-if="item.para"
            :to="item.para"
            class="flex items-center justify-between rounded-control px-2.5 py-2 text-[0.86rem] font-medium text-neutral-700 hover:bg-neutral-50"
            :class="{ '!bg-primary-50 font-semibold !text-primary-700 shadow-[inset_3px_0_0_theme(colors.primary.700)]': ativo(item) }"
          >
            {{ item.rotulo }}
            <em
              v-if="item.contador"
              class="rounded-full px-1.5 py-[3px] font-mono text-[0.7rem] font-semibold not-italic leading-none"
              :class="item.alerta ? 'bg-danger-soft text-danger' : 'bg-neutral-100 text-neutral-600'"
            >{{ item.contador }}</em>
          </NuxtLink>
          <span
            v-else
            class="flex cursor-default items-center justify-between rounded-control px-2.5 py-2 text-[0.86rem] font-medium text-neutral-400"
            title="Disponível nas próximas fases"
          >
            {{ item.rotulo }}
            <em
              v-if="item.contador"
              class="rounded-full px-1.5 py-[3px] font-mono text-[0.7rem] font-semibold not-italic leading-none"
              :class="item.alerta ? 'bg-danger-soft text-danger' : 'bg-neutral-100 text-neutral-600'"
            >{{ item.contador }}</em>
          </span>
        </template>
      </template>
    </nav>
  </aside>
</template>
