# ADR-0004: Perfil de interesses calculado no aparelho

- **Status:** proposto (implementação na Fase 1)
- **Data:** 2026-10-03

## Contexto

O modo de feed "por interesses" infere gostos a partir das interações. Inferências como "interesse em política" se aproximam de **opinião política**, que é dado sensível pela LGPD. O manifesto também promete não explorar dados.

## Decisão

- O **perfil de interesses** (tema → peso) é calculado e guardado **somente no aparelho**.
- O servidor entrega posts candidatos com suas tags de tema, e o app os ordena localmente.
- O perfil é alimentado só por ações explícitas: curtir, comentar, entrar numa comunidade. **Tempo de tela não entra.**
- A **blacklist de temas** é uma preferência explícita do usuário, não uma inferência. Ela é guardada no servidor, onde é aplicada para que o conteúdo bloqueado nem chegue ao aparelho.
- Opcional, mais tarde: backup do perfil cifrado de ponta a ponta, para quem troca de aparelho.

## Consequências

- O servidor nunca conhece o perfil inferido. Não há o que vazar nem o que vender.
- Trocar de aparelho zera o perfil, a menos que exista o backup.
- O ranking fica limitado ao conjunto de candidatos enviado. Fica mais difícil ter descoberta ampla fora dos temas conhecidos, o que é aceitável e até desejável (contra bolhas).
