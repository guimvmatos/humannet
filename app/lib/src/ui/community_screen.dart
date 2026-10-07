import 'dart:async';

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'community_form_screen.dart';
import 'community_members_screen.dart';
import 'error_messages.dart';
import 'new_topic_screen.dart';
import 'post_list.dart' show relativeTime;
import 'report_dialog.dart';
import 'topic_screen.dart';

/// Página de uma comunidade: descrição, regras, entrar/sair e tópicos.
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key, required this.session, required this.slug});

  final SessionController session;
  final String slug;

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  Community? _c;
  final List<Topic> _topics = [];
  String? _cursor;
  bool _loadingMore = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  String? get _token => widget.session.token;

  Future<void> _load() async {
    final token = _token;
    if (token == null) return;
    try {
      final c = await widget.session.api.community(token, widget.slug);
      Paged<Topic>? page;
      if (c.canRead) {
        page = await widget.session.api.topics(token, widget.slug);
      }
      if (!mounted) return;
      setState(() {
        _c = c;
        _error = null;
        _topics
          ..clear()
          ..addAll(page?.items ?? const []);
        _cursor = page?.nextCursor;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _more() async {
    final token = _token;
    final cursor = _cursor;
    if (token == null || cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.session.api.topics(
        token,
        widget.slug,
        before: cursor,
      );
      if (!mounted) return;
      setState(() {
        _topics.addAll(page.items);
        _cursor = page.nextCursor;
      });
    } catch (e) {
      _snack(errorMessage(e));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _join() async {
    final token = _token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      final status = await widget.session.api.joinCommunity(token, widget.slug);
      if (status == 'pending') {
        _snack('Pedido enviado. Um moderador vai aprovar.');
      }
      await _load();
    } catch (e) {
      _snack(errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    final token = _token;
    final c = _c;
    if (token == null || c == null) return;
    final ok = await _confirm(
      c.isPending ? 'Cancelar o pedido?' : 'Sair de ${c.name}?',
      c.isClosed && !c.isPending
          ? 'A comunidade é fechada: para voltar, vai precisar de aprovação.'
          : null,
      c.isPending ? 'Cancelar pedido' : 'Sair',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await widget.session.api.leaveCommunity(token, widget.slug);
      await _load();
    } catch (e) {
      _snack(errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String? body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: body == null ? null : Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            key: const Key('confirm_button'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _menu(String action) async {
    final c = _c;
    final token = _token;
    if (c == null || token == null) return;
    switch (action) {
      case 'edit':
        final saved = await Navigator.of(context).push<Community>(
          MaterialPageRoute(
            builder: (_) =>
                CommunityFormScreen(session: widget.session, existing: c),
          ),
        );
        if (saved != null) await _load();
      case 'members':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                CommunityMembersScreen(session: widget.session, community: c),
          ),
        );
        await _load();
      case 'report':
        await showReportDialog(
          context,
          session: widget.session,
          communitySlug: c.slug,
        );
      case 'delete':
        final ok = await _confirm(
          'Apagar ${c.name}?',
          'A comunidade e todos os tópicos somem para todo mundo. '
              'Não dá para desfazer.',
          'Apagar',
        );
        if (!ok) return;
        try {
          await widget.session.api.deleteCommunity(token, c.slug);
          if (mounted) Navigator.of(context).pop();
        } catch (e) {
          _snack(errorMessage(e));
        }
    }
  }

  Future<void> _newTopic() async {
    final created = await Navigator.of(context).push<Topic>(
      MaterialPageRoute(
        builder: (_) => NewTopicScreen(session: widget.session, slug: widget.slug),
      ),
    );
    if (created != null) {
      await _load();
      if (mounted) await _openTopic(created.id);
    }
  }

  Future<void> _openTopic(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TopicScreen(session: widget.session, topicId: id),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = _c;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: _error != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                )
              : const CircularProgressIndicator(),
        ),
      );
    }
    return Scaffold(
      key: const Key('community_screen'),
      appBar: AppBar(
        title: Text(c.name),
        actions: [
          PopupMenuButton<String>(
            key: const Key('community_menu'),
            onSelected: _menu,
            itemBuilder: (_) => [
              if (c.isOwner || (c.canModerate && !c.isMember))
                const PopupMenuItem(value: 'edit', child: Text('Editar')),
              if (c.isMember || c.canModerate)
                PopupMenuItem(
                  key: const Key('members_item'),
                  value: 'members',
                  child: Text(
                    c.canModerate && (c.pendingCount ?? 0) > 0
                        ? 'Membros (${c.pendingCount} pedidos)'
                        : 'Membros',
                  ),
                ),
              if (!c.isOwner)
                const PopupMenuItem(
                  value: 'report',
                  child: Text('Denunciar comunidade'),
                ),
              if (c.isOwner || (c.canModerate && !c.isMember))
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Apagar comunidade'),
                ),
            ],
          ),
        ],
      ),
      floatingActionButton: c.canPost
          ? FloatingActionButton.extended(
              heroTag: 'new_topic_fab',
              key: const Key('new_topic_button'),
              onPressed: _newTopic,
              icon: const Icon(Icons.edit),
              label: const Text('Novo tópico'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${c.themeLabel} · ${c.isClosed ? 'fechada' : 'aberta'}'
                    '${c.memberCount != null ? ' · ${c.memberCount} membros (só moderadores veem)' : ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (c.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(c.description),
                  ],
                  if (c.rules.isNotEmpty)
                    ExpansionTile(
                      key: const Key('rules_tile'),
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Regras'),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(c.rules),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  const SizedBox(height: 8),
                  _membershipButton(c),
                ],
              ),
            ),
            const Divider(),
            if (!c.canRead)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Comunidade fechada: só membros veem os tópicos.',
                  key: Key('closed_notice'),
                  textAlign: TextAlign.center,
                ),
              )
            else if (_topics.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nenhum tópico ainda.',
                  key: Key('no_topics'),
                  textAlign: TextAlign.center,
                ),
              )
            else ...[
              for (final t in _topics)
                ListTile(
                  key: Key('topic_${t.id}'),
                  leading: t.pinned
                      ? const Icon(Icons.push_pin, size: 20)
                      : t.locked
                      ? const Icon(Icons.lock_outline, size: 20)
                      : null,
                  title: Text(t.title),
                  subtitle: Text(
                    '${t.author.label} · ${t.replyCount} '
                    '${t.replyCount == 1 ? 'resposta' : 'respostas'} · '
                    '${relativeTime(t.lastActivityAt)}',
                  ),
                  onTap: () => _openTopic(t.id),
                ),
              if (_cursor != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Center(
                    child: _loadingMore
                        ? const CircularProgressIndicator()
                        : TextButton(
                            key: const Key('more_topics_button'),
                            onPressed: _more,
                            child: const Text('Mais tópicos'),
                          ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _membershipButton(Community c) {
    if (c.isBanned) {
      return const Text('Você foi removido desta comunidade.');
    }
    if (c.isOwner) {
      return const Text('Você é o dono desta comunidade.');
    }
    if (c.isMember) {
      return OutlinedButton(
        key: const Key('leave_community_button'),
        onPressed: _busy ? null : _leave,
        child: const Text('Sair da comunidade'),
      );
    }
    if (c.isPending) {
      return OutlinedButton(
        key: const Key('cancel_join_button'),
        onPressed: _busy ? null : _leave,
        child: const Text('Aguardando aprovação · cancelar'),
      );
    }
    return FilledButton(
      key: const Key('join_community_button'),
      onPressed: _busy ? null : _join,
      child: Text(c.isClosed ? 'Pedir para entrar' : 'Entrar'),
    );
  }
}
