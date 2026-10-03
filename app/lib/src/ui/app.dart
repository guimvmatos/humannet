import 'package:flutter/material.dart';

import '../auth/session_controller.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class HumanNetApp extends StatelessWidget {
  const HumanNetApp({super.key, required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3D6B5A);
    return MaterialApp(
      title: 'HumanNet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed),
      darkTheme: ThemeData(
        colorSchemeSeed: seed,
        brightness: Brightness.dark,
      ),
      home: ListenableBuilder(
        listenable: session,
        builder: (context, _) => switch (session.status) {
          SessionStatus.unknown => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          SessionStatus.signedOut => LoginScreen(session: session),
          SessionStatus.signedIn => HomeScreen(session: session),
        },
      ),
    );
  }
}
