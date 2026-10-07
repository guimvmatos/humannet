import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import 'token_store.dart';

enum SessionStatus { unknown, signedOut, signedIn }

/// Estado de autenticação do app. Única fonte da verdade sobre "quem está logado".
class SessionController extends ChangeNotifier {
  SessionController({required ApiClient api, required TokenStore tokenStore})
    : _api = api,
      _tokens = tokenStore;

  final ApiClient _api;
  final TokenStore _tokens;

  SessionStatus _status = SessionStatus.unknown;
  User? _user;
  String? _token;

  SessionStatus get status => _status;
  User? get user => _user;
  ApiClient get api => _api;

  /// Token atual, para chamadas autenticadas feitas por outras telas.
  String? get token => _token;

  /// Tenta restaurar a sessão salva. Token inválido/expirado é descartado.
  /// Falha de rede mantém o usuário deslogado sem apagar o token.
  Future<void> restore() async {
    final saved = await _tokens.read();
    if (saved == null) {
      _set(SessionStatus.signedOut);
      return;
    }
    try {
      _user = await _api.me(saved);
      _token = saved;
      _set(SessionStatus.signedIn);
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await _tokens.clear();
      }
      _set(SessionStatus.signedOut);
    } catch (_) {
      // Resposta inesperada: não trava o app na tela de carregamento.
      _set(SessionStatus.signedOut);
    }
  }

  Future<void> login({required String login, required String password}) async {
    final result = await _api.login(login: login, password: password);
    await _signIn(result);
  }

  Future<void> register({
    required String inviteCode,
    required String username,
    required String email,
    required String password,
    String? cpf,
  }) async {
    final result = await _api.register(
      inviteCode: inviteCode,
      username: username,
      email: email,
      password: password,
      cpf: cpf,
    );
    await _signIn(result);
  }

  /// Desloga localmente mesmo se a chamada à API falhar.
  Future<void> logout() async {
    final token = _token;
    if (token != null) {
      try {
        await _api.logout(token);
      } on ApiException {
        // A sessão expira no servidor de qualquer forma.
      }
    }
    await _tokens.clear();
    _token = null;
    _user = null;
    _set(SessionStatus.signedOut);
  }

  /// Atualiza os dados locais do usuário (ex.: após editar o perfil).
  /// Recarrega o próprio usuário (ex.: depois de informar o CPF).
  Future<void> refreshUser() async {
    final token = _token;
    if (token == null) return;
    _user = await _api.me(token);
    notifyListeners();
  }

  void updateUser(User user) {
    _user = user;
    notifyListeners();
  }

  Future<void> _signIn(AuthResult result) async {
    await _tokens.write(result.token);
    _token = result.token;
    _user = result.user;
    _set(SessionStatus.signedIn);
  }

  void _set(SessionStatus status) {
    _status = status;
    notifyListeners();
  }
}
