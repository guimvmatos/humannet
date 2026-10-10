# ADR-0007: Quatro modos de feed, algoritmo controlável e feed regional

- **Status:** aceito (implementação nos lotes 19 e 20)
- **Data:** 2026-10-10
- **Complementa:** [ADR-0004](0004-privacidade-perfil-de-interesses.md) (perfil de interesses no aparelho) e a regra R2 da SPEC.

## Contexto

O Guilherme quer quatro modos de feed: **A** cronológico, **B** algoritmizado, **C1** regional cronológico e **C2** regional algoritmizado. Ele quer também controle total sobre o algoritmo, inclusive no nível de assunto político, e um raio em km no regional.

## Decisão

1. **Modos.** A (padrão), B, C1 e C2, escolhidos pela pessoa e trocáveis a qualquer momento. O fim do feed continua explícito (R6).
2. **Algoritmo transparente (R2).**
   - Cada post do modo B ou C2 mostra "por que estou vendo isto".
   - A pessoa vê, edita, apaga e pausa os interesses.
   - O algoritmo **nunca** otimiza tempo de tela: só interesses, amizade e recência.
3. **Temas.** Os posts têm temas de uma lista fixa, com subtemas: Política, Futebol, Música, Trânsito, Clima/alertas e outros. O autor marca até 3 temas ao postar. Um classificador automático vem depois (SPEC 4.4, Fase 4).
4. **Política em nível fino (decisão do Guilherme).**
   - O app pode inferir a inclinação dentro de Política (espectro, figuras), **apenas com opt-in destacado** (LGPD art. 11: opinião política é dado sensível, art. 5º, II).
   - Vem desligado por padrão, com explicação clara, e é editável e apagável.
   - Pelo ADR-0004, **a inferência é calculada e guardada só no aparelho**. O servidor nunca conhece o espectro inferido de ninguém.
   - O servidor só conhece temas declarados pelos autores e hashtags seguidas explicitamente.
5. **Regional (C1/C2).**
   - Raio livre de **1 a 50 km**.
   - ~~Posts regionais são opt-in por post (público "Região").~~ Substituído pelo [ADR-0008](0008-posts-globais-e-posicao-com-desvio.md): todo post leva a área aproximada, com desvio de até 1,5 km.
   - A posição do post é **arredondada para uma célula de ~500 m**, e a distância nunca é exibida (proteção contra triangulação).
   - A posição de quem lê vai ao servidor só na consulta, já arredondada, e **não é guardada**.
   - Feed regional fica desligado para menores, quando houver verificação de idade.

## Consequências

- A regra R2 deixa de ser "sem algoritmo" e passa a ser "algoritmo visível, explicável e controlável". O cronológico continua padrão.
- Trocar de aparelho zera o perfil de interesses, a menos que exista o backup cifrado (ADR-0004).
- A inferência política só existe no aparelho de quem optou por ela. Não há base central com o espectro político das pessoas, nem o que vazar ou vender.
