import 'package:flutter/material.dart';

import '../auth/session_controller.dart';
import 'feed_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    final username = widget.session.user?.username ?? '';
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          FeedScreen(session: widget.session),
          ProfileScreen(
            session: widget.session,
            username: username,
            asTab: true,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            key: Key('nav_feed'),
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Feed',
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
