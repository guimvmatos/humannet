# ADR-0005: Autenticação com Argon2id e sessões opacas

- **Status:** aceito
- **Data:** 2026-10-03

## Decisão

- **Hash de senha:** Argon2id com os parâmetros mínimos da OWASP (m = 19 MiB, t = 2, p = 1). O salt é aleatório e o resultado fica no formato PHC.
- **Sessão:** token opaco de 32 bytes aleatórios (CSPRNG), enviado em base64url como `Authorization: Bearer <token>`.
  - O banco guarda **só o SHA-256** do token. Quem vazar o banco não consegue se passar por um usuário.
  - Expira em 30 dias. O logout apaga a sessão.
- **Login:** se o usuário não existe, o servidor verifica a senha contra um hash fictício, para que o tempo de resposta não revele se a conta existe. A mensagem de erro é genérica.
- **Convites:** o código é aleatório (128 bits) e o banco guarda só o SHA-256.
- **Limite de tentativas** nas rotas de autenticação: por IP no proxy reverso já na Fase 0, e na aplicação na Fase 1.

## Por que não JWT

O JWT dispensa consultar o banco a cada requisição, mas isso não ajuda aqui: a API já consulta o banco em toda requisição autenticada. Com JWT, revogar uma sessão (logout, conta comprometida, banimento) exigiria uma lista de revogação, o que traz de volta o estado no servidor. Um token opaco é mais simples e revoga na hora.

## Consequências

- Uma consulta por requisição autenticada para validar o token. É barata com índice único em `token_hash`.
- Falta implementar: troca de senha (que invalida as outras sessões), recuperação por e-mail e listagem de sessões ativas.
