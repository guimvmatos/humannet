import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../auth/session_controller.dart';
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
          ? await api.createPost(token, _text.text, mediaIds: ids)
          : await api.postToPlace(token, slug, _text.text, mediaIds: ids);
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
            Row(
              children: [
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
