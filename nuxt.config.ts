export default defineNuxtConfig({
  compatibilityDate: '2026-10-01',
  modules: ['@nuxtjs/tailwindcss', '@nuxtjs/supabase'],
  css: ['~/assets/css/main.css'],
  app: {
    head: {
      htmlAttrs: { lang: 'pt-BR' },
      title: 'Ouvidoria DMAE',
    },
  },
  supabase: {
    // Gerar com `supabase gen types typescript` quando o projeto Supabase existir.
    types: false,
    redirectOptions: {
      login: '/login',
      callback: '/confirmar',
      // O Painel Geral (Fase 4) será público.
      exclude: ['/painel'],
    },
  },
  typescript: { strict: true },
})
