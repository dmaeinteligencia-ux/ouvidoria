<script setup lang="ts">
import type { Perfil } from '~/composables/usePerfil'

// Gestão de acessos: só o administrador. O login fica no Supabase Auth (rotas /api/usuarios, com a
// chave secreta no servidor); o perfil, em public.usuarios.
interface Usuario {
  id: string
  nome: string
  perfil: Perfil
  diretoria_id: number | null
  ativo: boolean
  email: string | null
  ultimo_acesso: string | null
  convite_pendente: boolean
}

const { data: perfil } = await usePerfil()
const ehAdmin = computed(() => perfil.value?.perfil === 'administrador')
const { data: listas } = await useListas()
const { data: usuarios, status, error: erroLista, refresh } = useFetch<Usuario[]>('/api/usuarios', { immediate: ehAdmin.value, server: false })

const PERFIS: { valor: Perfil, nome: string, ajuda: string }[] = [
  { valor: 'ouvidoria', nome: 'Ouvidoria', ajuda: 'Registra e acompanha as manifestações.' },
  { valor: 'administrador', nome: 'Administrador', ajuda: 'Tudo da Ouvidoria, mais cadastros e usuários.' },
  { valor: 'diretor', nome: 'Diretor', ajuda: 'Só o Painel Gerencial da própria diretoria.' },
]
const nomePerfil = (p: Perfil) => PERFIS.find(x => x.valor === p)?.nome ?? p

const mensagem = ref<{ tipo: 'erro' | 'sucesso', texto: string } | null>(null)
const salvando = ref(false)

function erroDe(e: unknown): string {
  const f = e as { data?: { message?: string } } | null
  return f?.data?.message ?? 'Não foi possível concluir. Tente de novo.'
}

async function chamar<T>(trabalho: () => Promise<T>): Promise<T | null> {
  mensagem.value = null
  salvando.value = true
  try {
    return await trabalho()
  }
  catch (e) {
    mensagem.value = { tipo: 'erro', texto: erroDe(e) }
    return null
  }
  finally {
    salvando.value = false
  }
}

// Novo usuário
const novo = reactive({ nome: '', email: '', perfil: 'ouvidoria' as Perfil, diretoria_id: null as number | null })
async function cadastrar() {
  const r = await chamar(() => $fetch<{ email: string }>('/api/usuarios', { method: 'POST', body: novo }))
  if (!r) return
  mensagem.value = { tipo: 'sucesso', texto: `Convite enviado para ${r.email}. A pessoa escolhe a senha pelo link do e-mail.` }
  Object.assign(novo, { nome: '', email: '', perfil: 'ouvidoria', diretoria_id: null })
  await refresh()
}

// Edição
const editando = ref<string | null>(null)
const edicao = reactive({ nome: '', perfil: 'ouvidoria' as Perfil, diretoria_id: null as number | null })
function editar(u: Usuario) {
  mensagem.value = null
  editando.value = u.id
  Object.assign(edicao, { nome: u.nome, perfil: u.perfil, diretoria_id: u.diretoria_id })
}
async function salvarEdicao(u: Usuario) {
  const r = await chamar(() => $fetch(`/api/usuarios/${u.id}`, { method: 'PATCH', body: edicao }))
  if (!r) return
  editando.value = null
  mensagem.value = { tipo: 'sucesso', texto: `Dados de ${edicao.nome} salvos.` }
  await refresh()
  if (u.id === perfil.value?.id) await refreshNuxtData('perfil')
}

async function alternarAtivo(u: Usuario) {
  if (u.ativo && !confirm(`Desativar ${u.nome}? A pessoa deixa de entrar no sistema. O histórico do que ela registrou continua.`)) return
  const r = await chamar(() => $fetch(`/api/usuarios/${u.id}`, { method: 'PATCH', body: { ativo: !u.ativo } }))
  if (!r) return
  mensagem.value = { tipo: 'sucesso', texto: u.ativo ? `Acesso de ${u.nome} desativado.` : `Acesso de ${u.nome} reativado.` }
  await refresh()
}

// Convite pendente: reenvia o convite. Já com senha: manda o link para escolher outra.
async function enviarAcesso(u: Usuario) {
  const r = await chamar(() => $fetch<{ tipo: 'convite' | 'senha', email: string }>(`/api/usuarios/${u.id}/acesso`, { method: 'POST' }))
  if (!r) return
  mensagem.value = { tipo: 'sucesso', texto: r.tipo === 'convite' ? `Convite reenviado para ${r.email}.` : `Link de nova senha enviado para ${r.email}.` }
}

const ativos = computed(() => (usuarios.value ?? []).filter(u => u.ativo).length)
</script>

<template>
  <CabecalhoPagina titulo="Usuários" subtitulo="Quem entra no sistema e com qual perfil. Só o administrador vê esta tela." />

  <AvisoCaixa v-if="!ehAdmin" titulo="Acesso restrito" tipo="atencao">Só o administrador gerencia os usuários.</AvisoCaixa>

  <template v-else>
    <AvisoCaixa v-if="mensagem" :titulo="mensagem.texto" :tipo="mensagem.tipo" />

    <section class="cartao">
      <div class="cartao-topo"><b class="cartao-titulo">Novo usuário</b></div>
      <form class="flex flex-wrap items-end gap-3 px-3.5 py-3" @submit.prevent="cadastrar">
        <CampoForm rotulo="Nome" obrigatorio class="w-[240px]">
          <input v-model="novo.nome" class="campo" autocomplete="off">
        </CampoForm>
        <CampoForm rotulo="E-mail" obrigatorio class="w-[260px]">
          <input v-model="novo.email" type="email" class="campo" autocomplete="off" placeholder="nome@dmae.mg.gov.br">
        </CampoForm>
        <CampoForm rotulo="Perfil" obrigatorio :dica="PERFIS.find(p => p.valor === novo.perfil)?.ajuda">
          <select v-model="novo.perfil" class="campo">
            <option v-for="p in PERFIS" :key="p.valor" :value="p.valor">{{ p.nome }}</option>
          </select>
        </CampoForm>
        <CampoForm v-if="novo.perfil === 'diretor'" rotulo="Diretoria" obrigatorio class="min-w-[260px] flex-1">
          <select v-model="novo.diretoria_id" class="campo">
            <option :value="null" disabled>Escolha</option>
            <option v-for="d in listas?.diretorias" :key="d.id" :value="d.id">{{ nomeExibicao(d.nome) }}</option>
          </select>
        </CampoForm>
        <button class="btn btn-primario" :disabled="salvando">{{ salvando ? 'Enviando…' : 'Cadastrar e enviar convite' }}</button>
      </form>
    </section>

    <ClientOnly>
    <section class="cartao overflow-x-auto">
      <AvisoCaixa v-if="erroLista" class="m-3.5" titulo="Não foi possível carregar os usuários" tipo="erro">{{ erroDe(erroLista) }}</AvisoCaixa>
      <p v-else-if="status !== 'success'" class="px-4 py-6 text-[0.84rem] text-neutral-500">Carregando…</p>
      <table v-else class="lista">
        <thead>
          <tr><th>Nome e e-mail</th><th>Perfil</th><th>Último acesso</th><th>Situação</th><th /></tr>
        </thead>
        <tbody>
          <template v-for="u in usuarios" :key="u.id">
            <tr :class="{ 'opacity-60': !u.ativo }">
              <td>
                <div class="font-semibold text-neutral-900">{{ u.nome }}<span v-if="u.id === perfil?.id" class="ml-1.5 text-[0.72rem] font-medium text-neutral-500">(você)</span></div>
                <div class="text-[0.76rem] text-neutral-500">{{ u.email ?? 'sem login' }}</div>
              </td>
              <td>
                {{ nomePerfil(u.perfil) }}
                <div v-if="u.diretoria_id" class="text-[0.76rem] text-neutral-500">{{ nomeDiretoriaCurto(nomePorId(listas?.diretorias, u.diretoria_id)) }}</div>
              </td>
              <td class="text-neutral-600">
                <span v-if="u.ultimo_acesso" class="font-mono text-[0.8rem]">{{ formatarDataHora(u.ultimo_acesso) }}</span>
                <span v-else class="text-[0.8rem] text-neutral-500">Nunca entrou</span>
              </td>
              <td>
                <span v-if="!u.ativo" class="text-[0.8rem] font-semibold text-neutral-500">Desativado</span>
                <span v-else-if="u.convite_pendente" class="text-[0.8rem] font-semibold text-warning">Convite pendente</span>
                <span v-else class="text-[0.8rem] font-semibold text-success">Ativo</span>
              </td>
              <td>
                <span class="flex flex-wrap justify-end gap-x-3 gap-y-1">
                  <button type="button" class="text-[0.78rem] font-semibold text-primary-700 hover:underline" @click="editar(u)">Editar</button>
                  <button v-if="u.ativo && u.email" type="button" class="text-[0.78rem] font-semibold text-primary-700 hover:underline" @click="enviarAcesso(u)">
                    {{ u.convite_pendente ? 'Reenviar convite' : 'Enviar link de nova senha' }}
                  </button>
                  <button
                    v-if="u.id !== perfil?.id"
                    type="button"
                    class="text-[0.78rem] font-semibold hover:underline"
                    :class="u.ativo ? 'text-danger' : 'text-primary-700'"
                    @click="alternarAtivo(u)"
                  >
                    {{ u.ativo ? 'Desativar' : 'Reativar' }}
                  </button>
                </span>
              </td>
            </tr>
            <tr v-if="editando === u.id">
              <td colspan="5" class="bg-neutral-25">
                <form class="flex flex-wrap items-end gap-3 py-1" @submit.prevent="salvarEdicao(u)">
                  <CampoForm rotulo="Nome" obrigatorio class="w-[240px]">
                    <input v-model="edicao.nome" class="campo" autocomplete="off">
                  </CampoForm>
                  <CampoForm rotulo="Perfil" obrigatorio>
                    <select v-model="edicao.perfil" class="campo" :disabled="u.id === perfil?.id" :title="u.id === perfil?.id ? 'Outro administrador muda o seu perfil' : undefined">
                      <option v-for="p in PERFIS" :key="p.valor" :value="p.valor">{{ p.nome }}</option>
                    </select>
                  </CampoForm>
                  <CampoForm v-if="edicao.perfil === 'diretor'" rotulo="Diretoria" obrigatorio class="min-w-[260px] flex-1">
                    <select v-model="edicao.diretoria_id" class="campo">
                      <option :value="null" disabled>Escolha</option>
                      <option v-for="d in listas?.diretorias" :key="d.id" :value="d.id">{{ nomeExibicao(d.nome) }}</option>
                    </select>
                  </CampoForm>
                  <button type="button" class="btn btn-fantasma" @click="editando = null">Cancelar</button>
                  <button class="btn btn-primario" :disabled="salvando">Salvar</button>
                </form>
              </td>
            </tr>
          </template>
          <tr v-if="!usuarios?.length">
            <td colspan="5" class="text-neutral-500">Nenhum usuário.</td>
          </tr>
        </tbody>
      </table>
      <div class="flex justify-between border-t border-neutral-100 px-3.5 py-2.5 text-[0.76rem] text-neutral-500">
        <span>{{ usuarios?.length ?? 0 }} usuários, {{ ativos }} ativos</span>
        <span>Desativado não entra no sistema; o histórico continua.</span>
      </div>
    </section>
    <template #fallback><p class="cartao px-4 py-6 text-[0.84rem] text-neutral-500">Carregando…</p></template>
    </ClientOnly>
  </template>
</template>
