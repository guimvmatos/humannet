# ADR-0012: Plataforma fechada, sem federação

- **Status:** aceito
- **Data:** 2026-10-11

## Contexto

A SPEC (questão 2) e o backlog perguntavam se o HumanNet se conectaria a redes abertas (ActivityPub/Mastodon, AT Protocol/Bluesky). Há tensão com R1: contas de outros servidores não passam pela nossa verificação de "uma pessoa, uma conta".

## Decisão

- O HumanNet é uma **plataforma fechada**: não federa com outras redes.
- Portabilidade continua garantida pelo "Baixar meus dados" (LGPD).

## Consequências

- R1, moderação e regras de privacidade valem para todas as contas.
- Sem o alcance inicial de redes já existentes; o crescimento depende de convites e densidade local.
