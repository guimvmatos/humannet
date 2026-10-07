import 'dart:async';

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'error_messages.dart';
import 'post_list.dart' show relativeTime;
import 'report_dialog.dart';
import 'photos.dart';

/// Depoimentos de um perfil. No próprio perfil, mostra também os que esperam
/// aprovação. Amigos podem escrever (ou reescrever) o seu.
class TestimonialsScreen extends StatefulWidget {
  const TestimonialsScreen({
    super.key,
    required this.session,
    required this.username,
    required this.isSelf,
    required this.canWrite,
  });

  final SessionController session;
  final String username;
  final bool isSelf;
  final bool canWrite;

  @override
  State<TestimonialsScreen> createState() => _TestimonialsScreenState();
}

class _TestimonialsScreenState extends State<TestimonialsScreen> {
  List<Testimonial>? _items;
  List<Testimonial> _pending = const [];
  final Set<String> _busy = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  String? get _me => widget.session.user?.username;

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null) return;
    try {
      final api = widget.session.api;
      final items = await api.testimonials(token, widget.username);
      final pending = widget.isSelf
          ? await api.pendingTestimonials(token)
          : const <Testimonial>[];
      if (!mounted) return;
      setState(() {
        _items = items.where((t) => !t.isPending || !widget.isSelf).toList();
        _pending = pending;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _run(String id, Future<void> Function(String token) f) async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() => _busy.add(id));
    try {
      await f(token);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Testimonial? get _mine =>
      _items?.where((t) => t.author.username == _me).firstOrNull;

  Future<void> _write() async {
    final mine = _mine;
    final controller = TextEditingController(text: mine?.body);
    final body = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          mine == null ? 'Depoimento para @${widget.username}' : 'Reescrever',
        ),
        content: TextField(
          key: const Key('testimonial_field'),
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Escreva algo sobre essa pessoa.',
            helperText: 'Só aparece no perfil depois que ela aprovar.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('send_testimonial_button'),
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (body == null || body.isEmpty) return;
    await _run('write', (token) async {
      await widget.session.api.writeTestimonial(token, widget.username, body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enviado. Aparece quando a pessoa aprovar.'),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _items;
    return Scaffold(
      key: const Key('testimonials_screen'),
      appBar: AppBar(title: Text('Depoimentos · @${widget.username}')),
      floatingActionButton: widget.canWrite && !widget.isSelf
          ? FloatingActionButton.extended(
              heroTag: 'testimonial_fab',
              key: const Key('write_testimonial_button'),
              onPressed: _busy.contains('write') ? null : _write,
              icon: const Icon(Icons.edit),
              label: Text(_mine == null ? 'Escrever' : 'Reescrever o meu'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            if (_pending.isNotEmpty) ...[
              const _Header('Esperando sua aprovação'),
              for (final t in _pending)
                Card(
                  key: Key('pending_testimonial_${t.id}'),
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${t.author.label} · ${relativeTime(t.createdAt)}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(t.body),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton(
                              key: Key('reject_testimonial_${t.id}'),
                              onPressed: _busy.contains(t.id)
                                  ? null
                                  : () => _run(
                                      t.id,
                                      (token) => widget.session.api
                                          .deleteTestimonial(token, t.id),
                                    ),
                              child: const Text('Recusar'),
                            ),
                            FilledButton(
                              key: Key('approve_testimonial_${t.id}'),
                              onPressed: _busy.contains(t.id)
                                  ? null
                                  : () => _run(
                                      t.id,
                                      (token) => widget.session.api
                                          .approveTestimonial(token, t.id),
                                    ),
                              child: const Text('Aprovar'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            if (items == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  widget.isSelf
                      ? 'Ninguém escreveu um depoimento para você ainda.'
                      : 'Nenhum depoimento ainda.',
                  key: const Key('no_testimonials'),
                  textAlign: TextAlign.center,
                ),
              )
            else
              for (final t in items)
                ListTile(
                  key: Key('testimonial_${t.id}'),
                  leading: UserAvatar(t.author),
                  title: Text(
                    '${t.author.label} · ${relativeTime(t.createdAt)}'
                    '${t.isPending ? ' · esperando aprovação' : ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                  subtitle: Text(t.body, style: theme.textTheme.bodyMedium),
                  trailing: t.canDelete
                      ? IconButton(
                          key: Key('delete_testimonial_${t.id}'),
                          tooltip: 'Remover',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: _busy.contains(t.id)
                              ? null
                              : () => _run(
                                  t.id,
                                  (token) => widget.session.api
                                      .deleteTestimonial(token, t.id),
                                ),
                        )
                      : IconButton(
                          tooltip: 'Denunciar',
                          icon: const Icon(Icons.flag_outlined),
                          onPressed: () => showReportDialog(
                            context,
                            session: widget.session,
                            testimonialId: t.id,
                          ),
                        ),
                ),
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
