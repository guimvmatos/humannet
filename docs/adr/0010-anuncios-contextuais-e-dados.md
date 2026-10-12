# ADR-0010: Anúncios contextuais e uso de dados

- **Status:** aceito
- **Data:** 2026-10-11
- **Altera:** a regra R5 da SPEC ("não usar dado pessoal para anúncios") e a frase "não vendemos dados, não mostramos anúncios" dos Termos e da Política v2.

## Contexto

O modelo de negócio (backlog, seção "Monetização") depende de anúncios de intenção: mapa patrocinado, comércio no Regional, comunidades por tema, classificados. A Política v2 prometia "não mostramos anúncios", o que impediria qualquer receita desse tipo. O Guilherme decidiu mudar o texto **antes** de faturar, para que ninguém seja surpreendido.

## Decisão

- **Não vendemos dado pessoal.** Isso não muda.
- **Anúncios são contextuais:** escolhidos pela região visível na tela (mapa, Regional) ou pelo tema da comunidade/evento. Nunca pelo histórico da pessoa, mensagens ou perfil de interesses (que continua só no aparelho, ADR-0004).
- Sempre rotulados **"Patrocinado"**, com limite por sessão, nunca nas mensagens.
- **Com anunciantes e parceiros:** só estatísticas agregadas e anonimizadas, com no mínimo 100 pessoas por recorte. Qualquer outro uso de dado pessoal exige consentimento específico por finalidade (LGPD art. 8º §4º), revogável, sem bloquear o uso do app.
- **Nunca:** CPF, localização individual, mensagens, dados sensíveis, perfil do "Para você".
- Termos e Política sobem para a **versão 3**, com novo aceite.

## Consequências

- Hoje não há anúncios; o texto só abre a possibilidade. Implementar anúncios (M5–M9) continua exigindo pedido explícito.
- A tela de consentimentos por finalidade (M3) precisa existir antes de qualquer uso de dado pessoal além de agregados.
- APKs antigos mandam a versão 2 no aceite e são recusados: quem não atualizar o app fica parado na tela de Termos.
- Revisão jurídica (M4) continua pendente antes de abrir ao público.
