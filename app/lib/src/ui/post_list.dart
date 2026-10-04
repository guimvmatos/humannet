import 'dart:async';

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'error_messages.dart';
import 'profile_screen.dart';

typedef PageLoader = Future<PostPage> Function(String? before);

/// Lista paginada de posts com fim explícito: sem rolagem infinita (R6).
/// O usuário escolhe carregar mais; ao fim, aparece "Você está em dia".
class PagedPostList extends StatefulWidget {
  const PagedPostList({
    super.key,
    required this.session,
    required this.loader,
    this.header,
    this.onRefresh,
    this.emptyText = 'Nada por aqui ainda.',
  });

  final SessionController session;
  final PageLoader loader;
  final Widget? header;

  /// Chamado junto com o "puxar para atualizar" (ex.: recarregar o cabeçalho).
  final Future<void> Function()? onRefresh;
  final String emptyText;

  @override
  State<PagedPostList> createState() => PagedPostListState();
}

class PagedPostListState extends State<PagedPostList> {
  final List<Post> _posts = [];
  String? _cursor;
  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loading = true;
    unawaited(_fetch(reset: true));
  }

  /// Recarrega do início.
  Future<void> refresh() async {
    _cursor = null;
    await Future.wait([
      _load(reset: true),
      ?widget.onRefresh?.call(),
    ]);
  }

  /// Insere um post recém-criado no topo, sem recarregar.
  void prepend(Post post) => setState(() => _posts.insert(0, post));

  Future<void> _load({required bool reset}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    await _fetch(reset: reset);
  }

  Future<void> _fetch({required bool reset}) async {
    try {
      final page = await widget.loader(reset ? null : _cursor);
      if (!mounted) return;
      setState(() {
        if (reset) _posts.clear();
        _posts.addAll(page.items);
        _cursor = page.nextCursor;
        _loadedOnce = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _removed(Post post) =>
      setState(() => _posts.removeWhere((p) => p.id == post.id));

  @override
  Widget build(BuildContext context) {
    final header = widget.header;
    final children = <Widget>[
      ?header,
      for (final post in _posts)
        PostTile(
          key: ValueKey(post.id),
          post: post,
          session: widget.session,
          onDeleted: _removed,
        ),
      _footer(context),
    ];

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: children,
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final theme = Theme.of(context);
    Widget content;
    if (_error != null) {
      content = Column(
        children: [
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          TextButton(
            onPressed: () => _load(reset: !_loadedOnce),
            child: const Text('Tentar de novo'),
          ),
        ],
      );
    } else if (_loading) {
      content = const CircularProgressIndicator();
    } else if (_cursor != null) {
      content = OutlinedButton(
        key: const Key('load_more'),
        onPressed: () => _load(reset: false),
        child: const Text('Carregar mais'),
      );
    } else if (_posts.isEmpty) {
      content = Text(widget.emptyText, key: const Key('list_empty'));
    } else {
      content = Text(
        'Você está em dia.',
        key: const Key('list_end'),
        style: theme.textTheme.bodySmall,
      );
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(child: content),
    );
  }
}

class PostTile extends StatelessWidget {
  const PostTile({
    super.key,
    required this.post,
    required this.session,
    required this.onDeleted,
  });

  final Post post;
  final SessionController session;
  final void Function(Post) onDeleted;

  bool get _isMine => session.user?.id == post.author.id;

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar post?'),
        content: const Text('O texto será removido de forma permanente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final token = session.token;
    if (token == null) return;
    try {
      await session.api.deletePost(token, post.id);
      onDeleted(post);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    }
  }

  void _openAuthor(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ProfileScreen(session: session, username: post.author.username),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _openAuthor(context),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: post.author.label,
                            style: theme.textTheme.titleSmall,
                          ),
                          TextSpan(
                            text:
                                '  @${post.author.username} · '
                                '${relativeTime(post.createdAt)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (_isMine)
                  PopupMenuButton<String>(
                    key: Key('post_menu_${post.id}'),
                    onSelected: (_) => _delete(context),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'delete', child: Text('Apagar')),
                    ],
                  )
                else
                  const SizedBox(height: 40),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SelectableText(post.body),
            ),
          ],
        ),
      ),
    );
  }
}

/// "agora", "5 min", "3 h", "2 d" ou a data. Sem dependência de `intl`.
String relativeTime(DateTime t, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(t);
  if (diff.inMinutes < 1) return 'agora';
  if (diff.inHours < 1) return '${diff.inMinutes} min';
  if (diff.inDays < 1) return '${diff.inHours} h';
  if (diff.inDays < 7) return '${diff.inDays} d';
  final local = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year}';
}
