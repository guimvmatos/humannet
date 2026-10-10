import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../auth/session_controller.dart';
import '../feed/interests.dart';
import '../geo/location.dart';
import 'error_messages.dart';
import 'photos.dart';

/// Escreve um post (texto e/ou até 4 fotos). Retorna o `Post` criado via
/// Navigator.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({
    super.key,
    required this.session,
    this.pickPhotos,
    this.placeSlug,
    this.placeName,
  });

  final SessionController session;

  /// Publicar no mural desta página (quem administra), em vez do perfil.
  final String? placeSlug;
  final String? placeName;

  /// Para testes: substitui a galeria.
  final Future<List<Uint8List>> Function(int limit)? pickPhotos;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  static const _max = 5000;
  static const _maxPhotos = 4;

  final _text = TextEditingController();
  final List<Uint8List> _photos = [];
  final List<String> _topics = [];

  /// Público: amigos (padrão) ou a região (quem estiver perto, até 50 km).
  bool _region = false;
  bool _busy = false;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _canPublish =>
      !_busy && (_text.text.trim().isNotEmpty || _photos.isNotEmpty);

  Future<void> _addPhotos() async {
    final left = _maxPhotos - _photos.length;
    if (left <= 0) return;
    try {
      final picked = await (widget.pickPhotos ?? (n) => pickPhotos(limit: n))(
        left,
      );
      if (mounted) setState(() => _photos.addAll(picked.take(left)));
    } catch (_) {
      if (mounted) setState(() => _error = 'Não deu para abrir a galeria.');
    }
  }

  /// Até 3 temas (tema ou subtema, ex.: "Trânsito (Cidade e bairro)").
  Future<void> _pickTopics() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void toggle(String id) {
            setState(() {
              if (_topics.contains(id)) {
                _topics.remove(id);
              } else if (_topics.length < 3) {
                _topics.add(id);
              }
            });
            setSheet(() {});
          }

          Widget chip(String id, String label) => FilterChip(
            key: Key('topic_$id'),
            label: Text(label),
            selected: _topics.contains(id),
            onSelected: (_) => toggle(id),
          );
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Temas do post (até 3)',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ajudam quem usa o "Para você" a achar o seu post. Use '
                    '#hashtags no texto para detalhar.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  for (final t in appTopics) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        chip(t.id, t.label),
                        for (final (sid, label) in t.sub)
                          chip('${t.id}.$sid', label),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      key: const Key('topics_done'),
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Pronto'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _publish() async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = widget.session.api;
      final ids = <String>[];
      for (final (i, bytes) in _photos.indexed) {
        setState(() => _status = 'Enviando foto ${i + 1} de ${_photos.length}…');
        ids.add((await api.uploadMedia(token, 'post', bytes)).id);
      }
      setState(() => _status = 'Publicando…');
      final slug = widget.placeSlug;
      final post = slug == null
          ? await api.createPost(
              token,
              _text.text,
              mediaIds: ids,
              topics: _topics,
              region: _region ? await approxLocation() : null,
            )
          : await api.postToPlace(
              token,
              slug,
              _text.text,
              mediaIds: ids,
              topics: _topics,
            );
      if (mounted) Navigator.of(context).pop(post);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.placeName == null
              ? 'Novo post'
              : 'Post como ${widget.placeName}',
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              key: const Key('publish_button'),
              onPressed: _canPublish ? _publish : null,
              child: const Text('Publicar'),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: TextField(
                key: const Key('compose_field'),
                controller: _text,
                autofocus: true,
                maxLength: _max,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: 'O que você quer compartilhar?',
                  border: InputBorder.none,
                ),
              ),
            ),
            if (_topics.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (final t in _topics)
                      InputChip(
                        label: Text(topicLabel(t)),
                        onDeleted: _busy
                            ? null
                            : () => setState(() => _topics.remove(t)),
                      ),
                  ],
                ),
              ),
            if (_photos.isNotEmpty)
              SizedBox(
                height: 88,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final (i, bytes) in _photos.indexed)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                bytes,
                                key: Key('compose_photo_$i'),
                                width: 88,
                                height: 88,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: IconButton.filledTonal(
                                key: Key('remove_photo_$i'),
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Tirar foto',
                                iconSize: 16,
                                onPressed: _busy
                                    ? null
                                    : () => setState(() => _photos.removeAt(i)),
                                icon: const Icon(Icons.close),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            if (widget.placeSlug == null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: SegmentedButton<bool>(
                    key: const Key('audience'),
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Amigos'),
                        icon: Icon(Icons.people_outline),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Região', key: Key('audience_region')),
                        icon: Icon(Icons.near_me_outlined),
                      ),
                    ],
                    selected: {_region},
                    onSelectionChanged: _busy
                        ? null
                        : (s) => setState(() => _region = s.first),
                  ),
                ),
              ),
            if (_region && widget.placeSlug == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Qualquer pessoa num raio de até 50 km pode ver. Vai só a '
                  'área aproximada (~500 m), nunca o endereço, e a distância '
                  'não aparece para ninguém.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            Row(
              children: [
                TextButton.icon(
                  key: const Key('topics_button'),
                  onPressed: _busy ? null : _pickTopics,
                  icon: const Icon(Icons.sell_outlined),
                  label: Text(
                    _topics.isEmpty ? 'Temas' : 'Temas (${_topics.length}/3)',
                  ),
                ),
                TextButton.icon(
                  key: const Key('add_photos_button'),
                  onPressed: _busy || _photos.length >= _maxPhotos
                      ? null
                      : _addPhotos,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(
                    _photos.isEmpty
                        ? 'Fotos'
                        : 'Fotos (${_photos.length}/$_maxPhotos)',
                  ),
                ),
                const Spacer(),
                if (_status != null)
                  Text(_status!, style: theme.textTheme.bodySmall),
              ],
            ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ),
      ),
    );
  }
}
