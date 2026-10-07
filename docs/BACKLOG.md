# Backlog e ideias

> Decisões já tomadas saem daqui e viram ADR. Ex.: amizade mútua → [ADR-0006](adr/0006-amizade-mutua.md).

Ideias registradas que ainda não estão especificadas em detalhe. Quando uma ideia for priorizada, ela vira uma seção da `SPEC.md` e, se exigir decisão técnica, um ADR.

Para cada ideia: **fase prevista**, **dependências** e **riscos**.

---

## Assistente de bem-estar (IA)

**Ideia:** um chat fixado no app que funciona como assistente de bem-estar. Exemplo: "Notei que você está viajando. Aproveite, tire fotos e poste depois."

- **Fase:** 4+
- **Dependências:**
  - sinais de contexto: check-in (Fase 3), fuso horário do aparelho, local declarado em posts;
  - perfil de interesses (Fase 1).
- **Diretrizes:**
  - Rotulada como IA. Nunca posta nem interage com terceiros (R8).
  - Assistente, **não** "parceiro" ou companhia emocional. Persona afetiva cria dependência, que é o mesmo problema do vício.
  - **Quando falar** é decidido por regras determinísticas (uso contínuo > X min, viagem, madrugada). O modelo só escreve a mensagem.
  - Localização: usar primeiro os sinais já fornecidos. GPS em segundo plano só com opt-in explícito e processado no aparelho.
- **Opções técnicas:**
  - modelo pequeno no aparelho: privacidade total, custo zero por usuário, mas limitado em aparelhos fracos;
  - API de LLM: melhor qualidade, mas tem custo e envia dados para fora. Só com opt-in.
- **Riscos:** custo, privacidade e o tom paternalista incomodar parte dos usuários. A feature precisa poder ser desligada.

## Posts e feed regionais

**Ideia:** quem ativa a opção publica posts que só aparecem para pessoas dentro de um raio, e passa a ver posts dessa mesma região, no estilo Tinder.

- **Fase:** 2, junto com eventos, porque as duas features usam a mesma infraestrutura de localização.
- **Por que encaixa:**
  - Reforça "comunidade viva" e "identidade real" (manifesto).
  - Ajuda a resolver o problema dos primeiros usuários: densidade local tem mais valor que alcance global.
  - Combina com eventos e locais (pubs) e com o crescimento cidade a cidade.
- **Desenho proposto:**
  - **Aba "Local" separada**, opt-in. Não substitui o feed principal (R2: nada oculto, o usuário escolhe).
  - "Regional" é uma **opção de público do post**: Seguidores ou Região.
  - **Nunca guardar coordenadas.** O app converte a posição numa **célula de grade** (geohash ou H3, na escala de um bairro ou cidade) e só a célula vai para o servidor (R5).
  - **Nunca exibir distância** ("a 1,2 km"). No máximo o nome do bairro ou da cidade.
  - O raio é escolhido entre opções fixas (bairro, cidade, região), não em metros.
  - Posts regionais expiram ou deixam de ser regionais depois de um tempo (ex.: 7 dias).
- **Riscos:**
  - **Triangulação:** é o ataque clássico contra apps de distância. Quem consegue consultar a distância a partir de vários pontos descobre a posição exata. Células fixas e nenhuma distância exibida resolvem isso.
  - **Perseguição e assédio:** postar "estou aqui" expõe a pessoa. A feature precisa ser opt-in, o bloqueio precisa valer também na aba Local, e ela fica **desligada para menores**, o que depende da verificação de idade (Fase 4).
  - **Feed vazio** em regiões com poucos usuários: mostrar o fim explícito e sugerir ampliar o raio.
  - **Moderação local:** denúncias regionais podem exigir moderadores da região.
  - **LGPD:** localização é dado pessoal. Precisa de finalidade e consentimento específicos.
- **Dependências:** bloqueio e denúncia (Fase 1b), verificação de idade (Fase 4) ou restrição a maiores declarados no beta.

## Ferramentas de descanso digital

- **Fase:** 1–2
- Limite diário que o próprio usuário define, lembrete de pausa e "fim do feed" explícito (sem rolagem infinita).

## Classificador automático de temas

- **Fase:** 4
- Reduz o vazamento da blacklist em posts sem tag. Usaria embeddings multilíngues ou um classificador pequeno.
- **Risco:** um classificador errado vira censura percebida. Precisa de contestação ("este post não é sobre política").

## Pessoas de interesse em eventos

- **Fase:** 4+
- Opt-in mútuo, denúncia fácil, só para maiores verificados.
- **Risco:** virar app de encontros e expor pessoas a assédio.

## Verificação de identidade e idade

- **Fase:** 4. Ver ADR-0003.

## Contas de empresa verificadas (CNPJ)

- **Fase:** 4

## Marketplace com reputação

- **Fase:** 5+

## Anúncios éticos

- **Fase:** 5+
- **Conflito com o manifesto:** segmentar por idade e região usa dado pessoal. Alternativa compatível: anúncios **contextuais** (por comunidade ou tema da página, sem perfil do usuário) e opt-in.

## Iniciativas sociais com curadoria comunitária

- **Fase:** 5+

## Federação (ActivityPub / AT Protocol)

- **Decisão pendente** antes da Fase 2. Tensão com R1: contas de outros servidores não são verificadas.

## Web pública mínima

- **Fase:** 2
- Páginas de leitura para links de convite, evento e comunidade, com botão para baixar o app.
