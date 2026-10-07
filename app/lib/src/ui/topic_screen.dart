import 'dart:async';

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'error_messages.dart';
import 'post_list.dart' show relativeTime;
import 'report_dialog.dart';

/// Um tópico com as respostas (da mais antiga à mais nova) e o campo de resposta.
class TopicScreen extends StatefulWidget {
  const TopicScreen({super.key, required this.session, required this.topicId});

  final SessionController session;
  final String topicId;

  @override
  State<TopicScreen> createState() => _TopicScreenState();
}

class _TopicScreenState extends State<TopicScreen> {
  final _text = TextEditingController();
  Topic? _topic;
  final List<Reply> _replies = [];
  String? _cursor;
  bool _loadingMore = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    unawaited(_load());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String? get _token => widget.session.token;

  Future<void> _load() async {
    final token = _token;
    if (token == null) return;
    try {
      final api = widget.session.api;
      final t = await api.topic(token, widget.topicId);
      final page = await api.replies(token, widget.topicId);
      if (!mounted) return;
      setState(() {
        _topic = t;
        _error = null;
        _replies
          ..clear()
          ..addAll(page.items);
        _cursor = page.nextCursor;
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
      final page = await widget.session.api.replies(
        token,
        widget.topicId,
        after: cursor,
      );
      if (!mounted) return;
      setState(() {
        _replies.addAll(page.items);
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

  Future<void> _send() async {
    final token = _token;
    final body = _text.text.trim();
    if (token == null || body.isEmpty) return;
    setState(() => _sending = true);
    try {
      final r = await widget.session.api.addReply(token, widget.topicId, body);
      _text.clear();
      // Só acrescenta no fim quando já se está vendo o fim da conversa.
      if (mounted && _cursor == null) setState(() => _replies.add(r));
    } catch (e) {
      _snack(errorMessage(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteReply(Reply r) async {
    final token = _token;
    if (token == null) return;
    try {
      await widget.session.api.deleteReply(token, r.id);
      if (mounted) setState(() => _replies.removeWhere((x) => x.id == r.id));
    } catch (e) {
      _snack(errorMessage(e));
    }
  }

  Future<void> _menu(String action) async {
    final t = _topic;
    final token = _token;
    if (t == null || token == null) return;
    final api = widget.session.api;
    try {
      switch (action) {
        case 'pin':
          await api.updateTopic(token, t.id, pinned: !t.pinned);
          await _load();
        case 'lock':
          await api.updateTopic(token, t.id, locked: !t.locked);
          await _load();
        case 'report':
          await showReportDialog(
            context,
            session: widget.session,
            topicId: t.id,
          );
        case 'delete':
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Apagar este tópico?'),
              content: const Text('As respostas somem junto.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Voltar'),
                ),
                FilledButton(
                  key: const Key('confirm_button'),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Apagar'),
                ),
              ],
            ),
          );
          if (ok != true) return;
          await api.deleteTopic(token, t.id);
          if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      _snack(errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = _topic;
    if (t == null) {
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
    final mine = t.author.id == widget.session.user?.id;
    return Scaffold(
      key: const Key('topic_screen'),
      appBar: AppBar(
        title: Text(t.communityName),
        actions: [
          PopupMenuButton<String>(
            key: const Key('topic_menu'),
            onSelected: _menu,
            itemBuilder: (_) => [
              if (t.canModerate) ...[
                PopupMenuItem(
                  key: const Key('pin_item'),
                  value: 'pin',
                  child: Text(t.pinned ? 'Desafixar' : 'Fixar no topo'),
                ),
                PopupMenuItem(
                  key: const Key('lock_item'),
                  value: 'lock',
                  child: Text(t.locked ? 'Destrancar' : 'Trancar'),
                ),
              ],
              if (t.canDelete)
                const PopupMenuItem(
                  key: Key('delete_topic_item'),
                  value: 'delete',
                  child: Text('Apagar tópico'),
                ),
              if (!mine)
                const PopupMenuItem(
                  value: 'report',
                  child: Text('Denunciar tópico'),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.title, style: theme.textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          '${t.author.label} · ${relativeTime(t.createdAt)}'
                          '${t.pinned ? ' · fixado' : ''}'
                          '${t.locked ? ' · trancado' : ''}',
                          style: theme.textTheme.bodySmall,
                        ),
                        if (t.body.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(t.body),
                        ],
                      ],
                    ),
                  ),
                  const Divider(),
                  if (_replies.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Nenhuma resposta ainda.',
                        key: Key('no_replies'),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    for (final r in _replies)
                      ListTile(
                        key: Key('reply_${r.id}'),
                        title: Text(
                          '${r.author.label} · ${relativeTime(r.createdAt)}',
                          style: theme.textTheme.bodySmall,
                        ),
                        subtitle: Text(
                          r.body,
                          style: theme.textTheme.bodyMedium,
                        ),
                        trailing: r.canDelete
                            ? IconButton(
                                key: Key('delete_reply_${r.id}'),
                                tooltip: 'Apagar resposta',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deleteReply(r),
                              )
                            : IconButton(
                                key: Key('report_reply_${r.id}'),
                                tooltip: 'Denunciar resposta',
                                icon: const Icon(Icons.flag_outlined),
                                onPressed: () => showReportDialog(
                                  context,
                                  session: widget.session,
                                  replyId: r.id,
                                ),
                              ),
                      ),
                  if (_cursor != null)
                    Center(
                      child: _loadingMore
                          ? const Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(),
                            )
                          : TextButton(
                              key: const Key('more_replies_button'),
                              onPressed: _more,
                              child: const Text('Mais respostas'),
                            ),
                    ),
                ],
              ),
            ),
          ),
          if (t.canReply)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('reply_field'),
                        controller: _text,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: 5000,
                        decoration: const InputDecoration(
                          hintText: 'Responder',
                          counterText: '',
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('send_reply_button'),
                      tooltip: 'Enviar',
                      icon: const Icon(Icons.send),
                      onPressed: _sending || _text.text.trim().isEmpty
                          ? null
                          : _send,
                    ),
                  ],
                ),
              ),
            )
          else
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  t.locked
                      ? 'Tópico trancado.'
                      : 'Entre na comunidade para responder.',
                  key: const Key('cannot_reply_notice'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
