# ADR-0001: Backend em Rust (Axum) + PostgreSQL

- **Status:** aceito
- **Data:** 2026-10-03

## Contexto

Os requisitos colocam segurança e desempenho como prioridade. O backend precisa ser barato de operar no beta (uma VM pequena) e escalar sem reescrita. O fundador já domina Rust.

## Decisão

- **Linguagem:** Rust (stable).
- **HTTP:** Axum, que roda sobre Tokio e tower. Middlewares do `tower-http` cuidam de trace, limite de corpo e timeout.
- **Banco:** PostgreSQL 16+.
- **Acesso a dados:** `sqlx`, com as macros `query!` checadas em tempo de compilação. O cache offline fica em `backend/.sqlx/` e é versionado.
- **Migrações:** `sqlx migrate`, em `backend/migrations/`. Só avançam, nunca editam uma migração já aplicada.
- **Arquitetura:** monólito modular. Um binário com módulos por domínio (`auth`, `posts`, `communities`, ...). Separar serviços só quando houver uma razão medida.

## Alternativas consideradas

| Opção | Por que não |
|---|---|
| Python + Django/FastAPI | Itera mais rápido em CRUD, mas dá menos garantias em tempo de compilação e consome mais recursos por requisição. |
| Node/TypeScript | Ecossistema enorme, mas a segurança de tipos acaba na fronteira com o banco, a menos que se adote um ORM pesado. |
| Supabase/Firebase (BaaS) | Tem lock-in, e as regras de autorização ficam espalhadas. A privacidade fica difícil de auditar. |
| ORM (Diesel, SeaORM) | Diesel é síncrono por padrão. O SQL explícito do sqlx é mais fácil de revisar e otimizar. |

## Consequências

- Os tipos e o SQL são checados na compilação, e não há classes inteiras de bugs de memória.
- Compilar é mais lento, e iterar CRUD custa mais do que em Python.
- Mudar o esquema exige rodar `cargo sqlx prepare` para atualizar `.sqlx/`. O CI falha se o cache estiver desatualizado.
