// Quem entrou pelo convite ainda não tem senha: escolhe antes de usar o sistema.
export default defineNuxtRouteMiddleware((to) => {
  const user = useSupabaseUser()
  if (['/nova-senha', '/login', '/confirmar'].includes(to.path)) return
  if (user.value?.user_metadata?.trocar_senha === true) return navigateTo('/nova-senha')
})
