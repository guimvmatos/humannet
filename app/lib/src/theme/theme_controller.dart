import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../ui/wide_layout.dart';
import 'backgrounds.dart';

export 'backgrounds.dart' show AppBackground;

/// Um tema do app (como **eu** vejo o app; SPEC 4.7). Só cores e estilo,
/// sem identidade visual de terceiros.
class AppPalette {
  const AppPalette({
    required this.id,
    required this.label,
    required this.seed,
    this.variant = DynamicSchemeVariant.tonalSpot,
    this.fixedBrightness,
    this.background = AppBackground.none,
  });

  final String id;
  final String label;
  final Color seed;
  final DynamicSchemeVariant variant;

  /// Alguns temas só existem num modo (ex.: "Anos 80" é sempre escuro).
  final Brightness? fixedBrightness;

  /// Fundo ilustrado do tema (arte original, desenhada no app).
  final AppBackground background;

  ThemeData data(Brightness brightness) {
    final b = fixedBrightness ?? brightness;
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: b,
        dynamicSchemeVariant: variant,
      ),
    );
  }
}

const appPalettes = <AppPalette>[
  AppPalette(id: 'floresta', label: 'Floresta', seed: Color(0xFF3D6B5A)),
  AppPalette(id: 'oceano', label: 'Oceano', seed: Color(0xFF1E5AA8)),
  AppPalette(id: 'rosa', label: 'Rosa', seed: Color(0xFFC2185B)),
  AppPalette(id: 'lilas', label: 'Lilás', seed: Color(0xFF7E57C2)),
  AppPalette(id: 'por-do-sol', label: 'Pôr do sol', seed: Color(0xFFE65100)),
  AppPalette(
    id: 'aquarela',
    label: 'Aquarela',
    seed: Color(0xFF7FB3D5),
    variant: DynamicSchemeVariant.fruitSalad,
    fixedBrightness: Brightness.light,
  ),
  AppPalette(
    id: 'anos-80',
    label: 'Anos 80 neon',
    seed: Color(0xFFFF00A8),
    variant: DynamicSchemeVariant.vibrant,
    fixedBrightness: Brightness.dark,
    background: AppBackground.neon,
  ),
  AppPalette(
    id: 'medieval',
    label: 'Fantasia medieval',
    seed: Color(0xFFB0532F),
    variant: DynamicSchemeVariant.content,
    fixedBrightness: Brightness.dark,
    background: AppBackground.medieval,
  ),
  AppPalette(
    id: 'manga',
    label: 'Mangá',
    seed: Color(0xFFFF6D00),
    variant: DynamicSchemeVariant.vibrant,
    fixedBrightness: Brightness.light,
    background: AppBackground.manga,
  ),
  AppPalette(
    id: 'espaco',
    label: 'Espaço',
    seed: Color(0xFF5C6BC0),
    fixedBrightness: Brightness.dark,
    background: AppBackground.space,
  ),
  AppPalette(
    id: 'mata',
    label: 'Mata',
    seed: Color(0xFF2E7D32),
    fixedBrightness: Brightness.light,
    background: AppBackground.forest,
  ),
  AppPalette(
    id: 'praia',
    label: 'Praia',
    seed: Color(0xFF0288D1),
    fixedBrightness: Brightness.light,
    background: AppBackground.beach,
  ),
];

/// Que fundo usar: o do tema, nenhum ou uma foto da galeria.
enum BackgroundMode { theme, none, photo }

/// Onde guardar a preferência (no aparelho; R5: nada vai para o servidor).
abstract interface class PrefsStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SecurePrefsStore implements PrefsStore {
  SecurePrefsStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

class InMemoryPrefsStore implements PrefsStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

/// Tema escolhido + modo (sistema, claro, escuro).
class ThemeController extends ChangeNotifier {
  ThemeController(this._store);

  static const _paletteKey = 'theme_palette';
  static const _modeKey = 'theme_mode';
  static const _bgKey = 'theme_bg';
  static const _photoKey = 'theme_bg_photo';
  static const _strengthKey = 'theme_bg_strength';

  final PrefsStore _store;
  AppPalette _palette = appPalettes.first;
  ThemeMode _mode = ThemeMode.system;
  BackgroundMode _bgMode = BackgroundMode.theme;
  String? _photoPath;
  double _strength = 0.35;

  BackgroundMode get backgroundMode => _bgMode;

  /// Fundo ilustrado em uso (nenhum se o modo não for "do tema").
  AppBackground get background =>
      _bgMode == BackgroundMode.theme ? _palette.background : AppBackground.none;

  /// Foto de fundo em uso (só no modo "foto").
  String? get photoPath => _bgMode == BackgroundMode.photo ? _photoPath : null;
  String? get savedPhotoPath => _photoPath;

  /// Quanto o fundo aparece por trás do conteúdo (0,15 a 0,6).
  double get strength => _strength;
  bool get hasBackground => background != AppBackground.none || photoPath != null;

  AppPalette get palette => _palette;
  ThemeMode get mode => _palette.fixedBrightness == null
      ? _mode
      : (_palette.fixedBrightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light);
  ThemeMode get chosenMode => _mode;

  ThemeData get light => _withBackground(_palette.data(Brightness.light));
  ThemeData get dark => _withBackground(_palette.data(Brightness.dark));

  /// Telas abertas por cima ficam numa coluna central no notebook.
  static final _pages = widePageTransitions();

  /// Com fundo, as telas ficam transparentes para ele aparecer.
  ThemeData _withBackground(ThemeData t) => hasBackground
      ? t.copyWith(
          scaffoldBackgroundColor: Colors.transparent,
          pageTransitionsTheme: _pages,
          appBarTheme: AppBarTheme(
            backgroundColor: t.colorScheme.surface.withValues(alpha: 0.85),
          ),
        )
      : t.copyWith(pageTransitionsTheme: _pages);

  Future<void> load() async {
    try {
      final id = await _store.read(_paletteKey);
      final mode = await _store.read(_modeKey);
      _palette = appPalettes.firstWhere(
        (p) => p.id == id,
        orElse: () => appPalettes.first,
      );
      _mode = ThemeMode.values.firstWhere(
        (m) => m.name == mode,
        orElse: () => ThemeMode.system,
      );
      final bg = await _store.read(_bgKey);
      _bgMode = BackgroundMode.values.firstWhere(
        (m) => m.name == bg,
        orElse: () => BackgroundMode.theme,
      );
      _photoPath = await _store.read(_photoKey);
      if (_bgMode == BackgroundMode.photo && _photoPath == null) {
        _bgMode = BackgroundMode.theme;
      }
      _strength = (double.tryParse(await _store.read(_strengthKey) ?? '') ?? 0.35)
          .clamp(0.15, 0.6);
      notifyListeners();
    } catch (_) {
      // Sem preferência salva: fica o padrão.
    }
  }

  Future<void> setPalette(AppPalette p) async {
    _palette = p;
    notifyListeners();
    await _store.write(_paletteKey, p.id);
  }

  Future<void> setMode(ThemeMode m) async {
    _mode = m;
    notifyListeners();
    await _store.write(_modeKey, m.name);
  }

  Future<void> setBackgroundMode(BackgroundMode m) async {
    if (m == BackgroundMode.photo && _photoPath == null) return;
    _bgMode = m;
    notifyListeners();
    await _store.write(_bgKey, m.name);
  }

  /// Foto já salva no aparelho (caminho do arquivo). Passa a ser o fundo.
  Future<void> setPhoto(String path) async {
    _photoPath = path;
    _bgMode = BackgroundMode.photo;
    notifyListeners();
    await _store.write(_photoKey, path);
    await _store.write(_bgKey, BackgroundMode.photo.name);
  }

  Future<void> setStrength(double v) async {
    _strength = v.clamp(0.15, 0.6);
    notifyListeners();
    await _store.write(_strengthKey, _strength.toStringAsFixed(2));
  }
}

/// Dá acesso ao [ThemeController] em qualquer tela.
class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static ThemeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeScope>()?.notifier;
}
