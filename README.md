# Ouvidoria DMAE

Controle interno das manifestações da Ouvidoria do DMAE (Uberlândia), em substituição à planilha
"Controle de Manifestações". As regras de negócio (RN01 a RN24) estão no documento
"Sistema da Ouvidoria DMAE: plano e regras de negócio".

Stack: Nuxt 4.5.2, Vue 3.5, TypeScript, Tailwind CSS 3.4, Supabase (Postgres, Auth, RLS), Vercel.

## Rodar localmente

```bash
cp .env.example .env   # preencha SUPABASE_URL e SUPABASE_KEY (chave anon)
npm install
npm run dev
```

## Banco de dados

As migrações ficam em `supabase/migrations` e são aplicadas em ordem:

| Arquivo | Conteúdo |
| --- | --- |
| `..._esquema.sql` | Tabelas: cadastros, usuários, manifestações, ciclos, complementações, encaminhamentos, reaberturas, histórico |
| `..._prazos.sql` | Dias úteis, dia 0 com corte às 17h, prazos de 5 e 10 dias úteis, visão `ciclos_prazos` |
| `..._gatilhos.sql` | Número anual, ciclo original, avaliador × diretoria, histórico |
| `..._acesso.sql` | Perfis e políticas RLS |
| `..._cadastros_iniciais.sql` | Listas da aba CAMPOS e feriados de 2023 a 2027 |
| `..._permissoes_funcoes.sql` | Restringe a execução das funções `security definer` |
| `..._painel_acompanhamento.sql` | Visão `painel_manifestacoes` (ciclo atual, prazo e dias úteis restantes) |
| `..._nucleo_manifestacoes.sql` | Ações `registrar_resposta` e `arquivar_manifestacao`, trava de situação (RN24), correção do dia 0, aviso de duplicidade e histórico legível |
| `..._ciclos.sql` | Prorrogação (RN08), complementação com suspensão e arquivamento automático (RN10, RN11), reabertura em 30 dias (RN20 a RN22) e rotina horária `atualizar_situacoes` no pg_cron que marca Vencida (RN13) |
| `..._indicadores.sql` | Painel Geral (`painel_geral`, público, só números agregados), Painel Gerencial (`painel_gerencial`: Ouvidoria vê tudo, diretor só a própria diretoria) e `extrato_mensal` nas 35 colunas da planilha |
| `..._posicao_bairros.sql` | Latitude e longitude de cada bairro (marcadas pelo administrador em Cadastros › Bairros) para o mapa de bolhas do Painel Gerencial; o mapa usa o OpenStreetMap, sem chave |
| `..._complementacao_avaliadores.sql` | Texto do pedido de complementação; encaminhamento a um ou mais avaliadores, inclusive de diretorias diferentes (`encaminhar`), com a manifestação contando uma vez em cada diretoria envolvida |

Depois de uma migração, atualize `app/types/database.types.ts` (tipos gerados pelo Supabase).

Aplicar no Supabase: `supabase link --project-ref <ref>` e `supabase db push`
(ou colar os arquivos, em ordem, no SQL Editor).

### Testes das regras

```bash
DATABASE_URL=postgres://usuario@localhost/banco_de_teste npm run test:db
```

O script apaga e recria o schema `public` do banco informado antes de cada arquivo de teste; use um banco descartável.

### Usuários e convites

O administrador gerencia os acessos em **Administração › Usuários**: cadastra (nome, e-mail, perfil e, para diretor, a diretoria), edita, desativa e reenvia o convite ou o link de nova senha. O convite chega por e-mail; no link a pessoa escolhe a própria senha antes de usar o sistema. Quem é desativado não entra mais e perde o acesso aos dados; o histórico continua.

Configuração necessária:

- **Vercel › Settings › Environment Variables:** `NUXT_SUPABASE_SECRET_KEY` com a chave secreta do projeto (Supabase › Project Settings › API Keys › Secret keys). Ela fica só no servidor (rotas `server/api/usuarios`).
- **Supabase › Authentication › Emails › SMTP Settings:** servidor de e-mail do DMAE. Sem SMTP próprio, o Supabase só entrega para os e-mails da equipe do projeto e poucos por hora.
- **Supabase › Authentication › URL Configuration:** Site URL com o endereço do sistema e, em Redirect URLs, `https://<endereço>/**`.

### Primeiro administrador

Depois de criar o usuário em Authentication > Users, rode no SQL Editor:

```sql
insert into public.usuarios (id, nome, perfil)
select id, 'Nome do administrador', 'administrador' from auth.users where email = 'email@dmae.mg.gov.br';
```
