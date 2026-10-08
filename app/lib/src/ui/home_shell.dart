import 'dart:async';

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'communities_screen.dart';
import 'feed_screen.dart';
import 'friends_screen.dart';
import 'places_ui.dart';
import 'profile_screen.dart';

/// Navegação principal após o login: Feed, Amigos, Comunidades, Agenda e Perfil.
/// Mantém os contadores das bolinhas (atualizados ao trocar de aba, ao voltar
/// para o app e a cada minuto com o app aberto; sem notificações push).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.session});

  final SessionController session;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  final _friendsKey = GlobalKey<FriendsScreenState>();
  final _communitiesKey = GlobalKey<CommunitiesScreenState>();
  final _agendaKey = GlobalKey<AgendaScreenState>();
  final _counts = ValueNotifier<Counts>(const Counts());
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshCounts());
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshCounts(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _counts.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshCounts());
  }

  Future<void> _refreshCounts() async {
    final token = widget.session.token;
    if (token == null) return;
    try {
      final c = await widget.session.api.counts(token);
      if (mounted) _counts.value = c;
    } catch (_) {
      // Bolinhas são um extra: falha de rede não atrapalha o resto.
    }
  }

  void _select(int i) {
    setState(() => _index = i);
    // Abas recarregam ao serem abertas (pedidos novos).
    if (i == 1) _friendsKey.currentState?.refresh();
    if (i == 2) _communitiesKey.currentState?.refresh();
    if (i == 3) _agendaKey.currentState?.refresh();
    unawaited(_refreshCounts());
  }

  static Widget _badge(int n, IconData icon) => Badge(
    isLabelVisible: n > 0,
    label: Text(n > 99 ? '99+' : '$n'),
    child: Icon(icon),
  );

  @override
  Widget build(BuildContext context) {
    final username = widget.session.user?.username ?? '';
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          FeedScreen(
            session: widget.session,
            counts: _counts,
            onCountsChanged: _refreshCounts,
          ),
          FriendsScreen(key: _friendsKey, session: widget.session),
          CommunitiesScreen(key: _communitiesKey, session: widget.session),
          AgendaScreen(key: _agendaKey, session: widget.session),
          ProfileScreen(
            session: widget.session,
            username: username,
            asTab: true,
          ),
        ],
      ),
      bottomNavigationBar: ValueListenableBuilder<Counts>(
        valueListenable: _counts,
        builder: (context, c, _) => NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: [
            const NavigationDestination(
              key: Key('nav_feed'),
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Feed',
            ),
            NavigationDestination(
              key: const Key('nav_friends'),
              icon: _badge(c.friendRequests, Icons.people_outline),
              selectedIcon: _badge(c.friendRequests, Icons.people),
              label: 'Amigos',
            ),
            NavigationDestination(
              key: const Key('nav_communities'),
              icon: _badge(c.communityRequests, Icons.forum_outlined),
              selectedIcon: _badge(c.communityRequests, Icons.forum),
              label: 'Comunidades',
            ),
            const NavigationDestination(
              key: Key('nav_agenda'),
              icon: Icon(Icons.event_outlined),
              selectedIcon: Icon(Icons.event),
              label: 'Agenda',
            ),
            NavigationDestination(
              key: const Key('nav_profile'),
              icon: _badge(c.pendingTestimonials, Icons.person_outline),
              selectedIcon: _badge(c.pendingTestimonials, Icons.person),
              label: 'Perfil',
            ),
          ],
        ),
      ),
    );
  }
}
