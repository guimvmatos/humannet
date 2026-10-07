import 'package:flutter/material.dart';

import '../auth/session_controller.dart';
import 'error_messages.dart';

/// Confere os dígitos verificadores (mesma regra do servidor).
bool isValidCpf(String raw) {
  final d = raw.replaceAll(RegExp(r'[.\- ]'), '');
  if (!RegExp(r'^\d{11}$').hasMatch(d)) return false;
  if (d.split('').every((c) => c == d[0])) return false;
  int check(int n) {
    var sum = 0;
    for (var i = 0; i < n; i++) {
      sum += int.parse(d[i]) * (n + 1 - i);
    }
    final r = (sum * 10) % 11;
    return r == 10 ? 0 : r;
  }

  return check(9) == int.parse(d[9]) && check(10) == int.parse(d[10]);
}

const cpfHelp =
    'Uma conta por pessoa. Não guardamos o número: só um código que não '
    'dá para reverter, usado para evitar contas repetidas.';

/// Contas criadas antes da exigência informam o CPF uma vez.
class CpfScreen extends StatefulWidget {
  const CpfScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<CpfScreen> createState() => _CpfScreenState();
}

class _CpfScreenState extends State<CpfScreen> {
  final _cpf = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _cpf.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final token = widget.session.token;
    if (token == null) return;
    if (!isValidCpf(_cpf.text)) {
      setState(() => _error = 'CPF inválido. Confira os números.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.api.setCpf(token, _cpf.text.trim());
      await widget.session.refreshUser();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('cpf_screen'),
      appBar: AppBar(
        title: const Text('Confirme seu CPF'),
        actions: [
          TextButton(
            onPressed: widget.session.logout,
            child: const Text('Sair'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'A HumanNet agora pede o CPF de cada conta, para garantir uma '
            'pessoa por conta. É só uma vez.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('cpf_field'),
            controller: _cpf,
            keyboardType: TextInputType.number,
            maxLength: 14,
            decoration: const InputDecoration(
              labelText: 'CPF',
              hintText: '000.000.000-00',
              helperText: cpfHelp,
              helperMaxLines: 3,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('save_cpf_button'),
            onPressed: _busy ? null : _save,
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }
}
