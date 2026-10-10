import 'package:flutter/material.dart';

import 'src/api/api_client.dart';
import 'src/auth/session_controller.dart';
import 'src/auth/token_store.dart';
import 'src/config.dart';
import 'src/feed/interests.dart';
import 'src/theme/theme_controller.dart';
import 'src/ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient(baseUrl: apiBaseUrl);
  // Começa a acordar a API enquanto o usuário vê a tela de login.
  api.warmUp().ignore();
  final session = SessionController(
    api: api,
    tokenStore: SecureTokenStore(),
    interests: InterestProfile(SecurePrefsStore()),
  );
  final themes = ThemeController(SecurePrefsStore());
  // Carrega o tema salvo; até lá, mostra o padrão.
  themes.load().ignore();
  runApp(HumanNetApp(session: session, themes: themes));
  // Restaura a sessão em segundo plano; a UI mostra um carregando até lá.
  session.restore().ignore();
}
