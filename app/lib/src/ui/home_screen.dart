import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/session_controller.dart';
import 'error_messages.dart';

/// Tela inicial provisória (Fase 0). O feed entra na Fase 1.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _busy = false;

  Future<void> _createInvite() async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      final invite = await widget.session.api.createInvite(token);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Convite criado'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                invite.code,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Envie só para alguém que você conhece. '
                'O código vale para uma pessoa.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: invite.code));
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Copiar'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.session.user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('HumanNet'),
        actions: [
          IconButton(
            key: const Key('logout_button'),
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: widget.session.logout,
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Olá, @${user?.username ?? ''}',
                key: const Key('greeting'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'O feed chega na próxima fase. Por enquanto, convide pessoas '
                'reais que você conhece.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _createInvite,
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Gerar convite'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
