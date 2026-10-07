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
  bool carolFriend = false;
  String? displayName;
  String bio = '';
  int _seq = 2;

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
        if (text.isEmpty) return _json(422, {'error': 'invalid_post_body'});
        final id = '01a10000-0000-7000-8000-${(_seq++).toString().padLeft(12, '0')}';
        final post = _post(id, text);
        posts.insert(0, post);
        return _json(201, post);
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
      if (isSelf)
        'stats': {
          'friends': (bobRelation == 'friends' ? 1 : 0) + (carolFriend ? 1 : 0),
          'posts': posts.length,
          'pending_requests': carolRequested ? 1 : 0,
        },
    };
  }

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
