import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' hide MapEvent;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'error_messages.dart';
import 'events_ui.dart';
import 'places_ui.dart';
import 'wide_layout.dart';

/// Centro de Sorocaba: ponto inicial quando não há localização.
const _defaultCenter = LatLng(-23.5015, -47.4526);

/// Testes: sem mapa de fundo (rede) e sem GPS.
@visibleForTesting
bool mapOfflineForTests = false;

/// Fundo claro: cores do OpenStreetMap mais suaves (menos saturadas), para os
/// pinos dos eventos se destacarem.
const _softTiles = ColorFilter.matrix([
  0.78, 0.18, 0.04, 0, 12, //
  0.08, 0.86, 0.06, 0, 12, //
  0.08, 0.18, 0.74, 0, 16, //
  0, 0, 0, 1, 0,
]);

Widget _softTileBuilder(BuildContext context, Widget tile, TileImage _) =>
    ColorFiltered(colorFilter: _softTiles, child: tile);

/// Camadas comuns: fundo do OpenStreetMap (gratuito, sem chave), com filtro
/// suave no tema claro e versão noturna no tema escuro.
List<Widget> _baseLayers(BuildContext context) {
  if (mapOfflineForTests) return const [];
  final dark = Theme.of(context).brightness == Brightness.dark;
  return [
    TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'social.humannet.humannet',
      tileBuilder: dark ? darkModeTileBuilder : _softTileBuilder,
    ),
  ];
}

Widget _attribution() => RichAttributionWidget(
  attributions: [
    TextSourceAttribution(
      'OpenStreetMap contributors',
      onTap: () => launchUrl(
        Uri.parse('https://www.openstreetmap.org/copyright'),
        mode: LaunchMode.externalApplication,
      ),
    ),
  ],
);

/// Posição do aparelho, só para desenhar "você está aqui" (precisão alta:
/// não sai do celular). Cai para a precisão baixa se o GPS demorar.
/// `null` sem permissão ou sem GPS. Devolve também a margem de erro (m).
Future<(LatLng, double)?> _whereAmI() async {
  if (mapOfflineForTests) return null;
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return null;
    }
    Position p;
    try {
      p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
    } catch (_) {
      p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );
    }
    return (LatLng(p.latitude, p.longitude), p.accuracy);
  } catch (_) {
    return null;
  }
}

/// Quão perto está o evento: muda cor, destaque e animação do pino.
enum _When { now, today, week, later }

_When _whenOf(MapEvent e, DateTime now) {
  final end = e.endsAt ?? e.startsAt.add(const Duration(hours: 4));
  final start = e.startsAt.toLocal();
  if (!e.startsAt.isAfter(now) && end.isAfter(now)) return _When.now;
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(start.year, start.month, start.day);
  final diff = day.difference(today).inDays;
  if (diff <= 0) return _When.today;
  if (diff < 7) return _When.week;
  return _When.later;
}

const _weekdays = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

/// "Agora", "Hoje 22h", "Sáb 20h", "12/11".
String _shortWhen(MapEvent e, DateTime now) {
  final s = e.startsAt.toLocal();
  final hour = s.minute == 0
      ? '${s.hour}h'
      : '${s.hour}h${s.minute.toString().padLeft(2, '0')}';
  return switch (_whenOf(e, now)) {
    _When.now => 'Agora',
    _When.today => 'Hoje $hour',
    _When.week => '${_weekdays[s.weekday - 1]} $hour',
    _When.later =>
      '${s.day.toString().padLeft(2, '0')}/${s.month.toString().padLeft(2, '0')}',
  };
}

Color _colorOf(_When w, ColorScheme scheme) => switch (w) {
  _When.now => const Color(0xFFE91E63),
  _When.today => const Color(0xFFFF6D00),
  _When.week => scheme.primary,
  _When.later => scheme.outline,
};

/// Pino de um lugar com eventos: logo num círculo colorido, etiqueta com o
/// próximo horário e, se for agora ou hoje, um halo pulsando.
class _EventPin extends StatefulWidget {
  const _EventPin({required this.events, required this.onTap});

  final List<MapEvent> events;
  final VoidCallback onTap;

  @override
  State<_EventPin> createState() => _EventPinState();
}

class _EventPinState extends State<_EventPin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_EventPin old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final w = _whenOf(widget.events.first, DateTime.now());
    final animate = (w == _When.now || w == _When.today) &&
        !mapOfflineForTests &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!animate && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final first = widget.events.first;
    final w = _whenOf(first, now);
    final scheme = Theme.of(context).colorScheme;
    final color = _colorOf(w, scheme);
    final size = w == _When.later ? 40.0 : 48.0;
    return GestureDetector(
      key: Key('map_pin_${first.pageSlug}'),
      onTap: widget.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 76,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) {
                    final t = _pulse.value;
                    return Container(
                      width: size + 28 * t,
                      height: size + 28 * t,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(
                          alpha: _pulse.isAnimating ? 0.35 * (1 - t) : 0,
                        ),
                      ),
                    );
                  },
                ),
                Container(
                  width: size,
                  height: size,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: PlaceLogo(
                    name: first.pageName,
                    url: first.pageLogoUrl,
                    radius: size / 2 - 3,
                  ),
                ),
                if (widget.events.length > 1)
                  Positioned(
                    right: 8,
                    top: 0,
                    child: Badge(label: Text('${widget.events.length}')),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _shortWhen(first, now),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cartão de evento no carrossel de baixo.
class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onTap});

  final MapEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final w = _whenOf(event, now);
    final theme = Theme.of(context);
    final color = _colorOf(w, theme.colorScheme);
    return Card(
      key: Key('map_card_${event.id}'),
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Container(width: 6, color: color),
            Padding(
              padding: const EdgeInsets.all(10),
              child: PlaceLogo(
                name: event.pageName,
                url: event.pageLogoUrl,
                radius: 22,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _shortWhen(event, now).toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      event.pageName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
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

/// Mapa de eventos: o que vai rolar na área que o mapa mostra.
class EventsMapScreen extends StatefulWidget {
  const EventsMapScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<EventsMapScreen> createState() => _EventsMapScreenState();
}

class _EventsMapScreenState extends State<EventsMapScreen> {
  final _map = MapController();
  Timer? _debounce;
  List<MapEvent> _events = const [];
  LatLng? _me;
  double _meAccuracy = 0;
  final _cards = PageController(viewportFraction: 0.86);
  int _days = 7;
  bool _loading = false;
  bool _tooFar = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _map.dispose();
    _cards.dispose();
    super.dispose();
  }

  Future<void> _ready() async {
    unawaited(_load());
    final found = await _whereAmI();
    if (!mounted || found == null) return;
    final (me, accuracy) = found;
    setState(() {
      _me = me;
      _meAccuracy = accuracy;
    });
    _map.move(me, 14);
    unawaited(_load());
  }

  void _moved() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _load);
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null || !mounted) return;
    final b = _map.camera.visibleBounds;
    // O servidor só aceita uma região (até ~5°): longe demais, pede zoom.
    if (b.north - b.south > 5 || b.east - b.west > 5) {
      setState(() {
        _tooFar = true;
        _events = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _tooFar = false;
    });
    try {
      final events = await widget.session.api.mapEvents(
        token,
        south: b.south,
        west: b.west,
        north: b.north,
        east: b.east,
        days: _days,
      );
      if (mounted) {
        events.sort((a, b) => a.startsAt.compareTo(b.startsAt));
        setState(() {
          _events = events;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Eventos agrupados por lugar (um pino por lugar).
  Map<String, List<MapEvent>> get _byPlace {
    final out = <String, List<MapEvent>>{};
    for (final e in _events) {
      (out[e.pageSlug] ??= []).add(e);
    }
    return out;
  }

  Future<void> _openPlaceEvents(List<MapEvent> events) async {
    final first = events.first;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          key: const Key('map_place_sheet'),
          shrinkWrap: true,
          children: [
            ListTile(
              leading: PlaceLogo(name: first.pageName, url: first.pageLogoUrl),
              title: Text(first.pageName),
              subtitle: Text(first.location),
              trailing: TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  unawaited(openPlace(context, widget.session, first.pageSlug));
                },
                child: const Text('Ver página'),
              ),
            ),
            const Divider(height: 1),
            for (final e in events)
              ListTile(
                key: Key('map_event_${e.id}'),
                leading: const Icon(Icons.event),
                title: Text(e.title),
                subtitle: Text(formatWhen(e.startsAt)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  unawaited(openEvent(context, widget.session, e.id));
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = _me;
    return Scaffold(
      key: const Key('events_map_screen'),
      appBar: AppBar(
        title: const Text('Mapa de eventos'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('Hoje')),
                ButtonSegment(value: 7, label: Text('7 dias')),
                ButtonSegment(value: 30, label: Text('30 dias')),
              ],
              selected: {_days},
              onSelectionChanged: (s) {
                setState(() => _days = s.first);
                unawaited(_load());
              },
            ),
          ),
        ),
      ),
      floatingActionButton: me == null
          ? null
          : Padding(
              // Fica acima do carrossel de eventos.
              padding: EdgeInsets.only(bottom: _events.isEmpty ? 0 : 108),
              child: FloatingActionButton.small(
                heroTag: 'map_me_fab',
                tooltip: 'Onde estou',
                onPressed: () => _map.move(me, 15),
                child: const Icon(Icons.my_location),
              ),
            ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _defaultCenter,
              initialZoom: 13,
              minZoom: 4,
              maxZoom: 18,
              onMapReady: () => unawaited(_ready()),
              onPositionChanged: (_, _) => _moved(),
            ),
            children: [
              ..._baseLayers(context),
              if (me != null && _meAccuracy > 0)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: me,
                      radius: _meAccuracy,
                      useRadiusInMeter: true,
                      color: Colors.blue.withValues(alpha: 0.12),
                      borderColor: Colors.blue.withValues(alpha: 0.4),
                      borderStrokeWidth: 1,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (me != null)
                    Marker(
                      point: me,
                      width: 22,
                      height: 22,
                      child: Container(
                        key: const Key('map_me'),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                  for (final entry in _byPlace.entries)
                    Marker(
                      point: LatLng(entry.value.first.lat, entry.value.first.lng),
                      width: 76,
                      height: 84,
                      // A base do círculo fica sobre o ponto.
                      alignment: const Alignment(0, -0.45),
                      child: _EventPin(
                        events: entry.value,
                        onTap: () => _openPlaceEvents(entry.value),
                      ),
                    ),
                ],
              ),
              _attribution(),
            ],
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        _error ??
                            (_tooFar
                                ? 'Aproxime o mapa para ver os eventos.'
                                : _events.isEmpty
                                ? 'Nenhum evento nesta área. Mova o mapa.'
                                : '${_events.length} evento(s) nesta área · '
                                      'sua localização fica só no seu celular'),
                        key: const Key('map_status'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_events.isNotEmpty && !_tooFar)
            Positioned(
              left: 0,
              right: 0,
              bottom: 24 + MediaQuery.paddingOf(context).bottom,
              height: 92,
              child: PageView.builder(
                key: const Key('map_cards'),
                controller: _cards,
                scrollBehavior: mouseDragScroll,
                itemCount: _events.length,
                onPageChanged: (i) {
                  final e = _events[i];
                  _map.move(LatLng(e.lat, e.lng), _map.camera.zoom);
                },
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _EventCard(
                    event: _events[i],
                    onTap: () => unawaited(
                      openEvent(context, widget.session, _events[i].id),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Quem administra marca no mapa onde fica o lugar (quando o endereço não
/// foi achado ou caiu no lugar errado).
class PlacePinScreen extends StatefulWidget {
  const PlacePinScreen({super.key, required this.session, required this.place});

  final SessionController session;
  final Place place;

  @override
  State<PlacePinScreen> createState() => _PlacePinScreenState();
}

class _PlacePinScreenState extends State<PlacePinScreen> {
  late LatLng? _pin = widget.place.hasPin
      ? LatLng(widget.place.lat!, widget.place.lng!)
      : null;
  bool _busy = false;

  Future<void> _save({bool reset = false}) async {
    final token = widget.session.token;
    final pin = _pin;
    if (token == null || (!reset && pin == null)) return;
    setState(() => _busy = true);
    try {
      final p = reset
          ? await widget.session.api.updatePlace(
              token,
              widget.place.slug,
              resetPin: true,
            )
          : await widget.session.api.updatePlace(
              token,
              widget.place.slug,
              lat: pin?.latitude,
              lng: pin?.longitude,
            );
      if (mounted) Navigator.of(context).pop(p);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pin = _pin;
    return Scaffold(
      key: const Key('place_pin_screen'),
      appBar: AppBar(
        title: const Text('Ponto no mapa'),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => _save(reset: true),
            child: const Text('Usar endereço'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'save_pin_fab',
        key: const Key('save_pin_button'),
        onPressed: _busy || pin == null ? null : _save,
        icon: const Icon(Icons.check),
        label: const Text('Salvar ponto'),
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: pin ?? _defaultCenter,
              initialZoom: pin == null ? 13 : 17,
              onTap: (_, p) => setState(() => _pin = p),
            ),
            children: [
              ..._baseLayers(context),
              MarkerLayer(
                markers: [
                  if (pin != null)
                    Marker(
                      point: pin,
                      width: 48,
                      height: 48,
                      alignment: Alignment.topCenter,
                      child: Icon(
                        Icons.location_on,
                        size: 44,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                ],
              ),
              _attribution(),
            ],
          ),
          const Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Toque no mapa onde fica a entrada do lugar. Os eventos da '
                  'página aparecem nesse ponto.',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
