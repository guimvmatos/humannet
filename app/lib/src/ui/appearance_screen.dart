import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../theme/backgrounds.dart';
import '../theme/theme_controller.dart';
import 'photos.dart';

/// Escolhe uma foto da galeria e guarda uma cópia só neste aparelho.
Future<String?> _pickBackgroundPhoto() async {
  final photos = await pickPhotos();
  if (photos.isEmpty) return null;
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
  await file.writeAsBytes(photos.first, flush: true);
  return file.path;
}

/// Escolha do tema do app. Fica salvo só neste aparelho.
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themes = ThemeScope.maybeOf(context);
    if (themes == null) return const Scaffold();
    final fixed = themes.palette.fixedBrightness != null;
    return Scaffold(
      key: const Key('appearance_screen'),
      appBar: AppBar(title: const Text('Aparência')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SegmentedButton<ThemeMode>(
              key: const Key('theme_mode'),
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('Sistema'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Claro'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Escuro'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {themes.chosenMode},
              onSelectionChanged: fixed
                  ? null
                  : (s) => themes.setMode(s.first),
            ),
          ),
          if (fixed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '"${themes.palette.label}" tem modo próprio.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: themes.palette.id,
            onChanged: (id) => themes.setPalette(
              appPalettes.firstWhere((p) => p.id == id),
            ),
            child: Column(
              children: [
                for (final p in appPalettes)
                  RadioListTile<String>(
                    key: Key('palette_${p.id}'),
                    value: p.id,
                    title: Text(p.label),
                    subtitle: p.background == AppBackground.none
                        ? null
                        : const Text('com fundo ilustrado'),
                    secondary: p.background == AppBackground.none
                        ? _Swatch(p)
                        : _Preview(p.background),
                  ),
              ],
            ),
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Fundo', style: Theme.of(context).textTheme.titleSmall),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SegmentedButton<BackgroundMode>(
              key: const Key('background_mode'),
              segments: const [
                ButtonSegment(
                  value: BackgroundMode.theme,
                  label: Text('Do tema'),
                ),
                ButtonSegment(value: BackgroundMode.none, label: Text('Nenhum')),
                ButtonSegment(
                  value: BackgroundMode.photo,
                  label: Text('Minha foto'),
                ),
              ],
              selected: {themes.backgroundMode},
              onSelectionChanged: (s) async {
                final m = s.first;
                if (m == BackgroundMode.photo && themes.savedPhotoPath == null) {
                  final path = await _pickBackgroundPhoto();
                  if (path != null) await themes.setPhoto(path);
                } else {
                  await themes.setBackgroundMode(m);
                }
              },
            ),
          ),
          if (themes.backgroundMode == BackgroundMode.photo)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TextButton.icon(
                  onPressed: () async {
                    final path = await _pickBackgroundPhoto();
                    if (path != null) await themes.setPhoto(path);
                  },
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Trocar foto'),
                ),
              ),
            ),
          if (themes.hasBackground)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Text('Intensidade'),
                  Expanded(
                    child: Slider(
                      key: const Key('background_strength'),
                      value: themes.strength,
                      min: 0.15,
                      max: 0.6,
                      onChanged: themes.setStrength,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              'Os fundos são arte original desenhada no app. A sua foto fica '
              'só neste aparelho e ninguém mais vê.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'O tema muda só como você vê o app, e fica salvo neste aparelho.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.palette);

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final scheme = palette
        .data(palette.fixedBrightness ?? Theme.of(context).brightness)
        .colorScheme;
    Widget dot(Color c) => Container(
      width: 16,
      height: 16,
      margin: const EdgeInsets.only(left: 2),
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot(scheme.primary),
        dot(scheme.secondary),
        dot(scheme.tertiary),
        dot(scheme.surface),
      ],
    );
  }
}

/// Miniatura do fundo ilustrado.
class _Preview extends StatelessWidget {
  const _Preview(this.background);

  final AppBackground background;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: SizedBox(
      width: 56,
      height: 36,
      child: CustomPaint(painter: BackgroundPainter(background)),
    ),
  );
}
