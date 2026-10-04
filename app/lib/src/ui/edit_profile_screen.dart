import 'package:flutter/material.dart';

import '../auth/session_controller.dart';
import 'error_messages.dart';

/// Edita nome de exibição e bio. Retorna `true` via Navigator se salvou.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _bio;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = widget.session.user;
    _name = TextEditingController(text: user?.displayName ?? '');
    _bio = TextEditingController(text: user?.bio ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await widget.session.api.updateProfile(
        token,
        displayName: _name.text.trim(),
        bio: _bio.text.trim(),
      );
      widget.session.updateUser(user);
      if (mounted) Navigator.of(context).pop(true);
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
        title: const Text('Editar perfil'),
        actions: [
          TextButton(
            key: const Key('save_profile_button'),
            onPressed: _busy ? null : _save,
            child: const Text('Salvar'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            key: const Key('display_name_field'),
            controller: _name,
            maxLength: 50,
            decoration: const InputDecoration(
              labelText: 'Nome de exibição',
              helperText: 'Opcional. Deixe vazio para mostrar só o @usuário.',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('bio_field'),
            controller: _bio,
            maxLength: 300,
            maxLines: 5,
            minLines: 3,
            decoration: const InputDecoration(labelText: 'Bio'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
