export default defineNuxtConfig({
  compatibilityDate: '2026-10-01',
  modules: ['@nuxtjs/tailwindcss', '@nuxtjs/supabase'],
  css: ['~/assets/css/main.css'],
  app: {
    head: {
      htmlAttrs: { lang: 'pt-BR' },
      title: 'Ouvidoria DMAE',
      link: [
        { rel: 'preconnect', href: 'https://fonts.googleapis.com' },
        { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' },
        {
          rel: 'stylesheet',
          href: 'https://fonts.googleapis.com/css2?family=Archivo:wght@600;700;800&family=IBM+Plex+Mono:wght@400;500&family=Public+Sans:wght@400;500;600;700&display=swap',
        },
      ],
    },
  },
  supabase: {
    types: '~/types/database.types.ts',
    redirectOptions: {
      login: '/login',
      callback: '/confirmar',
      // O Painel Geral é público.
      exclude: ['/painel', '/nova-senha'],
    },
  },
  runtimeConfig: {
    public: {
      // Botões dos painéis (CI nº 6660/2025); sem endereço, o botão não aparece.
      linkRegistrarManifestacao: '',
      linkPaginaOuvidoria: '',
    },
  },
  typescript: { strict: true },
})
