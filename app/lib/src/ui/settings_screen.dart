import 'dart:async';

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'appearance_screen.dart';
import 'interests_screen.dart';
import 'error_messages.dart';
import 'moderation_screen.dart';
import 'rules_screen.dart';

/// Configurações da conta: senha, bloqueados, excluir conta, sair.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        children: [
          if (session.user?.isAdmin ?? false) ...[
            ListTile(
              key: const Key('moderation_tile'),
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Moderação'),
              subtitle: const Text('Denúncias e códigos de senha'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ModerationScreen(session: session),
                ),
              ),
            ),
            const Divider(),
          ],
          ListTile(
            key: const Key('rules_tile'),
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Regras de convivência'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const RulesScreen()),
            ),
          ),
          ListTile(
            key: const Key('interests_tile'),
            leading: const Icon(Icons.tune),
            title: const Text('Meus interesses'),
            subtitle: const Text('O que o "Para você" aprendeu (só neste celular)'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => InterestsScreen(profile: session.interests),
              ),
            ),
          ),
          ListTile(
            key: const Key('appearance_tile'),
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Aparência'),
            subtitle: const Text('Tema e modo claro/escuro'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AppearanceScreen()),
            ),
          ),
          ListTile(
            key: const Key('change_password_tile'),
            leading: const Icon(Icons.lock_outline),
            title: const Text('Trocar senha'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ChangePasswordScreen(session: session),
              ),
            ),
          ),
          ListTile(
            key: const Key('blocked_tile'),
            leading: const Icon(Icons.block),
            title: const Text('Pessoas bloqueadas'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => BlockedScreen(session: session),
              ),
            ),
          ),
          const Divider(),
          ListTile(
            key: const Key('logout_tile'),
            leading: const Icon(Icons.logout),
            title: const Text('Sair'),
            onTap: () async {
              Navigator.of(context).popUntil((r) => r.isFirst);
              await session.logout();
            },
          ),
          ListTile(
            key: const Key('delete_account_tile'),
            leading: Icon(
              Icons.delete_forever,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Excluir minha conta',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DeleteAccountScreen(session: session),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final token = widget.session.token;
    if (token == null) return;
    final n = _new.text.runes.length;
    if (n < 12 || n > 128) {
      setState(() => _error = 'A nova senha deve ter entre 12 e 128 caracteres.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.api.changePassword(
        token,
        currentPassword: _current.text,
        newPassword: _new.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Senha trocada. Outros aparelhos foram desconectados.'),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = errorMessage(e) == 'Usuário ou senha incorretos.'
              ? 'Senha atual incorreta.'
              : errorMessage(e),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trocar senha')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            key: const Key('current_password_field'),
            controller: _current,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Senha atual'),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('new_password_field'),
            controller: _new,
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
            key: const Key('save_password_button'),
            onPressed: _busy ? null : _save,
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}

class BlockedScreen extends StatefulWidget {
  const BlockedScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<BlockedScreen> createState() => _BlockedScreenState();
}

class _BlockedScreenState extends State<BlockedScreen> {
  List<Author>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null) return;
    try {
      final items = await widget.session.api.blocks(token);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _unblock(Author a) async {
    final token = widget.session.token;
    if (token == null) return;
    try {
      await widget.session.api.unblock(token, a.username);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Pessoas bloqueadas')),
      body: _error != null
          ? Center(child: Text(_error!))
          : items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? const Center(child: Text('Você não bloqueou ninguém.'))
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Quem você bloqueia não vê seu perfil nem seus posts, e '
                    'você não vê os dela. Ninguém é avisado. Desbloquear não '
                    'refaz a amizade.',
                  ),
                ),
                for (final a in items)
                  ListTile(
                    key: Key('blocked_${a.username}'),
                    title: Text(a.label),
                    subtitle: Text('@${a.username}'),
                    trailing: TextButton(
                      key: Key('unblock_${a.username}'),
                      onPressed: () => _unblock(a),
                      child: const Text('Desbloquear'),
                    ),
                  ),
              ],
            ),
    );
  }
}

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _password = TextEditingController();
  bool _confirmed = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.api.deleteAccount(token, _password.text);
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      await widget.session.logout();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = errorMessage(e) == 'Usuário ou senha incorretos.'
              ? 'Senha incorreta.'
              : errorMessage(e),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Excluir conta')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Isto apaga de forma definitiva:',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            '• seu perfil e seu nome de usuário\n'
            '• todos os seus posts\n'
            '• suas amizades e pedidos\n'
            '• seus convites não usados\n\n'
            'Não dá para desfazer.',
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            key: const Key('confirm_delete_checkbox'),
            value: _confirmed,
            onChanged: (v) => setState(() => _confirmed = v ?? false),
            title: const Text('Entendo que isto é definitivo.'),
            contentPadding: EdgeInsets.zero,
          ),
          TextField(
            key: const Key('delete_password_field'),
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Sua senha'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('delete_account_button'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: _busy || !_confirmed ? null : _delete,
            child: const Text('Excluir minha conta'),
          ),
        ],
      ),
    );
  }
}
