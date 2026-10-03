import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Erro devolvido pela API (`{"error": "<code>"}`) ou falha de rede.
class ApiException implements Exception {
  const ApiException(this.code, {this.statusCode});

  /// Código estável da API (ex.: `invalid_credentials`) ou `network_error`.
  final String code;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'ApiException($code, status: $statusCode)';
}

/// Cliente HTTP da HumanNet. Widgets nunca chamam `http` diretamente.
class ApiClient {
  ApiClient({required String baseUrl, http.Client? httpClient})
    : _baseUri = Uri.parse(baseUrl),
      _http = httpClient ?? http.Client();

  static const Duration _timeout = Duration(seconds: 15);

  final Uri _baseUri;
  final http.Client _http;

  Future<AuthResult> register({
    required String inviteCode,
    required String username,
    required String email,
    required String password,
  }) async {
    final json = await _send(
      'POST',
      '/v1/auth/register',
      body: {
        'invite_code': inviteCode,
        'username': username,
        'email': email,
        'password': password,
      },
    );
    return AuthResult.fromJson(json!);
  }

  Future<AuthResult> login({
    required String login,
    required String password,
  }) async {
    final json = await _send(
      'POST',
      '/v1/auth/login',
      body: {'login': login, 'password': password},
    );
    return AuthResult.fromJson(json!);
  }

  Future<void> logout(String token) async {
    await _send('POST', '/v1/auth/logout', token: token);
  }

  Future<User> me(String token) async {
    final json = await _send('GET', '/v1/me', token: token);
    return User.fromJson(json!);
  }

  Future<InviteCreated> createInvite(String token) async {
    final json = await _send('POST', '/v1/invites', token: token);
    return InviteCreated.fromJson(json!);
  }

  void close() => _http.close();

  Future<Map<String, dynamic>?> _send(
    String method,
    String path, {
    String? token,
    Map<String, Object?>? body,
  }) async {
    final request = http.Request(method, _baseUri.resolve(path));
    request.headers['Accept'] = 'application/json';
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      final streamed = await _http.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ApiException('network_error');
    } on http.ClientException {
      throw const ApiException('network_error');
    }

    final status = response.statusCode;
    final decoded = response.body.isEmpty ? null : _tryDecode(response.body);

    if (status >= 200 && status < 300) {
      return decoded;
    }
    final code = decoded?['error'];
    throw ApiException(
      code is String ? code : 'http_$status',
      statusCode: status,
    );
  }

  static Map<String, dynamic>? _tryDecode(String body) {
    try {
      final value = jsonDecode(body);
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    }
  }
}
