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
          final view = interests.feedView;
          final forYou = view == 'foryou';
          final region = view == 'region';
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

          final PageLoader loader = switch (view) {
            'foryou' => (_) => ranked(api.feedCandidates(token)),
            'region' => (before) async => api.feedRegion(
              token,
              at: await approxLocation(),
              radiusKm: km,
              before: before,
            ),
            _ => (before) => api.feed(token, before: before),
          };
          Widget chip(String value, String label, IconData icon) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              key: Key('feed_view_$value'),
              avatar: Icon(icon, size: 16),
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              labelStyle: Theme.of(context).textTheme.labelMedium,
              label: Text(label),
              selected: view == value,
              onSelected: (_) => interests.setFeedView(value),
            ),
          );
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
                child: Row(
                  children: [
                    chip('chrono', 'Cronológico', Icons.schedule),
                    chip('foryou', 'Para você', Icons.auto_awesome_outlined),
                    chip('region', 'Regional', Icons.near_me_outlined),
                    const Spacer(),
                    if (forYou)
                      IconButton(
                        key: const Key('open_interests'),
                        tooltip: 'Meus interesses',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.tune, size: 20),
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
              if (region) _RadiusBar(interests: interests),
              Expanded(
                child: PagedPostList(
                  key: view == 'chrono'
                      ? _listKey
                      : ValueKey('feed_${view}_$km'),
                  session: widget.session,
                  loader: loader,
                  reasonOf: forYou ? (p) => _why[p.id] : null,
                  emptyText: switch (view) {
                    'foryou' when interests.isEmpty =>
                      'Nada nos últimos 7 dias. Curta e comente posts: o '
                          '"Para você" aprende só com isso, e só no seu '
                          'celular.',
                    'foryou' => 'Nada nos últimos 7 dias.',
                    'region' =>
                      'Nenhum post para a região num raio de '
                          '${km.toStringAsFixed(0)} km. Aumente o raio ou '
                          'poste algo para a região.',
                    _ =>
                      'Seu feed está vazio. Adicione amigos (lupa, acima) '
                          'ou escreva o primeiro post.',
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

/// Barrinha do raio do feed regional (1 a 50 km). Recarrega só ao soltar.
class _RadiusBar extends StatefulWidget {
  const _RadiusBar({required this.interests});

  final InterestProfile interests;

  @override
  State<_RadiusBar> createState() => _RadiusBarState();
}

class _RadiusBarState extends State<_RadiusBar> {
  late double _km = widget.interests.radiusKm;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Row(
        children: [
          Text('Raio', style: style),
          Expanded(
            child: Slider(
              key: const Key('radius_slider'),
              value: _km,
              min: 1,
              max: 50,
              divisions: 49,
              label: '${_km.toStringAsFixed(0)} km',
              onChanged: (v) => setState(() => _km = v),
              onChangeEnd: widget.interests.setRadius,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '${_km.toStringAsFixed(0)} km',
              key: const Key('radius_value'),
              style: style,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
