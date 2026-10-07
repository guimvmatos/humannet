# ADR-0006: Amizade mútua no lugar de "seguir"

- **Status:** aceito (implementação substitui o "seguir" da Fase 1a)
- **Data:** 2026-10-07
- **Origem:** decisão de produto do fundador

## Contexto

A Fase 1a implementou "seguir", que é unilateral, no modelo do Instagram e do X. Esse modelo cria audiência e assimetria de status (quem tem mais seguidores). É a lógica de "performance e vaidade" que o manifesto rejeita.

## Decisão

Entre **pessoas**, a única relação é a **amizade mútua**:

1. A pede amizade a B. O pedido fica **pendente**.
2. B **aceita**, e os dois viram amigos, ou **recusa**, e o pedido é apagado.
3. Qualquer um dos dois pode **desfazer** a amizade a qualquer momento. Ela acaba para os dois, sem aviso.
4. **Pedidos simultâneos** (A pede a B enquanto B pede a A) viram amizade na hora.
5. Não existe estado intermediário. "Seguir" é removido.

### Consequências no produto

| Área | Regra |
|---|---|
| **Feed cronológico** | Posts de amigos + os meus |
| **Perfil de não-amigo** | Mostra nome, @ e bio, para dar contexto ao pedido. **Posts só para amigos.** |
| **Contagem de amigos** | Privada (R3) |
| **Recusa** | O app não envia aviso. O pedido some, e quem pediu volta a ver "Adicionar". |
| **Bloqueio** (Fase 1b) | Desfaz a amizade e apaga pedidos nos dois sentidos |
| **Anti-spam** | Limite de pedidos pendentes enviados (ex.: 50) |

### Modelo de dados

```
friend_requests(from_id, to_id, created_at)   PK (from_id, to_id)
friendships(user_a, user_b, created_at)       PK (user_a, user_b), CHECK user_a < user_b
```

A amizade é guardada **uma vez**, com o par ordenado (`user_a < user_b`). Não pode haver uma linha "meia-amizade" em uma só direção. Aceitar um pedido é uma transação: apaga o pedido e insere a amizade.

## Questões em aberto

1. **Contas de organização (Fase 2: pub, empresa).** Organização não é pessoa. Proposta: a pessoa **acompanha** a organização (unilateral, como uma inscrição), e a organização não vê quem a acompanha individualmente. Precisa de confirmação.
2. **Comunidades** continuam baseadas em "entrar", não em amizade.

## Verificação formal (candidato a TLA+)

A máquina de estados pedido/aceite/recusa/cancelamento/desfazer/bloqueio, com pedidos concorrentes, é pequena e tem invariantes claras:

- amizade é sempre simétrica;
- nunca existe um pedido pendente entre amigos;
- depois de um bloqueio, não existe amizade nem pedido entre o par.
