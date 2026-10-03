import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humannet/src/api/api_client.dart';
import 'package:humannet/src/auth/session_controller.dart';
import 'package:humannet/src/auth/token_store.dart';
import 'package:humannet/src/ui/app.dart';

import 'fake_backend.dart';

SessionController _session(FakeBackend backend, TokenStore store) =>
    SessionController(
      api: ApiClient(baseUrl: 'http://api.test', httpClient: backend.client),
      tokenStore: store,
    );

void main() {
  testWidgets('sem token salvo mostra login; login e logout funcionam', (
    tester,
  ) async {
    final backend = FakeBackend();
    final store = InMemoryTokenStore();
    final session = _session(backend, store);
    await session.restore();

    await tester.pumpWidget(HumanNetApp(session: session));
    expect(find.byKey(const Key('login_button')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('login_field')),
      FakeBackend.username,
    );
    await tester.enterText(
      find.byKey(const Key('password_field')),
      FakeBackend.password,
    );
    await tester.tap(find.byKey(const Key('login_button')));
    await tester.pumpAndSettle();

    expect(find.text('Olá, @alice'), findsOneWidget);
    expect(await store.read(), FakeBackend.validToken);

    await tester.tap(find.byKey(const Key('logout_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login_button')), findsOneWidget);
    expect(await store.read(), isNull);
    expect(backend.calls, contains('POST /v1/auth/logout'));
  });

  testWidgets('senha errada mostra mensagem', (tester) async {
    final backend = FakeBackend();
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();

    await tester.pumpWidget(HumanNetApp(session: session));
    await tester.enterText(find.byKey(const Key('login_field')), 'alice');
    await tester.enterText(find.byKey(const Key('password_field')), 'errada');
    await tester.tap(find.byKey(const Key('login_button')));
    await tester.pumpAndSettle();

    expect(find.text('Usuário ou senha incorretos.'), findsOneWidget);
    expect(session.status, SessionStatus.signedOut);
  });

  test('token salvo válido restaura a sessão; inválido é descartado', () async {
    final backend = FakeBackend();

    final good = InMemoryTokenStore(FakeBackend.validToken);
    final s1 = _session(backend, good);
    await s1.restore();
    expect(s1.status, SessionStatus.signedIn);
    expect(s1.user?.username, FakeBackend.username);

    final bad = InMemoryTokenStore('expirado');
    final s2 = _session(backend, bad);
    await s2.restore();
    expect(s2.status, SessionStatus.signedOut);
    expect(await bad.read(), isNull);
  });
}
