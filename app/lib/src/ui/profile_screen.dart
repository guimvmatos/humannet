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

  Future<void> _toggleFollow() async {
    final p = _profile;
    final token = _token;
    if (p == null || token == null) return;
    setState(() => _busy = true);
    try {
      if (p.isFollowing) {
        await widget.session.api.unfollow(token, p.username);
      } else {
        await widget.session.api.follow(token, p.username);
      }
      if (mounted) {
        setState(() => _profile = p.copyWith(isFollowing: !p.isFollowing));
      }
    } catch (e) {
      _snack(errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
      body: _error != null && p == null
          ? Center(child: Text(_error!))
          : PagedPostList(
                key: _listKey,
                onRefresh: _loadProfile,
                session: widget.session,
                loader: (before) => widget.session.api.userPosts(
                  _token ?? '',
                  widget.username,
                  before: before,
                ),
                header: p == null
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _Header(
                        profile: p,
                        busy: _busy,
                        onToggleFollow: _toggleFollow,
                        onEdit: _editProfile,
                        onInvite: _createInvite,
                      ),
                emptyText: isSelf
                    ? 'Você ainda não publicou nada.'
                    : 'Nenhum post ainda.',
              ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.profile,
    required this.busy,
    required this.onToggleFollow,
    required this.onEdit,
    required this.onInvite,
  });

  final Profile profile;
  final bool busy;
  final VoidCallback onToggleFollow;
  final VoidCallback onEdit;
  final VoidCallback onInvite;

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
          if (stats != null) ...[
            const SizedBox(height: 12),
            Text(
              '${stats.posts} posts · ${stats.followers} seguidores · '
              '${stats.following} seguindo',
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
                : [
                    profile.isFollowing
                        ? OutlinedButton(
                            key: const Key('follow_button'),
                            onPressed: busy ? null : onToggleFollow,
                            child: const Text('Seguindo'),
                          )
                        : FilledButton(
                            key: const Key('follow_button'),
                            onPressed: busy ? null : onToggleFollow,
                            child: const Text('Seguir'),
                          ),
                  ],
          ),
          const Divider(height: 32),
        ],
      ),
    );
  }
}
