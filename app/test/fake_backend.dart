import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Backend falso mínimo para testes, com um único usuário.
class FakeBackend {
  static const username = 'alice';
  static const password = 'senha-bem-longa-123';
  static const validToken = 'token-valido';

  final List<String> calls = [];

  late final http.Client client = MockClient((request) async {
    calls.add('${request.method} ${request.url.path}');
    final auth = request.headers['Authorization'];

    switch ('${request.method} ${request.url.path}') {
      case 'POST /v1/auth/login':
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['login'] == username && body['password'] == password) {
          return _json(200, {'token': validToken, 'user': _user});
        }
        return _json(401, {'error': 'invalid_credentials'});
      case 'GET /v1/me':
        return auth == 'Bearer $validToken'
            ? _json(200, _user)
            : _json(401, {'error': 'unauthorized'});
      case 'POST /v1/auth/logout':
        return http.Response('', 204);
      default:
        return _json(404, {'error': 'not_found'});
    }
  });

  static const Map<String, Object> _user = {
    'id': '01a1003a-f929-7263-8fa9-4455b0429248',
    'username': username,
    'email': 'alice@example.com',
    'created_at': '2026-10-03T05:27:07Z',
  };

  static http.Response _json(int status, Object body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}
