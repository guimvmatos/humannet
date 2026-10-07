import 'dart:async';

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'error_messages.dart';
import 'profile_screen.dart';

/// Membros de uma comunidade. Quem modera também vê pedidos e removidos.
class CommunityMembersScreen extends StatefulWidget {
  const CommunityMembersScreen({
    super.key,
    required this.session,
    required this.community,
  });

  final SessionController session;
  final Community community;

  @override
  State<CommunityMembersScreen> createState() => _CommunityMembersScreenState();
}

class _CommunityMembersScreenState extends State<CommunityMembersScreen> {
  List<Member>? _active;
  List<Member>? _pending;
  List<Member>? _banned;
  final Set<String> _busy = {};
  String? _error;

  Community get _c => widget.community;
  bool get _mod => _c.canModerate;

  /// Dono (ou admin da plataforma, que modera sem ser membro).
  bool get _boss => _c.isOwner || (_mod && !_c.isMember);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null) return;
    final api = widget.session.api;
    try {
      final active = await api.members(token, _c.slug);
      List<Member>? pending;
      List<Member>? banned;
      if (_mod) {
        pending = await api.members(token, _c.slug, status: 'pending');
        banned = await api.members(token, _c.slug, status: 'banned');
      }
      if (!mounted) return;
      setState(() {
        _active = active;
        _pending = pending;
        _banned = banned;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _act(Member m, String action) async {
    final token = widget.session.token;
    if (token == null) return;
    if (action == 'transfer') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Passar a comunidade para ${m.user.label}?'),
          content: const Text(
            'A pessoa vira dona e você vira moderador. Só ela poderá '
            'desfazer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              key: const Key('confirm_button'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Transferir'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy.add(m.user.username));
    try {
      await widget.session.api.memberAction(
        token,
        _c.slug,
        m.user.username,
        action,
      );
      if (action == 'transfer' && mounted) {
        Navigator.of(context).pop();
        return;
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(m.user.username));
    }
  }

  List<PopupMenuEntry<String>> _actionsFor(Member m) {
    final me = widget.session.user?.username;
    if (m.user.username == me || m.role == 'owner') return const [];
    return [
      if (_boss && m.role == 'member')
        const PopupMenuItem(value: 'promote', child: Text('Tornar moderador')),
      if (_boss && m.role == 'moderator')
        const PopupMenuItem(value: 'demote', child: Text('Tirar moderação')),
      if (_c.isOwner)
        const PopupMenuItem(value: 'transfer', child: Text('Passar a comunidade')),
      if (_mod && (m.role == 'member' || _boss))
        const PopupMenuItem(value: 'ban', child: Text('Remover e bloquear')),
    ];
  }

  void _openProfile(String username) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ProfileScreen(session: widget.session, username: username),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    final pending = _pending;
    final banned = _banned;
    return Scaffold(
      key: const Key('members_screen'),
      appBar: AppBar(title: Text('Membros · ${_c.name}')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!),
              ),
            if (pending != null && pending.isNotEmpty) ...[
              const _Header('Pedidos para entrar'),
              for (final m in pending)
                ListTile(
                  key: Key('pending_${m.user.username}'),
                  title: Text(m.user.label),
                  subtitle: Text('@${m.user.username}'),
                  onTap: () => _openProfile(m.user.username),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        key: Key('reject_${m.user.username}'),
                        tooltip: 'Recusar',
                        icon: const Icon(Icons.close),
                        onPressed: _busy.contains(m.user.username)
                            ? null
                            : () => _act(m, 'reject'),
                      ),
                      IconButton(
                        key: Key('approve_${m.user.username}'),
                        tooltip: 'Aprovar',
                        icon: const Icon(Icons.check),
                        onPressed: _busy.contains(m.user.username)
                            ? null
                            : () => _act(m, 'approve'),
                      ),
                    ],
                  ),
                ),
            ],
            const _Header('Membros'),
            if (active == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              for (final m in active)
                ListTile(
                  key: Key('member_${m.user.username}'),
                  title: Text(m.user.label),
                  subtitle: Text('@${m.user.username} · ${m.roleLabel}'),
                  onTap: () => _openProfile(m.user.username),
                  trailing: _actionsFor(m).isEmpty
                      ? null
                      : PopupMenuButton<String>(
                          key: Key('member_menu_${m.user.username}'),
                          enabled: !_busy.contains(m.user.username),
                          onSelected: (a) => _act(m, a),
                          itemBuilder: (_) => _actionsFor(m),
                        ),
                ),
            if (banned != null && banned.isNotEmpty) ...[
              const _Header('Removidos'),
              for (final m in banned)
                ListTile(
                  key: Key('banned_${m.user.username}'),
                  title: Text(m.user.label),
                  subtitle: Text('@${m.user.username}'),
                  trailing: TextButton(
                    key: Key('unban_${m.user.username}'),
                    onPressed: _busy.contains(m.user.username)
                        ? null
                        : () => _act(m, 'unban'),
                    child: const Text('Permitir voltar'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}
