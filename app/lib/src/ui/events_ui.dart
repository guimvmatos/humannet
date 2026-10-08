import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'error_messages.dart';
import 'photos.dart';
import 'report_dialog.dart';

const _weekdays = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

String _two(int n) => n.toString().padLeft(2, '0');

/// "sex, 10/10 às 21:00" (horário do celular). Sem dependência de `intl`.
String formatWhen(DateTime t) {
  final l = t.toLocal();
  return '${_weekdays[l.weekday - 1]}, ${_two(l.day)}/${_two(l.month)} '
      'às ${_two(l.hour)}:${_two(l.minute)}';
}

/// Link do Google Agenda com o evento preenchido (a pessoa confirma lá).
Uri googleCalendarUrl(PlaceEvent e) {
  String fmt(DateTime t) {
    final u = t.toUtc();
    return '${u.year}${_two(u.month)}${_two(u.day)}T'
        '${_two(u.hour)}${_two(u.minute)}${_two(u.second)}Z';
  }

  final end = e.endsAt ?? e.startsAt.add(const Duration(hours: 3));
  return Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': e.title,
    'dates': '${fmt(e.startsAt)}/${fmt(end)}',
    'details': '${e.description}\n\n${e.placeName} · via HumanNet'.trim(),
    'location': e.location,
  });
}

/// Item de evento nas listas (agenda, página).
class EventTile extends StatelessWidget {
  const EventTile({super.key, required this.event, required this.onTap});

  final PlaceEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final theme = Theme.of(context);
    final interest = switch (e.myInterest) {
      'going' => ' · você vai',
      'interested' => ' · você tem interesse',
      _ => '',
    };
    final friends = e.friendsCount == 0
        ? ''
        : ' · ${e.friendsCount} ${e.friendsCount == 1 ? 'amigo' : 'amigos'}';
    return ListTile(
      key: Key('event_${e.id}'),
      leading: Container(
        width: 48,
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _two(e.startsAt.toLocal().day),
              style: theme.textTheme.titleMedium,
            ),
            Text(
              _weekdays[e.startsAt.toLocal().weekday - 1],
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
      title: Text(
        e.cancelled ? '${e.title} (cancelado)' : e.title,
        style: e.cancelled
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: Text('${e.placeName} · ${formatWhen(e.startsAt)}$interest$friends'),
      onTap: onTap,
    );
  }
}

/// Detalhe do evento: interesse, amigos que vão, Google Agenda.
class EventScreen extends StatefulWidget {
  const EventScreen({
    super.key,
    required this.session,
    required this.eventId,
    this.onOpenPlace,
  });

  final SessionController session;
  final String eventId;
  final void Function(String slug)? onOpenPlace;

  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
  PlaceEvent? _e;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null) return;
    try {
      final e = await widget.session.api.event(token, widget.eventId);
      if (mounted) setState(() => _e = e);
    } catch (err) {
      if (mounted) setState(() => _error = errorMessage(err));
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _interest(String? status) async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      await widget.session.api.setInterest(token, widget.eventId, status);
      await _load();
    } catch (err) {
      _snack(errorMessage(err));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _calendar() async {
    final e = _e;
    if (e == null) return;
    final ok = await launchUrl(
      googleCalendarUrl(e),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) _snack('Não deu para abrir o Google Agenda.');
  }

  Future<void> _menu(String action) async {
    final e = _e;
    final token = widget.session.token;
    if (e == null || token == null) return;
    final api = widget.session.api;
    try {
      switch (action) {
        case 'edit':
          final saved = await Navigator.of(context).push<PlaceEvent>(
            MaterialPageRoute(
              builder: (_) => EventFormScreen(
                session: widget.session,
                placeSlug: e.placeSlug,
                existing: e,
              ),
            ),
          );
          if (saved != null) await _load();
        case 'cancel':
          await api.updateEvent(token, e.id, cancelled: !e.cancelled);
          await _load();
        case 'delete':
          await api.deleteEvent(token, e.id);
          if (mounted) Navigator.of(context).pop();
        case 'report':
          await showReportDialog(
            context,
            session: widget.session,
            eventId: e.id,
          );
      }
    } catch (err) {
      _snack(errorMessage(err));
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _e;
    final theme = Theme.of(context);
    if (e == null) {
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
      key: const Key('event_screen'),
      appBar: AppBar(
        title: Text(e.placeName),
        actions: [
          PopupMenuButton<String>(
            key: const Key('event_menu'),
            onSelected: _menu,
            itemBuilder: (_) => [
              if (e.canEdit) ...[
                const PopupMenuItem(value: 'edit', child: Text('Editar')),
                PopupMenuItem(
                  value: 'cancel',
                  child: Text(e.cancelled ? 'Desfazer cancelamento' : 'Cancelar evento'),
                ),
                const PopupMenuItem(value: 'delete', child: Text('Apagar')),
              ] else
                const PopupMenuItem(
                  value: 'report',
                  child: Text('Denunciar evento'),
                ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(e.title, style: theme.textTheme.headlineSmall),
          if (e.cancelled)
            Text(
              'Evento cancelado',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: Text(formatWhen(e.startsAt)),
            subtitle: e.endsAt == null
                ? null
                : Text('até ${formatWhen(e.endsAt!)}'),
          ),
          if (e.location.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.place_outlined),
              title: Text(e.location),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.storefront_outlined),
            title: Text(e.placeName),
            onTap: widget.onOpenPlace == null
                ? null
                : () => widget.onOpenPlace!(e.placeSlug),
          ),
          if (e.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(e.description),
          ],
          const SizedBox(height: 16),
          if (!e.cancelled)
            SegmentedButton<String>(
              key: const Key('interest_buttons'),
              emptySelectionAllowed: true,
              segments: const [
                ButtonSegment(
                  value: 'interested',
                  label: Text('Tenho interesse'),
                  icon: Icon(Icons.star_outline),
                ),
                ButtonSegment(
                  value: 'going',
                  label: Text('Vou'),
                  icon: Icon(Icons.check_circle_outline),
                ),
              ],
              selected: {?e.myInterest},
              onSelectionChanged: _busy
                  ? null
                  : (s) => _interest(s.isEmpty ? null : s.first),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('calendar_button'),
            onPressed: _calendar,
            icon: const Icon(Icons.event_available),
            label: const Text('Adicionar ao Google Agenda'),
          ),
          if (e.friends.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              e.friendsCount == 1
                  ? '1 amigo marcou interesse'
                  : '${e.friendsCount} amigos marcaram interesse',
              style: theme.textTheme.titleSmall,
            ),
            for (final f in e.friends)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: UserAvatar(f),
                title: Text(f.label),
              ),
          ],
          if (e.goingCount != null) ...[
            const SizedBox(height: 16),
            Text(
              '${e.goingCount} vão · ${e.interestedCount} com interesse '
              '(só administradores veem)',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// Criar ou editar evento de uma página.
class EventFormScreen extends StatefulWidget {
  const EventFormScreen({
    super.key,
    required this.session,
    required this.placeSlug,
    this.existing,
  });

  final SessionController session;
  final String placeSlug;
  final PlaceEvent? existing;

  @override
  State<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends State<EventFormScreen> {
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _description = TextEditingController(
    text: widget.existing?.description,
  );
  late final _location = TextEditingController();
  late DateTime? _start = widget.existing?.startsAt.toLocal();
  late DateTime? _end = widget.existing?.endsAt?.toLocal();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime? initial) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial ?? now),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _save() async {
    final token = widget.session.token;
    final start = _start;
    if (token == null) return;
    if (start == null) {
      setState(() => _error = 'Escolha a data e a hora de início.');
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
          ? await api.createEvent(
              token,
              widget.placeSlug,
              title: _title.text.trim(),
              description: _description.text.trim(),
              location: _location.text.trim(),
              startsAt: start,
              endsAt: _end,
            )
          : await api.updateEvent(
              token,
              existing.id,
              title: _title.text.trim(),
              description: _description.text.trim(),
              startsAt: start,
              endsAt: _end,
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Novo evento' : 'Editar evento'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('event_title_field'),
            controller: _title,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Título'),
          ),
          ListTile(
            key: const Key('event_start_tile'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: Text(
              _start == null ? 'Começa quando?' : 'Começa ${formatWhen(_start!)}',
            ),
            onTap: () async {
              final t = await _pick(_start);
              if (t != null) setState(() => _start = t);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.timelapse),
            title: Text(
              _end == null
                  ? 'Termina (opcional)'
                  : 'Termina ${formatWhen(_end!)}',
            ),
            trailing: _end == null
                ? null
                : IconButton(
                    tooltip: 'Tirar horário de fim',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _end = null),
                  ),
            onTap: () async {
              final t = await _pick(_end ?? _start);
              if (t != null) setState(() => _end = t);
            },
          ),
          if (widget.existing == null)
            TextField(
              controller: _location,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Local (opcional)',
                helperText: 'Vazio = endereço da página.',
              ),
            ),
          TextField(
            key: const Key('event_description_field'),
            controller: _description,
            maxLength: 3000,
            minLines: 3,
            maxLines: 10,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Descrição',
              alignLabelWithHint: true,
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('save_event_button'),
            onPressed: _busy ? null : _save,
            child: Text(widget.existing == null ? 'Criar evento' : 'Salvar'),
          ),
        ],
      ),
    );
  }
}
