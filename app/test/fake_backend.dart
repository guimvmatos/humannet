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
        return _json(200, _profile('bob', relation: bobRelation));
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
  };

  static http.Response _json(int status, Object body) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
