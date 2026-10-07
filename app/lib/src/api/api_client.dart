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

  // ------------------------------------------------------------ segurança

  Future<void> block(String token, String username) async {
    await _send(
      'PUT',
      '/v1/users/${Uri.encodeComponent(username)}/block',
      token: token,
    );
  }

  Future<void> unblock(String token, String username) async {
    await _send(
      'DELETE',
      '/v1/users/${Uri.encodeComponent(username)}/block',
      token: token,
    );
  }

  Future<List<Author>> blocks(String token) async {
    final json = await _send('GET', '/v1/blocks', token: token);
    return (json!['items'] as List<dynamic>)
        .map((e) => Author.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Denuncia um conteúdo. Informe exatamente um alvo.
  Future<void> report(
    String token, {
    required String reason,
    String? postId,
    String? username,
    String? commentId,
    String? topicId,
    String? replyId,
    String? communitySlug,
    String? testimonialId,
    String details = '',
  }) async {
    final targets = <String, String?>{
      'testimonial': testimonialId,
      'post': postId,
      'user': username,
      'comment': commentId,
      'topic': topicId,
      'reply': replyId,
      'community': communitySlug,
    }..removeWhere((_, v) => v == null);
    assert(targets.length == 1, 'informe exatamente um alvo');
    final kind = targets.keys.single;
    await _send(
      'POST',
      '/v1/reports',
      token: token,
      body: {
        'kind': kind,
        'post_id': ?postId,
        'username': ?username,
        'comment_id': ?commentId,
        'topic_id': ?topicId,
        'reply_id': ?replyId,
        'slug': ?communitySlug,
        'testimonial_id': ?testimonialId,
        'reason': reason,
        'details': details,
      },
    );
  }

  // ------------------------------------------------------------ moderação

  Future<List<AdminReport>> adminReports(String token) async {
    final json = await _send('GET', '/v1/admin/reports', token: token);
    return (json!['items'] as List<dynamic>)
        .map((e) => AdminReport.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `action`: dismiss | remove_content | suspend_user
  Future<void> resolveReport(String token, String id, String action) async {
    await _send(
      'POST',
      '/v1/admin/reports/${Uri.encodeComponent(id)}/resolve',
      token: token,
      body: {'action': action},
    );
  }

  Future<void> unsuspend(String token, String username) async {
    await _send(
      'POST',
      '/v1/admin/users/${Uri.encodeComponent(username)}/unsuspend',
      token: token,
    );
  }

  Future<ResetCode> createResetCode(String token, String username) async {
    final json = await _send(
      'POST',
      '/v1/admin/users/${Uri.encodeComponent(username)}/password-reset',
      token: token,
    );
    return ResetCode.fromJson(json!);
  }

  /// Público: troca a senha com o código gerado por um administrador.
  Future<void> resetPassword({
    required String username,
    required String code,
    required String newPassword,
  }) async {
    await _send(
      'POST',
      '/v1/auth/reset-password',
      body: {'username': username, 'code': code, 'new_password': newPassword},
    );
  }

  // ------------------------------------------------------------ conta

  Future<void> changePassword(
    String token, {
    required String currentPassword,
    required String newPassword,
  }) async {
    await _send(
      'PUT',
      '/v1/me/password',
      token: token,
      body: {'current_password': currentPassword, 'new_password': newPassword},
    );
  }

  /// Exclusão definitiva da conta. Exige a senha.
  Future<void> deleteAccount(String token, String password) async {
    await _send('DELETE', '/v1/me', token: token, body: {'password': password});
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

  Future<void> like(String token, String postId) async {
    await _send(
      'PUT',
      '/v1/posts/${Uri.encodeComponent(postId)}/like',
      token: token,
    );
  }

  Future<void> unlike(String token, String postId) async {
    await _send(
      'DELETE',
      '/v1/posts/${Uri.encodeComponent(postId)}/like',
      token: token,
    );
  }

  Future<List<Comment>> comments(String token, String postId) async {
    final json = await _send(
      'GET',
      '/v1/posts/${Uri.encodeComponent(postId)}/comments',
      token: token,
    );
    return (json!['items'] as List<dynamic>)
        .map((e) => Comment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Comment> addComment(String token, String postId, String body) async {
    final json = await _send(
      'POST',
      '/v1/posts/${Uri.encodeComponent(postId)}/comments',
      token: token,
      body: {'body': body},
    );
    return Comment.fromJson(json!);
  }

  Future<void> deleteComment(String token, String commentId) async {
    await _send(
      'DELETE',
      '/v1/comments/${Uri.encodeComponent(commentId)}',
      token: token,
    );
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

  // ------------------------------------------------------------ comunidades

  String _c(String slug) => '/v1/communities/${Uri.encodeComponent(slug)}';

  Future<List<CommunityItem>> communities(
    String token, {
    String? query,
    String? theme,
    bool mine = false,
  }) async {
    final json = await _send(
      'GET',
      '/v1/communities',
      token: token,
      query: {
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        'theme': ?theme,
        if (mine) 'mine': 'true',
      },
    );
    return (json!['items'] as List<dynamic>)
        .map((e) => CommunityItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Community> community(String token, String slug) async {
    final json = await _send('GET', _c(slug), token: token);
    return Community.fromJson(json!);
  }

  Future<Community> createCommunity(
    String token, {
    required String name,
    required String theme,
    required String visibility,
    String description = '',
    String rules = '',
  }) async {
    final json = await _send(
      'POST',
      '/v1/communities',
      token: token,
      body: {
        'name': name,
        'theme': theme,
        'visibility': visibility,
        'description': description,
        'rules': rules,
      },
    );
    return Community.fromJson(json!);
  }

  Future<Community> updateCommunity(
    String token,
    String slug, {
    String? name,
    String? description,
    String? rules,
    String? theme,
    String? visibility,
  }) async {
    final json = await _send(
      'PATCH',
      _c(slug),
      token: token,
      body: {
        'name': ?name,
        'description': ?description,
        'rules': ?rules,
        'theme': ?theme,
        'visibility': ?visibility,
      },
    );
    return Community.fromJson(json!);
  }

  Future<void> deleteCommunity(String token, String slug) async {
    await _send('DELETE', _c(slug), token: token);
  }

  /// Entra (pública) ou pede para entrar (fechada). Devolve active | pending.
  Future<String> joinCommunity(String token, String slug) async {
    final json = await _send('PUT', '${_c(slug)}/membership', token: token);
    return json!['status'] as String;
  }

  Future<void> leaveCommunity(String token, String slug) async {
    await _send('DELETE', '${_c(slug)}/membership', token: token);
  }

  /// `status`: active | pending | banned
  Future<List<Member>> members(
    String token,
    String slug, {
    String status = 'active',
  }) async {
    final json = await _send(
      'GET',
      '${_c(slug)}/members',
      token: token,
      query: {'status': status},
    );
    return (json!['items'] as List<dynamic>)
        .map((e) => Member.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// approve | reject | ban | unban | promote | demote | transfer
  Future<void> memberAction(
    String token,
    String slug,
    String username,
    String action,
  ) async {
    await _send(
      'POST',
      '${_c(slug)}/members/${Uri.encodeComponent(username)}',
      token: token,
      body: {'action': action},
    );
  }

  Future<Paged<Topic>> topics(
    String token,
    String slug, {
    String? before,
  }) async {
    final json = await _send(
      'GET',
      '${_c(slug)}/topics',
      token: token,
      query: {'before': ?before},
    );
    return Paged.fromJson(json!, Topic.fromJson);
  }

  Future<Topic> createTopic(
    String token,
    String slug, {
    required String title,
    String body = '',
  }) async {
    final json = await _send(
      'POST',
      '${_c(slug)}/topics',
      token: token,
      body: {'title': title, 'body': body},
    );
    return Topic.fromJson(json!);
  }

  Future<Topic> topic(String token, String id) async {
    final json = await _send(
      'GET',
      '/v1/topics/${Uri.encodeComponent(id)}',
      token: token,
    );
    return Topic.fromJson(json!);
  }

  Future<void> updateTopic(
    String token,
    String id, {
    bool? pinned,
    bool? locked,
  }) async {
    await _send(
      'PATCH',
      '/v1/topics/${Uri.encodeComponent(id)}',
      token: token,
      body: {'pinned': ?pinned, 'locked': ?locked},
    );
  }

  Future<void> deleteTopic(String token, String id) async {
    await _send(
      'DELETE',
      '/v1/topics/${Uri.encodeComponent(id)}',
      token: token,
    );
  }

  Future<Paged<Reply>> replies(
    String token,
    String topicId, {
    String? after,
  }) async {
    final json = await _send(
      'GET',
      '/v1/topics/${Uri.encodeComponent(topicId)}/replies',
      token: token,
      query: {'after': ?after},
    );
    return Paged.fromJson(json!, Reply.fromJson);
  }

  Future<Reply> addReply(String token, String topicId, String body) async {
    final json = await _send(
      'POST',
      '/v1/topics/${Uri.encodeComponent(topicId)}/replies',
      token: token,
      body: {'body': body},
    );
    return Reply.fromJson(json!);
  }

  Future<void> deleteReply(String token, String id) async {
    await _send(
      'DELETE',
      '/v1/replies/${Uri.encodeComponent(id)}',
      token: token,
    );
  }

  // ------------------------------------------------------------ depoimentos

  Future<List<Testimonial>> testimonials(String token, String username) async {
    final json = await _send(
      'GET',
      '/v1/users/${Uri.encodeComponent(username)}/testimonials',
      token: token,
    );
    return (json!['items'] as List<dynamic>)
        .map((e) => Testimonial.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Testimonial>> pendingTestimonials(String token) async {
    final json = await _send('GET', '/v1/me/testimonials/pending', token: token);
    return (json!['items'] as List<dynamic>)
        .map((e) => Testimonial.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Escreve (ou reescreve) o meu depoimento sobre um amigo.
  Future<Testimonial> writeTestimonial(
    String token,
    String username,
    String body,
  ) async {
    final json = await _send(
      'PUT',
      '/v1/users/${Uri.encodeComponent(username)}/testimonial',
      token: token,
      body: {'body': body},
    );
    return Testimonial.fromJson(json!);
  }

  Future<void> approveTestimonial(String token, String id) async {
    await _send(
      'POST',
      '/v1/testimonials/${Uri.encodeComponent(id)}/approve',
      token: token,
    );
  }

  Future<void> deleteTestimonial(String token, String id) async {
    await _send(
      'DELETE',
      '/v1/testimonials/${Uri.encodeComponent(id)}',
      token: token,
    );
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
