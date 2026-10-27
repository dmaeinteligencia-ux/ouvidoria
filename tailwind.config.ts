import type { Config } from 'tailwindcss'

export default {
  content: ['./app/**/*.{vue,ts}'],
  theme: {
    extend: {
      colors: {
        dmae: {
          50: '#eff6ff',
          100: '#dbeafe',
          600: '#1d5fa8',
          700: '#174c87',
          900: '#0f2f55',
        },
      },
    },
  },
} satisfies Config
