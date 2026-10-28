// Traduz erros do Supabase/Postgres para mensagens da tela.
const RESTRICOES: Record<string, string> = {
  manifestacoes_protocolo_mgouv_key: 'Este protocolo MG-OUV já está cadastrado.',
  manifestacoes_protocolo_falabr_key: 'Este protocolo Fala.BR já está cadastrado.',
  protocolo_mgouv_formato: 'O protocolo MG-OUV deve ter exatamente 13 dígitos.',
  protocolo_falabr_formato: 'O protocolo Fala.BR deve seguir o formato 00000.0000.000000-00.',
  tem_protocolo: 'Informe pelo menos um protocolo (MG-OUV ou Fala.BR).',
  bairros_nome_key: 'Já existe um bairro com esse nome.',
  cep_formato: 'O CEP deve seguir o formato 00000-000.',
  feriados_pkey: 'Já existe um feriado nessa data.',
  encaminhamento_atual_unico: 'Este avaliador já está no encaminhamento.',
}

export function mensagemErro(erro: unknown): string {
  const e = erro as { message?: string, code?: string, details?: string } | null
  const texto = `${e?.message ?? ''} ${e?.details ?? ''}`
  for (const [nome, mensagem] of Object.entries(RESTRICOES)) {
    if (texto.includes(nome)) return mensagem
  }
  if (e?.code === 'P0001' && e.message) return e.message
  if (e?.code === '42501') return 'Seu perfil não tem permissão para esta ação.'
  return e?.message ? `Não foi possível salvar: ${e.message}` : 'Não foi possível salvar. Tente de novo.'
}
