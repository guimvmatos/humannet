# Guia: colocar a HumanNet no ar para amigos e família

Passo a passo para sair de "só eu testando" para "10–20 pessoas usando".
Faça **na ordem**, um passo de cada vez. Cada passo termina com um
**✅ Confere** — só siga quando ele der certo.

Use o **computador** (fica bem mais fácil copiar e colar). O celular entra no
final, para testar.

---

## As escolhas (e por quê)

| Peça | Serviço | Custo | Por quê |
|---|---|---|---|
| Banco de dados | **Neon**, plano Free, região *AWS US East (N. Virginia)* | R$ 0 | Postgres de verdade, **não expira** (o do Render expira em 30 dias), sem cartão. 1 GB sobra para anos de texto. Mesma região do servidor = rápido. |
| Servidor da API | **Render** (já em uso) | R$ 0 agora → **US$ 7/mês** quando os amigos entrarem | O grátis "dorme" após 15 min sem uso e leva ~1 min para acordar — ruim para quem está testando pela primeira vez. O Starter nunca dorme. |
| Código e builds | **GitHub** (já em uso) | R$ 0 | Repositório público = Actions grátis. |
| Distribuir o app | **Google Play — teste interno** | **US$ 25 uma vez só** | Até 100 testadores, sem revisão do Google, atualização automática. Enquanto não tiver a conta, dá para mandar o link do APK. |
| Fotos (futuro, lote 4) | Cloudflare R2 | R$ 0 até 10 GB | Sem taxa de download. Ainda não precisa. |

**Total para começar:** US$ 25 (uma vez) + US$ 7/mês quando liberar para os
amigos. Até lá, tudo de graça.

---

## Passo 1 — Criar o banco no Neon (10 min)

1. Abra **https://neon.tech** e clique em **Sign up**.
2. Escolha **Continue with GitHub** (ou Google) e autorize.
3. Na tela de criar projeto (se não abrir sozinha: **New Project**):
   - **Project name:** `humannet`
   - **Postgres version:** a que vier marcada (17 ou mais nova serve)
   - **Cloud service provider:** **AWS**
   - **Region:** **AWS US East 1 (N. Virginia)** ← importante: é onde o servidor do Render está
   - Clique em **Create project**.
4. No painel do projeto, clique no botão **Connect** (canto superior direito).
5. Na janela que abrir:
   - **Branch:** `production` (ou `main`) — deixe como está.
   - **Database:** `neondb` — deixe como está.
   - **Connection pooling:** **DESLIGADO** ← importante (as migrações do banco
     não funcionam pelo pooler). Se o endereço tiver `-pooler` no meio, o
     botão ainda está ligado.
   - Clique em **Show password** e depois em **Copy snippet** (ou no ícone de
     copiar). Vem algo assim:
     ```
     postgresql://neondb_owner:SENHA@ep-nome-12345.us-east-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require
     ```
6. Cole esse texto num bloco de notas por enquanto. **É uma senha** — não
   mande para ninguém nem cole em chat.

✅ **Confere:** o endereço tem `us-east-1`, **não** tem `-pooler`, e termina
com `sslmode=require` (o `&channel_binding=require` pode ficar; o servidor ignora).

---

## Passo 2 — Apontar o servidor (Render) para o Neon (10 min)

> O banco novo começa **vazio**: as contas de teste de hoje somem. É
> proposital (eram só testes). Você vai criar sua conta de novo com um código
> de primeiro convite novo.

1. Abra **https://dashboard.render.com** e entre.
2. Clique no serviço **humannet-api**.
3. No menu da esquerda, clique em **Environment**.
4. Em **Environment Variables**, clique em **Edit**.
5. Ajuste três variáveis:
   - **DATABASE_URL** → apague o valor antigo e cole o endereço do Neon (passo 1).
     Se a variável não existir, clique em **+ Add Environment Variable** e crie.
   - **BOOTSTRAP_INVITE_CODE** → troque pelo código novo que te mandei no chat
     (só vale para a primeira conta do banco novo).
   - **ADMIN_USERNAMES** → confira que está `guimvmatos`. Se não existir, crie.
6. Clique em **Save, rebuild, and deploy** (ou **Save and deploy**).
7. No menu da esquerda, clique em **Events** e espere aparecer **Deploy live**
   (2–5 min). Se aparecer **Deploy failed**, clique em **Logs**, tire um
   print das últimas linhas e me mande.

✅ **Confere:** abra no navegador
`https://humannet-api.onrender.com/health` → deve mostrar `ok`.

### 2b — Criar sua conta de novo

1. No celular, abra o app HumanNet → **Tenho um convite**.
2. Código: o código novo do passo 5. Usuário: `guimvmatos`. Use uma senha
   **nova** (a antiga apareceu no chat; não reaproveite).
3. Entre. Vá em **Perfil → engrenagem**: deve aparecer **Moderação** no topo
   (isso confirma que você é administrador).

✅ **Confere:** você entra e vê **Moderação** nas Configurações.

### 2c — Apagar o banco antigo do Render (opcional, depois de tudo ok)

Me avise que o 2b deu certo; eu tiro o banco antigo do `render.yaml`. Depois
disso: Dashboard do Render → **humannet-db** → **Settings** → no fim da
página, **Delete Database**.

---

## Passo 2d — Ligar as fotos (armazenamento do Neon, 10 min) ✅ feito em 07/10/2026

Fotos ficam no **Object storage** do Neon (5 GB grátis, mesma conta). O
servidor recodifica cada foto sem metadados (tira GPS) antes de guardar.

1. **https://console.neon.tech** → projeto **humannet** → menu **Object storage**
   → **Create your first bucket**.
2. Nome `humannet-fotos`, visibilidade **Private** (não muda depois) → **Create bucket**.
3. Botão verde **Connect** → aba **Storage** → aba **.env**. Ali estão
   `AWS_ENDPOINT_URL_S3`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
   (**Reveal credential** para ver) e `AWS_REGION`.
4. Render → **humannet-api** → **Environment** → **Edit** → adicione as 4
   variáveis com os mesmos nomes e mais `MEDIA_BUCKET` = `humannet-fotos`.
   Copie um valor por vez (não use "Copy credentials").
5. **Save, rebuild, and deploy**.

✅ **Confere:** no app, **Escrever → Fotos** publica um post com foto.
Sem essas variáveis, o app avisa "Fotos ainda não estão ligadas no servidor".

> Se a senha vazar: no Neon, **Rotate credentials** e troque
> `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` no Render.

---

## Passo 3 — Chave de assinatura do app no GitHub (10 min)

O Google Play exige que o app seja assinado sempre com a mesma chave. Eu gerei
essa chave e te entreguei dois arquivos:

- `humannet-chave-SEGREDO.txt` — os três valores para copiar
- `humannet-upload-keystore.jks` — a chave em si

**Antes de tudo:** guarde os dois arquivos num lugar seguro e privado (ex.:
pasta no seu Google Drive pessoal). Se perder, para atualizar o app na Play é
preciso pedir troca de chave ao Google (demora dias).

Agora, cadastre os três valores no GitHub:

1. Abra **https://github.com/guimvmatos/humannet**.
2. Clique em **Settings** (aba no topo do repositório, ícone de engrenagem).
3. No menu da esquerda: **Secrets and variables** → **Actions**.
4. Clique no botão verde **New repository secret**.
5. Crie **um por vez** (Name exatamente como abaixo, Secret = o valor do
   arquivo `.txt`), clicando em **Add secret** em cada um:
   - Name: `ANDROID_KEY_ALIAS` → Secret: `upload`
   - Name: `ANDROID_KEYSTORE_PASSWORD` → Secret: a senha do arquivo
   - Name: `ANDROID_KEYSTORE_BASE64` → Secret: a linha enorme do arquivo
     (copie **inteira**, sem espaços nem quebras no começo/fim)
6. Me avise. Eu disparo um build novo.

✅ **Confere:** na página **Actions** do repositório, o último build do
**app** fica verde e aparecem **dois** arquivos em *Artifacts*:
`humannet-apk` e `humannet-aab`.

> ⚠️ A partir daqui o APK sai com a chave nova. **Na primeira vez**, o
> Android vai recusar instalar "por cima" do app antigo: desinstale o
> HumanNet do celular e instale de novo. Só acontece uma vez.

---

## Passo 4 — Distribuir para os amigos

### Opção A — já, de graça: link do APK

Mande este link: **https://github.com/guimvmatos/humannet/releases/tag/dev-latest**

A pessoa toca em `humannet-dev.apk`, baixa e instala. O Android vai pedir
para **permitir instalar apps desta fonte** (Chrome) — tem que aceitar. Não
atualiza sozinho: a cada versão nova, a pessoa baixa de novo.

Bom para 2–3 pessoas que topam mexer. Para a família toda, use a opção B.

### Opção B — Google Play, teste interno (recomendado)

**B1. Criar a conta de desenvolvedor (US$ 25, uma vez)**

1. Abra **https://play.google.com/console/signup** com a conta Google que vai
   ser "dona" do app.
2. Tipo de conta: **Você mesmo** (pessoal / *Yourself*).
3. Preencha nome de desenvolvedor (aparece para os testadores; ex.: `HumanNet`),
   e-mail e telefone de contato.
4. Pague os **US$ 25** com cartão.
5. **Verificação de identidade:** o Google pede documento com foto. Pode
   levar de algumas horas a alguns dias.
6. O Console também pede para você **confirmar um celular Android** pelo app
   *Google Play Console* — instale no seu celular e siga o que ele pedir.

✅ **Confere:** você entra em **https://play.google.com/console** e vê
**Todos os apps** sem avisos de verificação pendente.

**B2. Criar o app**

1. **Criar app** (botão no canto superior direito).
2. Nome do app: `HumanNet`. Idioma padrão: **Português (Brasil) – pt-BR**.
3. **App** (não jogo). **Gratuito**.
4. Marque as duas declarações (políticas do programa e leis de exportação dos EUA).
5. **Criar app**.

**B3. Subir a primeira versão (teste interno)**

1. Baixe o AAB: no GitHub, **Actions** → workflow **app** → clique no build
   verde mais recente da `main` → lá embaixo, em *Artifacts*, clique em
   **humannet-aab** (baixa um `.zip`; descompacte e pegue o `app-release.aab`).
2. No Play Console, menu da esquerda: **Testar e lançar** → **Testes** →
   **Teste interno**.
3. Aba **Testadores** → **Criar lista de e-mails**:
   nome `Família e amigos`, cole os e-mails (os que eles usam na Play Store do
   celular), separados por vírgula → **Salvar**. Marque a lista.
4. Aba **Versões** → **Criar nova versão**.
5. Se perguntar sobre **Assinatura de apps do Google Play**: **Continuar /
   Usar assinatura gerenciada pelo Google** (padrão).
6. **Pacotes de apps:** arraste o `app-release.aab`.
7. Nome da versão: deixe o automático. Notas: `Primeira versão de teste.`
8. **Próxima** → **Salvar** → **Revisar versão** → **Iniciar lançamento
   para teste interno**.
9. Volte na aba **Testadores** e copie o **Link para participar** (*Copy link*).

> Se o Console bloquear o lançamento pedindo para preencher itens de
> **Conteúdo do app**, veja o B4 e depois volte aqui.

**B4. Formulários que o Play pode pedir** (menu **Monitorar e melhorar →
Política e programas → Conteúdo do app**, ou na lista "Configurar o app" do
Painel)

- **Política de privacidade:** cole
  `https://github.com/guimvmatos/humannet/blob/main/docs/PRIVACIDADE.md`
  (antes, me diga qual e-mail de contato colocar nela).
- **Acesso ao app:** *Todas ou algumas funcionalidades são restritas* →
  adicione instruções: "App só para convidados. Usuário: … Senha: …" — crie
  uma conta só para isso (um convite seu para um usuário `revisor`). **Não**
  use a sua.
- **Anúncios:** *Não, meu app não contém anúncios.*
- **Classificação de conteúdo:** responda o questionário; categoria **Rede
  social / Comunicação**. Marque que usuários **interagem entre si** e
  **compartilham conteúdo**.
- **Público-alvo:** **18 anos ou mais**.
- **Segurança dos dados:**
  - Coleta dados? **Sim.** Compartilha com terceiros? **Não.**
  - Criptografados em trânsito? **Sim.** Usuário pode pedir exclusão? **Sim.**
  - Tipos: **Informações pessoais → Nome** e **Endereço de e-mail** e **IDs do
    usuário**; **Mensagens → Outras mensagens no app** (posts e comentários).
    Para cada um: *coletado*, *não compartilhado*, *obrigatório* (o nome de
    exibição é *opcional*), finalidade **Funcionalidade do app** e
    **Gerenciamento da conta**.
  - **Link para excluir a conta:** o mesmo link da política de privacidade
    (ela explica como excluir).
- **App de notícias:** Não. **App governamental:** Não. **Recursos
  financeiros:** Nenhum. **Saúde:** Nenhum.

**B5. Mandar para os amigos**

Mande o **link para participar** (passo B3.9). Cada pessoa:
1. Abre o link **no celular**, logada com o e-mail que você colocou na lista.
2. Toca em **Aceitar convite / Tornar-se testador**.
3. Toca em **Fazer download no Google Play** e instala.

Atualizações chegam sozinhas pela Play, como qualquer app.

✅ **Confere:** você mesmo instala pela Play (desinstale o APK antes — é outra
assinatura, os dois não convivem).

> Para cada versão nova: eu faço o código, o GitHub gera o AAB, e você repete
> **B3 itens 1, 2, 4, 6, 7, 8** (uns 3 minutos).

---

## Passo 5 — Antes de chamar a família: tirar o "soneca" (US$ 7/mês)

1. Render → canto superior direito → **Billing** (ou *Workspace settings →
   Billing*) → cadastre um cartão.
2. **Me avise.** Eu troco `plan: free` por `plan: starter` no `render.yaml`
   e o Render aplica. (Não mude pelo painel: o `render.yaml` desfaria a
   mudança no próximo deploy.)

✅ **Confere:** depois de 30 min sem usar, o app abre na hora (sem esperar
~1 min).

---

## Passo 6 — Convidar as pessoas

- No app: **Perfil → Gerar convite** → **Copiar** → mande por WhatsApp junto
  com o link do passo 4. Cada convite vale **uma pessoa** e **14 dias**.
- Cada pessoa pode ter **até 5 convites ativos** ao mesmo tempo. Gere 5, e
  quando forem usados, gere mais (ou peça para os primeiros convidarem os
  outros).
- Depois de entrar, cada um precisa **pedir amizade** e o outro **aceitar** —
  só amigos veem os posts um do outro.

**Alguém esqueceu a senha?** Configurações → **Moderação** → ícone de chave →
digite o usuário → **Gerar** → mande o código para a pessoa. No app dela:
**Esqueci minha senha** → usuário + código + senha nova. O código vale 24 horas.

**Alguém postou algo que não devia?** As denúncias aparecem em **Moderação**,
com as opções **Descartar**, **Remover post** ou **Suspender**.

---

## Passo 7 — Segurança da sua conta GitHub

- O **token do GitHub** que você me deu expira em 30 dias. Quando expirar (ou
  se quiser cortar antes): GitHub → foto → **Settings** → **Developer
  settings** → **Personal access tokens** → **Fine-grained tokens** → clique
  no token → **Delete**. Se quiser que eu continue fazendo push, gere outro
  igual e me mande.
- Ative a **verificação em duas etapas** no GitHub, Google, Neon e Render, se
  ainda não tiver.

---

## Checklist rápido

- [ ] 1. Neon criado, endereço copiado (sem `-pooler`)
- [ ] 2. Render com `DATABASE_URL` do Neon + `/health` ok + conta recriada
- [ ] 3. Três secrets no GitHub + build com `humannet-aab`
- [ ] 4. Play Console: conta verificada, app criado, teste interno publicado
- [ ] 5. Render Starter (antes da família)
- [ ] 6. Convites enviados
- [ ] 7. Token revogado/renovado, 2FA ligado

Em qualquer passo que travar: tire um print e me mande.

---

## Passo 8 — Versão web para iPhone (GitHub Pages, grátis, 2 min)

A versão web é o mesmo app, publicado em **https://guimvmatos.github.io/humannet/**
a cada push na `main` (job `web` + `pages` do workflow `app`).

1. **https://github.com/guimvmatos/humannet/settings/pages** → em **Build and
   deployment → Source**, escolha **GitHub Actions**. (Só uma vez.)
2. Rode de novo o workflow `app` na `main` (Actions → app → **Run workflow**) ou
   faça qualquer push em `app/`.

✅ **Confere:** abra o endereço no iPhone (Safari) → **Compartilhar** →
**Adicionar à Tela de Início**. O ícone abre o HumanNet em tela cheia.

- A API só aceita chamadas do navegador vindas de `https://guimvmatos.github.io`
  (CORS). Para testar a web em outro endereço (ex.: `http://localhost:8080`),
  defina no Render `CORS_EXTRA_ORIGINS` com esse endereço.
- Notificações push no iPhone ainda não estão ligadas na versão web.
