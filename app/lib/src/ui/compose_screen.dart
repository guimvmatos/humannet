import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../auth/session_controller.dart';
import '../feed/interests.dart';
import '../geo/location.dart';
import 'error_messages.dart';
import 'photos.dart';
import 'tags_ui.dart';

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

  /// "Com fulano": amigos marcados (ficam pendentes até aprovarem).
  List<String> _tags = [];
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
              at: await postLocation(),
              tags: _tags,
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
            MentionSuggestions(session: widget.session, controller: _text),
            if (_tags.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('com'),
                    for (final u in _tags)
                      InputChip(
                        key: Key('compose_tag_$u'),
                        label: Text('@$u'),
                        onDeleted: _busy
                            ? null
                            : () => setState(() => _tags.remove(u)),
                      ),
                  ],
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
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  key: const Key('topics_button'),
                  onPressed: _busy ? null : _pickTopics,
                  icon: const Icon(Icons.sell_outlined),
                  label: Text(
                    _topics.isEmpty ? 'Temas' : 'Temas (${_topics.length}/3)',
                  ),
                ),
                if (widget.placeSlug == null)
                  TextButton.icon(
                    key: const Key('tag_friends_button'),
                    onPressed: _busy
                        ? null
                        : () async {
                            final picked = await pickTaggedFriends(
                              context,
                              widget.session,
                              _tags,
                            );
                            if (picked != null && mounted) {
                              setState(() => _tags = picked);
                            }
                          },
                    icon: const Icon(Icons.person_pin_outlined),
                    label: Text(_tags.isEmpty ? 'Marcar' : 'Marcar (${_tags.length})'),
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
                if (_status != null)
                  Text(_status!, style: theme.textTheme.bodySmall),
              ],
            ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            if (widget.placeSlug == null)
              Text(
                'Todo post é público: amigos veem no Cronológico, e quem tem '
                'os mesmos interesses ou está perto pode ver no Para você e '
                'no Regional. Vai só uma área aproximada (desviada até '
                '~1,5 km), nunca a distância.',
                key: const Key('compose_public_note'),
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}
