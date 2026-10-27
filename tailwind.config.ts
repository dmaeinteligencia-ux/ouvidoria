// Tokens do guia visual v0.1 da Ouvidoria DMAE (cor primária #004790).
import type { Config } from 'tailwindcss'

export default {
  content: ['./app/**/*.{vue,ts}'],
  theme: {
    extend: {
      colors: {
        primary: {
          50: '#EEF5FC', 100: '#D6E7F8', 200: '#ADCDF0', 300: '#7AAEE4',
          400: '#4589D3', 500: '#1A6BC0', 600: '#0058AE',
          700: '#004790', DEFAULT: '#004790',
          800: '#003A75', 900: '#002D5B', 950: '#001C3A',
        },
        neutral: {
          0: '#FFFFFF', 25: '#F7F9FC', 50: '#F1F4F9', 100: '#E4E9F1',
          200: '#CDD5E1', 300: '#A9B4C5', 400: '#7F8CA1', 500: '#5E6B80',
          600: '#475367', 700: '#333D4F', 800: '#222A38', 900: '#141A24',
        },
        brand: { green: '#2E9B48' },
        success: { DEFAULT: '#1F7A3A', soft: '#DDF3E3' },
        warning: { DEFAULT: '#8A5A00', soft: '#FCEFC7' },
        due: { DEFAULT: '#B54708', soft: '#FEEBD7' },
        danger: { DEFAULT: '#B42318', soft: '#FDE6E3' },
        // As 6 situações da planilha; "arquivada" é a marca de arquivamento, não uma situação.
        status: {
          complementacao: { DEFAULT: '#5B3A99', soft: '#EEE8F8' },
          tratamento: { DEFAULT: '#004790', soft: '#D6E7F8' },
          prorrogada: { DEFAULT: '#8A5A00', soft: '#FCEFC7' },
          vencida: { DEFAULT: '#B42318', soft: '#FDE6E3' },
          respondida: { DEFAULT: '#1F7A3A', soft: '#DDF3E3' },
          reaberta: { DEFAULT: '#0B6B77', soft: '#D3F0F2' },
          arquivada: { DEFAULT: '#333D4F', soft: '#FFFFFF' },
        },
      },
      fontFamily: {
        display: ['Archivo', 'Arial Narrow', 'Arial', 'sans-serif'],
        sans: ['"Public Sans"', '"Segoe UI"', 'Roboto', 'Arial', 'sans-serif'],
        mono: ['"IBM Plex Mono"', 'ui-monospace', 'Consolas', 'monospace'],
      },
      fontSize: {
        caption: ['0.6875rem', { lineHeight: '1rem', letterSpacing: '0.1em' }],
        label: ['0.8125rem', { lineHeight: '1rem' }],
        body: ['0.875rem', { lineHeight: '1.25rem' }],
        h2: ['1.125rem', { lineHeight: '1.5rem' }],
        h1: ['1.5rem', { lineHeight: '1.75rem' }],
        display: ['2rem', { lineHeight: '2.25rem' }],
      },
      borderRadius: { control: '6px', panel: '10px' },
      boxShadow: {
        focus: '0 0 0 3px #D6E7F8',
        overlay: '0 12px 32px -8px rgb(0 28 58 / 0.25)',
      },
      height: { topbar: '56px' },
      width: { sidebar: '212px' },
    },
  },
} satisfies Config
