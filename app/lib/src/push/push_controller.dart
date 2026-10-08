import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../auth/session_controller.dart';
import '../config.dart';

/// Notificações push (Firebase Cloud Messaging).
///
/// Com o app fechado ou em segundo plano, o Android mostra o aviso sozinho.
/// Com o app aberto, só atualiza as bolinhas. Tocar no aviso chama [onOpen]
/// com o tipo (`message`, `friend_request`, ...) e o id do alvo.
class PushController {
  PushController({
    required this.session,
    required this.onForeground,
    required this.onOpen,
  });

  final SessionController session;
  final void Function() onForeground;
  final void Function(String kind, String id) onOpen;

  String? _deviceToken;
  final List<StreamSubscription<Object?>> _subs = [];
  bool _started = false;

  Future<void> start() async {
    if (!pushEnabled || _started) return;
    _started = true;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      final fm = FirebaseMessaging.instance;
      // Android 13+: pede a permissão de notificações.
      final perm = await fm.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      final t = await fm.getToken();
      if (t != null) await _register(t);
      _subs
        ..add(fm.onTokenRefresh.listen(_register))
        ..add(FirebaseMessaging.onMessage.listen((_) => onForeground()))
        ..add(FirebaseMessaging.onMessageOpenedApp.listen(_open));
      session.beforeLogout = forget;
      final initial = await fm.getInitialMessage();
      if (initial != null) _open(initial);
    } catch (_) {
      // Push é um extra: sem ele o app funciona (bolinhas a cada minuto).
    }
  }

  Future<void> _register(String deviceToken) async {
    _deviceToken = deviceToken;
    final token = session.token;
    if (token == null) return;
    try {
      await session.api.registerDevice(token, deviceToken);
    } catch (_) {
      // Tenta de novo na próxima abertura do app.
    }
  }

  void _open(RemoteMessage m) {
    final kind = m.data['kind'];
    final id = m.data['id'];
    onOpen(kind is String ? kind : '', id is String ? id : '');
  }

  /// Ao sair da conta: este aparelho deixa de receber os avisos dela.
  Future<void> forget() async {
    _cancel();
    final deviceToken = _deviceToken;
    final token = session.token;
    if (deviceToken != null && token != null) {
      await session.api.unregisterDevice(token, deviceToken);
    }
    await FirebaseMessaging.instance.deleteToken();
  }

  void _cancel() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
  }

  void dispose() {
    _cancel();
    if (session.beforeLogout == forget) session.beforeLogout = null;
  }
}
