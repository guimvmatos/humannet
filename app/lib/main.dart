import 'package:flutter/material.dart';

import 'src/api/api_client.dart';
import 'src/auth/session_controller.dart';
import 'src/auth/token_store.dart';
import 'src/config.dart';
import 'src/ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final session = SessionController(
    api: ApiClient(baseUrl: apiBaseUrl),
    tokenStore: SecureTokenStore(),
  );
  runApp(HumanNetApp(session: session));
  // Restaura a sessão em segundo plano; a UI mostra um carregando até lá.
  session.restore().ignore();
}
