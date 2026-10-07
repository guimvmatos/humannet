import 'package:flutter/material.dart';

import '../auth/session_controller.dart';
import 'error_messages.dart';

/// Motivos de denúncia (códigos da API → texto).
const reportReasons = <String, String>{
  'harassment': 'Assédio ou bullying',
  'hate': 'Discurso de ódio',
  'violence': 'Violência ou ameaça',
  'sexual': 'Conteúdo sexual',
  'minor_safety': 'Risco a criança ou adolescente',
  'self_harm': 'Risco à própria vida',
  'misinformation': 'Informação falsa',
  'impersonation': 'Perfil falso ou se passando por alguém',
  'spam': 'Spam ou golpe',
  'other': 'Outro motivo',
};

/// Abre o diálogo de denúncia. Informe `postId` OU `username`.
/// Devolve `true` se a denúncia foi enviada.
Future<bool> showReportDialog(
  BuildContext context, {
  required SessionController session,
  String? postId,
  String? username,
}) async {
  final sent = await showDialog<bool>(
    context: context,
    builder: (_) =>
        _ReportDialog(session: session, postId: postId, username: username),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Denúncia enviada. Obrigado por cuidar da comunidade.'),
      ),
    );
  }
  return sent == true;
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.session, this.postId, this.username});

  final SessionController session;
  final String? postId;
  final String? username;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _details = TextEditingController();
  String? _reason;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final token = widget.session.token;
    final reason = _reason;
    if (token == null || reason == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.api.report(
        token,
        reason: reason,
        postId: widget.postId,
        username: widget.username,
        details: _details.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.postId != null ? 'Denunciar post' : 'Denunciar perfil',
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            RadioGroup<String>(
              groupValue: _reason,
              onChanged: (v) => setState(() => _reason = v),
              child: Column(
                children: [
                  for (final e in reportReasons.entries)
                    RadioListTile<String>(
                      key: Key('reason_${e.key}'),
                      value: e.key,
                      title: Text(e.value),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            TextField(
              controller: _details,
              maxLength: 1000,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Detalhes (opcional)',
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('send_report_button'),
          onPressed: _busy || _reason == null ? null : _send,
          child: const Text('Enviar'),
        ),
      ],
    );
  }
}
