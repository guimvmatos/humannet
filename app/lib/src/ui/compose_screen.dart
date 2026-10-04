import 'package:flutter/material.dart';

import '../auth/session_controller.dart';
import 'error_messages.dart';

/// Escreve um post de texto. Retorna o `Post` criado via Navigator.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  static const _max = 5000;

  final _text = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _canPublish => !_busy && _text.text.trim().isNotEmpty;

  Future<void> _publish() async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final post = await widget.session.api.createPost(token, _text.text);
      if (mounted) Navigator.of(context).pop(post);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Novo post'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              key: const Key('publish_button'),
              onPressed: _canPublish ? _publish : null,
              child: const Text('Publicar'),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: TextField(
                key: const Key('compose_field'),
                controller: _text,
                autofocus: true,
                maxLength: _max,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: 'O que você quer compartilhar?',
                  border: InputBorder.none,
                ),
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
    );
  }
}
