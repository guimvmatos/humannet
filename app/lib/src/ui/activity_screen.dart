import 'dart:async';

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'error_messages.dart';
import 'post_list.dart' show relativeTime;
import 'post_screen.dart';
import 'scraps_screen.dart';
import 'topic_screen.dart';
import 'photos.dart';

/// Novidades dos últimos 30 dias: comentários nos meus posts e respostas nos
/// tópicos em que participo. Abrir a tela marca tudo como visto.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, required this.session, this.onSeen});

  final SessionController session;

  /// Chamado depois de marcar como visto (para zerar a bolinha).
  final VoidCallback? onSeen;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  List<ActivityItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null) return;
    try {
      final api = widget.session.api;
      final items = await api.activity(token);
      if (mounted) setState(() => _items = items);
      await api.markActivitySeen(token);
      widget.onSeen?.call();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _open(ActivityItem a) async {
    final token = widget.session.token;
    if (token == null) return;
    if (a.kind == 'scrap') {
      final me = widget.session.user?.username;
      if (me == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ScrapsScreen(
            session: widget.session,
            username: me,
            canWrite: false,
          ),
        ),
      );
      return;
    }
    if (a.kind == 'reply') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              TopicScreen(session: widget.session, topicId: a.targetId),
        ),
      );
      return;
    }
    try {
      final post = await widget.session.api.post(token, a.targetId);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PostScreen(session: widget.session, post: post),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _items;
    return Scaffold(
      key: const Key('activity_screen'),
      appBar: AppBar(title: const Text('Novidades')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              )
            else if (items == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nada de novo nos últimos 30 dias.',
                  key: Key('no_activity'),
                  textAlign: TextAlign.center,
                ),
              )
            else
              for (final (i, a) in items.indexed)
                ListTile(
                  key: Key('activity_$i'),
                  leading: UserAvatar(a.actor),
                  title: Text(
                    switch (a.kind) {
                      'reply' =>
                        '${a.actor.label} respondeu em "${a.targetTitle}"',
                      'scrap' => '${a.actor.label} deixou um recado',
                      _ => '${a.actor.label} comentou no seu post',
                    },
                    style: a.unread
                        ? const TextStyle(fontWeight: FontWeight.bold)
                        : null,
                  ),
                  subtitle: Text(
                    '${a.excerpt}\n${relativeTime(a.createdAt)}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: true,
                  onTap: () => _open(a),
                ),
          ],
        ),
      ),
    );
  }
}
