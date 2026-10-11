import 'package:flutter/material.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'error_messages.dart';
import 'events_ui.dart' show formatWhen;
import 'places_ui.dart';

/// Pedido para criar um coletivo estudantil (república, atlética, CA,
/// grupo): sem CNPJ, com e-mail institucional e aprovação da administração.
class CollectiveRequestScreen extends StatefulWidget {
  const CollectiveRequestScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<CollectiveRequestScreen> createState() =>
      _CollectiveRequestScreenState();
}

class _CollectiveRequestScreenState extends State<CollectiveRequestScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _email = TextEditingController();
  final _code = TextEditingController();
  String _category = 'republica';
  OrganizerRequest? _request;
  bool _loaded = false;
  bool _busy = false;
  bool _newRequest = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _email, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null) return;
    try {
      final r = await widget.session.api.myOrganizerRequest(token);
      if (mounted) {
        setState(() {
          _request = r;
          _loaded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorMessage(e);
          _loaded = true;
        });
      }
    }
  }

  Future<void> _run(Future<OrganizerRequest?> Function(String token) f) async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await f(token);
      if (mounted && r != null) {
        setState(() {
          _request = r;
          _newRequest = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _rules(ThemeData theme) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        'Como funciona (fase de teste, UFSCar):\n'
        '• Precisa de e-mail institucional da UFSCar.\n'
        '• A equipe da HumanNet aprova o pedido.\n'
        '• Você fica como responsável, com o nome visível nos eventos.\n'
        '• Os 2 primeiros eventos passam por revisão; depois saem direto.\n'
        '• No máximo 3 eventos por semana.\n'
        '• Dá para mostrar o endereço só para quem marcar "vou".\n'
        '• Denúncia procedente suspende o coletivo e a sua conta responde.',
        style: theme.textTheme.bodySmall,
      ),
    ),
  );

  Widget _form(ThemeData theme) {
    final previous = _request;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (previous != null && previous.status == 'rejected')
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'O pedido "${previous.name}" foi recusado'
                '${previous.reason.isEmpty ? '.' : ': ${previous.reason}'}'
                ' Você pode pedir de novo.',
              ),
            ),
          ),
        _rules(theme),
        const SizedBox(height: 12),
        TextField(
          key: const Key('collective_name'),
          controller: _name,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Nome do coletivo'),
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final e in collectiveCategories.entries)
              ChoiceChip(
                key: Key('collective_cat_${e.key}'),
                label: Text(e.value),
                selected: _category == e.key,
                onSelected: (_) => setState(() => _category = e.key),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('collective_description'),
          controller: _description,
          maxLength: 1000,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Sobre o coletivo (opcional)',
          ),
        ),
        TextField(
          key: const Key('collective_email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Seu e-mail institucional',
            hintText: 'voce@estudante.ufscar.br',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('collective_submit'),
          onPressed: _busy
              ? null
              : () => _run(
                  (t) => widget.session.api.requestCollective(
                    t,
                    name: _name.text.trim(),
                    category: _category,
                    description: _description.text.trim(),
                    institutionEmail: _email.text.trim(),
                  ),
                ),
          child: const Text('Enviar pedido'),
        ),
      ],
    );
  }

  Widget _status(ThemeData theme, OrganizerRequest r) {
    final needsCode = r.status == 'pending' &&
        r.emailCheck == 'code' &&
        !r.emailVerified;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: Key('collective_status_${r.status}'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(switch (r.status) {
            'approved' => Icons.verified_outlined,
            'rejected' => Icons.block,
            _ => Icons.hourglass_top,
          }),
          title: Text(r.name),
          subtitle: Text(switch (r.status) {
            'approved' => 'Aprovado! O coletivo já tem página.',
            _ when needsCode =>
              'Confirme o e-mail ${r.institutionEmail} com o código que mandamos.',
            _ => r.emailVerified
                ? 'E-mail confirmado. Aguardando a aprovação da equipe.'
                : 'Aguardando a equipe conferir o pedido e o e-mail '
                      '${r.institutionEmail}.',
          }),
        ),
        if (needsCode) ...[
          TextField(
            key: const Key('collective_code'),
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'Código (6 números)'),
          ),
          Row(
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run((t) async {
                        await widget.session.api.resendCollectiveCode(t);
                        return null;
                      }),
                child: const Text('Mandar outro código'),
              ),
              const Spacer(),
              FilledButton(
                key: const Key('collective_verify'),
                onPressed: _busy
                    ? null
                    : () => _run(
                        (t) => widget.session.api.verifyCollectiveEmail(
                          t,
                          _code.text.trim(),
                        ),
                      ),
                child: const Text('Confirmar'),
              ),
            ],
          ),
        ],
        if (r.status == 'approved' && r.pageSlug != null)
          FilledButton.icon(
            key: const Key('collective_open_page'),
            onPressed: () => openPlace(context, widget.session, r.pageSlug!),
            icon: const Icon(Icons.groups_outlined),
            label: const Text('Abrir a página do coletivo'),
          ),
        if (r.status == 'approved')
          TextButton(
            onPressed: () => setState(() => _newRequest = true),
            child: const Text('Pedir outro coletivo'),
          ),
        const SizedBox(height: 12),
        _rules(theme),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _request;
    final current = (r == null || r.status == 'rejected' || _newRequest)
        ? null
        : r;
    return Scaffold(
      key: const Key('collective_screen'),
      appBar: AppBar(title: const Text('Coletivo estudantil')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                if (current == null) _form(theme) else _status(theme, current),
              ],
            ),
    );
  }
}

/// Administração: pedidos de coletivo e eventos de coletivos para revisar.
class CollectiveReviewScreen extends StatefulWidget {
  const CollectiveReviewScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<CollectiveReviewScreen> createState() => _CollectiveReviewScreenState();
}

class _CollectiveReviewScreenState extends State<CollectiveReviewScreen> {
  List<OrganizerRequest>? _requests;
  List<PendingEvent>? _events;
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
      final api = widget.session.api;
      final r = await api.pendingCollectives(token);
      final e = await api.pendingEvents(token);
      if (mounted) {
        setState(() {
          _requests = r;
          _events = e;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _act(Future<void> Function(String token) f) async {
    final token = widget.session.token;
    if (token == null) return;
    try {
      await f(token);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    }
  }

  Future<void> _reject(OrganizerRequest r) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Recusar "${r.name}"?'),
        content: TextField(
          key: const Key('collective_reject_reason'),
          controller: reason,
          maxLength: 300,
          decoration: const InputDecoration(labelText: 'Motivo (a pessoa vê)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('collective_reject_confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Recusar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _act(
      (t) => widget.session.api.decideCollective(
        t,
        r.id,
        approve: false,
        reason: reason.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final requests = _requests;
    final events = _events;
    return Scaffold(
      key: const Key('collective_review_screen'),
      appBar: AppBar(title: const Text('Coletivos e eventos')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            Text('Pedidos de coletivo', style: theme.textTheme.titleMedium),
            if (requests == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (requests.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Nenhum pedido.'),
              )
            else
              for (final r in requests)
                Card(
                  key: Key('collective_request_${r.id}'),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.name, style: theme.textTheme.titleSmall),
                        Text(
                          '${collectiveCategories[r.category] ?? r.category}'
                          ' · @${r.user?.username ?? '?'}',
                        ),
                        Text(
                          '${r.institutionEmail} · '
                          '${r.emailVerified ? 'e-mail confirmado ✓' : 'e-mail NÃO confirmado'}',
                          style: theme.textTheme.bodySmall,
                        ),
                        if (r.description.isNotEmpty) Text(r.description),
                        OverflowBar(
                          alignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => _reject(r),
                              child: const Text('Recusar'),
                            ),
                            FilledButton(
                              key: Key('collective_approve_${r.id}'),
                              onPressed: () => _act(
                                (t) => widget.session.api.decideCollective(
                                  t,
                                  r.id,
                                  approve: true,
                                ),
                              ),
                              child: const Text('Aprovar'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 16),
            Text('Eventos para revisar', style: theme.textTheme.titleMedium),
            if (events == null)
              const SizedBox.shrink()
            else if (events.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Nenhum evento esperando.'),
              )
            else
              for (final e in events)
                Card(
                  key: Key('pending_event_${e.id}'),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.title, style: theme.textTheme.titleSmall),
                        Text(
                          '${e.pageName} · responsável @${e.responsible ?? '?'}',
                        ),
                        Text(
                          '${formatWhen(e.startsAt)} · ${e.location}',
                          style: theme.textTheme.bodySmall,
                        ),
                        if (e.description.isNotEmpty) Text(e.description),
                        OverflowBar(
                          alignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => _act(
                                (t) => widget.session.api.reviewEvent(
                                  t,
                                  e.id,
                                  approve: false,
                                ),
                              ),
                              child: const Text('Recusar'),
                            ),
                            FilledButton(
                              key: Key('event_approve_${e.id}'),
                              onPressed: () => _act(
                                (t) => widget.session.api.reviewEvent(
                                  t,
                                  e.id,
                                  approve: true,
                                ),
                              ),
                              child: const Text('Publicar'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
