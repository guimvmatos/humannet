import 'dart:async';

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'chat_ui.dart';
import 'compose_screen.dart';
import 'error_messages.dart';
import 'events_map.dart';
import 'events_ui.dart';
import 'photos.dart';
import 'post_list.dart';
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
          IconButton(
            key: const Key('events_map_button'),
            tooltip: 'Mapa de eventos',
            icon: const Icon(Icons.map_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EventsMapScreen(session: widget.session),
              ),
            ),
          ),
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

/// Logo da página (ou a inicial do nome).
class PlaceLogo extends StatelessWidget {
  const PlaceLogo({super.key, required this.name, this.url, this.radius = 20});

  final String name;
  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final u = url;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundImage: u == null ? null : webSafeImage(u),
      child: u == null ? Text(initial) : null,
    );
  }
}

/// Busca de lugares; os que você administra aparecem primeiro.
/// `adminOnly`: só os que você administra ("Minhas páginas").
class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key, required this.session, this.adminOnly = false});

  final SessionController session;
  final bool adminOnly;

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
      var items = await widget.session.api.places(
        token,
        query: q,
        mine: widget.adminOnly,
      );
      if (widget.adminOnly) {
        items = items.where((p) => p.myRole != null).toList();
      }
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

  Widget _tile(PlaceItem p) => ListTile(
    key: Key('place_${p.slug}'),
    leading: PlaceLogo(name: p.name, url: p.logoUrl),
    title: Text(p.verified ? '${p.name} ✓' : p.name),
    subtitle: Text(
      [
        p.categoryLabel,
        if (p.city.isNotEmpty) p.city,
        if (p.myRole == 'owner') 'você é dono',
        if (p.myRole == 'admin') 'você administra',
        if (p.following && p.myRole == null) 'acompanhando',
      ].join(' · '),
    ),
    onTap: () async {
      await openPlace(context, widget.session, p.slug);
      await _load();
    },
  );

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final theme = Theme.of(context);
    final mine = items?.where((p) => p.myRole != null).toList() ?? const [];
    final others = items?.where((p) => p.myRole == null).toList() ?? const [];
    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(title, style: theme.textTheme.titleSmall),
    );
    return Scaffold(
      key: const Key('places_screen'),
      appBar: AppBar(
        title: Text(widget.adminOnly ? 'Minhas páginas' : 'Lugares'),
      ),
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
          if (!widget.adminOnly)
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
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                widget.adminOnly
                    ? 'Você ainda não administra nenhuma página. Qualquer '
                          'pessoa pode criar até 3 (com o CNPJ do lugar).'
                    : 'Nenhum lugar encontrado. Você tem um bar, café ou '
                          'espaço? Crie a página dele.',
                key: const Key('no_places'),
                textAlign: TextAlign.center,
              ),
            )
          else ...[
            if (mine.isNotEmpty && !widget.adminOnly)
              section('Páginas que você administra'),
            for (final p in mine) _tile(p),
            if (others.isNotEmpty && mine.isNotEmpty) section('Outros lugares'),
            for (final p in others) _tile(p),
          ],
        ],
      ),
    );
  }
}

/// Página de um lugar: capa e logo, informações, acompanhar, mensagem,
/// eventos e o mural (posts da página).
class PlaceScreen extends StatefulWidget {
  const PlaceScreen({super.key, required this.session, required this.slug});

  final SessionController session;
  final String slug;

  @override
  State<PlaceScreen> createState() => _PlaceScreenState();
}

class _PlaceScreenState extends State<PlaceScreen> {
  final _wallKey = GlobalKey<PagedPostListState>();
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

  Future<void> _message() async {
    final p = _p;
    final token = widget.session.token;
    if (p == null || token == null) return;
    if (!p.following) {
      _snack('Acompanhe a página para mandar mensagem.');
      return;
    }
    try {
      final c = await widget.session.api.placeConversation(token, p.slug);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(session: widget.session, conversation: c),
        ),
      );
    } catch (err) {
      _snack(errorMessage(err));
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

  Future<void> _newPost() async {
    final p = _p;
    if (p == null) return;
    final post = await Navigator.of(context).push<Post>(
      MaterialPageRoute(
        builder: (_) => ComposeScreen(
          session: widget.session,
          placeSlug: p.slug,
          placeName: p.name,
        ),
      ),
    );
    if (post != null) _wallKey.currentState?.prepend(post);
  }

  /// Trocar ou remover a logo (`logo`) ou a capa.
  Future<void> _imageMenu({required bool logo}) async {
    final p = _p;
    if (p == null || !p.canManage) return;
    final has = logo ? p.logoUrl != null : p.coverUrl != null;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(logo ? 'Escolher logo' : 'Escolher capa'),
              subtitle: Text(
                logo
                    ? 'Fica redonda, como foto de perfil.'
                    : 'Faixa larga no topo da página (3:1).',
              ),
              onTap: () => Navigator.of(ctx).pop('pick'),
            ),
            if (has)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(logo ? 'Remover logo' : 'Remover capa'),
                onTap: () => Navigator.of(ctx).pop('remove'),
              ),
          ],
        ),
      ),
    );
    final token = widget.session.token;
    if (action == null || token == null) return;
    setState(() => _busy = true);
    try {
      final api = widget.session.api;
      if (action == 'remove') {
        await api.setPlaceImage(token, p.slug, logo: logo);
      } else {
        final photos = await pickPhotos();
        if (photos.isEmpty) return;
        _snack('Enviando foto…');
        final m = await api.uploadMedia(
          token,
          logo ? 'avatar' : 'cover',
          photos.first,
        );
        await api.setPlaceImage(token, p.slug, logo: logo, mediaId: m.id);
      }
      await _load();
    } catch (err) {
      _snack(errorMessage(err));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _admins() async {
    final p = _p;
    final token = widget.session.token;
    if (p == null || token == null) return;
    final api = widget.session.api;
    List<PlaceAdmin> admins;
    try {
      admins = await api.placeAdmins(token, p.slug);
    } catch (err) {
      _snack(errorMessage(err));
      return;
    }
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Quem administra'),
              subtitle: Text(
                'O dono pode adicionar e remover administradores. Todos '
                'editam a página, publicam no mural, criam eventos e '
                'respondem as mensagens.',
              ),
            ),
            for (final a in admins)
              ListTile(
                leading: UserAvatar(a.user),
                title: Text(a.user.label),
                subtitle: Text(
                  '@${a.user.username} · ${a.isOwner ? 'dono' : 'administra'}',
                ),
                trailing: p.isOwner && !a.isOwner
                    ? IconButton(
                        tooltip: 'Remover',
                        icon: const Icon(Icons.person_remove_outlined),
                        onPressed: () =>
                            Navigator.of(ctx).pop('remove:${a.user.username}'),
                      )
                    : null,
              ),
            if (p.isOwner)
              ListTile(
                key: const Key('add_place_admin'),
                leading: const Icon(Icons.person_add_alt),
                title: const Text('Adicionar administrador'),
                onTap: () => Navigator.of(ctx).pop('add'),
              ),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (action.startsWith('remove:')) {
      final u = action.substring(7);
      try {
        await api.removePlaceAdmin(token, p.slug, u);
        _snack('@$u não administra mais a página.');
      } catch (err) {
        _snack(errorMessage(err));
      }
      return;
    }
    if (!mounted) return;
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
            helperText: 'Poderá editar, publicar, criar eventos e responder.',
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
      case 'pin':
        final saved = await Navigator.of(context).push<Place>(
          MaterialPageRoute(
            builder: (_) => PlacePinScreen(session: widget.session, place: p),
          ),
        );
        if (saved != null) await _load();
      case 'logo':
        await _imageMenu(logo: true);
      case 'cover':
        await _imageMenu(logo: false);
      case 'admins':
        await _admins();
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

  Widget _cover(Place p, ThemeData theme) {
    final cover = p.coverUrl;
    return SizedBox(
      height: 172,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            bottom: 44,
            child: GestureDetector(
              onTap: p.canManage && !_busy
                  ? () => _imageMenu(logo: false)
                  : null,
              child: cover != null
                  ? NetPhoto(cover)
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            theme.colorScheme.primaryContainer,
                            theme.colorScheme.tertiaryContainer,
                          ],
                        ),
                      ),
                      child: p.canManage
                          ? const Center(child: Text('Toque para pôr uma capa'))
                          : null,
                    ),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 0,
            child: GestureDetector(
              key: const Key('place_logo'),
              onTap: p.canManage && !_busy
                  ? () => _imageMenu(logo: true)
                  : null,
              child: CircleAvatar(
                radius: 44,
                backgroundColor: theme.colorScheme.surface,
                child: PlaceLogo(name: p.name, url: p.logoUrl, radius: 40),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(Place p) {
    final theme = Theme.of(context);
    final cep = p.cep;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cover(p, theme),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.verified ? '${p.name} ✓' : p.name,
                style: theme.textTheme.titleLarge,
              ),
              Text(
                [p.categoryLabel, if (p.city.isNotEmpty) p.city].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
              if (p.address.isNotEmpty || cep != null) ...[
                const SizedBox(height: 4),
                Text(
                  [
                    if (p.address.isNotEmpty) p.address,
                    if (cep != null)
                      'CEP ${cep.substring(0, 5)}-${cep.substring(5)}',
                  ].join(' · '),
                ),
              ],
              if (p.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(p.description),
              ],
              const SizedBox(height: 4),
              Text('CNPJ ${p.cnpj}', style: theme.textTheme.bodySmall),
              if (p.canManage) ...[
                Text(
                  p.isOwner
                      ? 'Você é dono desta página.'
                      : 'Você administra esta página.',
                  key: const Key('place_role_note'),
                  style: theme.textTheme.bodySmall,
                ),
                if (p.followerCount != null)
                  Text(
                    '${p.followerCount} acompanham (só quem administra vê)',
                    style: theme.textTheme.bodySmall,
                  ),
                Text(
                  'Mensagens para a página chegam nas suas Mensagens.',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  p.hasPin
                      ? (p.pinManual
                            ? 'No mapa: ponto marcado por você.'
                            : 'No mapa: ponto achado pelo endereço '
                                  '(ajuste no menu se estiver errado).')
                      : 'Ainda sem ponto no mapa: confira o endereço ou '
                            'marque no menu ⋮ → Ajustar ponto no mapa.',
                  key: const Key('place_pin_note'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
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
                  if (!p.canManage)
                    OutlinedButton.icon(
                      key: const Key('place_message_button'),
                      onPressed: _busy ? null : _message,
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Mensagem'),
                    ),
                  if (p.canManage)
                    FilledButton.tonalIcon(
                      key: const Key('place_post_button'),
                      onPressed: _busy ? null : _newPost,
                      icon: const Icon(Icons.edit),
                      label: const Text('Publicar no mural'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 24),
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
            padding: EdgeInsets.all(16),
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
        const Divider(height: 24),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text('Mural', style: theme.textTheme.titleSmall),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final token = widget.session.token ?? '';
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
                const PopupMenuItem(value: 'logo', child: Text('Trocar logo')),
                const PopupMenuItem(value: 'cover', child: Text('Trocar capa')),
                const PopupMenuItem(
                  value: 'pin',
                  child: Text('Ajustar ponto no mapa'),
                ),
                const PopupMenuItem(
                  value: 'admins',
                  child: Text('Quem administra'),
                ),
                if (p.isOwner)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Apagar página'),
                  ),
              ] else ...[
                const PopupMenuItem(
                  value: 'admins',
                  child: Text('Quem administra'),
                ),
                const PopupMenuItem(
                  value: 'report',
                  child: Text('Denunciar página'),
                ),
              ],
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
      body: PagedPostList(
        key: _wallKey,
        session: widget.session,
        loader: (before) =>
            widget.session.api.placeWall(token, widget.slug, before: before),
        onRefresh: _load,
        header: _header(p),
        emptyText: p.canManage
            ? 'Nada no mural ainda. Publique novidades: quem acompanha vê no '
                  'feed.'
            : 'Nada no mural ainda.',
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
  late final _cep = TextEditingController(text: _formatCep(widget.existing?.cep));
  late final _address = TextEditingController(text: widget.existing?.address);
  late final _city = TextEditingController(text: widget.existing?.city);
  late final _description = TextEditingController(
    text: widget.existing?.description,
  );
  late String? _category = widget.existing?.category;
  bool _busy = false;
  bool _lookingUp = false;
  String? _cepNote;
  String? _lastCep;
  String? _error;

  static String _formatCep(String? d) =>
      d == null || d.length != 8 ? '' : '${d.substring(0, 5)}-${d.substring(5)}';

  @override
  void dispose() {
    for (final c in [_name, _cnpj, _cep, _address, _city, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Com 8 dígitos, busca rua, bairro e cidade; deixa o cursor no número.
  Future<void> _cepChanged(String raw) async {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 8 || digits == _lastCep) return;
    _lastCep = digits;
    setState(() {
      _lookingUp = true;
      _cepNote = null;
    });
    final found = await widget.session.api.lookupCep(digits);
    if (!mounted) return;
    setState(() {
      _lookingUp = false;
      if (found == null) {
        _cepNote = 'CEP não encontrado. Preencha o endereço à mão.';
        return;
      }
      final street = found.street;
      final prefix = street.isEmpty ? '' : '$street, ';
      final suffix = found.district.isEmpty ? '' : ' - ${found.district}';
      _address.value = TextEditingValue(
        text: '$prefix$suffix',
        selection: TextSelection.collapsed(offset: prefix.length),
      );
      _city.text = found.uf.isEmpty ? found.city : '${found.city} - ${found.uf}';
      _cepNote = street.isEmpty
          ? 'CEP geral da cidade: complete o endereço.'
          : 'Endereço preenchido. Complete com o número.';
    });
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
              cep: _cep.text.trim(),
              address: _address.text.trim(),
              city: _city.text.trim(),
              description: _description.text.trim(),
            )
          : await api.updatePlace(
              token,
              existing.slug,
              name: _name.text.trim(),
              category: category,
              cep: _cep.text.trim(),
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(creating ? 'Nova página' : 'Editar página')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (creating)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Qualquer pessoa pode criar até 3 páginas de lugar, com o '
                  'CNPJ do lugar (uma página por CNPJ). Quem cria vira dono '
                  'e pode adicionar administradores. Logo e capa você coloca '
                  'depois, na própria página.',
                  key: const Key('place_rules_note'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
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
            key: const Key('place_cep_field'),
            controller: _cep,
            keyboardType: TextInputType.number,
            maxLength: 9,
            onChanged: _cepChanged,
            decoration: InputDecoration(
              labelText: 'CEP',
              hintText: '00000-000',
              helperText: _cepNote ?? 'Preenche rua, bairro e cidade.',
              suffixIcon: _lookingUp
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          ),
          TextField(
            key: const Key('place_address_field'),
            controller: _address,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Endereço'),
          ),
          TextField(
            key: const Key('place_city_field'),
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
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
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
