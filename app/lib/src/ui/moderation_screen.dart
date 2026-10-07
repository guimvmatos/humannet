import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'error_messages.dart';
import 'post_list.dart';
import 'report_dialog.dart';

/// Fila de denúncias abertas (só administradores) e código de senha.
class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen> {
  List<AdminReport>? _reports;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null) return;
    try {
      final r = await widget.session.api.adminReports(token);
      if (mounted) setState(() => _reports = r);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _resolve(AdminReport r, String action) async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() => _busy.add(r.id));
    try {
      await widget.session.api.resolveReport(token, r.id, action);
      _snack(switch (action) {
        'remove_content' => 'Conteúdo removido.',
        'suspend_user' => '@${r.targetUsername} suspenso.',
        _ => 'Denúncia descartada.',
      });
      await _load();
    } catch (e) {
      _snack(errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  Future<void> _resetCode() async {
    final controller = TextEditingController();
    final username = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Código para redefinir senha'),
        content: TextField(
          key: const Key('reset_username_field'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            prefixText: '@',
            labelText: 'Usuário que esqueceu a senha',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('generate_code_button'),
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Gerar'),
          ),
        ],
      ),
    );
    final name = username?.trim().replaceFirst('@', '').toLowerCase() ?? '';
    final token = widget.session.token;
    if (name.isEmpty || token == null || !mounted) return;
    try {
      final c = await widget.session.api.createResetCode(token, name);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Código para @$name'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                c.code,
                key: const Key('reset_code_text'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Envie para a pessoa por um canal confiável (ex.: '
                'WhatsApp direto). Vale 24 h e uma única vez. Ela usa em '
                '"Esqueci minha senha" na tela de login.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: c.code));
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Copiar'),
            ),
          ],
        ),
      );
    } catch (e) {
      _snack(errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final reports = _reports;
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('moderation_screen'),
      appBar: AppBar(
        title: const Text('Moderação'),
        actions: [
          IconButton(
            key: const Key('reset_code_button'),
            tooltip: 'Código para redefinir senha',
            icon: const Icon(Icons.key),
            onPressed: _resetCode,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error))
            else if (reports == null)
              const Center(child: CircularProgressIndicator())
            else if (reports.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nenhuma denúncia aberta.',
                  key: Key('no_reports'),
                  textAlign: TextAlign.center,
                ),
              )
            else
              for (final r in reports)
                Card(
                  key: Key('report_${r.id}'),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_kindLabel(r.kind)} de '
                          '@${r.targetUsername ?? '(apagado)'}'
                          '${r.targetSuspended ? ' · suspenso' : ''}',
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          '${reportReasons[r.reason] ?? r.reason} · '
                          'por @${r.reporterUsername ?? '(conta apagada)'} · '
                          '${relativeTime(r.createdAt)}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Text(r.snapshot),
                        ),
                        if (r.details.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text('Detalhes: ${r.details}'),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton(
                              key: Key('dismiss_${r.id}'),
                              onPressed: _busy.contains(r.id)
                                  ? null
                                  : () => _resolve(r, 'dismiss'),
                              child: const Text('Descartar'),
                            ),
                            if (r.kind != 'user')
                              FilledButton.tonal(
                                key: Key('remove_${r.id}'),
                                onPressed: _busy.contains(r.id)
                                    ? null
                                    : () => _resolve(r, 'remove_content'),
                                child: Text(
                                  r.kind == 'community'
                                      ? 'Apagar comunidade'
                                      : 'Remover',
                                ),
                              ),
                            if (!r.targetSuspended && r.targetUsername != null)
                              FilledButton(
                                key: Key('suspend_${r.id}'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: theme.colorScheme.error,
                                  foregroundColor: theme.colorScheme.onError,
                                ),
                                onPressed: _busy.contains(r.id)
                                    ? null
                                    : () => _resolve(r, 'suspend_user'),
                                child: const Text('Suspender'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

String _kindLabel(String kind) => switch (kind) {
  'post' => 'Post',
  'comment' => 'Comentário',
  'topic' => 'Tópico',
  'reply' => 'Resposta em tópico',
  'community' => 'Comunidade (dono)',
  'testimonial' => 'Depoimento',
  _ => 'Perfil',
};
