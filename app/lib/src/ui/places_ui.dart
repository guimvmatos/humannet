import 'dart:async';

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'error_messages.dart';
import 'events_ui.dart';
import 'report_dialog.dart';

/// Abre a página de um lugar.
Future<void> openPlace(
  BuildContext context,
  SessionController session,
  String slug,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => PlaceScreen(session: session, slug: slug),
  ),
);

/// Abre um evento.
Future<void> openEvent(
  BuildContext context,
  SessionController session,
  String id,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (ctx) => EventScreen(
      session: session,
      eventId: id,
      onOpenPlace: (slug) => openPlace(ctx, session, slug),
    ),
  ),
);

/// Aba "Agenda": próximos eventos dos lugares que você acompanha e dos que
/// você marcou interesse.
class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<AgendaScreen> createState() => AgendaScreenState();
}

class AgendaScreenState extends State<AgendaScreen> {
  List<PlaceEvent>? _events;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  Future<void> refresh() async {
    final token = widget.session.token;
    if (token == null) return;
    try {
      final e = await widget.session.api.agenda(token);
      if (mounted) {
        setState(() {
          _events = e;
          _error = null;
        });
      }
    } catch (err) {
      if (mounted) setState(() => _error = errorMessage(err));
    }
  }

  Future<void> _places() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlacesScreen(session: widget.session),
      ),
    );
    await refresh();
  }

  @override
  Widget build(BuildContext context) {
    final events = _events;
    return Scaffold(
      key: const Key('agenda_screen'),
      appBar: AppBar(
        title: const Text('Agenda'),
        actions: [
          TextButton.icon(
            key: const Key('places_button'),
            onPressed: _places,
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('Lugares'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (_error != null)
              Padding(padding: const EdgeInsets.all(16), child: Text(_error!))
            else if (events == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (events.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text(
                      'Nada na agenda. Acompanhe lugares (bar, casa de show, '
                      'teatro…) para ver os eventos deles aqui.',
                      key: Key('empty_agenda'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _places,
                      child: const Text('Ver lugares'),
                    ),
                  ],
                ),
              )
            else
              for (final e in events)
                EventTile(
                  event: e,
                  onTap: () async {
                    await openEvent(context, widget.session, e.id);
                    await refresh();
                  },
                ),
          ],
        ),
      ),
    );
  }
}

/// Busca de lugares + os que você acompanha/administra.
class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<PlaceItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null) return;
    final q = _search.text.trim();
    try {
      final items = await widget.session.api.places(token, query: q);
      if (mounted && _search.text.trim() == q) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } catch (err) {
      if (mounted) setState(() => _error = errorMessage(err));
    }
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<Place>(
      MaterialPageRoute(
        builder: (_) => PlaceFormScreen(session: widget.session),
      ),
    );
    if (created != null && mounted) {
      await openPlace(context, widget.session, created.slug);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      key: const Key('places_screen'),
      appBar: AppBar(title: const Text('Lugares')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'create_place_fab',
        key: const Key('create_place_button'),
        onPressed: _create,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Criar página'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              key: const Key('place_search_field'),
              controller: _search,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), _load);
              },
              decoration: const InputDecoration(
                hintText: 'Buscar por nome ou cidade',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(_error!))
          else if (items == null)
            const Center(child: CircularProgressIndicator())
          else if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Nenhum lugar encontrado. Você tem um bar, café ou espaço? '
                'Crie a página dele.',
                key: Key('no_places'),
                textAlign: TextAlign.center,
              ),
            )
          else
            for (final p in items)
              ListTile(
                key: Key('place_${p.slug}'),
                leading: const CircleAvatar(child: Icon(Icons.storefront)),
                title: Text(p.verified ? '${p.name} ✓' : p.name),
                subtitle: Text(
                  [
                    p.categoryLabel,
                    if (p.city.isNotEmpty) p.city,
                    if (p.myRole != null) 'você administra',
                    if (p.following && p.myRole == null) 'acompanhando',
                  ].join(' · '),
                ),
                onTap: () async {
                  await openPlace(context, widget.session, p.slug);
                  await _load();
                },
              ),
        ],
      ),
    );
  }
}

/// Página de um lugar: informações, acompanhar, eventos.
class PlaceScreen extends StatefulWidget {
  const PlaceScreen({super.key, required this.session, required this.slug});

  final SessionController session;
  final String slug;

  @override
  State<PlaceScreen> createState() => _PlaceScreenState();
}

class _PlaceScreenState extends State<PlaceScreen> {
  Place? _p;
  List<PlaceEvent> _events = const [];
  bool _past = false;
  bool _busy = false;
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
      final api = widget.session.api;
      final p = await api.place(token, widget.slug);
      final ev = await api.placeEvents(token, widget.slug, past: _past);
      if (!mounted) return;
      setState(() {
        _p = p;
        _events = ev;
        _error = null;
      });
    } catch (err) {
      if (mounted) setState(() => _error = errorMessage(err));
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _follow() async {
    final p = _p;
    final token = widget.session.token;
    if (p == null || token == null) return;
    setState(() => _busy = true);
    try {
      await widget.session.api.followPlace(token, p.slug, follow: !p.following);
      await _load();
    } catch (err) {
      _snack(errorMessage(err));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newEvent() async {
    final created = await Navigator.of(context).push<PlaceEvent>(
      MaterialPageRoute(
        builder: (_) =>
            EventFormScreen(session: widget.session, placeSlug: widget.slug),
      ),
    );
    if (created != null) await _load();
  }

  Future<void> _menu(String action) async {
    final p = _p;
    final token = widget.session.token;
    if (p == null || token == null) return;
    final api = widget.session.api;
    switch (action) {
      case 'edit':
        final saved = await Navigator.of(context).push<Place>(
          MaterialPageRoute(
            builder: (_) =>
                PlaceFormScreen(session: widget.session, existing: p),
          ),
        );
        if (saved != null) await _load();
      case 'admin':
        final c = TextEditingController();
        final name = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Adicionar administrador'),
            content: TextField(
              controller: c,
              autofocus: true,
              decoration: const InputDecoration(
                prefixText: '@',
                helperText: 'A pessoa poderá editar a página e criar eventos.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(c.text),
                child: const Text('Adicionar'),
              ),
            ],
          ),
        );
        final u = name?.trim().replaceFirst('@', '').toLowerCase() ?? '';
        if (u.isEmpty) return;
        try {
          await api.addPlaceAdmin(token, p.slug, u);
          _snack('@$u agora administra a página.');
        } catch (err) {
          _snack(errorMessage(err));
        }
      case 'delete':
        try {
          await api.deletePlace(token, p.slug);
          if (mounted) Navigator.of(context).pop();
        } catch (err) {
          _snack(errorMessage(err));
        }
      case 'report':
        await showReportDialog(
          context,
          session: widget.session,
          placeSlug: p.slug,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final theme = Theme.of(context);
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: _error != null
              ? Text(_error!)
              : const CircularProgressIndicator(),
        ),
      );
    }
    return Scaffold(
      key: const Key('place_screen'),
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          PopupMenuButton<String>(
            key: const Key('place_menu'),
            onSelected: _menu,
            itemBuilder: (_) => [
              if (p.canManage) ...[
                const PopupMenuItem(value: 'edit', child: Text('Editar')),
                if (p.isOwner)
                  const PopupMenuItem(
                    value: 'admin',
                    child: Text('Adicionar administrador'),
                  ),
                if (p.isOwner)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Apagar página'),
                  ),
              ] else
                const PopupMenuItem(
                  value: 'report',
                  child: Text('Denunciar página'),
                ),
            ],
          ),
        ],
      ),
      floatingActionButton: p.canManage
          ? FloatingActionButton.extended(
              heroTag: 'new_event_fab',
              key: const Key('new_event_button'),
              onPressed: _newEvent,
              icon: const Icon(Icons.event),
              label: const Text('Novo evento'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      p.categoryLabel,
                      if (p.city.isNotEmpty) p.city,
                      if (p.verified) 'verificado ✓',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (p.address.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(p.address),
                  ],
                  if (p.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(p.description),
                  ],
                  const SizedBox(height: 4),
                  Text('CNPJ ${p.cnpj}', style: theme.textTheme.bodySmall),
                  if (p.followerCount != null)
                    Text(
                      '${p.followerCount} acompanham (só administradores veem)',
                      style: theme.textTheme.bodySmall,
                    ),
                  const SizedBox(height: 12),
                  if (p.following)
                    OutlinedButton.icon(
                      key: const Key('follow_place_button'),
                      onPressed: _busy ? null : _follow,
                      icon: const Icon(Icons.check),
                      label: const Text('Acompanhando'),
                    )
                  else
                    FilledButton.icon(
                      key: const Key('follow_place_button'),
                      onPressed: _busy ? null : _follow,
                      icon: const Icon(Icons.add),
                      label: const Text('Acompanhar'),
                    ),
                ],
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    _past ? 'Eventos passados' : 'Próximos eventos',
                    style: theme.textTheme.titleSmall,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() => _past = !_past);
                      unawaited(_load());
                    },
                    child: Text(_past ? 'Ver próximos' : 'Ver passados'),
                  ),
                ],
              ),
            ),
            if (_events.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nenhum evento.',
                  key: Key('no_events'),
                  textAlign: TextAlign.center,
                ),
              )
            else
              for (final e in _events)
                EventTile(
                  event: e,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            EventScreen(session: widget.session, eventId: e.id),
                      ),
                    );
                    await _load();
                  },
                ),
          ],
        ),
      ),
    );
  }
}

/// Criar (com CNPJ) ou editar página de lugar.
class PlaceFormScreen extends StatefulWidget {
  const PlaceFormScreen({super.key, required this.session, this.existing});

  final SessionController session;
  final Place? existing;

  @override
  State<PlaceFormScreen> createState() => _PlaceFormScreenState();
}

class _PlaceFormScreenState extends State<PlaceFormScreen> {
  late final _name = TextEditingController(text: widget.existing?.name);
  final _cnpj = TextEditingController();
  late final _address = TextEditingController(text: widget.existing?.address);
  late final _city = TextEditingController(text: widget.existing?.city);
  late final _description = TextEditingController(
    text: widget.existing?.description,
  );
  late String? _category = widget.existing?.category;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _cnpj, _address, _city, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final token = widget.session.token;
    final category = _category;
    if (token == null) return;
    if (category == null) {
      setState(() => _error = 'Escolha uma categoria.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = widget.session.api;
      final existing = widget.existing;
      final saved = existing == null
          ? await api.createPlace(
              token,
              name: _name.text.trim(),
              category: category,
              cnpj: _cnpj.text.trim(),
              address: _address.text.trim(),
              city: _city.text.trim(),
              description: _description.text.trim(),
            )
          : await api.updatePlace(
              token,
              existing.slug,
              name: _name.text.trim(),
              category: category,
              address: _address.text.trim(),
              city: _city.text.trim(),
              description: _description.text.trim(),
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
    final creating = widget.existing == null;
    return Scaffold(
      appBar: AppBar(title: Text(creating ? 'Nova página' : 'Editar página')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('place_name_field'),
            controller: _name,
            maxLength: 80,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nome do lugar'),
          ),
          DropdownButtonFormField<String>(
            key: const Key('place_category_field'),
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Categoria'),
            items: [
              for (final e in placeCategories.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => _category = v),
          ),
          if (creating)
            TextField(
              key: const Key('place_cnpj_field'),
              controller: _cnpj,
              keyboardType: TextInputType.number,
              maxLength: 18,
              decoration: const InputDecoration(
                labelText: 'CNPJ',
                hintText: '00.000.000/0000-00',
                helperText: 'Uma página por CNPJ. Aparece na página.',
              ),
            ),
          TextField(
            controller: _address,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Endereço'),
          ),
          TextField(
            controller: _city,
            maxLength: 80,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Cidade'),
          ),
          TextField(
            controller: _description,
            maxLength: 2000,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Sobre o lugar'),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('save_place_button'),
            onPressed: _busy ? null : _save,
            child: Text(creating ? 'Criar página' : 'Salvar'),
          ),
        ],
      ),
    );
  }
}
