# Política de Privacidade do HumanNet

Versão 2 — 11 de outubro de 2026 (inclui "Quem visitou meu perfil" e "Baixar meus dados")

Esta política explica quais dados o HumanNet trata, por quê, com quem compartilha e quais são os seus direitos pela Lei Geral de Proteção de Dados (LGPD, Lei 13.709/2018).

## 1. Controlador e contato

- **Controlador:** Guilherme Matos, pessoa física, responsável pelo HumanNet em fase de teste (beta).
- **Encarregado e canal para pedidos de dados:** guimvmatos@gmail.com.

## 2. Princípio: o mínimo necessário

- Não vendemos dados, não mostramos anúncios e não usamos tempo de tela para ordenar nada.
- O perfil de interesses do "Para você" é calculado e guardado **só no seu celular**. O servidor não recebe.

## 3. Dados que tratamos

| Dado | Para quê | Base legal (LGPD) |
|---|---|---|
| Nome de usuário, e-mail, senha (guardada só como hash Argon2) | Criar e proteger a conta | Execução do contrato (art. 7º, V) |
| CPF (guardamos só um código irreversível, HMAC; o número não fica salvo) | Garantir uma pessoa, uma conta | Execução do contrato e legítimo interesse na segurança (art. 7º, V e IX) |
| Perfil: nome de exibição, bio, foto, cidade natal, cidade, escola | Mostrar seu perfil | Execução do contrato |
| Linha do tempo (cidades, escolas, faculdade e curso, trabalhos, anos) | Mostrar no perfil e sugerir amigos, conforme a visibilidade que você escolhe em cada item | Execução do contrato |
| Posts, fotos, comentários, curtidas, recados, depoimentos, comunidades, eventos e páginas | Fazer a rede social funcionar | Execução do contrato |
| Mensagens | Entregar as conversas | Execução do contrato |
| Área aproximada dos posts | Mostrar o post no feed Regional de quem está perto | Execução do contrato |
| Token de notificação do aparelho | Enviar avisos (sem conteúdo das mensagens) | Consentimento, dado na permissão do Android |
| Visitas ao seu perfil (quem abriu e em que dia) | "Quem visitou meu perfil" | Legítimo interesse (art. 7º, IX), com opção de desligar a qualquer momento |
| Denúncias e decisões de moderação | Segurança da comunidade | Legítimo interesse e cumprimento de obrigação legal (art. 7º, II e IX) |
| Registros técnicos (endereço IP, data e hora) | Segurança, limite de tentativas de login e obrigações do Marco Civil | Cumprimento de obrigação legal e legítimo interesse |

**Fotos:** antes de guardar, o servidor recodifica cada foto **sem metadados** (inclusive GPS).

**Mensagens:** ainda **não** têm criptografia de ponta a ponta. Ficam legíveis no servidor, que é como a moderação consegue agir sobre denúncias. Avisaremos se isso mudar.

## 4. Localização

- **Seus posts:** ao publicar, o app manda a posição aproximada do aparelho. O servidor **desloca até cerca de 1,5 km**, numa direção sorteada uma vez, arredonda para uma área de ~500 m e só guarda o resultado. A posição real não é guardada. A distância nunca aparece para ninguém. Se você negar a localização, o post sai do mesmo jeito, só fora do Regional.
- **Feed Regional:** quando você lê, sua posição vai ao servidor só para aquela consulta, arredondada, e **não é guardada**.
- **Mapa de eventos:** usa a posição do aparelho só para centralizar o mapa, no próprio celular.
- **Páginas de lugares:** o endereço que o administrador informa é público e vira um ponto no mapa.

## 4.1 Quem visitou meu perfil

- Vem **ligado**. Quando você abre o perfil de alguém que também participa, essa pessoa vê que você visitou e em que **dia** (sem a hora). Abrir posts no feed não conta.
- É **recíproco**: se você desligar (Configurações → Quem visitou meu perfil), deixa de ver quem te visitou **e** deixa de aparecer para os outros. Ao desligar, as visitas guardadas (feitas e recebidas) são apagadas.
- Cada visita fica guardada por no máximo **30 dias**. Não há notificação nem contador.
- Pessoas com bloqueio entre si nunca aparecem uma para a outra.

## 5. Dados sensíveis

- Não pedimos raça, religião, saúde, orientação sexual nem opinião política.
- O "Para você" pode aprender detalhes sobre Política **só se você ligar essa opção**, e esse aprendizado fica **só no seu celular**. Desligar apaga o que foi aprendido.

## 6. Com quem compartilhamos

Usamos fornecedores (operadores) que processam dados em nosso nome, alguns **fora do Brasil** (transferência internacional, art. 33):

- **Render** (EUA): servidor do app.
- **Neon** (EUA, em infraestrutura da AWS): banco de dados e armazenamento de fotos.
- **Google Firebase Cloud Messaging** (EUA): entrega das notificações.
- **OpenStreetMap** (Reino Unido): imagens do mapa, buscadas pelo app (seu IP chega a eles), e conversão do endereço das páginas em ponto no mapa, feita pelo servidor.
- **ViaCEP** (Brasil): preenchimento do endereço das páginas a partir do CEP.

Além disso, só compartilhamos dados com autoridades quando houver ordem judicial ou obrigação legal.

## 7. Por quanto tempo guardamos

- Enquanto a conta existir.
- **Excluir a conta** (Configurações) apaga de forma definitiva o perfil, posts, fotos, comentários, amizades, linha do tempo e sessões. Páginas que você administra passam para outro administrador ou saem do ar.
- Mensagens que você já enviou continuam na conversa de quem recebeu, mas **sem o seu nome**, como uma carta já entregue.
- Denúncias feitas por você ficam anônimas; denúncias contra você podem ser mantidas para segurança da comunidade.
- Sessões de login expiram em 30 dias.
- Cópias de segurança do banco podem manter dados apagados por um período curto, até serem substituídas.

## 8. Seus direitos (art. 18)

Você pode pedir: confirmação e acesso aos dados, correção, anonimização ou eliminação, portabilidade, informação sobre compartilhamento, e revogação de consentimento. Muitas coisas você mesmo faz no app: **Configurações → Minha atividade** mostra e apaga seus posts, comentários, curtidas, recados e depoimentos, e o botão **Baixar meus dados** gera um arquivo com tudo o que é seu (portabilidade). Também dá para editar o perfil, ajustar a linha do tempo, desligar a localização ou as notificações no Android e excluir a conta. Para o resto, escreva para guimvmatos@gmail.com. Você também pode reclamar à ANPD (gov.br/anpd).

## 9. Segurança

Senhas com hash Argon2, conexões com HTTPS, CPF guardado só como código irreversível, fotos sem metadados e limite de tentativas de login. Nenhum sistema é 100% seguro; se houver incidente relevante, avisaremos você e a ANPD.

## 10. Idade

O HumanNet é só para maiores de 18 anos durante o beta. Se soubermos de uma conta de menor, ela será encerrada.

## 11. Mudanças

Se esta política mudar de forma importante, o app pede um novo aceite antes de você continuar.
