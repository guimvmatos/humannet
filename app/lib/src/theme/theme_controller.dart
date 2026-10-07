import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Um tema do app (como **eu** vejo o app; SPEC 4.7). Só cores e estilo,
/// sem identidade visual de terceiros.
class AppPalette {
  const AppPalette({
    required this.id,
    required this.label,
    required this.seed,
    this.variant = DynamicSchemeVariant.tonalSpot,
    this.fixedBrightness,
  });

  final String id;
  final String label;
  final Color seed;
  final DynamicSchemeVariant variant;

  /// Alguns temas só existem num modo (ex.: "Anos 80" é sempre escuro).
  final Brightness? fixedBrightness;

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
    label: 'Anos 80',
    seed: Color(0xFFFF00A8),
    variant: DynamicSchemeVariant.vibrant,
    fixedBrightness: Brightness.dark,
  ),
];

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

  final PrefsStore _store;
  AppPalette _palette = appPalettes.first;
  ThemeMode _mode = ThemeMode.system;

  AppPalette get palette => _palette;
  ThemeMode get mode => _palette.fixedBrightness == null
      ? _mode
      : (_palette.fixedBrightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light);
  ThemeMode get chosenMode => _mode;

  ThemeData get light => _palette.data(Brightness.light);
  ThemeData get dark => _palette.data(Brightness.dark);

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
