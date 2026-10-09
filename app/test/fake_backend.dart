import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Backend falso mínimo para testes: um usuário (alice) e um outro (bob).
class FakeBackend {
  static const username = 'alice';
  static const password = 'senha-bem-longa-123';
  static const validToken = 'token-valido';

  final List<String> calls = [];
  final List<Map<String, Object?>> posts = [
    _post('01a10000-0000-7000-8000-000000000001', 'Primeiro post da Alice'),
  ];
  /// Relação de alice com bob: none | request_sent | request_received | friends.
  String bobRelation = 'none';

  bool bobBlocked = false;
  final Set<String> liked = {};
  final List<Map<String, Object?>> comments = [];
  final List<Map<String, dynamic>> reports = [];
  bool accountDeleted = false;
  bool isAdmin = false;
  final List<Map<String, Object?>> openReports = [
    {
      'id': 'r1',
      'kind': 'post',
      'target_id': 'p-bob',
      'target_username': 'bob',
      'target_suspended': false,
      'snapshot': 'texto ofensivo',
      'reason': 'harassment',
      'details': '',
      'reporter_username': 'carol',
      'status': 'open',
      'created_at': '2026-10-08T12:00:00Z',
    },
  ];
  final List<String> resolved = [];
  static const resetCode = 'ABCDE23456';
  String currentPassword = password;

  /// Carol pediu amizade à alice.
  bool carolRequested = true;

  /// Comunidade pública "rock-sp" (de bob). alice: null | active.
  String? rockStatus;
  final List<Map<String, Object?>> topics = [];
  final List<Map<String, Object?>> replies = [];
  final List<Map<String, dynamic>> createdCommunities = [];

  /// Depoimento de carol sobre alice: pending → approved.
  String? carolTestimonial = 'pending';
  bool activitySeen = false;

  /// Sugestão de amizade: dave (null = some da lista).
  String? daveSuggestion = 'shown';

  /// Fotos recebidas em POST /v1/media (kind, bytes).
  final List<(String, List<int>)> uploads = [];
  List<dynamic> lastMediaIds = const [];

  String? status;
  bool needsCpf = false;

  /// Lugar "bar-do-ze" e um evento.
  bool followingBar = false;
  String? interest;
  final List<Map<String, dynamic>> createdPlaces = [];
  String? cpfSent;
  int? statusHours;
  final List<Map<String, Object?>> bobScraps = [];
  bool carolFriend = false;
  String? displayName;
  String bio = '';
  int _seq = 2;

  /// Conversa 1:1 com bob (cv1): mensagens e se alice já leu.
  final List<Map<String, Object?>> chat = [
    {
      'id': 'm1',
      'author': {'id': 'u-bob', 'username': 'bob', 'display_name': 'Bob'},
      'body': 'Oi Alice!',
      'created_at': '2026-10-08T12:00:00Z',
      'mine': false,
      'deleted': false,
    },
  ];
  bool chatRead = false;
  int chatSeq = 1;

  /// Mural da página "meu-bar" e conversa com "bar-do-ze".
  final List<Map<String, Object?>> pagePosts = [];
  bool pageConversationOpened = false;

  Map<String, Object?> _conversation() => {
    'id': 'cv1',
    'kind': 'direct',
    'title': '',
    'other': {'id': 'u-bob', 'username': 'bob', 'display_name': 'Bob'},
    'member_count': 2,
    'last_message': chat.last['body'],
    'last_message_at': '2026-10-08T12:00:00Z',
    'unread': chatRead ? 0 : 1,
    'is_owner': false,
  };

  late final http.Client client = MockClient((request) async {
    final route = '${request.method} ${request.url.path}';
    calls.add(route);
    final authed = request.headers['Authorization'] == 'Bearer $validToken';

    if (route == 'POST /v1/auth/reset-password') {
      final r = jsonDecode(request.body) as Map<String, dynamic>;
      if (r['username'] == username &&
          (r['code'] as String).toUpperCase() == resetCode) {
        currentPassword = r['new_password'] as String;
        return http.Response('', 204);
      }
      return _json(422, {'error': 'invalid_reset_code'});
    }
    if (route == 'POST /v1/auth/login') {
      final login = jsonDecode(request.body) as Map<String, dynamic>;
      if (login['login'] == username && login['password'] == password) {
        return _json(200, {'token': validToken, 'user': _user()});
      }
      return _json(401, {'error': 'invalid_credentials'});
    }
    if (!authed) return _json(401, {'error': 'unauthorized'});

    switch (route) {
      case 'GET /v1/me':
        return _json(200, _user());
      case 'POST /v1/auth/logout':
        return http.Response('', 204);
      case 'GET /v1/feed':
      case 'GET /v1/users/alice/posts':
        return _json(200, {'items': posts, 'next_cursor': null});
      case 'GET /v1/users/alice':
        return _json(200, _profile('alice', relation: 'self'));
      case 'GET /v1/users/bob':
        if (bobBlocked) return _json(404, {'error': 'not_found'});
        return _json(200, _profile('bob', relation: bobRelation));
      case 'PUT /v1/users/bob/block':
        bobBlocked = true;
        bobRelation = 'none';
        return http.Response('', 204);
      case 'DELETE /v1/users/bob/block':
        bobBlocked = false;
        return http.Response('', 204);
      case 'GET /v1/blocks':
        return _json(200, {
          'items': [
            if (bobBlocked) {'id': 'u-bob', 'username': 'bob', 'display_name': null},
          ],
        });
      case 'GET /v1/admin/reports':
        if (!isAdmin) return _json(403, {'error': 'forbidden'});
        return _json(200, {'items': openReports});
      case 'POST /v1/admin/reports/r1/resolve':
        final a = jsonDecode(request.body) as Map<String, dynamic>;
        resolved.add(a['action'] as String);
        openReports.clear();
        return http.Response('', 204);
      case 'POST /v1/admin/users/bob/password-reset':
        return _json(201, {
          'code': resetCode,
          'expires_at': '2026-10-09T12:00:00Z',
        });
      case 'POST /v1/reports':
        reports.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('', 202);
      case 'PUT /v1/me/password':
        final pw = jsonDecode(request.body) as Map<String, dynamic>;
        if (pw['current_password'] != currentPassword) {
          return _json(401, {'error': 'invalid_credentials'});
        }
        currentPassword = pw['new_password'] as String;
        return http.Response('', 204);
      case 'DELETE /v1/me':
        final del = jsonDecode(request.body) as Map<String, dynamic>;
        if (del['password'] != currentPassword) {
          return _json(401, {'error': 'invalid_credentials'});
        }
        accountDeleted = true;
        return http.Response('', 204);
      case 'GET /v1/users/bob/posts':
        if (bobRelation != 'friends') {
          return _json(403, {'error': 'forbidden'});
        }
        return _json(200, {'items': <Object>[], 'next_cursor': null});
      case 'PUT /v1/users/bob/friend':
        bobRelation = bobRelation == 'request_received' || bobRelation == 'friends'
            ? 'friends'
            : 'request_sent';
        return _json(200, {'relation': bobRelation});
      case 'DELETE /v1/users/bob/friend':
        bobRelation = 'none';
        return http.Response('', 204);
      case 'PUT /v1/users/carol/friend':
        carolRequested = false;
        carolFriend = true;
        return _json(200, {'relation': 'friends'});
      case 'DELETE /v1/users/carol/friend':
        carolRequested = false;
        carolFriend = false;
        return http.Response('', 204);
      case 'GET /v1/friend-requests':
        return _json(200, {
          'items': [
            if (carolRequested)
              {
                'user': {'id': 'u-carol', 'username': 'carol', 'display_name': 'Carol'},
                'created_at': '2026-10-07T12:00:00Z',
              },
          ],
        });
      case 'GET /v1/friends':
        return _json(200, {
          'items': [
            if (bobRelation == 'friends')
              {'id': 'u-bob', 'username': 'bob', 'display_name': null},
            if (carolFriend)
              {'id': 'u-carol', 'username': 'carol', 'display_name': 'Carol'},
          ],
        });
      case 'PATCH /v1/me/profile':
        final patch = jsonDecode(request.body) as Map<String, dynamic>;
        final name = patch['display_name'] as String?;
        if (name != null) displayName = name.isEmpty ? null : name;
        bio = (patch['bio'] as String?) ?? bio;
        return _json(200, _user());
      case 'GET /v1/posts/01a10000-0000-7000-8000-000000000001/comments':
        return _json(200, {'items': comments});
      case 'POST /v1/posts/01a10000-0000-7000-8000-000000000001/comments':
        final c = jsonDecode(request.body) as Map<String, dynamic>;
        final comment = <String, Object?>{
          'id': 'c${comments.length + 1}',
          'post_id': '01a10000-0000-7000-8000-000000000001',
          'author': {'id': 'u-alice', 'username': username, 'display_name': null},
          'body': (c['body'] as String).trim(),
          'created_at': '2026-10-08T12:00:00Z',
          'can_delete': true,
        };
        comments.add(comment);
        return _json(201, comment);
      case 'PUT /v1/posts/01a10000-0000-7000-8000-000000000001/like':
        liked.add('01a10000-0000-7000-8000-000000000001');
        return http.Response('', 204);
      case 'DELETE /v1/posts/01a10000-0000-7000-8000-000000000001/like':
        liked.remove('01a10000-0000-7000-8000-000000000001');
        return http.Response('', 204);
      case 'DELETE /v1/comments/c1':
        comments.removeWhere((c) => c['id'] == 'c1');
        return http.Response('', 204);
      case 'POST /v1/posts':
        final created = jsonDecode(request.body) as Map<String, dynamic>;
        final text = (created['body'] as String).trim();
        lastMediaIds = (created['media_ids'] as List<dynamic>?) ?? const [];
        if (text.isEmpty && lastMediaIds.isEmpty) {
          return _json(422, {'error': 'invalid_post_body'});
        }
        final id = '01a10000-0000-7000-8000-${(_seq++).toString().padLeft(12, '0')}';
        final post = _post(id, text);
        posts.insert(0, post);
        return _json(201, post);
      case 'POST /v1/media':
        final kind = request.url.queryParameters['kind'] ?? '';
        uploads.add((kind, request.bodyBytes));
        return _json(201, {
          'id': 'm${uploads.length}',
          'url': 'memory://m${uploads.length}',
          'width': 10,
          'height': 10,
        });
      case 'GET /v1/events':
        return _json(200, {
          'items': [if (followingBar || interest != null) _event()],
        });
      case 'GET /v1/pages':
        return _json(200, {
          'items': [
            {
              'slug': 'bar-do-ze',
              'name': 'Bar do Zé',
              'category': 'bar',
              'city': 'São Paulo',
              'verified': true,
              'following': followingBar,
              'my_role': null,
            },
          ],
        });
      case 'GET /v1/pages/bar-do-ze':
        return _json(200, {
          'id': 'p1',
          'slug': 'bar-do-ze',
          'name': 'Bar do Zé',
          'category': 'bar',
          'description': 'Samba toda sexta.',
          'address': 'Rua Augusta, 100',
          'city': 'São Paulo',
          'cnpj': '11.222.333/0001-81',
          'verified': true,
          'my_role': null,
          'following': followingBar,
          'follower_count': null,
        });
      case 'PUT /v1/pages/bar-do-ze/follow':
        followingBar = true;
        return http.Response('', 204);
      case 'DELETE /v1/pages/bar-do-ze/follow':
        followingBar = false;
        return http.Response('', 204);
      case 'GET /v1/pages/bar-do-ze/events':
        return _json(200, {'items': [_event()]});
      case 'GET /v1/events/e1':
        return _json(200, _event());
      case 'PUT /v1/events/e1/interest':
        interest = (jsonDecode(request.body) as Map<String, dynamic>)['status'] as String;
        return _json(200, _event());
      case 'DELETE /v1/events/e1/interest':
        interest = null;
        return http.Response('', 204);
      case 'POST /v1/pages':
        final b = jsonDecode(request.body) as Map<String, dynamic>;
        createdPlaces.add(b);
        return _json(201, {
          'id': 'p2',
          'slug': 'meu-bar',
          'name': b['name'],
          'category': b['category'],
          'description': '',
          'address': '',
          'city': '',
          'cnpj': b['cnpj'],
          'verified': false,
          'my_role': 'owner',
          'following': false,
          'follower_count': 0,
        });
      case 'GET /v1/pages/meu-bar':
        return _json(200, {
          'id': 'p2',
          'slug': 'meu-bar',
          'name': createdPlaces.single['name'],
          'category': 'bar',
          'description': '',
          'address': '',
          'city': '',
          'cnpj': '11.222.333/0001-81',
          'verified': false,
          'my_role': 'owner',
          'following': false,
          'follower_count': 0,
        });
      case 'GET /v1/pages/meu-bar/events':
        return _json(200, {'items': <Object>[]});
      case 'GET /v1/pages/meu-bar/posts':
        return _json(200, {'items': pagePosts, 'next_cursor': null});
      case 'GET /v1/pages/bar-do-ze/posts':
        return _json(200, {'items': <Object>[], 'next_cursor': null});
      case 'POST /v1/pages/meu-bar/posts':
        final b = jsonDecode(request.body) as Map<String, dynamic>;
        final post = <String, Object?>{
          ..._post('pp${pagePosts.length + 1}', b['body'] as String),
          'page': {'slug': 'meu-bar', 'name': 'Meu Bar', 'logo_url': null},
        };
        pagePosts.insert(0, post);
        return _json(201, post);
      case 'POST /v1/pages/bar-do-ze/conversation':
        if (!followingBar) return _json(422, {'error': 'follow_page_first'});
        pageConversationOpened = true;
        return _json(200, {
          'id': 'cv2',
          'kind': 'page',
          'title': 'Bar do Zé',
          'other': null,
          'member_count': 2,
          'last_message': null,
          'last_message_at': '2026-10-08T12:00:00Z',
          'unread': 0,
          'is_owner': false,
          'page_slug': 'bar-do-ze',
          'as_page': false,
        });
      case 'GET /v1/conversations/cv2/messages':
        return _json(200, {'items': <Object>[], 'next_cursor': null});
      case 'POST /v1/conversations/cv2/read':
        return http.Response('', 204);
      case 'GET /ws/18035000/json/':
        return _json(200, {
          'cep': '18035-000',
          'logradouro': 'Rua XV de Novembro',
          'bairro': 'Centro',
          'localidade': 'Sorocaba',
          'uf': 'SP',
        });
      case 'PUT /v1/me/cpf':
        cpfSent = (jsonDecode(request.body) as Map<String, dynamic>)['cpf'] as String;
        needsCpf = false;
        return http.Response('', 204);
      case 'PUT /v1/me/status':
        final st = jsonDecode(request.body) as Map<String, dynamic>;
        final text = st['text'] as String;
        status = text.isEmpty ? null : text;
        statusHours = st['hours'] as int?;
        return _json(200, {'text': text, 'expires_at': null});
      case 'GET /v1/users/bob/scraps':
        return _json(200, {'items': bobScraps, 'next_cursor': null});
      case 'POST /v1/users/bob/scraps':
        final b = jsonDecode(request.body) as Map<String, dynamic>;
        final scrap = <String, Object?>{
          'id': 's${bobScraps.length + 1}',
          'author': {'id': 'u-alice', 'username': username, 'display_name': null},
          'body': (b['body'] as String).trim(),
          'created_at': '2026-10-08T12:00:00Z',
          'can_delete': true,
        };
        bobScraps.insert(0, scrap);
        return _json(201, scrap);
      case 'GET /v1/me/suggestions':
        return _json(200, {
          'items': [
            if (daveSuggestion == 'shown')
              {
                'user': {'id': 'u-dave', 'username': 'dave', 'display_name': 'Dave'},
                'mutual_friends': 2,
                'reasons': ['2 amigos em comum', 'Também é de Recife'],
              },
          ],
        });
      case 'POST /v1/me/suggestions/dave/dismiss':
        daveSuggestion = 'dismissed';
        return http.Response('', 204);
      case 'PUT /v1/users/dave/friend':
        daveSuggestion = 'requested';
        return _json(200, {'relation': 'request_sent'});
      case 'GET /v1/me/counts':
        return _json(200, {
          'friend_requests': carolRequested ? 1 : 0,
          'pending_testimonials': carolTestimonial == 'pending' ? 1 : 0,
          'community_requests': 0,
          'unread_activity': activitySeen ? 0 : 1,
          'unread_messages': chatRead ? 0 : 1,
        });
      case 'GET /v1/conversations':
        return _json(200, {
          'items': [_conversation()],
        });
      case 'POST /v1/conversations/direct':
        return _json(200, _conversation());
      case 'GET /v1/conversations/cv1':
        return _json(200, _conversation());
      case 'GET /v1/conversations/cv1/messages':
        final after = request.url.queryParameters['after'];
        final idx = chat.indexWhere((m) => m['id'] == after);
        return _json(200, {
          'items': after == null ? chat : chat.sublist(idx + 1),
          'next_cursor': null,
        });
      case 'POST /v1/conversations/cv1/messages':
        final b = jsonDecode(request.body) as Map<String, dynamic>;
        chatSeq++;
        final msg = <String, Object?>{
          'id': 'm$chatSeq',
          'author': {'id': 'u-alice', 'username': username, 'display_name': null},
          'body': (b['body'] as String).trim(),
          'created_at': '2026-10-08T12:01:00Z',
          'mine': true,
          'deleted': false,
        };
        chat.add(msg);
        return _json(201, msg);
      case 'POST /v1/conversations/cv1/read':
        chatRead = true;
        return http.Response('', 204);
      case 'GET /v1/me/activity':
        return _json(200, {
          'items': [
            {
              'kind': 'comment',
              'actor': {'id': 'u-bob', 'username': 'bob', 'display_name': 'Bob'},
              'target_id': '01a10000-0000-7000-8000-000000000001',
              'target_title': '',
              'excerpt': 'Que legal!',
              'created_at': '2026-10-08T12:00:00Z',
              'unread': !activitySeen,
            },
          ],
        });
      case 'POST /v1/me/activity/seen':
        activitySeen = true;
        return http.Response('', 204);
      case 'GET /v1/posts/01a10000-0000-7000-8000-000000000001':
        return _json(200, posts.last);
      case 'GET /v1/users/alice/testimonials':
        return _json(200, {
          'items': [if (carolTestimonial == 'approved') _testimonial()],
        });
      case 'GET /v1/me/testimonials/pending':
        return _json(200, {
          'items': [if (carolTestimonial == 'pending') _testimonial()],
        });
      case 'POST /v1/testimonials/d1/approve':
        carolTestimonial = 'approved';
        return http.Response('', 204);
      case 'DELETE /v1/testimonials/d1':
        carolTestimonial = null;
        return http.Response('', 204);
      case 'GET /v1/communities':
        final mine = request.url.queryParameters['mine'] == 'true';
        return _json(200, {
          'items': [
            if (!mine || rockStatus != null) _rockItem(),
            for (final c in createdCommunities) c,
          ],
        });
      case 'POST /v1/communities':
        final c = jsonDecode(request.body) as Map<String, dynamic>;
        final created = <String, dynamic>{
          'id': 'c-new',
          'slug': 'nova',
          'name': c['name'],
          'description': c['description'],
          'rules': c['rules'],
          'theme': c['theme'],
          'visibility': c['visibility'],
          'created_at': '2026-10-08T12:00:00Z',
          'my_role': 'owner',
          'my_status': 'active',
          'can_read': true,
          'can_post': true,
          'can_moderate': true,
          'member_count': 1,
          'pending_count': 0,
        };
        createdCommunities.add(created);
        return _json(201, created);
      case 'GET /v1/communities/nova':
        return _json(200, createdCommunities.single);
      case 'GET /v1/communities/nova/topics':
        return _json(200, {'items': <Object>[], 'next_cursor': null});
      case 'GET /v1/communities/rock-sp':
        return _json(200, {
          ..._rockItem(),
          'rules': 'Respeito.',
          'created_at': '2026-10-08T12:00:00Z',
          'can_read': true,
          'can_post': rockStatus == 'active',
          'can_moderate': false,
        });
      case 'PUT /v1/communities/rock-sp/membership':
        rockStatus = 'active';
        return _json(200, {'status': 'active'});
      case 'GET /v1/communities/rock-sp/topics':
        return _json(200, {'items': topics, 'next_cursor': null});
      case 'POST /v1/communities/rock-sp/topics':
        final t = jsonDecode(request.body) as Map<String, dynamic>;
        final topic = _topic('t${topics.length + 1}', t['title'] as String);
        topics.insert(0, topic);
        return _json(201, topic);
      case 'GET /v1/topics/t1':
        return _json(200, topics.firstWhere((t) => t['id'] == 't1'));
      case 'GET /v1/topics/t1/replies':
        return _json(200, {'items': replies, 'next_cursor': null});
      case 'POST /v1/topics/t1/replies':
        final r = jsonDecode(request.body) as Map<String, dynamic>;
        final reply = <String, Object?>{
          'id': 'r${replies.length + 1}',
          'topic_id': 't1',
          'author': {'id': 'u-alice', 'username': username, 'display_name': null},
          'body': (r['body'] as String).trim(),
          'created_at': '2026-10-08T12:00:00Z',
          'can_delete': true,
        };
        replies.add(reply);
        return _json(201, reply);
      default:
        return _json(404, {'error': 'not_found'});
    }
  });

  Map<String, Object?> _user() => {
    'id': 'u-alice',
    'username': username,
    'email': 'alice@example.com',
    'display_name': displayName,
    'bio': bio,
    'role': isAdmin ? 'admin' : 'user',
    'needs_cpf': needsCpf,
    'created_at': '2026-10-03T05:27:07Z',
  };

  Map<String, Object?> _profile(String name, {required String relation}) {
    final isSelf = relation == 'self';
    return {
      'id': 'u-$name',
      'username': name,
      'display_name': isSelf ? displayName : null,
      'bio': isSelf ? bio : '',
      'created_at': '2026-10-03T05:27:07Z',
      'is_self': isSelf,
      'relation': relation,
      if (isSelf) 'status': status,
      if (isSelf)
        'stats': {
          'friends': (bobRelation == 'friends' ? 1 : 0) + (carolFriend ? 1 : 0),
          'posts': posts.length,
          'pending_requests': carolRequested ? 1 : 0,
          'pending_testimonials': carolTestimonial == 'pending' ? 1 : 0,
        },
    };
  }

  Map<String, Object?> _event() => {
    'id': 'e1',
    'page': {'slug': 'bar-do-ze', 'name': 'Bar do Zé'},
    'title': 'Samba de sexta',
    'description': 'Roda de samba',
    'starts_at': '2030-10-10T23:00:00Z',
    'ends_at': null,
    'location': 'Rua Augusta, 100',
    'cancelled': false,
    'my_interest': interest,
    'friends': [
      {'id': 'u-bob', 'username': 'bob', 'display_name': 'Bob'},
    ],
    'friends_count': 1,
    'interested_count': null,
    'going_count': null,
    'can_edit': false,
  };

  Map<String, Object?> _testimonial() => {
    'id': 'd1',
    'author': {'id': 'u-carol', 'username': 'carol', 'display_name': 'Carol'},
    'recipient': {'id': 'u-alice', 'username': username, 'display_name': null},
    'body': 'A Alice é a melhor amiga do mundo.',
    'status': carolTestimonial,
    'created_at': '2026-10-08T12:00:00Z',
    'can_delete': true,
  };

  Map<String, Object?> _rockItem() => {
    'id': 'c-rock',
    'slug': 'rock-sp',
    'name': 'Rock SP',
    'description': 'Shows e bandas.',
    'theme': 'musica',
    'visibility': 'public',
    'my_role': rockStatus == null ? null : 'member',
    'my_status': rockStatus,
  };

  static Map<String, Object?> _topic(String id, String title) => {
    'id': id,
    'community_slug': 'rock-sp',
    'community_name': 'Rock SP',
    'author': {'id': 'u-alice', 'username': username, 'display_name': null},
    'title': title,
    'body': '',
    'pinned': false,
    'locked': false,
    'reply_count': 0,
    'created_at': '2026-10-08T12:00:00Z',
    'last_activity_at': '2026-10-08T12:00:00Z',
    'can_reply': true,
    'can_delete': true,
    'can_moderate': false,
  };

  static Map<String, Object?> _post(String id, String body) => {
    'id': id,
    'author': {'id': 'u-alice', 'username': username, 'display_name': null},
    'body': body,
    'created_at': '2026-10-04T12:00:00Z',
    'edited_at': null,
    'comment_count': 0,
    'liked_by_me': false,
    'like_count': 3,
  };

  static http.Response _json(int status, Object body) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
