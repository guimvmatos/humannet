import 'dart:async';

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'error_messages.dart';

/// "Minha história" (própria, editável) ou a de um amigo (só leitura).
Future<void> openTimeline(
  BuildContext context,
  SessionController session, {
  String? username,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => TimelineScreen(session: session, username: username),
  ),
);

IconData _icon(String kind) => switch (kind) {
  'nasceu' => Icons.child_friendly_outlined,
  'morou' => Icons.home_outlined,
  'escola' => Icons.school_outlined,
  'faculdade' => Icons.account_balance_outlined,
  'trabalho' => Icons.work_outline,
  _ => Icons.circle_outlined,
};

String _visibilityLabel(String? v) => switch (v) {
  'friends' => 'Amigos veem',
  'suggestions' => 'Só para sugestões',
  'private' => 'Só você',
  _ => '',
};

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key, required this.session, this.username});

  final SessionController session;

  /// Nulo = a minha.
  final String? username;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  List<LifeEntry>? _items;
  String? _error;

  bool get _mine => widget.username == null;

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
      final u = widget.username;
      final items = u == null
          ? await api.myTimeline(token)
          : await api.userTimeline(token, u);
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _add() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in lifeKinds.entries)
              ListTile(
                key: Key('add_kind_${e.key}'),
                leading: Icon(_icon(e.key)),
                title: Text(e.value),
                onTap: () => Navigator.of(ctx).pop(e.key),
              ),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;
    await _edit(LifeEntry(id: '', kind: kind));
  }

  Future<void> _edit(LifeEntry entry) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LifeEntryForm(session: widget.session, entry: entry),
      ),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('timeline_screen'),
      appBar: AppBar(
        title: Text(_mine ? 'Minha história' : 'História de @${widget.username}'),
      ),
      floatingActionButton: _mine
          ? FloatingActionButton.extended(
              heroTag: 'timeline_add_fab',
              key: const Key('timeline_add_button'),
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('Adicionar'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            if (_mine)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Conte onde você nasceu, morou, estudou e trabalhou, com os '
                  'anos. Assim a HumanNet sugere quem estudou ou trabalhou com '
                  'você na mesma época, sempre dizendo o motivo. Você escolhe, '
                  'item a item, quem vê e se quer ser encontrado por ele.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(16), child: Text(_error!))
            else if (items == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _mine
                      ? 'Comece pela escola ou pela faculdade: é o que mais '
                            'ajuda a reencontrar gente.'
                      : 'Nada para mostrar.',
                  key: const Key('timeline_empty'),
                  textAlign: TextAlign.center,
                ),
              )
            else
              for (final e in items)
                ListTile(
                  key: Key('life_${e.id}'),
                  leading: Icon(_icon(e.kind)),
                  title: Text(e.title),
                  subtitle: Text(
                    [
                      if (e.period.isNotEmpty) e.period,
                      if (e.level != null) lifeLevels[e.level] ?? '',
                      if (_mine) _visibilityLabel(e.visibility),
                      if (_mine && e.discoverable == false) 'não encontrável',
                    ].where((s) => s.isNotEmpty).join(' · '),
                  ),
                  trailing: _mine ? const Icon(Icons.edit_outlined) : null,
                  onTap: _mine ? () => _edit(e) : null,
                ),
          ],
        ),
      ),
    );
  }
}

/// Criar ou editar um item. `entry.id` vazio = novo.
class LifeEntryForm extends StatefulWidget {
  const LifeEntryForm({super.key, required this.session, required this.entry});

  final SessionController session;
  final LifeEntry entry;

  @override
  State<LifeEntryForm> createState() => _LifeEntryFormState();
}

class _LifeEntryFormState extends State<LifeEntryForm> {
  late final String _kind = widget.entry.kind;
  late Municipality? _city = widget.entry.municipality ??
      widget.entry.org?.municipality;
  late Org? _org = widget.entry.org;
  late Course? _course = widget.entry.course;
  late String? _level = widget.entry.level;
  late final _start = TextEditingController(
    text: widget.entry.startYear?.toString() ?? '',
  );
  late final _end = TextEditingController(
    text: widget.entry.endYear?.toString() ?? '',
  );
  late bool _current =
      widget.entry.id.isNotEmpty && widget.entry.endYear == null;
  late String _visibility = widget.entry.visibility ??
      (_kind == 'nasceu' || _kind == 'escola' ? 'suggestions' : 'friends');
  late bool _discoverable = widget.entry.discoverable ?? true;
  bool _busy = false;
  String? _error;

  bool get _isNew => widget.entry.id.isEmpty;
  bool get _usesOrg => const {'escola', 'faculdade', 'trabalho'}.contains(_kind);
  String get _orgKind => switch (_kind) {
    'escola' => 'escola',
    'faculdade' => 'faculdade',
    _ => 'empresa',
  };

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  String? get _token => widget.session.token;

  Future<void> _pickCity() async {
    final token = _token;
    if (token == null) return;
    final m = await Navigator.of(context).push<Municipality>(
      MaterialPageRoute(
        builder: (_) => SearchPickerScreen<Municipality>(
          title: 'Cidade',
          hint: 'Nome da cidade',
          search: (q) => widget.session.api.municipalities(token, q),
          label: (m) => m.label,
        ),
      ),
    );
    if (m != null) {
      setState(() {
        _city = m;
        if (_org?.municipality?.code != m.code) _org = null;
      });
    }
  }

  Future<void> _pickOrg() async {
    final token = _token;
    if (token == null) return;
    final city = _city;
    final api = widget.session.api;
    final o = await Navigator.of(context).push<Org>(
      MaterialPageRoute(
        builder: (_) => SearchPickerScreen<Org>(
          title: switch (_orgKind) {
            'escola' => 'Escola',
            'faculdade' => 'Faculdade',
            _ => 'Empresa',
          },
          hint: city == null ? 'Nome' : 'Nome (em ${city.name})',
          search: (q) => api.orgs(token, _orgKind, q, city: city?.code),
          label: (o) => o.label,
          create: (name) =>
              api.createOrg(token, _orgKind, name, city: city?.code),
          createLabel: (name) => city == null
              ? 'Adicionar "$name"'
              : 'Adicionar "$name" em ${city.name}',
        ),
      ),
    );
    if (o != null) setState(() => _org = o);
  }

  Future<void> _pickCourse() async {
    final token = _token;
    if (token == null) return;
    final api = widget.session.api;
    final c = await Navigator.of(context).push<Course>(
      MaterialPageRoute(
        builder: (_) => SearchPickerScreen<Course>(
          title: 'Curso',
          hint: 'Nome do curso',
          search: (q) => api.courses(token, q),
          label: (c) => c.name,
          create: (name) => api.createCourse(token, name),
          createLabel: (name) => 'Adicionar "$name"',
        ),
      ),
    );
    if (c != null) setState(() => _course = c);
  }

  int? _year(TextEditingController c) => int.tryParse(c.text.trim());

  Future<void> _save() async {
    final token = _token;
    if (token == null) return;
    if (!_usesOrg && _city == null) {
      setState(() => _error = 'Escolha a cidade.');
      return;
    }
    if (_usesOrg && _org == null) {
      setState(() => _error = 'Escolha ou adicione a instituição.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final entry = LifeEntry(
        id: widget.entry.id,
        kind: _kind,
        municipality: _usesOrg ? null : _city,
        org: _usesOrg ? _org : null,
        course: _kind == 'faculdade' ? _course : null,
        level: _usesOrg && _kind != 'trabalho' ? _level : null,
        startYear: _year(_start),
        endYear: _kind == 'nasceu' || _current ? null : _year(_end),
        visibility: _visibility,
        discoverable: _discoverable,
      );
      await widget.session.api.saveLifeEntry(
        token,
        entry,
        id: _isNew ? null : widget.entry.id,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final token = _token;
    if (token == null) return;
    try {
      await widget.session.api.deleteLifeEntry(token, widget.entry.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final city = _city;
    final org = _org;
    final course = _course;
    final levels = switch (_kind) {
      'escola' => const ['fundamental', 'medio', 'tecnico'],
      'faculdade' => const ['graduacao', 'pos'],
      _ => const <String>[],
    };
    return Scaffold(
      key: const Key('life_form'),
      appBar: AppBar(
        title: Text(lifeKinds[_kind] ?? ''),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Apagar',
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            key: const Key('life_city'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.location_city_outlined),
            title: Text(
              city?.label ??
                  (_usesOrg ? 'Cidade (opcional, ajuda a achar)' : 'Cidade'),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickCity,
          ),
          if (_usesOrg)
            ListTile(
              key: const Key('life_org'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(_icon(_kind)),
              title: Text(
                org?.name ??
                    switch (_kind) {
                      'escola' => 'Escola',
                      'faculdade' => 'Faculdade',
                      _ => 'Empresa',
                    },
              ),
              subtitle: org?.municipality == null
                  ? null
                  : Text(org!.municipality!.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickOrg,
            ),
          if (_kind == 'faculdade')
            ListTile(
              key: const Key('life_course'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(course?.name ?? 'Curso'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickCourse,
            ),
          if (levels.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _level,
              decoration: const InputDecoration(labelText: 'Nível'),
              items: [
                for (final l in levels)
                  DropdownMenuItem(value: l, child: Text(lifeLevels[l] ?? l)),
              ],
              onChanged: (v) => setState(() => _level = v),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('life_start'),
                  controller: _start,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: InputDecoration(
                    labelText: _kind == 'nasceu' ? 'Ano em que nasci' : 'De (ano)',
                    counterText: '',
                  ),
                ),
              ),
              if (_kind != 'nasceu') ...[
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    key: const Key('life_end'),
                    controller: _end,
                    enabled: !_current,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    decoration: const InputDecoration(
                      labelText: 'Até (ano)',
                      counterText: '',
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (_kind != 'nasceu')
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _current,
              onChanged: (v) => setState(() => _current = v ?? false),
              title: const Text('Até hoje'),
            ),
          const SizedBox(height: 8),
          Text('Quem vê este item', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            key: const Key('life_visibility'),
            segments: const [
              ButtonSegment(value: 'friends', label: Text('Amigos')),
              ButtonSegment(value: 'suggestions', label: Text('Ninguém*')),
              ButtonSegment(value: 'private', label: Text('Só eu')),
            ],
            selected: {_visibility},
            onSelectionChanged: (s) => setState(() => _visibility = s.first),
          ),
          const SizedBox(height: 4),
          Text(
            '* Não aparece no seu perfil, mas pode gerar sugestões. Onde você '
            'nasceu e a escola começam assim porque são perguntas de '
            'segurança de banco.',
            style: theme.textTheme.bodySmall,
          ),
          SwitchListTile(
            key: const Key('life_discoverable'),
            contentPadding: EdgeInsets.zero,
            value: _discoverable && _visibility != 'private',
            onChanged: _visibility == 'private'
                ? null
                : (v) => setState(() => _discoverable = v),
            title: const Text('Quero ser encontrado por este item'),
            subtitle: const Text(
              'Quem tem o mesmo item na mesma época pode receber você como '
              'sugestão, com o motivo.',
            ),
          ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('life_save'),
            onPressed: _busy ? null : _save,
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}

/// Tela de busca com lista de resultados e, opcionalmente, "Adicionar".
class SearchPickerScreen<T> extends StatefulWidget {
  const SearchPickerScreen({
    super.key,
    required this.title,
    required this.hint,
    required this.search,
    required this.label,
    this.create,
    this.createLabel,
  });

  final String title;
  final String hint;
  final Future<List<T>> Function(String q) search;
  final String Function(T) label;
  final Future<T> Function(String name)? create;
  final String Function(String name)? createLabel;

  @override
  State<SearchPickerScreen<T>> createState() => _SearchPickerScreenState<T>();
}

class _SearchPickerScreenState<T> extends State<SearchPickerScreen<T>> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<T> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _run);
    setState(() {});
  }

  Future<void> _run() async {
    final q = _q.text.trim();
    if (q.length < 2) {
      setState(() => _results = const []);
      return;
    }
    setState(() => _loading = true);
    try {
      final r = await widget.search(q);
      if (mounted && _q.text.trim() == q) {
        setState(() {
          _results = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final create = widget.create;
    final name = _q.text.trim();
    if (create == null || name.length < 2) return;
    try {
      final created = await create(name);
      if (mounted) Navigator.of(context).pop(created);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _q.text.trim();
    final canCreate = widget.create != null && name.length >= 2;
    return Scaffold(
      key: const Key('search_picker'),
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              key: const Key('picker_field'),
              controller: _q,
              autofocus: true,
              onChanged: _changed,
              decoration: InputDecoration(
                hintText: widget.hint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _loading
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
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
          Expanded(
            child: ListView(
              children: [
                for (final (i, r) in _results.indexed)
                  ListTile(
                    key: Key('picker_result_$i'),
                    title: Text(widget.label(r)),
                    onTap: () => Navigator.of(context).pop(r),
                  ),
                if (canCreate)
                  ListTile(
                    key: const Key('picker_create'),
                    leading: const Icon(Icons.add),
                    title: Text(widget.createLabel?.call(name) ?? name),
                    subtitle: const Text(
                      'Não achou? Adicione. Confira a grafia: outras pessoas '
                      'vão escolher o mesmo nome.',
                    ),
                    onTap: _create,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
