import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Guarda a foto e devolve onde ficou (caminho do arquivo).
Future<String> saveLocalPhoto(Uint8List bytes) async {
  final dir = await getApplicationDocumentsDirectory();
  // Nome novo a cada troca (o Flutter guarda imagens em cache pelo caminho).
  for (final old in dir.listSync().whereType<File>()) {
    if (old.path.contains('fundo_')) {
      try {
        old.deleteSync();
      } catch (_) {}
    }
  }
  final file = File(
    '${dir.path}/fundo_${DateTime.now().millisecondsSinceEpoch}.jpg',
  );
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Widget _hide(BuildContext context, Object error, StackTrace? stack) =>
    const SizedBox.shrink();

Widget localPhotoImage(String path, {Key? key}) {
  const error = _hide;
  if (path.startsWith('data:')) {
    return Image.memory(
      base64Decode(path.substring(path.indexOf(',') + 1)),
      key: key,
      fit: BoxFit.cover,
      errorBuilder: error,
    );
  }
  return Image.file(File(path), key: key, fit: BoxFit.cover, errorBuilder: error);
}
