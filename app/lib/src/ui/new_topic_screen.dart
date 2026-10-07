import 'package:flutter/material.dart';

import '../auth/session_controller.dart';
import 'error_messages.dart';

/// Novo tópico numa comunidade. Devolve o tópico criado.
class NewTopicScreen extends StatefulWidget {
  const NewTopicScreen({super.key, required this.session, required this.slug});

  final SessionController session;
  final String slug;

  @override
  State<NewTopicScreen> createState() => _NewTopicScreenState();
}

class _NewTopicScreenState extends State<NewTopicScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = await widget.session.api.createTopic(
        token,
        widget.slug,
        title: _title.text.trim(),
        body: _body.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(t);
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
        title: const Text('Novo tópico'),
        actions: [
          TextButton(
            key: const Key('publish_topic_button'),
            onPressed: _busy || _title.text.trim().length < 3
                ? null
                : _publish,
            child: const Text('Publicar'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('topic_title_field'),
            controller: _title,
            maxLength: 150,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Título'),
          ),
          TextField(
            key: const Key('topic_body_field'),
            controller: _body,
            maxLength: 5000,
            minLines: 5,
            maxLines: 15,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Texto (opcional)',
              alignLabelWithHint: true,
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }
}
