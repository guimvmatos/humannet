# HumanNet: app

App Flutter. Começa só em Android.

## Primeira vez

```bash
flutter pub get
./tool/setup_android.sh   # gera android/ e aplica os ajustes; depois faça commit de android/
```

O script faz três ajustes:

- adiciona a permissão de internet ao build de release;
- em **debug**, permite HTTP sem TLS **só** para `10.0.2.2`, `localhost` e `127.0.0.1`;
- define minSdk 24, exigido pelo `flutter_secure_storage`.

## Rodar

```bash
# Emulador, com a API rodando no host:
flutter run

# Celular físico na mesma rede (troque pelo IP do seu computador).
# O IP não está na lista de HTTP permitido; use um túnel HTTPS
# (ex.: cloudflared ou ngrok) e passe a URL:
flutter run --dart-define=API_BASE_URL=https://seu-tunel.example
```

## Estrutura

```
lib/
  main.dart                 monta as dependências
  src/config.dart           API_BASE_URL (dart-define)
  src/api/                  cliente HTTP e modelos (o único lugar que usa http)
  src/auth/                 SessionController (estado de login) e TokenStore
  src/ui/                   telas
test/
  fake_backend.dart         API falsa para testes
```

## Antes de commitar

```bash
dart format lib test && flutter analyze && flutter test
```
