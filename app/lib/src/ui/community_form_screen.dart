import 'package:flutter/material.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'error_messages.dart';

/// Criar comunidade (sem `existing`) ou editar (dono). Devolve a comunidade salva.
class CommunityFormScreen extends StatefulWidget {
  const CommunityFormScreen({super.key, required this.session, this.existing});

  final SessionController session;
  final Community? existing;

  @override
  State<CommunityFormScreen> createState() => _CommunityFormScreenState();
}

class _CommunityFormScreenState extends State<CommunityFormScreen> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _description = TextEditingController(
    text: widget.existing?.description,
  );
  late final _rules = TextEditingController(text: widget.existing?.rules);
  late String? _theme = widget.existing?.theme;
  late String _visibility = widget.existing?.visibility ?? 'public';
  bool _busy = false;
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _rules.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final token = widget.session.token;
    final theme = _theme;
    if (token == null) return;
    if (theme == null) {
      setState(() => _error = 'Escolha um tema.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = widget.session.api;
      final saved = _editing
          ? await api.updateCommunity(
              token,
              widget.existing!.slug,
              name: _name.text.trim(),
              description: _description.text.trim(),
              rules: _rules.text.trim(),
              theme: theme,
              visibility: _visibility,
            )
          : await api.createCommunity(
              token,
              name: _name.text.trim(),
              description: _description.text.trim(),
              rules: _rules.text.trim(),
              theme: theme,
              visibility: _visibility,
            );
      if (mounted) Navigator.of(context).pop(saved);
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
        title: Text(_editing ? 'Editar comunidade' : 'Nova comunidade'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('community_name_field'),
            controller: _name,
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nome'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const Key('community_theme_field'),
            initialValue: _theme,
            decoration: const InputDecoration(labelText: 'Tema'),
            items: [
              for (final e in communityThemes.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => _theme = v),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('community_description_field'),
            controller: _description,
            maxLength: 2000,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Descrição',
              hintText: 'Sobre o que é a comunidade?',
            ),
          ),
          TextField(
            key: const Key('community_rules_field'),
            controller: _rules,
            maxLength: 2000,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Regras (opcional)',
              hintText: 'Ex.: respeito sempre; nada de propaganda.',
            ),
          ),
          const SizedBox(height: 8),
          Text('Quem pode entrar', style: Theme.of(context).textTheme.titleSmall),
          RadioGroup<String>(
            groupValue: _visibility,
            onChanged: (v) => setState(() => _visibility = v ?? _visibility),
            child: const Column(
              children: [
                RadioListTile<String>(
                  key: Key('visibility_public'),
                  value: 'public',
                  title: Text('Aberta'),
                  subtitle: Text('Qualquer pessoa lê e entra.'),
                ),
                RadioListTile<String>(
                  key: Key('visibility_closed'),
                  value: 'closed',
                  title: Text('Fechada'),
                  subtitle: Text(
                    'Só membros leem os tópicos. Para entrar, um '
                    'moderador aprova.',
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('save_community_button'),
            onPressed: _busy ? null : _save,
            child: Text(_editing ? 'Salvar' : 'Criar comunidade'),
          ),
        ],
      ),
    );
  }
}
