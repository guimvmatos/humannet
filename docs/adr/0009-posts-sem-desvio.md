# ADR-0009: Posts sem desvio de 1,5 km

- **Status:** aceito
- **Data:** 2026-10-11
- **Altera:** o item 4 do [ADR-0008](0008-posts-globais-e-posicao-com-desvio.md).

## Contexto

O ADR-0008 deslocava a posição de cada post até 1,5 km numa direção sorteada, para dificultar triangulação. O Guilherme achou o resultado ruim para o produto e decidiu retirar o desvio. Se der problema no futuro, a decisão é revista.

## Decisão

- O servidor **não desloca** mais a posição. Só arredonda para a célula de ~500 m e guarda a célula; a posição exata continua não sendo guardada.
- A distância continua nunca exibida, o raio mínimo continua 1 km e a posição de quem lê continua não sendo guardada.
- Posts antigos ficam com a célula que já tinham (deslocada); não há como recalcular.

## Consequências

- **Risco maior de triangulação:** quem posta sempre do mesmo lugar revela a área de ~500 m (quarteirões), não mais só o bairro. Variar o raio e mudar de lugar ajuda a estimar a célula.
- Termos e Política foram ajustados no texto, sem nova versão (a mudança vai junto com os Termos v3, item M2 do backlog, que já exigirão novo aceite).
- Quando houver verificação de idade, posts de menores continuam sem posição.
