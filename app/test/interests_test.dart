import 'package:flutter_test/flutter_test.dart';
import 'package:humannet/src/api/models.dart';
import 'package:humannet/src/feed/interests.dart';
import 'package:humannet/src/theme/theme_controller.dart';

Post _post(
  String id, {
  String author = 'bob',
  List<String> topics = const [],
  List<String> tags = const [],
  int hoursAgo = 1,
}) => Post(
  id: id,
  author: Author(id: 'u-$author', username: author),
  body: 'x',
  createdAt: DateTime(2026, 10, 10, 12).subtract(Duration(hours: hoursAgo)),
  topics: topics,
  hashtags: tags,
);

void main() {
  final now = DateTime(2026, 10, 10, 12);

  test('aprende com curtidas e ordena com motivo', () async {
    final store = InMemoryPrefsStore();
    final p = InterestProfile(store);
    await p.loadFor('u1');
    await p.learn(_post('a', topics: ['esportes.futebol']), weight: 2);

    final ranked = p.rank([
      _post('musica', topics: ['musica'], author: 'dave'),
      _post('jogo', topics: ['esportes.futebol'], hoursAgo: 5),
    ], now: now);
    expect(ranked.first.post.id, 'jogo');
    expect(ranked.first.reasons.first, 'Você curte Futebol (Esportes)');
    expect(ranked.last.reasons, ['Recente, de quem você acompanha']);

    // Fica salvo por conta.
    final again = InterestProfile(store);
    await again.loadFor('u1');
    expect(again.topics['esportes.futebol'], 2);
    await again.loadFor('u2');
    expect(again.isEmpty, isTrue);
  });

  test('política: detalhe só com consentimento; retirar apaga', () async {
    final p = InterestProfile(InMemoryPrefsStore());
    await p.loadFor('u1');
    final pol = _post('p', topics: ['politica'], tags: ['reforma'], author: 'carol');
    await p.learn(pol);
    expect(p.topics['politica'], 1);
    expect(p.tags, isEmpty, reason: 'sem consentimento, só o tema');
    expect(p.people, isEmpty);

    await p.setPoliticsDetail(true);
    await p.learn(pol);
    expect(p.tags['reforma'], closeTo(0.6, 1e-9));
    await p.learn(_post('f', topics: ['humor'], tags: ['meme']));
    await p.setPoliticsDetail(false);
    expect(p.tags.containsKey('reforma'), isFalse);
    expect(p.tags.containsKey('meme'), isTrue);
  });

  test('pausa, tema oculto e zerar', () async {
    final p = InterestProfile(InMemoryPrefsStore());
    await p.loadFor('u1');
    await p.setPaused(true);
    await p.learn(_post('a', topics: ['games']));
    expect(p.isEmpty, isTrue);
    await p.setHidden('politica', true);
    final ranked = p.rank([
      _post('x', topics: ['politica.eleicoes']),
      _post('y', topics: ['games']),
    ], now: now);
    expect(ranked.map((r) => r.post.id), ['y']);
    await p.setPaused(false);
    await p.learn(_post('a', topics: ['games']));
    await p.reset();
    expect(p.isEmpty, isTrue);
  });
}
