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
  });
}
