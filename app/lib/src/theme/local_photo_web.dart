import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Na web não há arquivos: a foto (já reduzida) vira um data URL, guardado
/// nas preferências deste navegador.
Future<String> saveLocalPhoto(Uint8List bytes) async =>
    'data:image/jpeg;base64,${base64Encode(bytes)}';

Widget localPhotoImage(String path, {Key? key}) {
  if (!path.startsWith('data:')) return const SizedBox.shrink();
  return Image.memory(
    base64Decode(path.substring(path.indexOf(',') + 1)),
    key: key,
    fit: BoxFit.cover,
    gaplessPlayback: true,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );
}
