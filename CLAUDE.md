# CLAUDE.md — instruções para agentes trabalhando neste repo

## Leia primeiro

1. `docs/SPEC.md`: produto, fases e regras de produto R1–R8. **Toda feature deve respeitar R1–R8.**
2. `docs/adr/`: decisões técnicas. Não contradiga um ADR aceito sem propor um novo ADR.
3. `docs/BACKLOG.md`: ideias futuras. Não implemente nada daqui sem pedido explícito.

## Estrutura

```
backend/   API Rust (Axum + sqlx + Postgres)
app/       App Flutter (Android primeiro)
docs/      Spec, ADRs, backlog
```

## Backend

- Rodar localmente: `docker compose up -d db`, depois, em `backend/`, `cp .env.example .env && cargo run`.
- Banco de teste: os testes usam `#[sqlx::test]`, que cria um banco temporário por teste. Precisa de `DATABASE_URL` apontando para um Postgres com permissão de criar bancos.
- **Mudou alguma query `sqlx::query!`?** Rode `cargo sqlx prepare` em `backend/` e faça commit de `.sqlx/`.
- **Nova migração:** `sqlx migrate add -r <nome>`. Nunca edite uma migração já commitada.
- Antes de commitar: `cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test`.

### Convenções

- Erros: use `AppError` (`src/error.rs`). Nunca devolva mensagens internas nem de banco ao cliente.
- **Nunca** logue senha, token, código de convite, e-mail completo ou conteúdo de post.
- Toda rota nova autenticada usa o extractor `AuthUser`.
- Toda entrada do cliente é validada no handler antes de tocar o banco.
- IDs são UUID v7, gerados na aplicação.
- Rotas da API ficam sob `/v1`.

## App

- `cd app && flutter pub get && flutter run`.
- Emulador Android acessa o host em `http://10.0.2.2:8080`. Configure com `--dart-define=API_BASE_URL=...`.
- Antes de commitar: `dart format . && flutter analyze && flutter test`.
- A camada HTTP fica em `lib/src/api/`. Widgets nunca chamam `http` diretamente.

## Fluxo de trabalho

- Uma feature por branch e por PR. O PR referencia a seção da SPEC que implementa.
- Testes acompanham cada endpoint novo: caso feliz, entrada inválida e autorização.
- Commits curtos, no imperativo, em português ou inglês (consistente dentro do PR).
