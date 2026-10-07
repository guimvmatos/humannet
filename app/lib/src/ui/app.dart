import 'package:flutter/material.dart';

import '../auth/session_controller.dart';
import '../theme/theme_controller.dart';
import 'cpf.dart';
import 'home_shell.dart';
import 'login_screen.dart';

class HumanNetApp extends StatefulWidget {
  const HumanNetApp({super.key, required this.session, this.themes});

  final SessionController session;

  /// Tema escolhido. Sem ele (testes), usa o padrão em memória.
  final ThemeController? themes;

  @override
  State<HumanNetApp> createState() => _HumanNetAppState();
}

class _HumanNetAppState extends State<HumanNetApp> {
  late final ThemeController _themes =
      widget.themes ?? ThemeController(InMemoryPrefsStore());

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return ListenableBuilder(
      listenable: _themes,
      builder: (context, _) => ThemeScope(
        controller: _themes,
        child: MaterialApp(
          title: 'HumanNet',
          debugShowCheckedModeBanner: false,
          theme: _themes.light,
          darkTheme: _themes.dark,
          themeMode: _themes.mode,
          home: ListenableBuilder(
            listenable: session,
            builder: (context, _) => switch (session.status) {
              SessionStatus.unknown => const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              ),
              SessionStatus.signedOut => LoginScreen(session: session),
              SessionStatus.signedIn when session.user?.needsCpf ?? false =>
                CpfScreen(session: session),
              SessionStatus.signedIn => HomeShell(session: session),
            },
          ),
        ),
      ),
    );
  }
}
