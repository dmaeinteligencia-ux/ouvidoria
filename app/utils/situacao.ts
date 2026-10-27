// Mapa único das situações (RN24) ligado aos tokens de cor do tailwind.config.
export const SITUACOES = [
  { valor: 'em_tratamento', nome: 'Em tratamento', classes: 'bg-status-tratamento-soft text-status-tratamento' },
  { valor: 'aguardando_complementacao', nome: 'Aguardando complementação', classes: 'bg-status-complementacao-soft text-status-complementacao' },
  { valor: 'prorrogada', nome: 'Prorrogada', classes: 'bg-status-prorrogada-soft text-status-prorrogada' },
  { valor: 'vencida', nome: 'Vencida', classes: 'bg-status-vencida-soft text-status-vencida' },
  { valor: 'reaberta', nome: 'Reaberta', classes: 'bg-status-reaberta-soft text-status-reaberta' },
  { valor: 'respondida', nome: 'Respondida', classes: 'bg-status-respondida-soft text-status-respondida' },
] as const

export type Situacao = typeof SITUACOES[number]['valor']
