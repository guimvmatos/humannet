/// Configuração de build. Defina com `--dart-define=API_BASE_URL=https://...`.
///
/// O padrão `10.0.2.2` é o endereço do host visto de dentro do emulador Android.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8080',
);
