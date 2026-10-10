# ADR-0008: Posts globais e posição do post com desvio

- **Status:** aceito
- **Data:** 2026-10-10
- **Substitui:** o item 5 do [ADR-0007](0007-feeds-algoritmo-controlavel-e-regional.md) ("posts regionais são opt-in por post").
- **Altera:** a regra R7 da SPEC, para o feed Regional.

## Contexto

No lote 20, quem escrevia escolhia o público do post (Amigos ou Região). O Guilherme decidiu que **quem escreve não escolhe público**: o post é um só, e é **quem lê** que escolhe o que ver.

## Decisão

1. **Todo post pessoal é global.** Qualquer pessoa pode abrir, curtir, comentar e denunciar. Exceções: bloqueio entre as duas pessoas (nos dois sentidos) e autor suspenso. A lista de posts no perfil continua só para amigos.
2. **Três modos no topo do feed**, escolhidos por quem lê:
   - **Cronológico:** amigos, eu e páginas que acompanho. Não traz desconhecidos, para não virar enxurrada nem premiar quem posta em volume.
   - **Para você:** a rede, mais posts de outras pessoas com tema ou hashtag (últimas 48 h). O app só mostra estes se baterem com um interesse do perfil, que fica no aparelho (ADR-0004).
   - **Regional:** posts de qualquer pessoa num raio de 1 a 50 km, em ordem cronológica ou "Para você".
3. **Posição em todo post (decisão do Guilherme, opção "a").** Ao publicar, o app manda a posição aproximada do aparelho. Se não houver permissão ou GPS, o post sai igual, só fora do Regional. Post de página não leva posição.
4. **Proteção contra triangulação.**
   - O servidor desloca a posição até **1,5 km**, numa direção sorteada **uma vez**, e arredonda para a célula de ~500 m.
   - A posição real nunca é guardada.
   - A distância nunca é exibida, e quem lê não é guardado.
   - Com isso, variar o raio (mínimo 1 km) e mudar de lugar não revela onde a pessoa estava.
5. **Transparência.** A tela de escrever diz que o post é público e que vai uma área aproximada, desviada.

## Consequências

- **R7 deixa de valer para posts.** Expor localização em posts não é mais opt-in; o desvio é a mitigação. Isso é decisão consciente de produto.
- **Risco residual:** quem posta sempre do mesmo lugar, com muitos posts, ainda revela a região (bairro), não o endereço.
- **Para você global em escala:** os candidatos de fora da rede são os 300 mais recentes com tema ou hashtag. Com muito volume, isso precisa de um índice por tema no servidor, sem mandar o perfil do usuário. Vai para o backlog.
- **Menores:** quando houver verificação de idade, posts de menores não levam posição.
