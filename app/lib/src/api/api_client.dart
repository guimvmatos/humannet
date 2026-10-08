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
    String? cpf,
  }) async {
    final json = await _send(
      'POST',
      '/v1/auth/register',
      body: {
        'invite_code': inviteCode,
        'username': username,
        'email': email,
        'password': password,
        'cpf': ?cpf,
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

  /// `''` remove o campo; `null` não altera.
  Future<User> updateProfile(
    String token, {
    String? displayName,
    String? bio,
    String? hometown,
    String? city,
    String? school,
  }) async {
    final json = await _send(
      'PATCH',
      '/v1/me/profile',
      token: token,
      body: {
        'display_name': ?displayName,
        'bio': ?bio,
        'hometown': ?hometown,
        'city': ?city,
        'school': ?school,
      },
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
    String? scrapId,
    String? placeSlug,
    String? eventId,
    String? messageId,
    String details = '',
  }) async {
    final targets = <String, String?>{
      'message': messageId,
      'page': placeSlug,
      'event': eventId,
      'scrap': scrapId,
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
        'slug': ?(communitySlug ?? placeSlug),
        'event_id': ?eventId,
        'message_id': ?messageId,
        'testimonial_id': ?testimonialId,
        'scrap_id': ?scrapId,
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

  /// Contas antigas informam o CPF uma vez (o servidor guarda só um código).
  Future<void> setCpf(String token, String cpf) async {
    await _send('PUT', '/v1/me/cpf', token: token, body: {'cpf': cpf});
  }

  /// Admin: tira o CPF de uma conta (ex.: usado por outra pessoa).
  Future<void> releaseCpf(String token, String username) async {
    await _send(
      'POST',
      '/v1/admin/users/${Uri.encodeComponent(username)}/release-cpf',
      token: token,
    );
  }

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

  Future<Post> createPost(
    String token,
    String body, {
    List<String> mediaIds = const [],
  }) async {
    final json = await _send(
      'POST',
      '/v1/posts',
      token: token,
      body: {'body': body, if (mediaIds.isNotEmpty) 'media_ids': mediaIds},
    );
    return Post.fromJson(json!);
  }

  // ------------------------------------------------------------ fotos

  /// Envia uma foto. `kind`: post | avatar | daily. O servidor recodifica
  /// (sem metadados) e devolve o id para usar no post/avatar/Foto do dia.
  Future<MediaRef> uploadMedia(
    String token,
    String kind,
    List<int> bytes,
  ) async {
    final uri = _baseUri
        .resolve('/v1/media')
        .replace(queryParameters: {'kind': kind});
    final request = http.Request('POST', uri)
      ..headers['Accept'] = 'application/json'
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/octet-stream'
      ..bodyBytes = bytes;
    final json = await _execute(request);
    return MediaRef.fromJson(json!);
  }

  Future<MediaRef> setAvatar(String token, String mediaId) async {
    final json = await _send(
      'PUT',
      '/v1/me/avatar',
      token: token,
      body: {'media_id': mediaId},
    );
    return MediaRef.fromJson(json!);
  }

  Future<void> deleteAvatar(String token) async {
    await _send('DELETE', '/v1/me/avatar', token: token);
  }

  Future<DailyPhoto> setDailyPhoto(
    String token,
    String mediaId, {
    String caption = '',
  }) async {
    final json = await _send(
      'PUT',
      '/v1/me/daily-photo',
      token: token,
      body: {'media_id': mediaId, 'caption': caption},
    );
    return DailyPhoto.fromJson(json!);
  }

  Future<void> deleteDailyPhoto(String token) async {
    await _send('DELETE', '/v1/me/daily-photo', token: token);
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

  // ------------------------------------------------------------ mensagens

  String _c2(String id) => '/v1/conversations/${Uri.encodeComponent(id)}';

  Future<List<Conversation>> conversations(String token) async {
    final json = await _send('GET', '/v1/conversations', token: token);
    return (json!['items'] as List<dynamic>)
        .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Conversation> conversation(String token, String id) async =>
      Conversation.fromJson((await _send('GET', _c2(id), token: token))!);

  /// Abre (ou cria) a conversa 1:1 com um amigo.
  Future<Conversation> directConversation(String token, String username) async {
    final json = await _send(
      'POST',
      '/v1/conversations/direct',
      token: token,
      body: {'username': username},
    );
    return Conversation.fromJson(json!);
  }

  Future<Conversation> createGroup(
    String token,
    String title,
    List<String> usernames,
  ) async {
    final json = await _send(
      'POST',
      '/v1/conversations',
      token: token,
      body: {'title': title, 'usernames': usernames},
    );
    return Conversation.fromJson(json!);
  }

  Future<void> addToGroup(
    String token,
    String id,
    List<String> usernames,
  ) async {
    await _send(
      'POST',
      '${_c2(id)}/members',
      token: token,
      body: {'usernames': usernames},
    );
  }

  Future<List<Author>> conversationMembers(String token, String id) async {
    final json = await _send('GET', '${_c2(id)}/members', token: token);
    return (json!['items'] as List<dynamic>)
        .map((e) => Author.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> leaveGroup(String token, String id) async {
    await _send('DELETE', '${_c2(id)}/members/me', token: token);
  }

  /// Em ordem cronológica. `before`: mais antigas; `after`: só as novas.
  Future<Paged<ChatMessage>> chatMessages(
    String token,
    String id, {
    String? before,
    String? after,
  }) async {
    final json = await _send(
      'GET',
      '${_c2(id)}/messages',
      token: token,
      query: {'before': ?before, 'after': ?after},
    );
    return Paged.fromJson(json!, ChatMessage.fromJson);
  }

  Future<ChatMessage> sendMessage(String token, String id, String body) async {
    final json = await _send(
      'POST',
      '${_c2(id)}/messages',
      token: token,
      body: {'body': body},
    );
    return ChatMessage.fromJson(json!);
  }

  Future<void> markRead(String token, String id) async {
    await _send('POST', '${_c2(id)}/read', token: token);
  }

  Future<void> deleteMessage(String token, String id) async {
    await _send('DELETE', '/v1/messages/${Uri.encodeComponent(id)}', token: token);
  }

  // ------------------------------------------------------------ lugares e eventos

  String _p(String slug) => '/v1/pages/${Uri.encodeComponent(slug)}';
  String _e(String id) => '/v1/events/${Uri.encodeComponent(id)}';

  List<PlaceEvent> _events(Map<String, dynamic>? json) =>
      (json!['items'] as List<dynamic>)
          .map((e) => PlaceEvent.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<List<PlaceItem>> places(
    String token, {
    String? query,
    bool mine = false,
  }) async {
    final json = await _send(
      'GET',
      '/v1/pages',
      token: token,
      query: {
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        if (mine) 'mine': 'true',
      },
    );
    return (json!['items'] as List<dynamic>)
        .map((e) => PlaceItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Place> place(String token, String slug) async =>
      Place.fromJson((await _send('GET', _p(slug), token: token))!);

  Future<Place> createPlace(
    String token, {
    required String name,
    required String category,
    required String cnpj,
    String description = '',
    String address = '',
    String city = '',
  }) async {
    final json = await _send(
      'POST',
      '/v1/pages',
      token: token,
      body: {
        'name': name,
        'category': category,
        'cnpj': cnpj,
        'description': description,
        'address': address,
        'city': city,
      },
    );
    return Place.fromJson(json!);
  }

  Future<Place> updatePlace(
    String token,
    String slug, {
    String? name,
    String? category,
    String? description,
    String? address,
    String? city,
  }) async {
    final json = await _send(
      'PATCH',
      _p(slug),
      token: token,
      body: {
        'name': ?name,
        'category': ?category,
        'description': ?description,
        'address': ?address,
        'city': ?city,
      },
    );
    return Place.fromJson(json!);
  }

  Future<void> deletePlace(String token, String slug) async {
    await _send('DELETE', _p(slug), token: token);
  }

  Future<void> followPlace(String token, String slug, {bool follow = true}) async {
    await _send(follow ? 'PUT' : 'DELETE', '${_p(slug)}/follow', token: token);
  }

  Future<void> addPlaceAdmin(String token, String slug, String username) async {
    await _send(
      'POST',
      '${_p(slug)}/admins',
      token: token,
      body: {'username': username},
    );
  }

  Future<List<PlaceEvent>> placeEvents(
    String token,
    String slug, {
    bool past = false,
  }) async => _events(
    await _send(
      'GET',
      '${_p(slug)}/events',
      token: token,
      query: {if (past) 'past': 'true'},
    ),
  );

  /// Agenda: próximos eventos dos lugares que acompanho e dos que marquei.
  Future<List<PlaceEvent>> agenda(String token) async =>
      _events(await _send('GET', '/v1/events', token: token));

  Future<PlaceEvent> event(String token, String id) async =>
      PlaceEvent.fromJson((await _send('GET', _e(id), token: token))!);

  Future<PlaceEvent> createEvent(
    String token,
    String slug, {
    required String title,
    required DateTime startsAt,
    DateTime? endsAt,
    String description = '',
    String location = '',
  }) async {
    final json = await _send(
      'POST',
      '${_p(slug)}/events',
      token: token,
      body: {
        'title': title,
        'description': description,
        'location': location,
        'starts_at': startsAt.toUtc().toIso8601String(),
        'ends_at': ?endsAt?.toUtc().toIso8601String(),
      },
    );
    return PlaceEvent.fromJson(json!);
  }

  Future<PlaceEvent> updateEvent(
    String token,
    String id, {
    String? title,
    String? description,
    String? location,
    DateTime? startsAt,
    DateTime? endsAt,
    bool? cancelled,
  }) async {
    final json = await _send(
      'PATCH',
      _e(id),
      token: token,
      body: {
        'title': ?title,
        'description': ?description,
        'location': ?location,
        'starts_at': ?startsAt?.toUtc().toIso8601String(),
        'ends_at': ?endsAt?.toUtc().toIso8601String(),
        'cancelled': ?cancelled,
      },
    );
    return PlaceEvent.fromJson(json!);
  }

  Future<void> deleteEvent(String token, String id) async {
    await _send('DELETE', _e(id), token: token);
  }

  /// `status`: interested | going | null (tira o interesse).
  Future<PlaceEvent?> setInterest(String token, String id, String? status) async {
    if (status == null) {
      await _send('DELETE', '${_e(id)}/interest', token: token);
      return null;
    }
    final json = await _send(
      'PUT',
      '${_e(id)}/interest',
      token: token,
      body: {'status': status},
    );
    return PlaceEvent.fromJson(json!);
  }

  // ------------------------------------------------------------ recados e status

  Future<Paged<Scrap>> scraps(
    String token,
    String username, {
    String? before,
  }) async {
    final json = await _send(
      'GET',
      '/v1/users/${Uri.encodeComponent(username)}/scraps',
      token: token,
      query: {'before': ?before},
    );
    return Paged.fromJson(json!, Scrap.fromJson);
  }

  Future<Scrap> writeScrap(String token, String username, String body) async {
    final json = await _send(
      'POST',
      '/v1/users/${Uri.encodeComponent(username)}/scraps',
      token: token,
      body: {'body': body},
    );
    return Scrap.fromJson(json!);
  }

  Future<void> deleteScrap(String token, String id) async {
    await _send('DELETE', '/v1/scraps/${Uri.encodeComponent(id)}', token: token);
  }

  /// `text == ''` apaga. `hours`: 24, 72, 168 ou 0 (sem validade).
  Future<void> setStatus(String token, String text, {int hours = 24}) async {
    await _send(
      'PUT',
      '/v1/me/status',
      token: token,
      body: {'text': text, 'hours': hours},
    );
  }

  // ------------------------------------------------------------ sugestões

  Future<List<Suggestion>> suggestions(String token) async {
    final json = await _send('GET', '/v1/me/suggestions', token: token);
    return (json!['items'] as List<dynamic>)
        .map((e) => Suggestion.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> dismissSuggestion(String token, String username) async {
    await _send(
      'POST',
      '/v1/me/suggestions/${Uri.encodeComponent(username)}/dismiss',
      token: token,
    );
  }

  // ------------------------------------------------------------ avisos

  Future<Counts> counts(String token) async {
    final json = await _send('GET', '/v1/me/counts', token: token);
    return Counts.fromJson(json!);
  }

  /// Este aparelho passa a receber notificações push desta conta.
  Future<void> registerDevice(String token, String deviceToken) async {
    await _send(
      'PUT',
      '/v1/me/devices',
      token: token,
      body: {'token': deviceToken},
    );
  }

  /// Ao sair da conta: o aparelho para de receber avisos dela.
  Future<void> unregisterDevice(String token, String deviceToken) async {
    await _send(
      'DELETE',
      '/v1/me/devices/${Uri.encodeComponent(deviceToken)}',
      token: token,
    );
  }

  Future<List<ActivityItem>> activity(String token) async {
    final json = await _send('GET', '/v1/me/activity', token: token);
    return (json!['items'] as List<dynamic>)
        .map((e) => ActivityItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> markActivitySeen(String token) async {
    await _send('POST', '/v1/me/activity/seen', token: token);
  }

  Future<Post> post(String token, String id) async {
    final json = await _send(
      'GET',
      '/v1/posts/${Uri.encodeComponent(id)}',
      token: token,
    );
    return Post.fromJson(json!);
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
    return _execute(request);
  }

  Future<Map<String, dynamic>?> _execute(http.Request request) async {
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
