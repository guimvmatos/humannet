# HumanNet — Especificação

> Versão 0.1 · 2026-10-03 · Autor: Guilherme Matos
> Fonte: Manifesto de Fundação (jun/2025), Proposta de Rede Social Alternativa, Etapas, conversas de definição.
> Este documento é a fonte da verdade do produto. Decisões técnicas ficam em `docs/adr/`. Ideias futuras ficam em `docs/BACKLOG.md`.

---

## 1. Visão

Uma rede social ética, humana e autêntica, construída a partir do Brasil. Ela é o oposto da lógica de engajamento a qualquer custo.

### Princípios (do manifesto)

1. A pessoa é mais importante que o algoritmo.
2. A comunidade é mais importante que o conteúdo viral.
3. A privacidade é mais importante que a performance.
4. O diálogo é mais importante que o like.
5. A responsabilidade é mais importante que a escala.

### O que a HumanNet NÃO é

- Uma plataforma de influência artificial.
- Um lugar com algoritmos **ocultos** ou manipulação emocional.
- Um lugar com bots, perfis falsos ou contas duplicadas.
- Um palco de performance e vaidade.

### Regras de produto derivadas dos princípios

Toda feature nova é validada contra estas regras:

| Regra | Implicação |
|---|---|
| **R1. Uma pessoa, uma conta** | Toda conta pessoal corresponde a um humano. Bots só existem como contas declaradas da própria plataforma. |
| **R2. Nada oculto** | Qualquer ordenação ou filtro do feed é visível, explicável ("por que estou vendo isto") e desligável. |
| **R3. Métricas privadas** | Contagens de curtidas, visualizações e seguidores são visíveis apenas ao dono. |
| **R4. Sem amplificação em massa** | Não existe repost nem compartilhamento. O conteúdo circula por autoria, comentários e comunidades. |
| **R5. Dados mínimos** | Coletar só o necessário. Preferir processamento no aparelho. Não usar dado pessoal para anúncios. |
| **R6. Sem métricas de vício** | Tempo de tela e dwell time nunca alimentam ranking. |
| **R7. Segurança antes de alcance** | Toda feature que expõe localização ou presença física é opt-in, com padrão restritivo. |
| **R8. IA não se passa por humano** | Nenhuma IA posta, comenta ou interage com terceiros. A IA conversa só com o próprio usuário e é rotulada como IA. |

---

## 2. Plataforma

- **Cliente:** app Android em Flutter. O mesmo código atende iOS e web no futuro. Ver [ADR-0002](adr/0002-cliente-flutter-api-first.md).
- **Backend:** API HTTP/JSON em Rust (Axum) + PostgreSQL. Ver [ADR-0001](adr/0001-backend-rust-axum-postgres.md).
- **Web mínima (fase posterior):** páginas públicas de leitura para links de convite, eventos e comunidades, com botão para baixar o app.

---

## 3. Fases

| Fase | Escopo | Critério de saída |
|---|---|---|
| **0. Fundação** | Repo, CI, auth por convite, app com login | App instalado num Android real, logando na API |
| **1. MVP social** | Perfis, depoimentos, posts (texto + imagem), seguir, feed (2 modos), comunidades-fórum, curtir/comentar, denúncia, bloqueio, temas visuais | Grupo de ~12+ testadores usando o app por 14 dias (teste fechado do Play) |
| **2. Eventos** | Contas de organização, eventos, presença (RSVP), calendário no app, exportação `.ics`/assinatura | Um local real publicando eventos |
| **3. Presença física** | Check-in por QR rotativo, "quem está aqui" com controles de privacidade | Check-in validado num evento real |
| **4+. Depois** | Verificação de identidade e idade, classificador de temas, assistente de bem-estar (IA), marketplace, anúncios éticos | Ver backlog |

---

## 4. Requisitos funcionais

### 4.1 Contas e identidade (Fase 0)

- **Beta só por convite.** Cada código vale para um uso e expira.
  - Cada usuário pode gerar um número limitado de convites (padrão: 5 ativos).
  - Quem convidou quem fica registrado (`invited_by`). Isso forma uma rede de confiança e ajuda na moderação.
  - O primeiro convite é gerado pelo administrador via CLI.
- **Registro:** convite + nome de usuário + e-mail + senha.
  - Nome de usuário: 3–30 caracteres `[a-z0-9_]`, único, sem diferenciar maiúsculas.
  - Senha: 12–128 caracteres.
- **Login:** nome de usuário ou e-mail + senha. Devolve um token de sessão opaco.
- **Logout:** revoga a sessão no servidor.
- **Excluir conta:** obrigatório para o Play. Entra na Fase 1.
- **Futuro (Fase 4):** verificação de identidade e idade. O modelo de dados não pode impedir que ela seja adicionada sem migração destrutiva. Ver [ADR-0003](adr/0003-identidade-beta-por-convite.md).

### 4.2 Perfil (Fase 1)

- Nome de exibição, bio, avatar e tema visual escolhido.
- **Depoimentos fixos** (no estilo do Orkut): um usuário escreve sobre outro, e o dono aprova antes de aparecer.
- Contagens (seguidores, curtidas) visíveis só para o dono (R3).

### 4.3 Posts (Fase 1)

- Texto (até 5.000 caracteres) e até 4 imagens. **Vídeo fica fora do MVP.**
- Tags de tema opcionais, escolhidas pelo autor de uma lista controlada, mais o tema herdado da comunidade.
- Editar (com marca de "editado") e apagar.
- Curtir e comentar. Comentários em threads de 1 nível no MVP.
- **Sem repost/compartilhar** (R4).

### 4.4 Feed (Fase 1)

**Dois modos, escolhidos pelo usuário (R2):**

| Modo | Fonte | Ordem |
|---|---|---|
| **Cronológico** (padrão) | Quem eu sigo + minhas comunidades | Data de publicação, decrescente |
| **Por interesses** (opt-in) | A mesma fonte + feeds temáticos | Pontuação pelo perfil de interesses |

- **Feeds temáticos públicos** ("tecnologia", "música", ...): sempre cronológicos.
- **Perfil de interesses:**
  - Inferido **somente** de ações explícitas: curtir, comentar, entrar numa comunidade (R6).
  - Na Fase 1 é **calculado e guardado no aparelho** (R5). O servidor envia candidatos com tags e o app ordena. Ver [ADR-0004](adr/0004-privacidade-perfil-de-interesses.md).
  - O usuário vê os interesses e os pesos, pode apagar itens, pausar o aprendizado ou zerar o perfil.
- **Blacklist de temas:** vale nos **dois** modos. Na Fase 1 é aplicada no servidor (para não trafegar o conteúdo) e se baseia em tags. **Limitação conhecida:** um post sem tag escapa do filtro. Um classificador automático (Fase 4) reduz isso, mas não zera.
- "Por que estou vendo isto?" em cada item do modo por interesses.

### 4.5 Comunidades (Fase 1)

- Criadas por usuários, com tema principal, descrição e regras.
- Estrutura de **fórum**: tópicos com respostas. Tópicos podem ser fixados e trancados.
- Papéis: dono, moderador, membro.
- Pública (qualquer um lê e entra) ou fechada (entrar exige aprovação).

### 4.6 Moderação e segurança (Fase 1, obrigatória para a Play Store)

- Denunciar post, comentário, perfil ou comunidade (com motivo).
- Bloquear usuário. O bloqueio é **bidirecional e invisível**: nenhum dos dois vê o outro em lugar nenhum.
- Fila de moderação: moderadores de comunidade + administradores da plataforma.
- Fluxo da denúncia: `aberta → em análise → ação tomada | descartada → (recurso) → revisada`. Candidato a especificação em TLA+.
- Política de conteúdo escrita e visível no app antes de abrir o teste fechado.
- **Aberto:** detecção de material de abuso infantil (CSAM) em imagens enviadas. Exige ferramenta de hash especializada. Precisa estar resolvido antes de abrir para o público.

### 4.7 Temas visuais (Fase 1)

- Paletas pré-definidas (claro, escuro, rosa, verde, ...) e estéticas **originais** ("anos 80", "aquarela", ...).
- **Proibido** usar nome ou identidade visual de propriedade intelectual de terceiros (ex.: séries, estúdios).

### 4.8 Eventos (Fase 2)

- **Conta de organização** ligada a um ou mais usuários responsáveis. Na Fase 2 entra por convite. A verificação de CNPJ vem na Fase 4.
- **Evento:** título, descrição, local (endereço + coordenadas), início/fim com fuso, capa, capacidade opcional.
- **Presença (RSVP):** vou / tenho interesse / não vou.
- **Visibilidade da presença,** escolhida por usuário: todos / amigos / ninguém. Padrão: **amigos**.
- **Calendário no app** com os eventos marcados.
- **Exportação para outros calendários:**
  - `.ics` por evento (RFC 5545);
  - link "Adicionar ao Google Agenda";
  - **assinatura de calendário**: URL `webcal://` com token secreto e revogável, que mantém o calendário externo atualizado;
  - gravação no calendário do aparelho.
- "Quem mais vai": lista filtrada pela visibilidade de cada pessoa e pelos bloqueios.

### 4.9 Check-in e presença física (Fase 3)

- **QR rotativo:** o token é assinado pelo servidor (HMAC), muda a cada 30–60 s e aparece no "modo organizador" do app.
- O check-in só vale se: o token for válido, estiver dentro da janela do evento e (opcionalmente) o aparelho estiver dentro do raio do local.
- **Alternativa para eventos com ingresso:** o QR pessoal do usuário é escaneado pela equipe.
- **Privacidade (R7), todas obrigatórias:**
  - A presença é visível só para amigos por padrão. Ficar visível para todos no evento é opt-in.
  - Existe check-in **invisível**.
  - Os bloqueios são respeitados.
  - A lista só é visível para quem fez check-in no mesmo evento.
  - A presença expira no fim do evento, e os dados são apagados após um prazo curto (a definir, ex.: 7 dias).
  - A feature fica desabilitada para menores. Isso depende de verificação de idade.
- **"Pessoas de interesse" (não conhecidas):** fora da Fase 3. Se vier, será opt-in mútuo.

---

## 5. Requisitos não funcionais

### Segurança

- **Senhas:** hash Argon2id com parâmetros OWASP. Nunca logadas. Ver [ADR-0005](adr/0005-autenticacao-sessoes-opacas.md).
- **Sessões:** tokens opacos aleatórios (256 bits). O banco guarda só o SHA-256 do token. São revogáveis e expiram.
- **Login:** tempo de resposta uniforme para usuário inexistente (não revela se a conta existe). Limite de tentativas por IP e por conta.
- **Transporte:** HTTPS obrigatório em produção, com HSTS no proxy.
- **Entrada:** validação e limite de tamanho de corpo em todos os endpoints. SQL só parametrizado (sqlx com checagem em tempo de compilação).
- **Dependências:** `cargo audit` no CI. Atualizações semanais.
- **App:** token guardado no armazenamento seguro do aparelho (Android Keystore).

### Privacidade e LGPD

- Base legal e finalidade documentadas para cada dado coletado.
- Perfil de interesses no aparelho (R5). Qualquer inferência que se aproxime de dado sensível (ex.: opinião política) não sai do aparelho.
- Exportação e exclusão de dados pelo próprio usuário.
- **Aberto:** revisão jurídica (LGPD, responsabilidade de plataformas, proteção de menores) antes de abrir para o público.

### Desempenho (metas iniciais)

- p95 < 150 ms nos endpoints de leitura do feed com 100k posts.
- A API roda numa VM pequena (1 vCPU / 1 GB) no beta.

### Observabilidade

- Logs estruturados (JSON em produção), com ID de requisição.
- Nunca logar senha, token, e-mail completo ou conteúdo de post.

---

## 6. Modelo de dados (núcleo)

Fase 0 implementada em `backend/migrations/`. As entidades das fases seguintes são indicativas.

```
users(id, username, email, password_hash, invited_by → users, created_at)
sessions(id, user_id → users, token_hash, created_at, expires_at)
invites(id, code_hash, created_by → users?, created_at, expires_at, used_by → users?, used_at)

-- Fase 1 (1a implementada: display_name/bio em users, follows, posts de texto)
users += (display_name, bio)                -- avatar e tema virão depois
testimonials(id, author_id, subject_id, body, status, created_at)
follows(follower_id, followee_id, created_at)
blocks(blocker_id, blocked_id, created_at)
topics(id, slug, name)                      -- lista controlada de temas
posts(id, author_id, community_id?, body, created_at, edited_at, deleted_at)
post_topics(post_id, topic_id)
post_media(id, post_id, storage_key, kind, width, height)
likes(user_id, post_id, created_at)
comments(id, post_id, author_id, parent_id?, body, created_at, deleted_at)
communities(id, slug, name, topic_id, description, rules, visibility, created_by)
community_members(community_id, user_id, role, status)
threads(id, community_id, author_id, title, pinned, locked, created_at)
topic_blacklist(user_id, topic_id)
reports(id, reporter_id, target_kind, target_id, reason, status, created_at, resolved_by?)

-- Fase 2
organizations(id, name, slug, verified_at?)
organization_members(org_id, user_id, role)
events(id, org_id, title, description, address, geo, starts_at, ends_at, tz, capacity?)
rsvps(event_id, user_id, status, visibility)
calendar_feeds(user_id, token_hash, created_at, revoked_at?)

-- Fase 3
checkins(event_id, user_id, visibility, created_at, expires_at)
```

---

## 7. Questões em aberto

1. Nome definitivo e domínio.
2. Plataforma fechada × protocolo aberto (ActivityPub / AT Protocol). Precisa de um ADR antes da Fase 2.
3. Fornecedor e base legal para a verificação de identidade (Fase 4).
4. Detecção de CSAM em imagens. Precisa estar resolvida antes do acesso público.
5. Modelo de monetização ético (ver backlog).
6. Hospedagem de produção e orçamento.
