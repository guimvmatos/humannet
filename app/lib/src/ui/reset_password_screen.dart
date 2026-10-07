import 'package:flutter/material.dart';

import '../api/api_client.dart';
import 'error_messages.dart';

/// "Esqueci minha senha": no beta, o código vem de um administrador.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _username = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final n = _password.text.runes.length;
    if (n < 12 || n > 128) {
      setState(() => _error = 'A nova senha deve ter entre 12 e 128 caracteres.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.resetPassword(
        username: _username.text.trim().replaceFirst('@', '').toLowerCase(),
        code: _code.text.trim(),
        newPassword: _password.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Senha trocada. Entre com a nova senha.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Esqueci minha senha')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Durante o beta, peça um código de redefinição para quem administra '
            'a HumanNet. O código vale 24 horas e só pode ser usado uma vez.',
          ),
          const SizedBox(height: 24),
          TextField(
            key: const Key('reset_user_field'),
            controller: _username,
            decoration: const InputDecoration(labelText: 'Nome de usuário'),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('reset_code_field'),
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Código'),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('reset_new_password_field'),
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Nova senha',
              helperText: 'Mínimo de 12 caracteres',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('reset_submit_button'),
            onPressed: _busy ? null : _submit,
            child: const Text('Trocar senha'),
          ),
        ],
      ),
    );
  }
}
