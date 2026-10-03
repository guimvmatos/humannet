# HumanNet

Uma rede social ética, humana e autêntica, feita a partir do Brasil.

> Sem algoritmos ocultos. Sem bots. Sem métricas de vaidade. Uma pessoa, uma conta.

**Status:** Fase 0 (fundação). O backend tem autenticação por convite e o app Android tem login.

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
| GET | `/v1/me` | Bearer | Dados do próprio usuário |
| POST | `/v1/invites` | Bearer | Gera um convite (até 5 ativos) |

Os erros têm o formato `{"error": "<codigo>"}`. Os códigos estão em `backend/src/error.rs` e `app/lib/src/ui/error_messages.dart`.

## Licença

Todos os direitos reservados (provisório).
