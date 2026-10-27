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
    { rotulo: 'Manifestações', contador: props.contagens?.abertas },
    { rotulo: 'Vencidas', contador: props.contagens?.vencidas, alerta: true },
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

function ativo(item: Item) {
  if (!item.para) return false
  const [caminho, busca] = item.para.split('?')
  if (route.path !== caminho) return false
  if (!busca) return true
  const aba = new URLSearchParams(busca).get('aba')
  return (route.query.aba ?? 'diretorias') === aba
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
