import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import '../feed/interests.dart';
import '../geo/location.dart';
import 'activity_screen.dart';
import 'chat_ui.dart';
import 'compose_screen.dart';
import 'interests_screen.dart';
import 'post_list.dart';
import 'profile_screen.dart';

/// Feed: amigos ou região, cronológico ou "Para você" (ADR-0007).
class FeedScreen extends StatefulWidget {
  const FeedScreen({
    super.key,
    required this.session,
    this.counts,
    this.onCountsChanged,
  });

  final SessionController session;

  /// Contadores para a bolinha de novidades.
  final ValueListenable<Counts>? counts;
  final Future<void> Function()? onCountsChanged;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

/// Sem contadores (ex.: testes da tela isolada).
final _noCounts = ValueNotifier<Counts>(const Counts());

class _FeedScreenState extends State<FeedScreen> {
  final _listKey = GlobalKey<PagedPostListState>();

  /// "Por que estou vendo isto", por post (feed "Para você").
  final _why = <String, String>{};

  Future<void> _compose() async {
    final post = await Navigator.of(context).push<Post>(
      MaterialPageRoute(builder: (_) => ComposeScreen(session: widget.session)),
    );
    if (post != null) _listKey.currentState?.prepend(post);
  }

  Future<void> _pickRadius(InterestProfile interests) async {
    var km = interests.radiusKm;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Raio: ${km.toStringAsFixed(0)} km',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                Slider(
                  key: const Key('radius_slider'),
                  value: km,
                  min: 1,
                  max: 50,
                  divisions: 49,
                  label: '${km.toStringAsFixed(0)} km',
                  onChanged: (v) => setSheet(() => km = v),
                ),
                Text(
                  'Mostra posts feitos "para a região" dentro deste raio. Sua '
                  'posição vai arredondada (~500 m) só na consulta e não fica '
                  'guardada. A distância dos posts nunca aparece.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    key: const Key('radius_done'),
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Aplicar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok == true) await interests.setRadius(km);
  }

  Future<void> _openActivity() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ActivityScreen(
          session: widget.session,
          onSeen: () => widget.onCountsChanged?.call(),
        ),
      ),
    );
    await widget.onCountsChanged?.call();
  }

  Future<void> _openMessages() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationsScreen(session: widget.session),
      ),
    );
    await widget.onCountsChanged?.call();
  }

  Future<void> _findPerson() async {
    final controller = TextEditingController();
    final username = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Encontrar pessoa'),
        content: TextField(
          key: const Key('find_person_field'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            prefixText: '@',
            hintText: 'nome de usuário',
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Abrir'),
          ),
        ],
      ),
    );
    // O controller não é descartado aqui: o diálogo ainda pode estar
    // animando a saída e usando-o.
    final name = username?.trim().replaceFirst('@', '').toLowerCase() ?? '';
    if (name.isEmpty || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(session: widget.session, username: name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final token = widget.session.token ?? '';
    return Scaffold(
      key: const Key('feed_screen'),
      appBar: AppBar(
        title: const Text('HumanNet'),
        actions: [
          ValueListenableBuilder<Counts>(
            valueListenable: widget.counts ?? _noCounts,
            builder: (context, c, _) => IconButton(
              key: const Key('activity_button'),
              tooltip: 'Novidades',
              onPressed: _openActivity,
              icon: Badge(
                isLabelVisible: c.unreadActivity > 0,
                label: Text('${c.unreadActivity}'),
                child: const Icon(Icons.notifications_outlined),
              ),
            ),
          ),
          ValueListenableBuilder<Counts>(
            valueListenable: widget.counts ?? _noCounts,
            builder: (context, c, _) => IconButton(
              key: const Key('messages_button'),
              tooltip: 'Mensagens',
              onPressed: _openMessages,
              icon: Badge(
                isLabelVisible: c.unreadMessages > 0,
                label: Text('${c.unreadMessages}'),
                child: const Icon(Icons.chat_bubble_outline),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Encontrar pessoa',
            icon: const Icon(Icons.person_search),
            onPressed: _findPerson,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.session.interests,
        builder: (context, _) {
          final interests = widget.session.interests;
          final forYou = interests.feedMode == 'foryou';
          final region = interests.feedScope == 'region';
          final km = interests.radiusKm;
          final api = widget.session.api;
          Future<PostPage> ranked(Future<PostPage> source) async {
            final page = await source;
            final r = interests.rank(page.items);
            _why
              ..clear()
              ..addEntries(
                r.map((x) => MapEntry(x.post.id, x.reasons.join(' · '))),
              );
            return PostPage(items: [for (final x in r) x.post]);
          }

          final PageLoader loader = switch ((region, forYou)) {
            (false, false) => (before) => api.feed(token, before: before),
            (false, true) => (_) => ranked(api.feedCandidates(token)),
            (true, false) => (before) async => api.feedRegion(
              token,
              at: await approxLocation(),
              radiusKm: km,
              before: before,
            ),
            (true, true) => (_) async => ranked(
              api.feedRegionCandidates(
                token,
                at: await approxLocation(),
                radiusKm: km,
              ),
            ),
          };
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<String>(
                        key: const Key('feed_scope'),
                        segments: const [
                          ButtonSegment(
                            value: 'friends',
                            label: Text('Amigos'),
                            icon: Icon(Icons.people_outline),
                          ),
                          ButtonSegment(
                            value: 'region',
                            label: Text('Região'),
                            icon: Icon(Icons.near_me_outlined),
                          ),
                        ],
                        selected: {interests.feedScope},
                        onSelectionChanged: (s) =>
                            interests.setFeedScope(s.first),
                      ),
                    ),
                    if (region)
                      TextButton(
                        key: const Key('radius_button'),
                        onPressed: () => _pickRadius(interests),
                        child: Text('${km.toStringAsFixed(0)} km'),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<String>(
                        key: const Key('feed_mode'),
                        segments: const [
                          ButtonSegment(
                            value: 'chrono',
                            label: Text('Cronológico'),
                            icon: Icon(Icons.schedule),
                          ),
                          ButtonSegment(
                            value: 'foryou',
                            label: Text('Para você'),
                            icon: Icon(Icons.auto_awesome_outlined),
                          ),
                        ],
                        selected: {interests.feedMode},
                        onSelectionChanged: (s) =>
                            interests.setFeedMode(s.first),
                      ),
                    ),
                    if (forYou)
                      IconButton(
                        key: const Key('open_interests'),
                        tooltip: 'Meus interesses',
                        icon: const Icon(Icons.tune),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                InterestsScreen(profile: interests),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: PagedPostList(
                  key: region || forYou
                      ? ValueKey('feed_${interests.feedScope}_'
                            '${interests.feedMode}_$km')
                      : _listKey,
                  session: widget.session,
                  loader: loader,
                  reasonOf: forYou ? (p) => _why[p.id] : null,
                  emptyText: switch ((region, forYou)) {
                    (false, false) =>
                      'Seu feed está vazio. Adicione amigos (lupa, acima) '
                          'ou escreva o primeiro post.',
                    (false, true) when interests.isEmpty =>
                      'Nada nos últimos 7 dias. Curta e comente posts: o '
                          '"Para você" aprende só com isso, e só no seu '
                          'celular.',
                    (false, true) => 'Nada nos últimos 7 dias.',
                    (true, _) =>
                      'Nenhum post para a região num raio de '
                          '${km.toStringAsFixed(0)} km. Aumente o raio ou '
                          'poste algo para a região.',
                  },
                  endText: forYou
                      ? 'Você viu tudo dos últimos 7 dias.'
                      : 'Você está em dia.',
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'compose_fab',
        key: const Key('compose_button'),
        onPressed: _compose,
        icon: const Icon(Icons.edit),
        label: const Text('Escrever'),
      ),
    );
  }
}
