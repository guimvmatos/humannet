import 'package:flutter/material.dart';

import '../auth/session_controller.dart';
import 'feed_screen.dart';
import 'friends_screen.dart';
import 'profile_screen.dart';

/// Navegação principal após o login: Feed e Perfil.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.session});

  final SessionController session;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _friendsKey = GlobalKey<FriendsScreenState>();

  void _select(int i) {
    setState(() => _index = i);
    // A aba Amigos recarrega ao ser aberta (pedidos novos).
    if (i == 1) _friendsKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final username = widget.session.user?.username ?? '';
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          FeedScreen(session: widget.session),
          FriendsScreen(key: _friendsKey, session: widget.session),
          ProfileScreen(
            session: widget.session,
            username: username,
            asTab: true,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
            key: Key('nav_feed'),
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Feed',
          ),
          NavigationDestination(
            key: Key('nav_friends'),
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Amigos',
          ),
          NavigationDestination(
            key: Key('nav_profile'),
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}
