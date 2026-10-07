import 'package:flutter/material.dart';

import '../theme/theme_controller.dart';

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
                    secondary: _Swatch(p),
                  ),
              ],
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
