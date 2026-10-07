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

  testWidgets('pedir amizade, cancelar; posts só para amigos', (tester) async {
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

    expect(find.byKey(const Key('friends_only')), findsOneWidget);
    expect(find.text('Só você vê esses números.'), findsNothing);
    expect(find.text('Adicionar'), findsOneWidget);
    expect(backend.calls, isNot(contains('GET /v1/users/bob/posts')));

    await tester.tap(find.byKey(const Key('friend_button')));
    await tester.pumpAndSettle();
    expect(backend.bobRelation, 'request_sent');
    expect(find.text('Pedido enviado · cancelar'), findsOneWidget);

    await tester.tap(find.byKey(const Key('friend_button')));
    await tester.pumpAndSettle();
    expect(backend.bobRelation, 'none');
    expect(find.text('Adicionar'), findsOneWidget);
  });

  testWidgets('aceitar pedido de amizade na aba Amigos', (tester) async {
    final backend = FakeBackend();
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);

    await tester.tap(find.byKey(const Key('nav_friends')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('request_carol')), findsOneWidget);
    await tester.tap(find.byKey(const Key('accept_carol')));
    await tester.pumpAndSettle();

    expect(backend.carolFriend, isTrue);
    expect(find.byKey(const Key('request_carol')), findsNothing);
    expect(find.byKey(const Key('friend_carol')), findsOneWidget);
  });

  testWidgets('desfazer amizade pede confirmação', (tester) async {
    final backend = FakeBackend()..bobRelation = 'friends';
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);

    await tester.tap(find.byTooltip('Encontrar pessoa'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('find_person_field')), 'bob');
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('friends_only')), findsNothing);
    await tester.tap(find.byKey(const Key('friend_button')));
    await tester.pumpAndSettle();
    expect(find.text('Desfazer amizade?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm_button')));
    await tester.pumpAndSettle();
    expect(backend.bobRelation, 'none');
    expect(find.byKey(const Key('friends_only')), findsOneWidget);
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

  Future<void> openBob(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Encontrar pessoa'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('find_person_field')), 'bob');
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('denunciar perfil envia motivo e detalhes', (tester) async {
    final backend = FakeBackend();
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);
    await openBob(tester);

    await tester.tap(find.byKey(const Key('profile_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Denunciar perfil'));
    await tester.pumpAndSettle();

    // Sem motivo, não envia.
    final send = find.byKey(const Key('send_report_button'));
    expect(tester.widget<FilledButton>(send).onPressed, isNull);

    await tester.ensureVisible(find.byKey(const Key('reason_impersonation')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reason_impersonation')));
    await tester.pump();
    await tester.tap(send);
    await tester.pumpAndSettle();

    expect(backend.reports.single['kind'], 'user');
    expect(backend.reports.single['username'], 'bob');
    expect(backend.reports.single['reason'], 'impersonation');
    expect(find.textContaining('Denúncia enviada'), findsOneWidget);
  });

  testWidgets('bloquear pela tela de perfil e desbloquear nas configurações', (
    tester,
  ) async {
    final backend = FakeBackend()..bobRelation = 'friends';
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);
    await openBob(tester);

    await tester.tap(find.byKey(const Key('profile_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bloquear'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_button')));
    await tester.pumpAndSettle();

    expect(backend.bobBlocked, isTrue);
    expect(backend.bobRelation, 'none');
    // Voltou para o feed.
    expect(find.byKey(const Key('feed_screen')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('blocked_tile')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('blocked_bob')), findsOneWidget);

    await tester.tap(find.byKey(const Key('unblock_bob')));
    await tester.pumpAndSettle();
    expect(backend.bobBlocked, isFalse);
    expect(find.text('Você não bloqueou ninguém.'), findsOneWidget);
  });

  testWidgets('excluir conta exige confirmação e senha', (tester) async {
    final backend = FakeBackend();
    final store = InMemoryTokenStore();
    final session = _session(backend, store);
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);

    await tester.tap(find.byKey(const Key('nav_profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete_account_tile')));
    await tester.pumpAndSettle();

    final button = find.byKey(const Key('delete_account_button'));
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await tester.tap(find.byKey(const Key('confirm_delete_checkbox')));
    await tester.enterText(
      find.byKey(const Key('delete_password_field')),
      'senha-errada-123',
    );
    await tester.pump();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Senha incorreta.'), findsOneWidget);
    expect(backend.accountDeleted, isFalse);

    await tester.enterText(
      find.byKey(const Key('delete_password_field')),
      FakeBackend.password,
    );
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(backend.accountDeleted, isTrue);
    expect(find.byKey(const Key('login_button')), findsOneWidget);
    expect(await store.read(), isNull);
  });

  testWidgets('trocar senha', (tester) async {
    final backend = FakeBackend();
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);

    await tester.tap(find.byKey(const Key('nav_profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('change_password_tile')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('current_password_field')),
      FakeBackend.password,
    );
    await tester.enterText(
      find.byKey(const Key('new_password_field')),
      'nova-senha-segura-1',
    );
    await tester.tap(find.byKey(const Key('save_password_button')));
    await tester.pumpAndSettle();

    expect(backend.currentPassword, 'nova-senha-segura-1');
    expect(find.textContaining('Senha trocada'), findsOneWidget);
  });

  testWidgets('curtir no feed; autor vê o número', (tester) async {
    const id = '01a10000-0000-7000-8000-000000000001';
    final backend = FakeBackend();
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);

    // Post da própria alice: número de curtidas visível só para ela.
    expect(find.byKey(const Key('like_count_$id')), findsOneWidget);

    await tester.tap(find.byKey(const Key('like_$id')));
    await tester.pumpAndSettle();
    expect(backend.liked, contains(id));
    expect(find.byIcon(Icons.favorite), findsOneWidget);

    await tester.tap(find.byKey(const Key('like_$id')));
    await tester.pumpAndSettle();
    expect(backend.liked, isEmpty);
  });

  testWidgets('comentar abre a tela do post e envia', (tester) async {
    const id = '01a10000-0000-7000-8000-000000000001';
    final backend = FakeBackend();
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);

    await tester.tap(find.byKey(const Key('comments_$id')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('post_screen')), findsOneWidget);
    expect(find.byKey(const Key('no_comments')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('comment_field')), 'Boa!');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_comment_button')));
    await tester.pumpAndSettle();

    expect(backend.comments.single['body'], 'Boa!');
    expect(find.text('Boa!'), findsOneWidget);

    await tester.tap(find.byKey(const Key('delete_comment_c1')));
    await tester.pumpAndSettle();
    expect(find.text('Boa!'), findsNothing);
  });
}
