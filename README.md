# HumanNet

Uma rede social ética, humana e autêntica, feita a partir do Brasil.

> Sem algoritmos ocultos. Sem bots. Sem métricas de vaidade. Uma pessoa, uma conta.

**Status:** Fase 1 em andamento. Já funcionam convites, login, perfis, amizade mútua, posts de texto, feed cronológico, comentários, curtidas, bloqueio, denúncia, troca de senha e exclusão de conta.

## Documentação

| Documento | Conteúdo |
|---|---|
| [`docs/SPEC.md`](docs/SPEC.md) | Visão, regras de produto (R1–R8), fases, requisitos, modelo de dados |
| [`docs/adr/`](docs/adr/) | Decisões técnicas (stack, identidade, privacidade, autenticação) |
| [`docs/BACKLOG.md`](docs/BACKLOG.md) | Ideias futuras com fase, dependências e riscos |
| [`docs/SETUP-BETA.md`](docs/SETUP-BETA.md) | Passo a passo: Neon, Render, assinatura, Google Play, convites |
| [`docs/PRIVACIDADE.md`](docs/PRIVACIDADE.md) | Política de privacidade do beta |
| [`docs/REGRAS.md`](docs/REGRAS.md) | Regras de convivência (as mesmas do app) |
| [`CLAUDE.md`](CLAUDE.md) | Convenções do repo (para pessoas e agentes de IA) |

## Estrutura

```
backend/   API em Rust (Axum + sqlx + PostgreSQL)
app/       App em Flutter (Android primeiro)
docs/      Especificação e ADRs
```

## Rodando localmente

**Pré-requisitos:** Docker, Rust stable, Flutter stable, `sqlx-cli` (`cargo install sqlx-cli --no-default-features --features rustls,postgres`).

```bash
# 1. Banco
docker compose up -d db

# 2. API
cd backend
cp .env.example .env
cargo run                     # aplica migrações e sobe em :8080
cargo run -- invite           # gera o primeiro convite (copie o código)

# 3. App (em outro terminal, com o emulador Android aberto)
cd app
./tool/setup_android.sh       # só na primeira vez; depois faça commit de android/
flutter run
```

No app, toque em **"Tenho um convite"** e use o código gerado no passo 2.

## Testar só com o celular (sem PC)

1. **API:** no [Render](https://render.com), entre com o GitHub, escolha **New → Blueprint** e selecione este repo. O `render.yaml` cria a API e o Postgres nos planos gratuitos. O Render pede um valor para `BOOTSTRAP_INVITE_CODE`: invente um código com 16 caracteres ou mais. Ele vira o convite do primeiro usuário.
2. **APK apontando para a API:** defina a variável de repositório `API_BASE_URL` com a URL do Render (ex.: `https://humannet-api.onrender.com`) e rode o workflow **app** em Actions.
3. **Instalar:** baixe `humannet-dev.apk` na release [dev-latest](../../releases/tag/dev-latest).

No plano gratuito, a API dorme quando não é usada. A primeira requisição depois disso pode levar cerca de 1 minuto.

## Testes

```bash
cd backend && cargo test      # precisa do Postgres (docker compose up -d db)
cd app && flutter test
```

## API (v1)

| Método | Rota | Auth | Descrição |
|---|---|---|---|
| GET | `/health` | — | Liveness + banco |
| POST | `/v1/auth/register` | — | `{invite_code, username, email, password, cpf}` (CPF obrigatório se o servidor tem `CPF_HMAC_KEY`) → `{token, expires_at, user}` |
| POST | `/v1/auth/login` | — | `{login, password}` (login = usuário ou e-mail) |
| POST | `/v1/auth/logout` | Bearer | Revoga a sessão atual |
| POST | `/v1/auth/reset-password` | — | `{username, code, new_password}`: código gerado por um admin (24 h, uso único, 5 tentativas) |
| GET | `/v1/me` | Bearer | Dados do próprio usuário |
| DELETE | `/v1/me` | Bearer | `{password}`: **exclui a conta** de forma definitiva |
| GET | `/v1/me/counts` | Bearer | Bolinhas: `friend_requests`, `pending_testimonials`, `community_requests` (comunidades que modero), `unread_activity` |
| GET | `/v1/me/activity` | Bearer | Novidades (30 dias, até 50): comentários nos meus posts e respostas em tópicos em que participo. Sem curtidas (R3/R6) |
| POST | `/v1/me/activity/seen` | Bearer | Marca as novidades como vistas |
| PUT | `/v1/me/cpf` | Bearer | `{cpf}`: contas antigas informam uma vez (`needs_cpf` em `/v1/me`). Uma conta por CPF; o servidor guarda só HMAC-SHA256 com `CPF_HMAC_KEY` |
| PUT | `/v1/me/password` | Bearer | `{current_password, new_password}`: encerra as outras sessões |
| POST | `/v1/invites` | Bearer | Gera um convite (até 5 ativos) |
| PATCH | `/v1/me/profile` | Bearer | `{display_name?, bio?, hometown?, city?, school?}` (`""` remove; cidade/escola até 80) |
| PUT | `/v1/me/status` | Bearer | Status/subnick `{text, hours: 24\|72\|168\|0}` (até 80; `""` apaga; 0 = sem validade). Só amigos veem (perfil e lista de amigos) |
| GET / POST | `/v1/users/{username}/scraps` | Bearer | Recados (mais novos primeiro) / deixar recado `{body}` (1–1000). Só amigos escrevem e leem |
| DELETE | `/v1/scraps/{id}` | Bearer | Apagar recado (dono do perfil ou autor) |
| GET | `/v1/me/suggestions` | Bearer | Pessoas que você talvez conheça, cada uma com `reasons` (amigos em comum, mesma escola, cidade natal ou cidade atual). Sem contatos nem localização |
| POST | `/v1/me/suggestions/{username}/dismiss` | Bearer | Não sugerir mais essa pessoa |
| GET | `/v1/users/{username}` | Bearer | Perfil + `relation` (`self`, `none`, `friends`, `request_sent`, `request_received`); `stats` só no próprio perfil (R3) |
| PUT | `/v1/users/{username}/friend` | Bearer | Pede amizade, ou aceita se a pessoa já pediu → `{relation}` |
| DELETE | `/v1/users/{username}/friend` | Bearer | Desfaz amizade, cancela ou recusa o pedido (idempotente) |
| GET | `/v1/friend-requests` | Bearer | Pedidos recebidos |
| GET | `/v1/friends` | Bearer | Meus amigos |
| PUT / DELETE | `/v1/users/{username}/block` | Bearer | Bloquear / desbloquear (bloqueio invisível: 404 nos dois sentidos) |
| GET | `/v1/blocks` | Bearer | Quem eu bloqueei |
| POST | `/v1/reports` | Bearer | `{kind, <alvo>, reason, details?}` → 202. Alvos: `post` + `post_id`, `user` + `username`, `comment` + `comment_id`, `topic` + `topic_id`, `reply` + `reply_id`, `community` + `slug`, `testimonial` + `testimonial_id`, `scrap` + `scrap_id`, `page` + `slug`, `event` + `event_id` |
| GET | `/v1/users/{username}/posts` | Bearer | Posts do usuário (só para o próprio e amigos; senão 403) |
| POST | `/v1/media?kind=post\|avatar\|daily` | Bearer | Corpo = bytes da imagem (JPEG/PNG/WebP, até 10 MB). O servidor recodifica em JPEG **sem metadados** (tira GPS), reduz (1600 px; avatar 512×512) e devolve `{id, url, width, height}`. Fotos não usadas em 24 h são apagadas |
| POST | `/v1/posts` | Bearer | `{body, media_ids?}`: texto (até 5000) e/ou até 4 fotos (`kind=post`). Posts trazem `images` |
| PUT / DELETE | `/v1/me/avatar` | Bearer | `{media_id}` (`kind=avatar`) / remover. Perfil traz `avatar_url` |
| PUT / DELETE | `/v1/me/daily-photo` | Bearer | Foto do dia `{media_id, caption?}` (`kind=daily`, legenda até 200) / apagar a de hoje. Perfil traz `daily_photo` (a mais recente, até 7 dias; só amigos) |
| GET / DELETE | `/v1/posts/{id}` | Bearer | Ler (autor e amigos; senão 404) / apagar (só o autor; o texto é removido do banco) |
| PUT / DELETE | `/v1/posts/{id}/like` | Bearer | Curtir / descurtir. `like_count` só vem para o autor (R3) |
| GET / POST | `/v1/posts/{id}/comments` | Bearer | Listar (mais antigo primeiro) / comentar `{body}` (1–2000) |
| DELETE | `/v1/comments/{id}` | Bearer | Apagar comentário (autor do comentário ou do post) |
| GET | `/v1/feed` | Bearer | Cronológico: amigos + você |

**Depoimentos** (SPEC 4.2): só amigos escrevem; o dono do perfil aprova antes de aparecer. Quem vê: o dono, os amigos dele e o autor.

| Método | Rota | Descrição |
|---|---|---|
| GET | `/v1/users/{username}/testimonials` | Aprovados (+ o meu, mesmo pendente) |
| PUT | `/v1/users/{username}/testimonial` | `{body}` (1–1000): escreve ou reescreve o meu (volta a pendente) |
| GET | `/v1/me/testimonials/pending` | Esperando minha aprovação (contagem em `stats.pending_testimonials`) |
| POST | `/v1/testimonials/{id}/approve` | Aprovar (dono do perfil) |
| DELETE | `/v1/testimonials/{id}` | Recusar/remover (dono do perfil) ou apagar (autor) |

**Lugares e eventos** (lote 12). Página de lugar com CNPJ (uma por CNPJ); quem administra cria eventos; as pessoas marcam "tenho interesse" ou "vou" (sem ingresso). Números totais só para quem administra (R3); os outros veem quais amigos vão.

| Método | Rota | Descrição |
|---|---|---|
| GET / POST | `/v1/pages?q=&mine=true` | Buscar / criar `{name, category, cnpj, cep?, address?, city?, description?}` (até 3 por pessoa) |
| GET / PATCH / DELETE | `/v1/pages/{slug}` | Ver / editar (administradores) / apagar (dono) |
| PUT / DELETE | `/v1/pages/{slug}/follow` | Acompanhar (única relação unilateral, ADR-0006) |
| GET / POST / DELETE | `/v1/pages/{slug}/admins[/{username}]` | Quem administra (público) / dono adiciona e remove |
| PUT / DELETE | `/v1/pages/{slug}/logo` · `/v1/pages/{slug}/cover` | `{media_id}`: logo (foto kind=avatar) e capa 3:1 (kind=cover) |
| GET | `/v1/events/map?south=&west=&north=&east=&days=` | Eventos na área do mapa (até ~5°), próximos 1–60 dias (padrão 14). Só a área vai ao servidor, nunca a posição de quem usa |
| GET / POST | `/v1/pages/{slug}/posts` | Mural da página (todos veem) / quem administra publica; vai para o feed de quem acompanha |
| POST | `/v1/pages/{slug}/conversation` | Abre a conversa com a página (só quem acompanha); quem administra responde como a página |
| GET / POST | `/v1/pages/{slug}/events?past=` | Eventos da página / criar `{title, starts_at, ends_at?, location?, description?}` |
| GET | `/v1/events` | Agenda: próximos eventos dos lugares que acompanho e dos que marquei |
| GET / PATCH / DELETE | `/v1/events/{id}` | Ver / editar ou `{cancelled}` / apagar |
| PUT / DELETE | `/v1/events/{id}/interest` | `{status: interested\|going}` / tirar |
| POST | `/v1/admin/pages/{slug}/verify` | Administração marca a página como verificada |

**Comunidades** (SPEC 4.5). Pública: qualquer pessoa lê e entra. Fechada: só membros leem; entrar exige aprovação. Administradores moderam qualquer comunidade.

| Método | Rota | Descrição |
|---|---|---|
| GET | `/v1/communities?q=&theme=&mine=true` | Busca (nome/endereço) ou só as minhas; ordem alfabética, até 100 |
| POST | `/v1/communities` | `{name, theme, visibility: public\|closed, description?, rules?, slug?}`: quem cria vira dono (até 10) |
| GET / PATCH / DELETE | `/v1/communities/{slug}` | Ver (com `my_role`, `my_status`, `can_*`; contagens só para quem modera) / editar e apagar (dono) |
| PUT / DELETE | `/v1/communities/{slug}/membership` | Entrar (ou pedir, se fechada) / sair ou cancelar pedido. O dono não sai |
| GET | `/v1/communities/{slug}/members?status=active\|pending\|banned` | Membros (membros veem ativos; pedidos e banidos, só quem modera) |
| POST | `/v1/communities/{slug}/members/{username}` | `{action}`: `approve`, `reject`, `ban`, `unban` (moderação); `promote`, `demote` (dono); `transfer` (só o dono) |
| GET / POST | `/v1/communities/{slug}/topics` | Tópicos: fixados primeiro, depois pela última resposta / criar `{title, body?}` (membros) |
| GET / PATCH / DELETE | `/v1/topics/{id}` | Ver / `{pinned?, locked?}` (moderação) / apagar (autor ou moderação) |
| GET / POST | `/v1/topics/{id}/replies?after=` | Respostas (mais antiga primeiro) / responder `{body}`; tópico trancado só aceita da moderação |
| DELETE | `/v1/replies/{id}` | Apagar resposta (autor ou moderação) |

**Mensagens diretas**: conversa 1:1 só entre amigos (e sem bloqueio); grupos de até 50 amigos de quem cria. Atualização por consulta (`after=`), sem push por enquanto.

| Método | Rota | Descrição |
|---|---|---|
| GET / POST | `/v1/conversations` | Minhas conversas (mais recente primeiro, com `unread`) / criar grupo `{title, usernames}` |
| POST | `/v1/conversations/direct` | `{username}`: abre ou cria a conversa 1:1 com um amigo |
| GET | `/v1/conversations/{id}` | Ver conversa (só membros) |
| GET / POST | `/v1/conversations/{id}/messages?before=&after=` | Mensagens em ordem cronológica / enviar `{body}` (até 30 por minuto) |
| POST | `/v1/conversations/{id}/read` | Marca como lida |
| GET / POST | `/v1/conversations/{id}/members` | Membros / adicionar amigos `{usernames}` (grupo) |
| DELETE | `/v1/conversations/{id}/members/me` | Sair do grupo |
| DELETE | `/v1/messages/{id}` | Apagar mensagem própria |

**Notificações push** (Firebase Cloud Messaging): pedido e aceite de amizade, depoimento, recado, comentário no seu post e mensagem. O aviso diz quem fez e o quê, nunca o conteúdo. Respeita bloqueio.

| Método | Rota | Descrição |
|---|---|---|
| PUT | `/v1/me/devices` | `{token}`: este aparelho recebe os avisos desta conta (até 10 aparelhos) |
| DELETE | `/v1/me/devices/{token}` | Ao sair da conta |

**Administração** (papel `admin`, definido pela variável `ADMIN_USERNAMES` no servidor):

| Método | Rota | Descrição |
|---|---|---|
| GET | `/v1/admin/reports?status=open` | Fila de denúncias (com cópia do conteúdo) |
| POST | `/v1/admin/reports/{id}/resolve` | `{action: dismiss \| remove_content \| suspend_user}`: fecha todas as denúncias do mesmo alvo e registra a ação |
| POST | `/v1/admin/users/{username}/release-cpf` | Tira o CPF de uma conta (ex.: usado por outra pessoa) |
| POST | `/v1/admin/users/{username}/unsuspend` | Reativa uma conta suspensa |
| POST | `/v1/admin/users/{username}/password-reset` | Gera o código de redefinição de senha |

Paginação: `?limit=1..50&before=<id>`. A resposta é `{items, next_cursor}`, e `next_cursor: null` marca o fim da lista (sem rolagem infinita, R6).

Os erros têm o formato `{"error": "<codigo>"}`. Os códigos estão em `backend/src/error.rs` e `app/lib/src/ui/error_messages.dart`.

## Licença

Todos os direitos reservados (provisório).
