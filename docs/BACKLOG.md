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

## Evento ao vivo: fotos e conversa de quem está lá

**Ideia:** o check-in no evento (QR rotativo, SPEC 4.9) libera, **só para quem fez check-in**:

1. **Fotos na página do evento.** Quem está no evento envia fotos para uma galeria do evento. A organização pode **destacar** fotos na página.
2. **Conversa do evento.** Um chat geral só entre quem fez check-in.

- **Fase:** 3, junto com o check-in.
- **Por que encaixa:** comunidade presencial, conteúdo autoral, memória do evento ("memória digital" da Proposta).
- **Desenho proposto:**
  - **Galeria:** quem envia é o autor (o crédito aparece). "Destacar" pela organização **não é repost** (R4): a foto fica só na página do evento e não vai para o feed de ninguém.
  - **Política de imagem obrigatória antes de lançar:**
    - quem aparece na foto pode pedir remoção com um toque ("estou nesta foto");
    - nada de fotos de menores;
    - moderação da organização e da plataforma;
    - detecção de CSAM (ver SPEC 7).
  - **Conversa do evento:** abre no início do evento e fica **só leitura** algumas horas depois do fim. Depois é apagada (ex.: 7 dias). Bloqueios são respeitados.
  - A presença na conversa segue a visibilidade do check-in (R7). Quem fez check-in invisível pode ler sem aparecer na lista.
- **Riscos:** fotos de terceiros sem consentimento, assédio em chat aberto, custo de armazenamento de imagens, moderação em tempo real.

## Turmas (grupos criados juntos, no presencial)

**Ideia:** um grupo de amigos que está junto cria uma **Turma**, um grupo com nome próprio. Para criar, todos precisam estar **fisicamente juntos** ("encostar os celulares"). A Turma pode ter a própria página e publicar como grupo. O nome ainda está em aberto: "Turma", "Galera", "Bonde", "Rolê"... (definir com o público-alvo).

- **Fase:** 3+ (depois de eventos e check-in, que testam a mesma mecânica de presença).
- **Por que encaixa:** relação real e presencial (só cria quem está junto), "comunidade > audiência". Pode pegar em nichos (bandas, times de futebol de várzea, grupos de faculdade, viagens).
- **Desenho proposto:**
  - **Criação por QR em vez de Bluetooth:** um celular mostra um QR rotativo (o mesmo mecanismo do check-in) e os outros escaneiam em até 2 min.
    - Bluetooth exige permissões pesadas no Android, falha com frequência e funciona de forma diferente no iOS.
    - O QR prova a mesma coisa: "estávamos juntos".
    - "Encostar" (NFC) pode vir depois, como enfeite.
  - Membros precisam ser **amigos** entre si? Proposta: não precisam, mas cada um precisa aceitar entrar.
  - **Publicar "como Turma":** o post aparece como "Turma X", **com o autor sempre visível** ("por @fulano"). Assim mantém R1: ninguém se esconde atrás do grupo.
  - Entrar depois: por convite de um membro, ou de novo presencialmente (decidir).
- **Riscos:** grupos usados para assédio coordenado (moderação de grupo), confusão com Comunidades (Turma = pequeno e fechado; Comunidade = aberto e temático).

## Linha do tempo pessoal e reencontros

**Ideia:** no começo, a pessoa conta um pouco da própria história: cidade onde nasceu, ano de nascimento, cidades onde morou, escolas e faculdades, trabalhos, cada item com um **período** (ex.: Escola X, 1998–2005). A partir disso, a HumanNet sugere **pessoas da mesma época e do mesmo lugar**: colegas de escola, da faculdade, da cidade antiga ou da nova. É o "reencontro" do Orkut e do Facebook antigo.

- **Fase:** 1c. Logo depois da amizade mútua e da 1b, porque é o principal jeito de **encontrar amigos** num modelo só de amizade.
- **Por que encaixa:**
  - "Identidade real" e "construir relações" (manifesto).
  - Resolve como achar pessoas sem algoritmo de engajamento: a sugestão vem de **fatos que você mesmo informou**.
- **Desenho proposto:**
  - **Opcional**, com "pular" e "completar depois" (R5: dados mínimos). O app incentiva, mas não obriga.
  - **Dados estruturados, não texto livre:**
    - cidades da lista oficial do IBGE;
    - escolas do Censo Escolar (INEP);
    - faculdades do e-MEC;
    - entrada livre só quando o lugar não está na lista.
    - Sem isso, "Col. São José" e "Colégio São José" não casam.
  - **Períodos em ano**, nunca data exata. Do nascimento, guardar só o **ano**.
  - **Sugestão transparente (R2):** "Sugerido porque vocês estudaram na Escola X na mesma época". Sem pontuação oculta.
  - **Casamento:** mesmo lugar **e** períodos que se sobrepõem, com margem de ±2 anos para escolas e cidades da infância.
  - **Visibilidade por item:** "visível para amigos", "só para sugestões, nunca exibido" ou "só eu".
  - **Consentimento dos dois lados:** só aparece como sugestão quem ativou "quero ser encontrado por este item". A razão da sugestão só é mostrada se o item for visível para quem recebe a sugestão.
  - Sugestão ≠ amizade: continua sendo preciso pedir e aceitar (R9).
- **Riscos:**
  - **Perguntas de segurança.** "Nome da primeira escola" e "cidade onde nasceu" são perguntas clássicas de recuperação de conta em bancos. Expor isso ajuda golpes. Por padrão, esses itens **nunca são exibidos publicamente**.
  - **Menores de idade:** a escola **atual** de um menor é informação sensível (perseguição). Para menores, escola atual nunca é exibida nem usada em sugestões. Depende da verificação de idade (Fase 4).
  - **Perseguição:** um ex-parceiro ou agressor pode reencontrar a vítima. Bloqueio impede sugestões nos dois sentidos, e a pessoa pode desligar "ser encontrado" a qualquer momento.
  - **Perfilamento:** a linha do tempo de alguém é um dossiê. Ela nunca vai para anúncios nem para terceiros (R5), e o usuário pode apagar tudo.
  - **LGPD:** finalidade específica ("sugerir pessoas") e consentimento explícito.
- **Dependências:** amizade mútua (ADR-0006), bloqueio (1b), importação das bases IBGE/INEP/e-MEC (dados públicos).
- **Extensão futura:** a mesma linha do tempo pode alimentar "lembranças" ("há 10 anos você se formava na Faculdade Y"), ligada à "memória digital" da Proposta.

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
