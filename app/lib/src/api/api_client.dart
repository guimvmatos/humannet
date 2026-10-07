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

  /// Generoso de propósito: no plano gratuito do Render, a API "dorme" e a
  /// primeira requisição pode levar ~1 min para ela acordar.
  static const Duration _timeout = Duration(seconds: 75);

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

  // ------------------------------------------------------------ perfis

  Future<Profile> profile(String token, String username) async {
    final json = await _send(
      'GET',
      '/v1/users/${Uri.encodeComponent(username)}',
      token: token,
    );
    return Profile.fromJson(json!);
  }

  /// `displayName == ''` remove o nome de exibição; `null` não altera.
  Future<User> updateProfile(
    String token, {
    String? displayName,
    String? bio,
  }) async {
    final json = await _send(
      'PATCH',
      '/v1/me/profile',
      token: token,
      body: {'display_name': ?displayName, 'bio': ?bio},
    );
    return User.fromJson(json!);
  }

  // ------------------------------------------------------------ amizade

  /// Pede amizade, ou aceita se a outra pessoa já pediu. Devolve a relação.
  Future<Relation> requestFriend(String token, String username) async {
    final json = await _send(
      'PUT',
      '/v1/users/${Uri.encodeComponent(username)}/friend',
      token: token,
    );
    return Relation.parse(json?['relation'] as String?);
  }

  /// Desfaz amizade, cancela o pedido enviado ou recusa o recebido.
  Future<void> removeFriend(String token, String username) async {
    await _send(
      'DELETE',
      '/v1/users/${Uri.encodeComponent(username)}/friend',
      token: token,
    );
  }

  Future<List<FriendRequest>> friendRequests(String token) async {
    final json = await _send('GET', '/v1/friend-requests', token: token);
    return (json!['items'] as List<dynamic>)
        .map((e) => FriendRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Author>> friends(String token) async {
    final json = await _send('GET', '/v1/friends', token: token);
    return (json!['items'] as List<dynamic>)
        .map((e) => Author.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ------------------------------------------------------------ posts

  Future<Post> createPost(String token, String body) async {
    final json = await _send(
      'POST',
      '/v1/posts',
      token: token,
      body: {'body': body},
    );
    return Post.fromJson(json!);
  }

  Future<void> deletePost(String token, String id) async {
    await _send('DELETE', '/v1/posts/${Uri.encodeComponent(id)}', token: token);
  }

  /// Feed cronológico: seus amigos + você.
  Future<PostPage> feed(String token, {String? before}) async {
    final json = await _send(
      'GET',
      '/v1/feed',
      token: token,
      query: {'before': ?before},
    );
    return PostPage.fromJson(json!);
  }

  Future<PostPage> userPosts(
    String token,
    String username, {
    String? before,
  }) async {
    final json = await _send(
      'GET',
      '/v1/users/${Uri.encodeComponent(username)}/posts',
      token: token,
      query: {'before': ?before},
    );
    return PostPage.fromJson(json!);
  }

  /// Acorda a API (plano gratuito dorme sem uso). Ignora qualquer erro.
  Future<void> warmUp() async {
    try {
      await _http.get(_baseUri.resolve('/health')).timeout(_timeout);
    } catch (_) {
      // Só um "despertador"; falhas aparecem na próxima chamada real.
    }
  }

  void close() => _http.close();

  Future<Map<String, dynamic>?> _send(
    String method,
    String path, {
    String? token,
    Map<String, Object?>? body,
    Map<String, String>? query,
  }) async {
    var uri = _baseUri.resolve(path);
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }
    final request = http.Request(method, uri);
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
