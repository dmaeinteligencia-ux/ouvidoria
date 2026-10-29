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
| `..._importacao_historico.sql` | Fase 5: área de carga `importacao_linhas` e `importacao_processar` (confere sem gravar ou importa) para as planilhas antigas; ver “Importação do histórico” |
| `..._importacao_pela_tela.sql` | Importação pela tela do administrador: conferência e importação em blocos, equivalências de valores fora do cadastro e regras dos formatos antigos (2024 a 2026) |
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

O administrador gerencia os acessos em **Administração › Usuários**: cadastra (nome, e-mail, perfil e, para avaliador, a diretoria; no banco o perfil se chama `diretor`), edita, desativa e gera de novo o link de convite ou de nova senha. O sistema não envia e-mail: gera o link (`auth.admin.generateLink`) e o administrador o repassa por e-mail institucional, Teams ou WhatsApp. O link abre `/confirmar` com o código de uso único, que só é gasto quando a pessoa clica em **Continuar** (a prévia de link do WhatsApp e do Teams abre o endereço antes e gastaria um link do `/verify` do Supabase). Depois a pessoa escolhe a própria senha antes de usar o sistema. Quem é desativado não entra mais e perde o acesso aos dados; o histórico continua.

Configuração necessária:

- **Vercel › Settings › Environment Variables:** `NUXT_SUPABASE_SECRET_KEY` com a chave secreta do projeto (Supabase › Project Settings › API Keys › Secret keys). Ela fica só no servidor (rotas `server/api/usuarios`).
- **Supabase › Authentication › URL Configuration:** Site URL com o endereço do sistema e, em Redirect URLs, `https://<endereço>/**`.
- Opcional: **Supabase › Authentication › Providers › Email › Email OTP Expiration** até 86400 (24 horas) para o link durar mais que 1 hora.

### Primeiro administrador

Depois de criar o usuário em Authentication > Users, rode no SQL Editor:

```sql
insert into public.usuarios (id, nome, perfil)
select id, 'Nome do administrador', 'administrador' from auth.users where email = 'email@dmae.mg.gov.br';
```

## Importação do histórico

As planilhas mensais antigas entram pela tela **Administração › Importar planilha** (só o administrador), sem passar pela equipe técnica:

1. O administrador escolhe os arquivos .xlsx (sem senha). O navegador lê todas as abas e acha as colunas pelo nome do cabeçalho, em qualquer um dos formatos usados desde 2024 (`app/utils/importacao.ts`). Nada sai do computador antes da confirmação.
2. **Enviar e conferir** grava uma linha por manifestação em `importacao_linhas` e confere em blocos (`importacao_conferir`), desfazendo tudo: cada linha guarda os `erros` (impedem a importação) e `avisos` (bairro novo, avaliador antigo cadastrado como inativo, sem resolutividade).
3. Valores fora do cadastro ("Esgoto", "PMU", "TAXA DE LIXO") aparecem agrupados; a equivalência escolhida (`importacao_equivaler`, tabela `importacao_equivalencias`) vale para todas as linhas e para os próximos envios. "Cadastrar como novo" cria o item inativo.
4. **Importar** grava as linhas sem erro (`importacao_importar`). As com erro ficam no envio: corrigidas na planilha, basta enviar o arquivo de novo; as já importadas são reconhecidas pelo protocolo.

Regras dos formatos antigos: "SOLUCIONADO" é Respondida; sem DATA DA RESPOSTA (janeiro e março de 2024), vale o recebimento mais os dias úteis da coluna TEMPO; sem a coluna Identificação (até março de 2025) a manifestação entra como "NÃO INFORMADA"; sem resolutividade, fica fora do índice de resolutividade; a coluna ASSUNTO das planilhas até março de 2025 é a descrição (SINTOMA é o assunto); ENDEREÇO vai para o logradouro; o RESUMO vai para as observações; "ENCAMINHADO PARA LUCAS" vale o único avaliador da diretoria cujo nome começa por Lucas; DATA DA REABERTURA quer dizer reabertura aceita nesse dia, com ASSUNTO, DATA DA RESPOSTA e SEGUNDA RESPOSTA seguintes como pedido e resposta da reabertura.

Regras da carga: a numeração interna segue a ordem de recebimento; a origem fica em `manifestacoes.importada_de`; “Aguardando complementação” é registrada à mão; a prorrogação vale quando a situação é Prorrogada ou a resposta saiu depois dos 5 dias úteis com o prazo prorrogado preenchido. Depois da carga, a rotina `atualizar_situacoes` marca como Vencida o que estiver em aberto fora do prazo.
