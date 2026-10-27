-- Fecha funções SECURITY DEFINER para quem não deve chamá-las pela API (alertas do Supabase Advisor).
-- registrar_historico só roda por gatilho; perfil_atual é usada pelas políticas RLS de usuários logados.
revoke execute on function public.registrar_historico() from public, anon, authenticated;
revoke execute on function public.perfil_atual() from public, anon;
grant execute on function public.perfil_atual() to authenticated;
