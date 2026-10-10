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

## Ideias "nostálgicas" (lote 2026-10-07)

Ideias inspiradas no Orkut, no MSN e no Flogão. Algumas já estão na SPEC; as outras ficam aqui.

| Ideia | Situação | Fase | Observações |
|---|---|---|---|
| **Fóruns por tópicos** (comunidades do Orkut) | Já está na SPEC 4.5 | 1 | Tópicos com começo, meio e fim. É o modelo de Comunidades da HumanNet. |
| **Depoimentos** | Já está na SPEC 4.2 | 1 | O dono aprova antes de aparecer. |
| **Livro de visitas** (recados/scraps) | Novo | 1–2 | Mural informal no perfil: só **amigos** escrevem, o dono pode apagar, e ele aparece para quem visita o perfil. Diferente do depoimento: mais leve e sem aprovação prévia (o dono pode ligar a aprovação). |
| **Selo de confiança humana** ("Bom ouvinte", "Criativo", "Engraçado") | Novo | 2 | Só **amigos** dão. **Sem números públicos** (R3): o perfil mostra os traços, não a contagem. Não pode ranking nem traço de aparência ("sexy"), por risco de assédio e de menores. |
| **Ver quem visitou o perfil** | Novo | 2 | **Opcional e recíproco**, como no Orkut: só vê quem visitou quem também aparece nas visitas dos outros. Desligado por padrão. Guarda só os últimos 30 dias. |
| **Status de disponibilidade** (Disponível / Ocupado / Ausente / **Invisível**) | Novo | junto com Mensagens | Padrão: nunca mostrar "online agora" (anti-cobrança). Sem "visto por último". "Invisível" de verdade. |
| **Subnick / música do momento** | Novo | 2 | Primeiro, texto livre curto (o "subnick") com validade (ex.: 24 h). Depois, integração opcional com streaming (ex.: "ouvindo agora" via API do Spotify/Deezer, com OAuth). Mostra só nome e artista, nunca toca o áudio (direitos autorais). |
| **Chamar atenção** (vibrar o celular do amigo) | Novo | junto com Mensagens e notificações | Só entre **amigos**. Limite: 3 por dia no total e 1 por dia por amigo. O receptor pode silenciar ou bloquear. Depende de push notification. |
| **Uma foto por dia** (Flogão) | Novo, **decisão pendente** | 1 (com imagens) | Opções: (a) toda foto é limitada a 1 por dia; (b) "Foto do dia" é um espaço especial no perfil, e os posts de texto continuam livres. Encaixa com "sem vício" (R6). |
| **Canais de chat de texto puro** (#cinema-sp, #programacao) | Novo | 3+ | Estilo IRC, só texto. Sobreposição com Comunidades: talvez cada comunidade tenha um canal. Moderação em tempo real é cara e precisa de moderadores voluntários. |

## Mensagens diretas (fundação que falta)

Várias ideias dependem de **conversa 1:1 e em grupo** (status, chamar atenção, Turmas, conversa do evento), e isso ainda **não está na SPEC**.

- **Fase:** 2.
- **Regras iniciais:**
  - só entre **amigos** (R9);
  - sem "visto por último" e sem confirmação de leitura por padrão;
  - bloqueio impede tudo.
- **Decisão técnica pendente:** criptografia de ponta a ponta (protocolo MLS ou Signal) desde o início, ou mensagens legíveis pelo servidor no começo, o que é mais simples e permite moderação. Precisa de um ADR.

## Linha do tempo pessoal e reencontros

> **Implementado no lote 18** (2026-10-10): municípios do IBGE, catálogo comum de escolas, faculdades e empresas (sem duplicatas, por nome normalizado e cidade), cursos, visibilidade por item, "quero ser encontrado" e sugestões com motivo.
> **Pendente:** importar os catálogos oficiais completos do INEP (escolas) e do e-MEC (faculdades e cursos), e juntar instituições duplicadas pela administração.


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

**Usos (hiperlocal, ajuda mútua):** pedir uma ferramenta emprestada, organizar mutirão de limpeza de praia, achar parceiro de surf, avisar sobre falta de luz na rua. Proposta: posts da aba Local com **tipo** (Pedido de ajuda, Oferta, Mutirão, Procuro parceiro), para dar para filtrar.

- **Fase:** 2, junto com eventos, porque as duas features usam a mesma infraestrutura de localização.
- **Por que encaixa:**
  - Reforça "comunidade viva" e "identidade real" (manifesto).
  - Ajuda a resolver o problema dos primeiros usuários: densidade local tem mais valor que alcance global.
  - Combina com eventos e locais (pubs) e com o crescimento cidade a cidade.
- **Desenho proposto:**
  - **Aba "Local" separada**, opt-in. Não substitui o feed principal (R2: nada oculto, o usuário escolhe).
  - ~~"Regional" é uma **opção de público do post**: Seguidores ou Região.~~ Feito de outro jeito: posts globais com área desviada (ADR-0008).
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


## Anúncios éticos

- **Fase:** 5+
- **Conflito com o manifesto:** segmentar por idade e região usa dado pessoal. Alternativa compatível: anúncios **contextuais** (por comunidade ou tema da página, sem perfil do usuário) e opt-in.

## Iniciativas sociais com curadoria comunitária

- **Fase:** 5+


## Web pública mínima

- **Fase:** 2
- Páginas de leitura para links de convite, evento e comunidade, com botão para baixar o app.

---

## Em análise (Guilherme decide se entra)

### Marketplace com reputação
Compra, venda e troca entre pessoas da rede (tipo OLX/Marketplace do Facebook), com reputação baseada em quem convidou e em avaliações de negócios anteriores. Riscos: fraude, pagamentos, Código de Defesa do Consumidor. Fase 5+ se entrar.

### Federação (ActivityPub / AT Protocol)
Conversar com outras redes abertas (Mastodon, Bluesky). Tensão com R1: contas de outros servidores não passam pela nossa verificação de "uma pessoa, uma conta".

## Depois (decidido que entra, sem data)

- **Assistente de bem-estar (IA)** — ver seção acima. Guilherme quer; fica para depois dos eventos.

## Decisão 2026-10-08: páginas de lugares e eventos

- Lugares (bar, restaurante, casa de show…) têm uma **página** (perfil de lugar), administrada por uma ou mais pessoas.
- A página cria **eventos**. Quem vê registra **interesse** ("tenho interesse / vou"), **sem venda de ingresso** e sem pagamento no app.
- Pessoas acompanham páginas de lugares (única relação unilateral permitida, ADR-0006).

## Decisão 2026-10-08: CPF

- **Agora (feito, lote 11):** convite + CPF obrigatório, uma conta por CPF. O servidor guarda só HMAC-SHA256 (chave `CPF_HMAC_KEY`, nunca trocar). Não prova que o CPF é da pessoa; a administração libera CPF usado indevidamente.
- **Depois:** verificação real (documento + selfie) por serviço pago (Unico, idwall…), com selo "verificado" no perfil.

## Decisão 2026-10-10: posts globais (ADR-0008)

- Quem escreve não escolhe público. Quem lê escolhe Cronológico, Para você ou Regional (este com ordem cronológica ou "Para você" e raio de 1 a 50 km).
- Todo post pessoal leva a área aproximada, com desvio de até 1,5 km.
- **Pendente:** "Para você" com desconhecidos em escala. Hoje vêm os 300 posts mais recentes com tema/hashtag (48 h). Com volume, criar consulta por tema no servidor sem enviar o perfil de interesses.
- **Pendente:** posts de menores sem posição, quando houver verificação de idade.

## Decisão 2026-10-10: Termos de Uso e Privacidade (lote 22)

- Textos em `backend/legal/` (versão 1), servidos em `/legal/termos` e `/legal/privacidade`. Aceite obrigatório no cadastro (com declaração de 18+); contas antigas aceitam ao abrir o app.
- Contato/encarregado: Gmail do Guilherme por enquanto. **Trocar** pelo e-mail do domínio quando houver (mudar o texto e subir a versão só se a mudança for importante).
- **Pendente (jurídico):** revisão por advogado antes de abrir ao público geral.
- **Pendente (Marco Civil, art. 15):** se o HumanNet virar atividade organizada com fins econômicos (ex.: com CNPJ), guardar registros de acesso (IP, data e hora) por 6 meses, em sigilo.
