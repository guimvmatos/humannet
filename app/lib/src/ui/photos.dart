import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api/models.dart';

/// Abre a galeria (seletor de fotos do Android: não pede permissão).
/// O app já reduz a foto antes de enviar; o servidor recodifica e tira os
/// metadados (inclusive localização).
Future<List<Uint8List>> pickPhotos({int limit = 1}) async {
  final picker = ImagePicker();
  const maxSide = 1600.0;
  const quality = 85;
  final List<XFile> files;
  if (limit > 1) {
    files = await picker.pickMultiImage(
      maxWidth: maxSide,
      maxHeight: maxSide,
      imageQuality: quality,
      // Na web o seletor não aceita limite; cortamos abaixo.
      limit: kIsWeb ? null : limit,
    );
  } else {
    final f = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: maxSide,
      maxHeight: maxSide,
      imageQuality: quality,
    );
    files = [?f];
  }
  return [for (final f in files.take(limit)) await f.readAsBytes()];
}

/// Imagem da rede que também funciona na versão web (cai para <img> quando
/// o armazenamento não libera CORS).
ImageProvider webSafeImage(String url) =>
    NetworkImage(url, webHtmlElementStrategy: WebHtmlElementStrategy.fallback);

/// Foto da rede com carregando e erro discretos.
class NetPhoto extends StatelessWidget {
  const NetPhoto(this.url, {super.key, this.fit = BoxFit.cover});

  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Image.network(
      url,
      fit: fit,
      // Web: se o armazenamento das fotos não liberar CORS, usa <img>.
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : ColoredBox(color: bg),
      errorBuilder: (context, _, _) => ColoredBox(
        color: bg,
        child: const Center(child: Icon(Icons.broken_image_outlined)),
      ),
    );
  }
}

/// Fotos de um post: uma grande, ou grade 2×2.
class PostImages extends StatelessWidget {
  const PostImages({super.key, required this.images});

  final List<MediaRef> images;

  void _open(BuildContext context, int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoViewer(images: images, initial: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();
    final radius = BorderRadius.circular(12);
    if (images.length == 1) {
      final m = images.first;
      return ClipRRect(
        borderRadius: radius,
        child: AspectRatio(
          aspectRatio: m.aspectRatio.clamp(0.6, 2.0),
          child: GestureDetector(
            onTap: () => _open(context, 0),
            child: NetPhoto(m.url),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: radius,
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        children: [
          for (final (i, m) in images.indexed)
            GestureDetector(
              key: Key('post_image_$i'),
              onTap: () => _open(context, i),
              child: NetPhoto(m.url),
            ),
        ],
      ),
    );
  }
}

/// Tela cheia com zoom; arraste para os lados para passar.
class PhotoViewer extends StatelessWidget {
  const PhotoViewer({super.key, required this.images, this.initial = 0});

  final List<MediaRef> images;
  final int initial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: PageView(
        controller: PageController(initialPage: initial),
        children: [
          for (final m in images)
            InteractiveViewer(
              maxScale: 4,
              child: Center(child: NetPhoto(m.url, fit: BoxFit.contain)),
            ),
        ],
      ),
    );
  }
}

/// Foto de perfil redonda; sem foto, a inicial do nome.
class UserAvatar extends StatelessWidget {
  const UserAvatar(this.author, {super.key, this.radius = 18});

  final Author author;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = author.avatarUrl;
    final name = author.displayName ?? author.username;
    return CircleAvatar(
      radius: radius,
      backgroundImage: url == null ? null : webSafeImage(url),
      onBackgroundImageError: url == null ? null : (_, _) {},
      child: url == null
          ? Text(name.isEmpty ? '?' : name.characters.first.toUpperCase())
          : null,
    );
  }
}
