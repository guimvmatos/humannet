import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:humannet/src/api/api_client.dart';

import 'fake_backend.dart';

void main() {
  group('ApiClient', () {
    late FakeBackend backend;
    late ApiClient api;

    setUp(() {
      backend = FakeBackend();
      api = ApiClient(baseUrl: 'http://api.test', httpClient: backend.client);
    });

    test('login devolve token e usuário', () async {
      final result = await api.login(
        login: FakeBackend.username,
        password: FakeBackend.password,
      );
      expect(result.token, FakeBackend.validToken);
      expect(result.user.username, FakeBackend.username);
    });

    test('erro da API vira ApiException com código', () async {
      await expectLater(
        api.login(login: 'alice', password: 'errada'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'invalid_credentials')
              .having((e) => e.isUnauthorized, 'isUnauthorized', true),
        ),
      );
    });

    test('me envia Bearer token', () async {
      final user = await api.me(FakeBackend.validToken);
      expect(user.username, FakeBackend.username);
      await expectLater(api.me('outro'), throwsA(isA<ApiException>()));
    });

    test('feed envia cursor como query e devolve página', () async {
      Uri? seen;
      final client = ApiClient(
        baseUrl: 'http://api.test',
        httpClient: MockClient((req) async {
          seen = req.url;
          return http.Response(
            '{"items":[{"id":"p1","author":{"id":"u1","username":"bob",'
            '"display_name":null},"body":"oi","created_at":'
            '"2026-10-04T12:00:00Z","edited_at":null}],"next_cursor":"p1"}',
            200,
          );
        }),
      );
      final page = await client.feed('t', before: 'abc');
      expect(seen?.path, '/v1/feed');
      expect(seen?.queryParameters['before'], 'abc');
      expect(page.items.single.author.label, '@bob');
      expect(page.nextCursor, 'p1');

      await client.feed('t');
      expect(seen?.hasQuery, isFalse);
    });

    test('updateProfile omite campos nulos', () async {
      String? sentBody;
      final client = ApiClient(
        baseUrl: 'http://api.test',
        httpClient: MockClient((req) async {
          sentBody = req.body;
          return http.Response(
            '{"id":"u1","username":"alice","email":"a@example.com",'
            '"display_name":null,"bio":"x","created_at":"2026-10-04T12:00:00Z"}',
            200,
          );
        }),
      );
      await client.updateProfile('t', bio: 'x');
      expect(sentBody, '{"bio":"x"}');
    });

    test('falha de rede vira network_error', () async {
      final offline = ApiClient(
        baseUrl: 'http://api.test',
        httpClient: MockClient((_) => throw http.ClientException('offline')),
      );
      await expectLater(
        offline.me('x'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'network_error'),
        ),
      );
    });

    test('resposta não-JSON de erro vira http_<status>', () async {
      final weird = ApiClient(
        baseUrl: 'http://api.test',
        httpClient: MockClient((_) async => http.Response('<html>', 502)),
      );
      await expectLater(
        weird.me('x'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'http_502')),
      );
    });

    test('registra e remove o aparelho do push', () async {
      final seen = <String>[];
      final client = ApiClient(
        baseUrl: 'http://api.test',
        httpClient: MockClient((req) async {
          seen.add('${req.method} ${req.url.path} ${req.body}');
          return http.Response('', 204);
        }),
      );
      await client.registerDevice('t', 'abc-123');
      await client.unregisterDevice('t', 'abc-123');
      expect(seen, [
        'PUT /v1/me/devices {"token":"abc-123"}',
        'DELETE /v1/me/devices/abc-123 ',
      ]);
    });
  });
}
