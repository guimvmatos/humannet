import 'dart:async';

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'error_messages.dart';
import 'profile_screen.dart';

/// Aba "Amigos": pedidos recebidos (aceitar/recusar) e lista de amigos.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<FriendsScreen> createState() => FriendsScreenState();
}

class FriendsScreenState extends State<FriendsScreen> {
  List<FriendRequest> _requests = const [];
  List<Author> _friends = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    unawaited(_fetch());
  }

  /// Recarrega pedidos e amigos (chamado também ao abrir a aba).
  Future<void> refresh() async {
    if (mounted) setState(() => _error = null);
    await _fetch();
  }

  Future<void> _fetch() async {
    final token = widget.session.token;
    if (token == null) return;
    try {
      final api = widget.session.api;
      final results = await Future.wait([
        api.friendRequests(token),
        api.friends(token),
      ]);
      if (!mounted) return;
      setState(() {
        _requests = results[0] as List<FriendRequest>;
        _friends = results[1] as List<Author>;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _answer(FriendRequest r, {required bool accept}) async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() => _busy.add(r.user.username));
    try {
      final api = widget.session.api;
      if (accept) {
        await api.requestFriend(token, r.user.username);
      } else {
        await api.removeFriend(token, r.user.username);
      }
      await _fetch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(r.user.username));
    }
  }

  Future<void> _open(String username) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileScreen(session: widget.session, username: username),
      ),
    );
    // Ao voltar, a amizade pode ter mudado.
    await refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('friends_screen'),
      appBar: AppBar(title: const Text('Amigos')),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (_loading && _friends.isEmpty && _requests.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            if (_requests.isNotEmpty) ...[
              _SectionTitle('Pedidos de amizade (${_requests.length})'),
              for (final r in _requests)
                ListTile(
                  key: Key('request_${r.user.username}'),
                  title: Text(r.user.label),
                  subtitle: Text('@${r.user.username}'),
                  onTap: () => _open(r.user.username),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        key: Key('decline_${r.user.username}'),
                        tooltip: 'Recusar',
                        icon: const Icon(Icons.close),
                        onPressed: _busy.contains(r.user.username)
                            ? null
                            : () => _answer(r, accept: false),
                      ),
                      IconButton.filled(
                        key: Key('accept_${r.user.username}'),
                        tooltip: 'Aceitar',
                        icon: const Icon(Icons.check),
                        onPressed: _busy.contains(r.user.username)
                            ? null
                            : () => _answer(r, accept: true),
                      ),
                    ],
                  ),
                ),
              const Divider(),
            ],
            _SectionTitle('Seus amigos (${_friends.length})'),
            if (!_loading && _friends.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Você ainda não tem amigos aqui. Use a lupa no Feed para '
                  'encontrar alguém pelo @ e toque em "Adicionar".',
                ),
              ),
            for (final f in _friends)
              ListTile(
                key: Key('friend_${f.username}'),
                leading: const Icon(Icons.person_outline),
                title: Text(f.label),
                subtitle: Text('@${f.username}'),
                onTap: () => _open(f.username),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}
