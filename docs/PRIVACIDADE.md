# Política de Privacidade — HumanNet (beta fechado)

Última atualização: 8 de outubro de 2026

A HumanNet é uma rede social em teste, só para convidados. Este texto explica,
de forma direta, o que guardamos sobre você e por quê.

> Rascunho escrito para o beta com amigos e família. Antes de abrir para o
> público, revisar com alguém da área jurídica (LGPD).

## Quem é o responsável

Guilherme Matos, pessoa física, desenvolvedor do app.
Contato: **CONTATO@EXEMPLO** (substituir pelo e-mail de contato).

## O que guardamos

| Dado | Para quê |
|---|---|
| Nome de usuário, e-mail e senha (guardada só como hash Argon2id, nunca em texto) | Criar a conta e entrar |
| Nome de exibição e bio | Mostrar seu perfil para seus amigos |
| Posts, comentários e curtidas | É o conteúdo que você publica |
| Amizades, pedidos de amizade e bloqueios | Decidir quem vê o quê |
| Denúncias que você faz ou recebe (com uma cópia do conteúdo denunciado) | Moderação e segurança |
| Sessões de login (só um resumo criptográfico do token) | Manter você conectado |
| CPF — **não guardamos o número**, só um código criptográfico (HMAC) que não dá para reverter | Garantir uma conta por pessoa |
| Fotos que você publica (sem localização: o servidor apaga os metadados) | Posts, foto de perfil e Foto do dia |
| Recados, depoimentos, status, cidade natal/atual e escola (opcionais) | Perfil e sugestão de amigos |

**Não** coletamos localização, contatos, fotos do aparelho, identificador de
publicidade nem dados de navegação. **Não** há anúncios, **não** vendemos
dados e **não** usamos algoritmo de recomendação: o feed é cronológico, só
com seus amigos.

O endereço IP de quem tenta entrar fica apenas na memória do servidor, por
até 15 minutos, para bloquear tentativas repetidas de adivinhar senha.

## Quem vê o seu conteúdo

Só você e seus amigos (amizade mútua, aceita pelos dois). Pessoas que você
bloqueou não encontram seu perfil nem seu conteúdo. O administrador do beta
pode ver conteúdo **denunciado**, para moderação.

## Onde os dados ficam

Em servidores contratados pela HumanNet nos Estados Unidos: Render (servidor
da API) e Neon (banco de dados). A conexão do app com o servidor é sempre
criptografada (HTTPS).

## Por quanto tempo

Enquanto sua conta existir. Posts e comentários apagados deixam de aparecer na
hora.

## Como excluir sua conta

No app: **Perfil → ícone de engrenagem → Excluir conta**, confirmando a senha.
A exclusão é imediata e definitiva: perfil, posts, comentários, curtidas,
amizades, pedidos, bloqueios e sessões são apagados. Denúncias que você fez
continuam existindo, mas sem ligação com você. Cópias de segurança do banco
se renovam e somem em até 7 dias.

Se não conseguir entrar no app, peça a exclusão pelo e-mail de contato acima.

## Seus direitos (LGPD)

Você pode pedir acesso, correção ou exclusão dos seus dados pelo e-mail de
contato. Respondemos em até 15 dias.

## Idade mínima

A HumanNet é para maiores de 18 anos durante o beta.

## Mudanças

Se esta política mudar, avisamos no app antes de a mudança valer.
