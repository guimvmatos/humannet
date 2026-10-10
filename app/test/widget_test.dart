import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humannet/src/api/api_client.dart';
import 'package:humannet/src/auth/session_controller.dart';
import 'package:humannet/src/auth/token_store.dart';
import 'package:humannet/src/theme/theme_controller.dart';
import 'package:humannet/src/ui/app.dart';
import 'package:humannet/src/ui/compose_screen.dart';
import 'package:humannet/src/ui/cpf.dart';
import 'package:humannet/src/ui/events_map.dart';

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

  testWidgets('esqueci minha senha com código do admin', (tester) async {
    final backend = FakeBackend();
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));

    await tester.tap(find.byKey(const Key('forgot_password_button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('reset_user_field')), 'alice');
    await tester.enterText(
      find.byKey(const Key('reset_code_field')),
      'abcde23456',
    );
    await tester.enterText(
      find.byKey(const Key('reset_new_password_field')),
      'senha-nova-segura-1',
    );
    await tester.tap(find.byKey(const Key('reset_submit_button')));
    await tester.pumpAndSettle();

    expect(backend.currentPassword, 'senha-nova-segura-1');
    expect(find.byKey(const Key('login_button')), findsOneWidget);
  });

  testWidgets('admin vê fila de denúncias e resolve', (tester) async {
    final backend = FakeBackend()..isAdmin = true;
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);

    await tester.tap(find.byKey(const Key('nav_profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('moderation_tile')));
    await tester.pumpAndSettle();

    expect(find.text('texto ofensivo'), findsOneWidget);
    await tester.tap(find.byKey(const Key('remove_r1')));
    await tester.pumpAndSettle();
    expect(backend.resolved, ['remove_content']);
    expect(find.byKey(const Key('no_reports')), findsOneWidget);
  });

  testWidgets('quem não é admin não vê moderação', (tester) async {
    final backend = FakeBackend();
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);

    await tester.tap(find.byKey(const Key('nav_profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('moderation_tile')), findsNothing);
  });

  testWidgets('comunidades: explorar, entrar, criar tópico e responder', (
    tester,
  ) async {
    final backend = FakeBackend();
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);

    await tester.tap(find.byKey(const Key('nav_communities')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('no_communities')), findsOneWidget);

    await tester.tap(find.byKey(const Key('explore_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('community_rock-sp')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('community_screen')), findsOneWidget);
    expect(find.byKey(const Key('new_topic_button')), findsNothing);

    await tester.tap(find.byKey(const Key('join_community_button')));
    await tester.pumpAndSettle();
    expect(backend.rockStatus, 'active');
    expect(find.byKey(const Key('leave_community_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('new_topic_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('topic_title_field')),
      'Melhor show do ano',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('publish_topic_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('topic_screen')), findsOneWidget);
    expect(find.text('Melhor show do ano'), findsOneWidget);
    expect(find.byKey(const Key('no_replies')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('reply_field')), 'Foi demais!');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_reply_button')));
    await tester.pumpAndSettle();
    expect(backend.replies.single['body'], 'Foi demais!');
    expect(find.text('Foi demais!'), findsOneWidget);
  });

  testWidgets('criar comunidade abre a página dela', (tester) async {
    final backend = FakeBackend();
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);

    await tester.tap(find.byKey(const Key('nav_communities')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create_community_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('community_name_field')),
      'Família Matos',
    );
    await tester.tap(find.byKey(const Key('community_theme_field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Música').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('visibility_closed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('visibility_closed')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('save_community_button')));
    await tester.tap(find.byKey(const Key('save_community_button')));
    await tester.pumpAndSettle();

    final sent = backend.createdCommunities.single;
    expect(sent['name'], 'Família Matos');
    expect(sent['theme'], 'musica');
    expect(sent['visibility'], 'closed');
    expect(find.byKey(const Key('community_screen')), findsOneWidget);
    expect(find.text('Você é o dono desta comunidade.'), findsOneWidget);
  });

  testWidgets('aprovar depoimento no próprio perfil', (tester) async {
    final backend = FakeBackend();
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);

    await tester.tap(find.byKey(const Key('nav_profile')));
    await tester.pumpAndSettle();
    expect(find.text('Depoimentos (1 para aprovar)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('testimonials_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pending_testimonial_d1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('approve_testimonial_d1')));
    await tester.pumpAndSettle();
    expect(backend.carolTestimonial, 'approved');
    expect(find.byKey(const Key('pending_testimonial_d1')), findsNothing);
    expect(find.byKey(const Key('testimonial_d1')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Depoimentos'), findsOneWidget);
  });

  testWidgets('bolinhas e novidades', (tester) async {
    final backend = FakeBackend();
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);

    // Pedido de carol (Amigos) e depoimento pendente (Perfil).
    final badges = tester.widgetList<Badge>(find.byType(Badge)).toList();
    expect(badges.where((b) => b.isLabelVisible).length, 4);

    await tester.tap(find.byKey(const Key('activity_button')));
    await tester.pumpAndSettle();
    expect(find.text('Bob comentou no seu post'), findsOneWidget);
    expect(backend.activitySeen, isTrue);

    await tester.tap(find.byKey(const Key('activity_0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('post_screen')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    final after = tester.widgetList<Badge>(find.byType(Badge)).toList();
    expect(after.where((b) => b.isLabelVisible).length, 3);
  });

  testWidgets('trocar o tema do app', (tester) async {
    final backend = FakeBackend();
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    final store = InMemoryPrefsStore();
    final themes = ThemeController(store);
    await tester.pumpWidget(HumanNetApp(session: session, themes: themes));
    await _login(tester);

    await tester.tap(find.byKey(const Key('nav_profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('appearance_tile')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('palette_rosa')));
    await tester.pumpAndSettle();
    expect(themes.palette.id, 'rosa');
    expect(store.values['theme_palette'], 'rosa');

    await tester.tap(find.text('Escuro'));
    await tester.pumpAndSettle();
    expect(themes.mode, ThemeMode.dark);

    // Recarregar lê a preferência salva.
    final again = ThemeController(store);
    await again.load();
    expect(again.palette.id, 'rosa');
    expect(again.mode, ThemeMode.dark);
  });

  testWidgets('sugestões de amizade com motivo', (tester) async {
    final backend = FakeBackend();
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);

    await tester.tap(find.byKey(const Key('nav_friends')));
    await tester.pumpAndSettle();
    expect(
      find.text('@dave · 2 amigos em comum · Também é de Recife'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(const Key('suggest_add_dave')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('suggest_add_dave')));
    await tester.pumpAndSettle();
    expect(backend.daveSuggestion, 'requested');
    expect(find.byKey(const Key('suggestion_dave')), findsNothing);
  });

  testWidgets('post com foto: envia a foto e depois o post', (tester) async {
    // PNG 1×1 válido.
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );
    final backend = FakeBackend();
    final session = _session(backend, InMemoryTokenStore());
    await session.login(
      login: FakeBackend.username,
      password: FakeBackend.password,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open_compose'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ComposeScreen(
                    session: session,
                    pickPhotos: (limit) async => [png, png],
                  ),
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_compose')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add_photos_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('compose_photo_1')), findsOneWidget);
    expect(find.text('Fotos (2/4)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('remove_photo_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('compose_photo_1')), findsNothing);

    // Só foto, sem texto, já pode publicar.
    await tester.tap(find.byKey(const Key('publish_button')));
    await tester.pumpAndSettle();
    expect(backend.uploads.single.$1, 'post');
    expect(backend.uploads.single.$2, png);
    expect(backend.lastMediaIds, ['m1']);
  });

  testWidgets('status no próprio perfil e recado para um amigo', (
    tester,
  ) async {
    final backend = FakeBackend()..bobRelation = 'friends';
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);

    await tester.tap(find.byKey(const Key('nav_profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('status_line')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('status_field')), 'de férias');
    await tester.tap(find.text('3 dias'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('save_status_button')));
    await tester.pumpAndSettle();
    expect(backend.status, 'de férias');
    expect(backend.statusHours, 72);
    expect(find.text('de férias'), findsOneWidget);

    // Recado no perfil de bob (amigo).
    await tester.tap(find.byKey(const Key('nav_feed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Encontrar pessoa'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('find_person_field')), 'bob');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scraps_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('no_scraps')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('scrap_field')), 'Saudades!');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_scrap_button')));
    await tester.pumpAndSettle();
    expect(backend.bobScraps.single['body'], 'Saudades!');
    expect(find.text('Saudades!'), findsOneWidget);
  });

  testWidgets('cadastro exige aceitar as regras', (tester) async {
    final backend = FakeBackend();
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await tester.tap(find.text('Tenho um convite'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('register_button')));
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('register_button')),
    );
    expect(button.onPressed, isNull);
    await tester.ensureVisible(find.byKey(const Key('accept_rules')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('accept_rules')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('register_button')))
          .onPressed,
      isNotNull,
    );
  });

  test('validação de CPF', () {
    expect(isValidCpf('529.982.247-25'), isTrue);
    expect(isValidCpf('52998224725'), isTrue);
    expect(isValidCpf('529.982.247-24'), isFalse);
    expect(isValidCpf('111.111.111-11'), isFalse);
    expect(isValidCpf('123'), isFalse);
  });

  testWidgets('conta antiga sem CPF: pede antes de entrar', (tester) async {
    final backend = FakeBackend()..needsCpf = true;
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);

    expect(find.byKey(const Key('cpf_screen')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('cpf_field')), '123');
    await tester.tap(find.byKey(const Key('save_cpf_button')));
    await tester.pump();
    expect(find.text('CPF inválido. Confira os números.'), findsOneWidget);
    expect(backend.cpfSent, isNull);

    await tester.enterText(find.byKey(const Key('cpf_field')), '529.982.247-25');
    await tester.tap(find.byKey(const Key('save_cpf_button')));
    await tester.pumpAndSettle();
    expect(backend.cpfSent, '529.982.247-25');
    expect(find.byKey(const Key('feed_screen')), findsOneWidget);
  });

  testWidgets('agenda: acompanhar um lugar e marcar "vou"', (tester) async {
    final backend = FakeBackend();
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);

    await tester.tap(find.byKey(const Key('nav_agenda')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('empty_agenda')), findsOneWidget);

    await tester.tap(find.byKey(const Key('places_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('place_bar-do-ze')));
    await tester.pumpAndSettle();
    expect(find.text('CNPJ 11.222.333/0001-81'), findsOneWidget);
    await tester.tap(find.byKey(const Key('follow_place_button')));
    await tester.pumpAndSettle();
    expect(backend.followingBar, isTrue);
    expect(find.text('Acompanhando'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('event_e1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('event_e1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('event_screen')), findsOneWidget);
    expect(find.text('1 amigo marcou interesse'), findsOneWidget);
    await tester.tap(find.text('Vou'));
    await tester.pumpAndSettle();
    expect(backend.interest, 'going');

    // Volta para a agenda: o evento aparece.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('event_e1')), findsOneWidget);
  });

  testWidgets('criar página de lugar com CNPJ', (tester) async {
    final backend = FakeBackend();
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);

    await tester.tap(find.byKey(const Key('nav_agenda')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('places_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create_place_button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('place_name_field')), 'Meu Bar');
    await tester.tap(find.byKey(const Key('place_category_field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bar').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('place_cnpj_field')),
      '11.222.333/0001-81',
    );
    expect(find.byKey(const Key('place_rules_note')), findsOneWidget);
    // CEP preenche rua, bairro e cidade.
    await tester.ensureVisible(find.byKey(const Key('place_cep_field')));
    await tester.enterText(find.byKey(const Key('place_cep_field')), '18035-000');
    await tester.pumpAndSettle();
    final address = tester.widget<TextField>(
      find.byKey(const Key('place_address_field')),
    );
    expect(address.controller!.text, 'Rua XV de Novembro,  - Centro');
    final city = tester.widget<TextField>(
      find.byKey(const Key('place_city_field')),
    );
    expect(city.controller!.text, 'Sorocaba - SP');
    await tester.ensureVisible(find.byKey(const Key('save_place_button')));
    await tester.tap(find.byKey(const Key('save_place_button')));
    await tester.pumpAndSettle();

    expect(backend.createdPlaces.single['cnpj'], '11.222.333/0001-81');
    expect(backend.createdPlaces.single['cep'], '18035-000');
    expect(find.byKey(const Key('place_screen')), findsOneWidget);
    expect(find.byKey(const Key('new_event_button')), findsOneWidget);
    expect(find.byKey(const Key('place_role_note')), findsOneWidget);

    // Publicar no mural.
    await tester.tap(find.byKey(const Key('place_post_button')));
    await tester.pumpAndSettle();
    expect(find.text('Post como Meu Bar'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('compose_field')), 'Abrimos!');
    await tester.pump();
    await tester.tap(find.byKey(const Key('publish_button')));
    await tester.pumpAndSettle();
    expect(backend.pagePosts.single['body'], 'Abrimos!');
    await tester.scrollUntilVisible(
      find.text('Abrimos!'),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('place_screen')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.textContaining('por @alice'), findsOneWidget);
  });

  testWidgets('mensagem para página exige acompanhar', (tester) async {
    final backend = FakeBackend();
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);

    await tester.tap(find.byKey(const Key('nav_agenda')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('places_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('place_bar-do-ze')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('place_message_button')));
    await tester.pumpAndSettle();
    expect(find.text('Acompanhe a página para mandar mensagem.'), findsOneWidget);
    expect(backend.pageConversationOpened, isFalse);

    await tester.tap(find.byKey(const Key('follow_place_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('place_message_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat_screen')), findsOneWidget);
    expect(backend.pageConversationOpened, isTrue);
  });

  testWidgets('mensagens: badge, abrir conversa e enviar', (tester) async {
    final backend = FakeBackend()..bobRelation = 'friends';
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);

    final badge = find.descendant(
      of: find.byKey(const Key('messages_button')),
      matching: find.text('1'),
    );
    expect(badge, findsOneWidget);

    await tester.tap(find.byKey(const Key('messages_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conversations_screen')), findsOneWidget);
    await tester.tap(find.byKey(const Key('conversation_cv1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat_screen')), findsOneWidget);
    expect(find.text('Oi Alice!'), findsOneWidget);
    expect(backend.chatRead, isTrue);

    await tester.enterText(find.byKey(const Key('message_field')), 'Oi Bob');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();
    expect(find.text('Oi Bob'), findsOneWidget);
    expect(backend.chat.last['body'], 'Oi Bob');

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(badge, findsNothing);
  });

  testWidgets('perfil de amigo tem botão Mensagem', (tester) async {
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

    await tester.tap(find.byKey(const Key('message_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat_screen')), findsOneWidget);
  });

  testWidgets('mapa de eventos: pino abre os eventos do lugar', (tester) async {
    mapOfflineForTests = true;
    final backend = FakeBackend();
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);

    await tester.tap(find.byKey(const Key('nav_agenda')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('events_map_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('events_map_screen')), findsOneWidget);
    // Espera o debounce do movimento do mapa.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(backend.calls, contains('GET /v1/events/map'));
    expect(find.text('1 evento(s) nesta área'), findsOneWidget);

    await tester.tap(find.byKey(const Key('map_pin_bar-do-ze')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('map_place_sheet')), findsOneWidget);
    expect(find.text('Samba de sexta'), findsOneWidget);
    await tester.tap(find.byKey(const Key('map_event_e1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('event_screen')), findsOneWidget);
  });

  testWidgets('tema com fundo ilustrado e opção sem fundo', (tester) async {
    final store = InMemoryPrefsStore();
    final themes = ThemeController(store);
    final backend = FakeBackend();
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session, themes: themes));
    await _login(tester);
    expect(find.byKey(const Key('themed_background')), findsNothing);

    await themes.setPalette(appPalettes.firstWhere((p) => p.id == 'espaco'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('themed_background')), findsOneWidget);
    expect(store.values['theme_palette'], 'espaco');

    await themes.setBackgroundMode(BackgroundMode.none);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('themed_background')), findsNothing);

    // Sem foto salva, "minha foto" não liga.
    await themes.setBackgroundMode(BackgroundMode.photo);
    expect(themes.backgroundMode, BackgroundMode.none);

    final again = ThemeController(store);
    await again.load();
    expect(again.backgroundMode, BackgroundMode.none);
    expect(again.palette.id, 'espaco');
  });

  testWidgets('minha história: adicionar faculdade com curso', (tester) async {
    final backend = FakeBackend();
    final session = _session(backend, InMemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(HumanNetApp(session: session));
    await _login(tester);

    await tester.tap(find.byKey(const Key('nav_profile')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('timeline_button')));
    await tester.tap(find.byKey(const Key('timeline_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('timeline_empty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('timeline_add_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add_kind_faculdade')));
    await tester.pumpAndSettle();

    // Cidade (IBGE).
    await tester.tap(find.byKey(const Key('life_city')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('picker_field')), 'soro');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('picker_result_0')));
    await tester.pumpAndSettle();
    expect(find.text('Sorocaba - SP'), findsOneWidget);

    // Faculdade nova (não estava no catálogo).
    await tester.tap(find.byKey(const Key('life_org')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('picker_field')), 'UFSCar Sorocaba');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('picker_create')));
    await tester.pumpAndSettle();
    expect(backend.createdOrgs, ['UFSCar Sorocaba']);

    // Curso.
    await tester.tap(find.byKey(const Key('life_course')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('picker_field')), 'comp');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('picker_result_0')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('life_start')), '2011');
    await tester.enterText(find.byKey(const Key('life_end')), '2015');
    await tester.ensureVisible(find.byKey(const Key('life_save')));
    await tester.tap(find.byKey(const Key('life_save')));
    await tester.pumpAndSettle();

    final saved = backend.timeline.single;
    expect(saved['kind'], 'faculdade');
    expect(saved['org']! as Map, containsPair('id', 'o1'));
    expect(saved['start_year'], 2011);
    expect(saved['end_year'], 2015);
    expect(saved['visibility'], 'friends');
    expect(find.text('Ciência da Computação · UFSCar Sorocaba'), findsOneWidget);
  });
}
