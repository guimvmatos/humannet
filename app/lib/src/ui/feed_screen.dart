import 'package:flutter/material.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'activity_screen.dart';
import 'compose_screen.dart';
import 'post_list.dart';
import 'profile_screen.dart';

/// Feed cronológico: seus amigos + você. Sem algoritmo (R2).
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
          IconButton(
            tooltip: 'Encontrar pessoa',
            icon: const Icon(Icons.person_search),
            onPressed: _findPerson,
          ),
        ],
      ),
      body: PagedPostList(
        key: _listKey,
        session: widget.session,
        loader: (before) => widget.session.api.feed(token, before: before),
        emptyText:
            'Seu feed está vazio. Adicione amigos (lupa, acima) '
            'ou escreva o primeiro post.',
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
