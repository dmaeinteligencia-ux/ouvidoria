// Os cadastros vêm em maiúsculas da planilha; nas telas, viram "Falta de Água".
const MINUSCULAS = new Set(['a', 'à', 'ao', 'as', 'da', 'das', 'de', 'do', 'dos', 'e', 'em', 'na', 'no', 'o', 'os', 'para'])
const SIGLAS = new Set(['MG-OUV', 'FALA.BR', 'DMAE', 'PREMEND'])

// Numerais romanos depois da primeira palavra ("MORADA NOVA III" → "Morada Nova III").
const ROMANOS = /^(I{1,3}|IV|VI{0,3}|IX|XI{0,3})$/i

export function nomeExibicao(texto: string | null | undefined): string {
  if (!texto) return ''
  return texto
    .split(/\s+/)
    .map((palavra, i) => {
      if (SIGLAS.has(palavra.toUpperCase())) return palavra.toUpperCase()
      if (i > 0 && ROMANOS.test(palavra)) return palavra.toUpperCase()
      const minuscula = palavra.toLocaleLowerCase('pt-BR')
      if (i > 0 && MINUSCULAS.has(minuscula)) return minuscula
      return minuscula.replace(/^\p{L}/u, l => l.toLocaleUpperCase('pt-BR'))
    })
    .join(' ')
}

// "DIRETORIA DO SISTEMA DE ABASTECIMENTO DE ÁGUA" → "Sistema de Abastecimento de Água"
export function nomeDiretoriaCurto(texto: string): string {
  return nomeExibicao(texto.replace(/^DIRETORIA (DE |DO |DA )?/i, ''))
}
