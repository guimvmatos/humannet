import 'package:flutter/material.dart';

import '../auth/session_controller.dart';
import 'error_messages.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static final _usernamePattern = RegExp(r'^[a-z0-9_]{3,30}$');

  final _formKey = GlobalKey<FormState>();
  final _invite = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _invite.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.register(
        inviteCode: _invite.text.trim(),
        username: _username.text.trim().toLowerCase(),
        email: _email.text.trim(),
        password: _password.text,
      );
      // Sessão aberta: volta para a raiz, que agora mostra a home.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Criar conta')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'A HumanNet está em beta fechado. Para entrar, você precisa '
                  'do convite de alguém que já faz parte.',
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _invite,
                  decoration: const InputDecoration(
                    labelText: 'Código de convite',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _username,
                  decoration: const InputDecoration(
                    labelText: 'Nome de usuário',
                    helperText: '3–30 caracteres: letras, números ou _',
                  ),
                  autofillHints: const [AutofillHints.newUsername],
                  validator: (v) =>
                      _usernamePattern.hasMatch((v ?? '').trim().toLowerCase())
                      ? null
                      : 'Nome de usuário inválido',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'E-mail'),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  validator: (v) =>
                      (v ?? '').contains('@') ? null : 'E-mail inválido',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _password,
                  decoration: const InputDecoration(
                    labelText: 'Senha',
                    helperText: 'Mínimo de 12 caracteres',
                  ),
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: (v) {
                    final n = (v ?? '').runes.length;
                    return (n >= 12 && n <= 128)
                        ? null
                        : 'A senha deve ter entre 12 e 128 caracteres';
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Criar conta'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
