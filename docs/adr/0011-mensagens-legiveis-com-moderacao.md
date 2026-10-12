# ADR-0011: Mensagens sem criptografia de ponta a ponta, com moderação

- **Status:** aceito
- **Data:** 2026-10-11

## Contexto

O backlog deixava em aberto se as mensagens diretas teriam criptografia de ponta a ponta (MLS ou Signal) ou ficariam legíveis no servidor. Com ponta a ponta, a moderação não consegue verificar uma denúncia sem que quem denuncia envie o conteúdo pelo aparelho.

## Decisão

- Mensagens ficam **legíveis no servidor** (cifradas em trânsito por TLS e em repouso pelo provedor do banco), para que a moderação possa agir sobre denúncias.
- Só moderação acessa conteúdo, e só a partir de denúncia. Nada de leitura para anúncios ou métricas (ADR-0010).
- A Política de Privacidade já diz isso de forma explícita.

## Consequências

- Mais simples de implementar e permite moderar assédio e golpes.
- Um vazamento do banco expõe as mensagens. Mitigação: acesso ao banco restrito e auditado.
- Pode ser revisto no futuro (ex.: ponta a ponta opcional para conversas 1:1), com novo ADR e aviso na Política.
