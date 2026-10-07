import 'dart:async';

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'error_messages.dart';
import 'photos.dart';
import 'post_list.dart' show relativeTime;
import 'report_dialog.dart';

/// Recados de um perfil (estilo scrapbook). Amigos escrevem; o dono do
/// perfil e o autor apagam.
class ScrapsScreen extends StatefulWidget {
  const ScrapsScreen({
    super.key,
    required this.session,
    required this.username,
    required this.canWrite,
  });

  final SessionController session;
  final String username;
  final bool canWrite;

  @override
  State<ScrapsScreen> createState() => _ScrapsScreenState();
}

class _ScrapsScreenState extends State<ScrapsScreen> {
  final _text = TextEditingController();
  final List<Scrap> _items = [];
  String? _cursor;
  bool _loaded = false;
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

  Future<void> _load({bool more = false}) async {
    final token = widget.session.token;
    if (token == null) return;
    try {
      final page = await widget.session.api.scraps(
        token,
        widget.username,
        before: more ? _cursor : null,
      );
      if (!mounted) return;
      setState(() {
        if (!more) _items.clear();
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _loaded = true;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _send() async {
    final token = widget.session.token;
    final body = _text.text.trim();
    if (token == null || body.isEmpty) return;
    setState(() => _sending = true);
    try {
      final s = await widget.session.api.writeScrap(
        token,
        widget.username,
        body,
      );
      _text.clear();
      if (mounted) setState(() => _items.insert(0, s));
    } catch (e) {
      _snack(errorMessage(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(Scrap s) async {
    final token = widget.session.token;
    if (token == null) return;
    try {
      await widget.session.api.deleteScrap(token, s.id);
      if (mounted) setState(() => _items.removeWhere((x) => x.id == s.id));
    } catch (e) {
      _snack(errorMessage(e));
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('scraps_screen'),
      appBar: AppBar(title: Text('Recados · @${widget.username}')),
      body: Column(
        children: [
          if (widget.canWrite)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('scrap_field'),
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Deixe um recado',
                        counterText: '',
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('send_scrap_button'),
                    tooltip: 'Enviar',
                    icon: const Icon(Icons.send),
                    onPressed: _sending || _text.text.trim().isEmpty
                        ? null
                        : _send,
                  ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
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
                  else if (!_loaded)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Nenhum recado ainda.',
                        key: Key('no_scraps'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  for (final s in _items)
                    ListTile(
                      key: Key('scrap_${s.id}'),
                      leading: UserAvatar(s.author),
                      title: Text(
                        '${s.author.label} · ${relativeTime(s.createdAt)}',
                        style: theme.textTheme.bodySmall,
                      ),
                      subtitle: Text(s.body, style: theme.textTheme.bodyMedium),
                      trailing: s.canDelete
                          ? IconButton(
                              key: Key('delete_scrap_${s.id}'),
                              tooltip: 'Apagar recado',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(s),
                            )
                          : IconButton(
                              tooltip: 'Denunciar',
                              icon: const Icon(Icons.flag_outlined),
                              onPressed: () => showReportDialog(
                                context,
                                session: widget.session,
                                scrapId: s.id,
                              ),
                            ),
                    ),
                  if (_cursor != null)
                    Center(
                      child: TextButton(
                        onPressed: () => _load(more: true),
                        child: const Text('Mais recados'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
