import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
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

/// Centro de Sorocaba: ponto inicial quando não há localização.
const _defaultCenter = LatLng(-23.5015, -47.4526);

/// Testes: sem mapa de fundo (rede) e sem GPS.
@visibleForTesting
bool mapOfflineForTests = false;

/// Camadas comuns: fundo do OpenStreetMap e o crédito que ele exige.
List<Widget> _baseLayers() => [
  if (!mapOfflineForTests)
    TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'social.humannet.humannet',
    ),
];

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

/// Posição aproximada do aparelho, só para desenhar "você está aqui".
/// Nunca é enviada ao servidor. `null` sem permissão ou sem GPS.
Future<LatLng?> _whereAmI() async {
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
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 10),
      ),
    );
    return LatLng(p.latitude, p.longitude);
  } catch (_) {
    return null;
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
  int _days = 7;
  bool _loading = false;
  bool _tooFar = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _map.dispose();
    super.dispose();
  }

  Future<void> _ready() async {
    unawaited(_load());
    final me = await _whereAmI();
    if (!mounted || me == null) return;
    setState(() => _me = me);
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
    final scheme = theme.colorScheme;
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
          : FloatingActionButton.small(
              heroTag: 'map_me_fab',
              tooltip: 'Onde estou',
              onPressed: () => _map.move(me, 14),
              child: const Icon(Icons.my_location),
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
              ..._baseLayers(),
              MarkerLayer(
                markers: [
                  if (me != null)
                    Marker(
                      point: me,
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                  for (final entry in _byPlace.entries)
                    Marker(
                      point: LatLng(entry.value.first.lat, entry.value.first.lng),
                      width: 48,
                      height: 48,
                      alignment: Alignment.topCenter,
                      child: GestureDetector(
                        key: Key('map_pin_${entry.key}'),
                        onTap: () => _openPlaceEvents(entry.value),
                        child: Badge(
                          isLabelVisible: entry.value.length > 1,
                          label: Text('${entry.value.length}'),
                          child: Icon(
                            Icons.location_on,
                            size: 44,
                            color: scheme.primary,
                          ),
                        ),
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
                                : '${_events.length} evento(s) nesta área'),
                        key: const Key('map_status'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 28,
            child: Text(
              'Sua localização fica só no seu celular.',
              style: theme.textTheme.labelSmall?.copyWith(
                backgroundColor: scheme.surface.withValues(alpha: 0.8),
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
              ..._baseLayers(),
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
