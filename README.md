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
| POST | `/v1/auth/register` | — | `{invite_code, username, email, password}` → `{token, expires_at, user}` |
| POST | `/v1/auth/login` | — | `{login, password}` (login = usuário ou e-mail) |
| POST | `/v1/auth/logout` | Bearer | Revoga a sessão atual |
| POST | `/v1/auth/reset-password` | — | `{username, code, new_password}`: código gerado por um admin (24 h, uso único, 5 tentativas) |
| GET | `/v1/me` | Bearer | Dados do próprio usuário |
| DELETE | `/v1/me` | Bearer | `{password}`: **exclui a conta** de forma definitiva |
| PUT | `/v1/me/password` | Bearer | `{current_password, new_password}`: encerra as outras sessões |
| POST | `/v1/invites` | Bearer | Gera um convite (até 5 ativos) |
| PATCH | `/v1/me/profile` | Bearer | `{display_name?, bio?}` (`""` em display_name remove) |
| GET | `/v1/users/{username}` | Bearer | Perfil + `relation` (`self`, `none`, `friends`, `request_sent`, `request_received`); `stats` só no próprio perfil (R3) |
| PUT | `/v1/users/{username}/friend` | Bearer | Pede amizade, ou aceita se a pessoa já pediu → `{relation}` |
| DELETE | `/v1/users/{username}/friend` | Bearer | Desfaz amizade, cancela ou recusa o pedido (idempotente) |
| GET | `/v1/friend-requests` | Bearer | Pedidos recebidos |
| GET | `/v1/friends` | Bearer | Meus amigos |
| PUT / DELETE | `/v1/users/{username}/block` | Bearer | Bloquear / desbloquear (bloqueio invisível: 404 nos dois sentidos) |
| GET | `/v1/blocks` | Bearer | Quem eu bloqueei |
| POST | `/v1/reports` | Bearer | `{kind: "post", post_id \| kind: "user", username, reason, details?}` → 202 |
| GET | `/v1/users/{username}/posts` | Bearer | Posts do usuário (só para o próprio e amigos; senão 403) |
| POST | `/v1/posts` | Bearer | `{body}` (1–5000 caracteres) |
| GET / DELETE | `/v1/posts/{id}` | Bearer | Ler (autor e amigos; senão 404) / apagar (só o autor; o texto é removido do banco) |
| PUT / DELETE | `/v1/posts/{id}/like` | Bearer | Curtir / descurtir. `like_count` só vem para o autor (R3) |
| GET / POST | `/v1/posts/{id}/comments` | Bearer | Listar (mais antigo primeiro) / comentar `{body}` (1–2000) |
| DELETE | `/v1/comments/{id}` | Bearer | Apagar comentário (autor do comentário ou do post) |
| GET | `/v1/feed` | Bearer | Cronológico: amigos + você |

**Administração** (papel `admin`, definido pela variável `ADMIN_USERNAMES` no servidor):

| Método | Rota | Descrição |
|---|---|---|
| GET | `/v1/admin/reports?status=open` | Fila de denúncias (com cópia do conteúdo) |
| POST | `/v1/admin/reports/{id}/resolve` | `{action: dismiss \| remove_post \| suspend_user}`: fecha todas as denúncias do mesmo alvo e registra a ação |
| POST | `/v1/admin/users/{username}/unsuspend` | Reativa uma conta suspensa |
| POST | `/v1/admin/users/{username}/password-reset` | Gera o código de redefinição de senha |

Paginação: `?limit=1..50&before=<id>`. A resposta é `{items, next_cursor}`, e `next_cursor: null` marca o fim da lista (sem rolagem infinita, R6).

Os erros têm o formato `{"error": "<codigo>"}`. Os códigos estão em `backend/src/error.rs` e `app/lib/src/ui/error_messages.dart`.

## Licença

Todos os direitos reservados (provisório).
