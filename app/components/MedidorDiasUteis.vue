<script setup lang="ts">
// Medidor do prazo do ciclo: os 10 dias úteis depois do dia 0; os 5 últimos só contam se houver prorrogação.
const props = defineProps<{
  diaZero: string
  prazo: string
  prorrogado: boolean
  respondidoEm: string | null
  diasRestantes: number | null
  suspenso?: boolean
  limiteComplementacao?: string | null
  feriados: string[]
}>()

const hoje = hojeBrasilia()
const limite = computed(() => (props.prorrogado ? 10 : 5))

const dias = computed(() => {
  const lista: string[] = []
  let d = props.diaZero
  while (lista.length < 10) {
    d = somarDias(d, 1)
    if (!ehFimDeSemana(d) && !props.feriados.includes(d)) lista.push(d)
  }
  return lista
})

const referencia = computed(() => props.respondidoEm ?? hoje)
const decorridos = computed(() => dias.value.filter(d => d <= referencia.value).length)

// Usado no prazo: azul; depois do prazo: vermelho; hoje (ou dia da resposta) em destaque.
function classe(d: string, i: number) {
  const atrasado = d > props.prazo
  if (d === referencia.value) return atrasado ? 'bg-danger' : props.respondidoEm ? 'bg-success' : 'bg-due'
  if (d < referencia.value) return atrasado ? 'bg-danger' : 'bg-primary-700'
  if (i >= limite.value) return 'bg-[repeating-linear-gradient(45deg,theme(colors.neutral.100)_0_3px,#fff_3px_6px)]'
  return 'bg-neutral-100'
}

const titulo = computed(() => {
  if (props.suspenso) {
    return {
      grande: '—',
      texto: props.limiteComplementacao ? `prazo suspenso · complementação até ${formatarData(props.limiteComplementacao, true)}` : 'prazo suspenso até a complementação',
      cor: 'text-status-complementacao',
    }
  }
  if (props.respondidoEm) {
    const noPrazo = props.respondidoEm <= props.prazo
    return {
      grande: `${decorridos.value}`,
      texto: `${decorridos.value === 1 ? 'dia útil' : 'dias úteis'} até a resposta · ${noPrazo ? 'no prazo' : 'fora do prazo'}`,
      cor: noPrazo ? 'text-success' : 'text-danger',
    }
  }
  const r = props.diasRestantes ?? 0
  if (r < 0) return { grande: `${-r}`, texto: `${r === -1 ? 'dia útil' : 'dias úteis'} de atraso`, cor: 'text-danger' }
  if (decorridos.value === 0) return { grande: 'Dia 0', texto: `recebida · prazo de ${limite.value} dias úteis`, cor: 'text-primary-700' }
  if (r === 0) return { grande: `${decorridos.value}º`, texto: `de ${limite.value} dias úteis · vence hoje`, cor: 'text-due' }
  return {
    grande: `${decorridos.value}º`,
    texto: `de ${limite.value} dias úteis · ${r === 1 ? 'falta 1' : `faltam ${r}`}`,
    cor: r <= 2 ? 'text-warning' : 'text-primary-700',
  }
})
</script>

<template>
  <div class="cartao grid gap-2.5 p-4">
    <span class="rotulo-caps">Prazo do ciclo</span>
    <div class="flex items-baseline gap-2">
      <b class="font-display text-[2.2rem] font-extrabold leading-none" :class="titulo.cor">{{ titulo.grande }}</b>
      <span class="text-[0.82rem] text-neutral-600">{{ titulo.texto }}</span>
    </div>
    <p v-if="suspenso" class="text-[0.74rem] text-neutral-500">Quando a complementação chegar, a contagem recomeça com novo dia 0 (RN10).</p>
    <div v-if="!suspenso" class="grid grid-cols-10 gap-[3px]">
      <i v-for="(d, i) in dias" :key="d" class="h-[22px] rounded-[3px]" :class="classe(d, i)" :title="formatarData(d)" />
    </div>
    <div v-if="!suspenso" class="grid grid-cols-10 gap-[3px] text-center font-mono text-[0.62rem] text-neutral-500">
      <span v-for="d in dias" :key="d">{{ d.slice(8) }}</span>
    </div>
    <div v-if="!suspenso" class="flex justify-between text-[0.72rem] text-neutral-500">
      <span>Prazo {{ formatarData(prazo, true) }}</span>
      <span v-if="!prorrogado">Prorrogação até {{ formatarData(dias[9], true) }}</span>
      <span v-else>Prorrogada</span>
    </div>
  </div>
</template>
