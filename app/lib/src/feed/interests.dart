import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../api/models.dart';
import '../theme/theme_controller.dart' show PrefsStore;

/// Temas dos posts (mesma lista do servidor, `GET /v1/topics`).
class TopicDef {
  const TopicDef(this.id, this.label, [this.sub = const []]);

  final String id;
  final String label;
  final List<(String, String)> sub;
}

const appTopics = <TopicDef>[
  TopicDef('politica', 'Política', [
    ('brasil', 'Brasil'),
    ('mundo', 'Mundo'),
    ('economia', 'Economia'),
    ('eleicoes', 'Eleições'),
  ]),
  TopicDef('esportes', 'Esportes', [
    ('futebol', 'Futebol'),
    ('volei', 'Vôlei'),
    ('basquete', 'Basquete'),
    ('lutas', 'Lutas'),
    ('corrida', 'Corrida'),
  ]),
  TopicDef('musica', 'Música'),
  TopicDef('cinema-series', 'Cinema e séries'),
  TopicDef('games', 'Games'),
  TopicDef('tecnologia', 'Tecnologia'),
  TopicDef('ciencia', 'Ciência'),
  TopicDef('universidade', 'Faculdade e estudos'),
  TopicDef('trabalho', 'Trabalho e carreira'),
  TopicDef('humor', 'Humor'),
  TopicDef('comida', 'Comida'),
  TopicDef('viagem', 'Viagem'),
  TopicDef('natureza', 'Natureza e animais'),
  TopicDef('saude', 'Saúde e bem-estar'),
  TopicDef('arte', 'Arte e cultura'),
  TopicDef('eventos', 'Eventos e rolês'),
  TopicDef('cidade', 'Cidade e bairro', [
    ('transito', 'Trânsito'),
    ('clima', 'Clima e alertas'),
    ('seguranca', 'Segurança'),
  ]),
  TopicDef('vida', 'Vida pessoal'),
];

/// "politica.eleicoes" → "Eleições (Política)".
String topicLabel(String id) {
  final (main, sub) = switch (id.split('.')) {
    [final m, final s] => (m, s),
    [final m] => (m, null),
    _ => (id, null),
  };
  for (final t in appTopics) {
    if (t.id != main) continue;
    if (sub == null) return t.label;
    for (final (sid, label) in t.sub) {
      if (sid == sub) return '$label (${t.label})';
    }
  }
  return id;
}

bool _isPolitical(Post p) => p.topics.any((t) => t.split('.').first == 'politica');

/// Um post ordenado e o porquê.
class RankedPost {
  const RankedPost(this.post, this.reasons);

  final Post post;
  final List<String> reasons;
}

/// Perfil de interesses do feed "Para você". Fica **só neste aparelho**
/// (ADR-0004): o servidor nunca recebe nem guarda.
///
/// Aprende só com ações explícitas (curtir, comentar), nunca com tempo de
/// tela. A pessoa vê, ajusta e apaga tudo, e pode pausar o aprendizado.
/// Detalhes de Política (hashtags e pessoas em posts políticos) só com
/// consentimento explícito (`politicsDetail`, ADR-0007).
class InterestProfile extends ChangeNotifier {
  InterestProfile(this._store);

  static const _maxWeight = 20.0;
  static const _maxEntries = 120;

  final PrefsStore _store;
  String _key = 'interests_v1';

  final Map<String, double> topics = {};
  final Map<String, double> tags = {};
  final Map<String, double> people = {};

  /// Hashtags aprendidas em posts de Política (apagadas se o consentimento
  /// for retirado).
  final Set<String> politicalTags = {};
  final Set<String> hiddenTopics = {};
  bool paused = false;
  bool politicsDetail = false;

  /// Modo do feed escolhido: "chrono" (padrão) ou "foryou".
  String feedMode = 'chrono';

  Future<void> setFeedMode(String m) async {
    feedMode = m == 'foryou' ? 'foryou' : 'chrono';
    await _save();
  }

  /// Carrega o perfil desta conta (cada conta no aparelho tem o seu).
  Future<void> loadFor(String userId) async {
    _key = 'interests_v1_$userId';
    topics.clear();
    tags.clear();
    people.clear();
    politicalTags.clear();
    hiddenTopics.clear();
    paused = false;
    politicsDetail = false;
    feedMode = 'chrono';
    try {
      final raw = await _store.read(_key);
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        Map<String, double> m(String k) =>
            ((j[k] as Map<String, dynamic>?) ?? const {}).map(
              (key, v) => MapEntry(key, (v as num).toDouble()),
            );
        topics.addAll(m('topics'));
        tags.addAll(m('tags'));
        people.addAll(m('people'));
        politicalTags.addAll(
          ((j['political_tags'] as List<dynamic>?) ?? const []).cast<String>(),
        );
        hiddenTopics.addAll(
          ((j['hidden'] as List<dynamic>?) ?? const []).cast<String>(),
        );
        paused = (j['paused'] as bool?) ?? false;
        politicsDetail = (j['politics_detail'] as bool?) ?? false;
        feedMode = (j['mode'] as String?) == 'foryou' ? 'foryou' : 'chrono';
      }
    } catch (_) {
      // Perfil corrompido: começa do zero.
    }
    notifyListeners();
  }

  Future<void> _save() async {
    notifyListeners();
    await _store.write(
      _key,
      jsonEncode({
        'topics': topics,
        'tags': tags,
        'people': people,
        'political_tags': politicalTags.toList(),
        'hidden': hiddenTopics.toList(),
        'paused': paused,
        'politics_detail': politicsDetail,
        'mode': feedMode,
      }),
    );
  }

  static void _bump(Map<String, double> m, String k, double w) {
    m[k] = math.min(_maxWeight, (m[k] ?? 0) + w);
    if (m.length > _maxEntries) {
      final weakest = m.entries.reduce((a, b) => a.value <= b.value ? a : b);
      m.remove(weakest.key);
    }
  }

  /// Curtir = 1; comentar = 2.
  Future<void> learn(Post p, {double weight = 1, String? me}) async {
    if (paused) return;
    final political = _isPolitical(p);
    for (final t in p.topics) {
      _bump(topics, t, weight);
      final main = t.split('.').first;
      if (main != t) _bump(topics, main, weight * 0.5);
    }
    if (!political || politicsDetail) {
      for (final h in p.hashtags) {
        _bump(tags, h, weight * 0.6);
        if (political) politicalTags.add(h);
      }
      if (p.author.username != me) {
        _bump(people, p.author.username, weight * 0.5);
      }
    }
    await _save();
  }

  Future<void> setWeight(Map<String, double> m, String k, double w) async {
    m[k] = w.clamp(0, _maxWeight);
    await _save();
  }

  Future<void> remove(Map<String, double> m, String k) async {
    m.remove(k);
    politicalTags.remove(k);
    await _save();
  }

  Future<void> setHidden(String topic, bool hidden) async {
    if (hidden) {
      hiddenTopics.add(topic);
    } else {
      hiddenTopics.remove(topic);
    }
    await _save();
  }

  Future<void> setPaused(bool v) async {
    paused = v;
    await _save();
  }

  /// Retirar o consentimento apaga o que foi aprendido em posts políticos.
  Future<void> setPoliticsDetail(bool v) async {
    politicsDetail = v;
    if (!v) {
      for (final t in politicalTags) {
        tags.remove(t);
      }
      politicalTags.clear();
    }
    await _save();
  }

  Future<void> reset() async {
    topics.clear();
    tags.clear();
    people.clear();
    politicalTags.clear();
    await _save();
  }

  bool get isEmpty => topics.isEmpty && tags.isEmpty && people.isEmpty;

  /// Ordena os candidatos: interesses × recência (meia-vida ~1 dia).
  /// Esconde temas ocultos. Cada item diz por que está ali.
  List<RankedPost> rank(List<Post> posts, {DateTime? now}) {
    final t0 = now ?? DateTime.now();
    final scored = <(double, RankedPost)>[];
    for (final p in posts) {
      if (p.topics.any(
        (t) => hiddenTopics.contains(t) || hiddenTopics.contains(t.split('.').first),
      )) {
        continue;
      }
      final parts = <(double, String)>[];
      for (final t in p.topics) {
        final w = (topics[t] ?? 0) + 0.5 * (topics[t.split('.').first] ?? 0);
        if (w > 0) parts.add((w, 'Você curte ${topicLabel(t)}'));
      }
      for (final h in p.hashtags) {
        final w = tags[h] ?? 0;
        if (w > 0) parts.add((w, 'Você curte #$h'));
      }
      final pw = people[p.author.username] ?? 0;
      if (pw > 0) parts.add((pw, 'Você interage com @${p.author.username}'));
      final interest = parts.fold<double>(0, (a, b) => a + b.$1);
      final ageH = t0.difference(p.createdAt).inMinutes / 60;
      final recency = math.exp(-math.max(0, ageH) / 36);
      final score = recency * (1 + math.log(1 + interest));
      parts.sort((a, b) => b.$1.compareTo(a.$1));
      final reasons = parts.take(2).map((e) => e.$2).toList();
      if (reasons.isEmpty) reasons.add('Recente, de quem você acompanha');
      scored.add((score, RankedPost(p, reasons)));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final s in scored) s.$2];
  }
}
