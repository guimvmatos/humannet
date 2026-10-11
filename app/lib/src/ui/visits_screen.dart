import 'package:flutter/material.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'error_messages.dart';
import 'photos.dart';
import 'profile_screen.dart';

/// "Hoje", "ontem", "3 dias atrás" (só o dia, sem hora).
String visitDay(String day, {DateTime? now}) {
  final d = DateTime.parse(day);
  final t = now ?? DateTime.now();
  final today = DateTime(t.year, t.month, t.day);
  final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;
  return switch (diff) {
    <= 0 => 'hoje',
    1 => 'ontem',
    _ => '$diff dias atrás',
  };
}

/// Quem visitou meu perfil (últimos 30 dias). Recíproco: desligado, não vejo
/// e não apareço. Sem notificação nem contador.
class VisitsScreen extends StatefulWidget {
  const VisitsScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<VisitsScreen> createState() => _VisitsScreenState();
}

class _VisitsScreenState extends State<VisitsScreen> {
  VisitsInfo? _info;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null) return;
    try {
      final info = await widget.session.api.visits(token);
      if (mounted) setState(() => _info = info);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _set(bool on) async {
    final token = widget.session.token;
    if (token == null) return;
    if (!on) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Desligar as visitas?'),
          content: const Text(
            'Você deixa de ver quem te visitou e deixa de aparecer quando '
            'visitar alguém. As visitas guardadas são apagadas.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const Key('visits_off_confirm'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Desligar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      final info = await widget.session.api.setVisits(token, enabled: on);
      if (mounted) setState(() => _info = info);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('visits_screen'),
      appBar: AppBar(title: const Text('Quem visitou meu perfil')),
      body: info == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(_error!),
            )
          : ListView(
              children: [
                SwitchListTile(
                  key: const Key('visits_switch'),
                  value: info.enabled,
                  onChanged: _busy ? null : _set,
                  title: const Text('Ver e aparecer nas visitas'),
                  subtitle: const Text(
                    'É de mão dupla: desligado, você não vê quem te visitou e '
                    'também não aparece para os outros. Mostra só o dia, '
                    'guarda por 30 dias e não manda notificação.',
                  ),
                ),
                const Divider(),
                if (!info.enabled)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Visitas desligadas.'),
                  )
                else if (info.visitors.isEmpty)
                  const Padding(
                    key: Key('visits_empty'),
                    padding: EdgeInsets.all(24),
                    child: Text('Ninguém nos últimos 30 dias.'),
                  )
                else
                  for (final v in info.visitors)
                    ListTile(
                      key: Key('visitor_${v.author.username}'),
                      leading: UserAvatar(v.author),
                      title: Text(v.author.label),
                      subtitle: Text(
                        '@${v.author.username} · ${visitDay(v.day)}',
                        style: theme.textTheme.bodySmall,
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ProfileScreen(
                            session: widget.session,
                            username: v.author.username,
                          ),
                        ),
                      ),
                    ),
              ],
            ),
    );
  }
}
