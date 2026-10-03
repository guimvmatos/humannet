# Backlog e ideias

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
