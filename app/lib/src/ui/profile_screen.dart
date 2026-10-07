import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'edit_profile_screen.dart';
import 'error_messages.dart';
import 'post_list.dart';

/// Perfil de um usuário. `asTab: true` = aba "Perfil" do próprio usuário
/// (sem botão de voltar).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.session,
    required this.username,
    this.asTab = false,
  });

  final SessionController session;
  final String username;
  final bool asTab;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _listKey = GlobalKey<PagedPostListState>();
  Profile? _profile;
  String? _error;
  bool _busy = false;

  String? get _token => widget.session.token;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfile());
  }

  Future<void> _loadProfile() async {
    final token = _token;
    if (token == null) return;
    try {
      final p = await widget.session.api.profile(token, widget.username);
      if (mounted) setState(() => _profile = p);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  /// Ação principal do botão de amizade, conforme a relação atual.
  Future<void> _friendAction({bool decline = false}) async {
    final p = _profile;
    final token = _token;
    if (p == null || token == null) return;

    if (p.relation == Relation.friends) {
      final ok = await _confirm(
        'Desfazer amizade?',
        'Vocês deixam de ver os posts um do outro. @${p.username} não é avisado.',
        'Desfazer',
      );
      if (!ok) return;
    }

    setState(() => _busy = true);
    try {
      final api = widget.session.api;
      final Relation next;
      if (decline ||
          p.relation == Relation.friends ||
          p.relation == Relation.requestSent) {
        await api.removeFriend(token, p.username);
        next = Relation.none;
      } else {
        next = await api.requestFriend(token, p.username);
      }
      if (mounted) setState(() => _profile = p.copyWith(relation: next));
    } catch (e) {
      _snack(errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('confirm_button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _editProfile() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(session: widget.session),
      ),
    );
    if (changed == true) await _loadProfile();
  }

  Future<void> _createInvite() async {
    final token = _token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      final invite = await widget.session.api.createInvite(token);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Convite criado'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                invite.code,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Envie só para alguém que você conhece. '
                'O código vale para uma pessoa.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: invite.code));
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Copiar'),
            ),
          ],
        ),
      );
    } catch (e) {
      _snack(errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    final isSelf = p?.isSelf ?? false;
    return Scaffold(
      key: const Key('profile_screen'),
      appBar: AppBar(
        automaticallyImplyLeading: !widget.asTab,
        title: Text('@${widget.username}'),
        actions: [
          if (isSelf)
            IconButton(
              key: const Key('logout_button'),
              tooltip: 'Sair',
              icon: const Icon(Icons.logout),
              onPressed: widget.session.logout,
            ),
        ],
      ),
      body: _body(p, isSelf),
    );
  }

  Widget _body(Profile? p, bool isSelf) {
    if (_error != null && p == null) return Center(child: Text(_error!));
    if (p == null) return const Center(child: CircularProgressIndicator());

    final header = _Header(
      profile: p,
      busy: _busy,
      onFriendAction: () => _friendAction(),
      onDecline: () => _friendAction(decline: true),
      onEdit: _editProfile,
      onInvite: _createInvite,
    );

    // Posts só para o próprio e amigos (ADR-0006). Sem chamar a API.
    if (!p.relation.canSeePosts) {
      return RefreshIndicator(
        onRefresh: _loadProfile,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            header,
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Os posts de @${p.username} aparecem só para amigos.',
                key: const Key('friends_only'),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return PagedPostList(
      key: _listKey,
      onRefresh: _loadProfile,
      session: widget.session,
      loader: (before) => widget.session.api.userPosts(
        _token ?? '',
        widget.username,
        before: before,
      ),
      header: header,
      emptyText: isSelf ? 'Você ainda não publicou nada.' : 'Nenhum post ainda.',
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.profile,
    required this.busy,
    required this.onFriendAction,
    required this.onDecline,
    required this.onEdit,
    required this.onInvite,
  });

  final Profile profile;
  final bool busy;
  final VoidCallback onFriendAction;
  final VoidCallback onDecline;
  final VoidCallback onEdit;
  final VoidCallback onInvite;

  List<Widget> _friendButtons() {
    final onTap = busy ? null : onFriendAction;
    return switch (profile.relation) {
      Relation.self => const [],
      Relation.none => [
        FilledButton.icon(
          key: const Key('friend_button'),
          onPressed: onTap,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Adicionar'),
        ),
      ],
      Relation.requestSent => [
        OutlinedButton.icon(
          key: const Key('friend_button'),
          onPressed: onTap,
          icon: const Icon(Icons.schedule),
          label: const Text('Pedido enviado · cancelar'),
        ),
      ],
      Relation.requestReceived => [
        FilledButton.icon(
          key: const Key('friend_button'),
          onPressed: onTap,
          icon: const Icon(Icons.check),
          label: const Text('Aceitar amizade'),
        ),
        OutlinedButton(
          key: const Key('decline_button'),
          onPressed: busy ? null : onDecline,
          child: const Text('Recusar'),
        ),
      ],
      Relation.friends => [
        OutlinedButton.icon(
          key: const Key('friend_button'),
          onPressed: onTap,
          icon: const Icon(Icons.people),
          label: const Text('Amigos'),
        ),
      ],
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = profile.stats;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            profile.displayName ?? '@${profile.username}',
            key: const Key('profile_name'),
            style: theme.textTheme.headlineSmall,
          ),
          if (profile.displayName != null)
            Text('@${profile.username}', style: theme.textTheme.bodyMedium),
          if (profile.bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(profile.bio),
          ],
          if (profile.relation == Relation.requestReceived) ...[
            const SizedBox(height: 12),
            Text(
              '@${profile.username} quer ser seu amigo.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (stats != null) ...[
            const SizedBox(height: 12),
            Text(
              '${stats.posts} posts · ${stats.friends} amigos',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              'Só você vê esses números.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: profile.isSelf
                ? [
                    OutlinedButton.icon(
                      key: const Key('edit_profile_button'),
                      onPressed: busy ? null : onEdit,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Editar perfil'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : onInvite,
                      icon: const Icon(Icons.person_add_alt),
                      label: const Text('Gerar convite'),
                    ),
                  ]
                : _friendButtons(),
          ),
          const Divider(height: 32),
        ],
      ),
    );
  }
}
