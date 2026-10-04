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

Future<void> _login(WidgetTester tester) async {
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
}

void main() {
  testWidgets('login abre o feed; logout pelo perfil volta ao login', (
    tester,
  ) async {
    final backend = FakeBackend();
    final store = InMemoryTokenStore();
    final session = _session(backend, store);
    await session.restore();

    await tester.pumpWidget(HumanNetApp(session: session));
    expect(find.byKey(const Key('login_button')), findsOneWidget);

    await _login(tester);

    expect(find.byKey(const Key('feed_screen')), findsOneWidget);
    expect(find.text('Primeiro post da Alice'), findsOneWidget);
    expect(find.byKey(const Key('list_end')), findsOneWidget);
    expect(await store.read(), FakeBackend.validToken);

    await tester.tap(find.byKey(const Key('nav_profile')));
    await tester.pumpAndSettle();
    expect(find.text('Só você vê esses números.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('logout_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login_button')), findsOneWidget);
    expect(await store.read(), isNull);
    expect(backend.calls, contains('POST /v1/auth/logout'));
  });

  testWidgets('escrever um post coloca o post no topo do feed', (
    tester,
  ) async {
    final backend = FakeBackend();
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);

    await tester.tap(find.byKey(const Key('compose_button')));
    await tester.pumpAndSettle();

    // Publicar fica desabilitado com texto vazio.
    final publish = find.byKey(const Key('publish_button'));
    expect(tester.widget<FilledButton>(publish).onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('compose_field')),
      'Olá, pessoas reais!',
    );
    await tester.pump();
    await tester.tap(publish);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('feed_screen')), findsOneWidget);
    expect(find.text('Olá, pessoas reais!'), findsOneWidget);
    expect(backend.calls, contains('POST /v1/posts'));
  });

  testWidgets('seguir e deixar de seguir outro perfil', (tester) async {
    final backend = FakeBackend();
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);

    await tester.tap(find.byTooltip('Encontrar pessoa'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('find_person_field')), 'Bob');
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(find.text('@bob'), findsWidgets);
    expect(find.text('Só você vê esses números.'), findsNothing);
    expect(find.text('Seguir'), findsOneWidget);

    await tester.tap(find.byKey(const Key('follow_button')));
    await tester.pumpAndSettle();
    expect(backend.followingBob, isTrue);
    expect(find.text('Seguindo'), findsOneWidget);

    await tester.tap(find.byKey(const Key('follow_button')));
    await tester.pumpAndSettle();
    expect(backend.followingBob, isFalse);
  });

  testWidgets('editar perfil atualiza o nome exibido', (tester) async {
    final backend = FakeBackend();
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);

    await tester.tap(find.byKey(const Key('nav_profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_profile_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('display_name_field')),
      'Alice A.',
    );
    await tester.tap(find.byKey(const Key('save_profile_button')));
    await tester.pumpAndSettle();

    expect(session.user?.displayName, 'Alice A.');
    expect(find.text('Alice A.'), findsOneWidget);
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
