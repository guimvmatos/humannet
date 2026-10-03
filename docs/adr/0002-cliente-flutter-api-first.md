# ADR-0002: Cliente Flutter, API primeiro

- **Status:** aceito
- **Data:** 2026-10-03

## Contexto

O público-alvo inicial é brasileiro, onde o uso de redes sociais é majoritariamente mobile e em Android. Mais adiante, a verificação facial e o check-in por QR usam a câmera. iOS e web são desejáveis, mas não são prioridade.

## Decisão

- O cliente é um **app Flutter**, lançado primeiro para **Android**.
- Toda a lógica de negócio e de autorização fica na **API**. O app é um cliente dela.
- O contrato da API é versionado por prefixo (`/v1`). Mudanças que quebram compatibilidade criam `/v2`.
- **Estado no app:** começa com `ChangeNotifier` do próprio Flutter, sem framework de estado. Reavaliar (Riverpod) quando houver mais de ~5 telas com estado compartilhado.
- **Token de sessão:** guardado com `flutter_secure_storage` (Android Keystore).

## Alternativas consideradas

| Opção | Por que não |
|---|---|
| Kotlin + Compose (nativo) | É a melhor qualidade no Android, mas iOS exigiria reescrever tudo. |
| React Native / Expo | Viável. Flutter foi escolhido pela renderização consistente e pelo build de APK simples no Linux. |
| Web primeiro | Atrito menor para o usuário experimentar, mas não combina com o uso mobile nem com a câmera. |

## Consequências

- Um só código para Android agora, e para iOS e web depois.
- A equipe precisa aprender Dart.
- Links públicos (convites, eventos) vão precisar de uma web mínima numa fase posterior.
- Publicar no Play exige teste fechado com testadores antes da produção.
