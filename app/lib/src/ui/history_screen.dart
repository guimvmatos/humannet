import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'error_messages.dart';
import 'post_list.dart' show relativeTime;
import 'post_screen.dart';

/// Abre o link de "Baixar meus dados" (testes trocam por um registro).
@visibleForTesting
Future<bool> Function(Uri) openExportLink = (uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

const _tabs = <(String, String, IconData)>[
  ('posts', 'Posts', Icons.article_outlined),
  ('comments', 'Comentários', Icons.mode_comment_outlined),
  ('likes', 'Curtidas', Icons.favorite_border),
  ('scraps', 'Recados', Icons.sticky_note_2_outlined),
  ('testimonials', 'Depoimentos', Icons.format_quote),
];

/// "Minha atividade": tudo o que eu postei, comentei, curti e escrevi para
/// os outros, com opção de apagar (um ou vários) e de baixar meus dados.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.session});

  final SessionController session;

  Future<void> _export(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Baixar meus dados'),
        content: const Text(
          'Gera um arquivo (JSON) com seu perfil, posts, comentários, '
          'curtidas, amigos, recados, depoimentos, mensagens enviadas e linha '
          'do tempo. O link abre no navegador, vale 10 minutos e funciona uma '
          'vez só.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('export_confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Gerar e baixar'),
          ),
        ],
      ),
    );
    final token = session.token;
    if (ok != true || token == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final uri = await session.api.exportLink(token);
      final opened = await openExportLink(uri);
      if (!opened) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Não deu para abrir o navegador.')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        key: const Key('history_screen'),
        appBar: AppBar(
          title: const Text('Minha atividade'),
          actions: [
            IconButton(
              key: const Key('export_button'),
              tooltip: 'Baixar meus dados',
              icon: const Icon(Icons.download_outlined),
              onPressed: () => _export(context),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final (kind, label, icon) in _tabs)
                Tab(key: Key('history_tab_$kind'), icon: Icon(icon), text: label),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final (kind, _, _) in _tabs)
              _HistoryList(session: session, kind: kind),
          ],
        ),
      ),
    );
  }
}

class _HistoryList extends StatefulWidget {
  const _HistoryList({required this.session, required this.kind});

  final SessionController session;
  final String kind;

  @override
  State<_HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends State<_HistoryList>
    with AutomaticKeepAliveClientMixin {
  final _items = <HistoryItem>[];
  final _selected = <String>{};
  String? _cursor;
  bool _loading = false;
  bool _done = false;
  bool _deleting = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.session.api.history(
        token,
        widget.kind,
        before: _cursor,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _done = page.nextCursor == null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _isLikes => widget.kind == 'likes';

  Future<void> _deleteSelected() async {
    final token = widget.session.token;
    if (token == null || _selected.isEmpty) return;
    final n = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isLikes ? 'Descurtir $n?' : 'Apagar $n?'),
        content: Text(
          _isLikes
              ? 'As curtidas saem dos posts.'
              : 'Não dá para desfazer. Some para todo mundo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('history_delete_confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_isLikes ? 'Descurtir' : 'Apagar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      final ids = _selected.toList();
      await widget.session.api.deleteHistory(token, widget.kind, ids);
      if (!mounted) return;
      setState(() {
        _items.removeWhere((i) => ids.contains(i.id));
        _selected.clear();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _open(HistoryItem item) async {
    final token = widget.session.token;
    final postId = item.postId;
    if (token == null || postId == null) return;
    try {
      final post = await widget.session.api.post(token, postId);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PostScreen(session: widget.session, post: post),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    }
  }

  String _context(HistoryItem i) {
    final other = i.otherUsername;
    final when = relativeTime(i.createdAt);
    return switch (widget.kind) {
      'posts' when other != null => 'No mural de $other · $when',
      'comments' => 'No post de @$other · $when',
      'likes' => 'Post de @$other · $when',
      'scraps' => 'Recado para @$other · $when',
      'testimonials' => 'Depoimento para @$other · $when',
      _ => when,
    };
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty && _error != null) {
      return Center(child: Text(_error!));
    }
    if (_items.isEmpty) {
      return Center(
        key: Key('history_empty_${widget.kind}'),
        child: const Text('Nada por aqui.'),
      );
    }
    final all = _items.every((i) => _selected.contains(i.id));
    return Column(
      children: [
        Material(
          color: theme.colorScheme.surfaceContainerLow,
          child: Row(
            children: [
              Checkbox(
                key: Key('history_select_all_${widget.kind}'),
                value: all,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selected.addAll(_items.map((i) => i.id));
                  } else {
                    _selected.clear();
                  }
                }),
              ),
              Text(
                _selected.isEmpty
                    ? 'Selecionar tudo o que está carregado'
                    : '${_selected.length} selecionado(s)',
                style: theme.textTheme.bodySmall,
              ),
              const Spacer(),
              if (_selected.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilledButton.tonalIcon(
                    key: Key('history_delete_${widget.kind}'),
                    onPressed: _deleting ? null : _deleteSelected,
                    icon: Icon(
                      _isLikes ? Icons.heart_broken_outlined : Icons.delete,
                    ),
                    label: Text(_isLikes ? 'Descurtir' : 'Apagar'),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _items.length + 1,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (i == _items.length) {
                if (_done) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Isso é tudo.')),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: OutlinedButton(
                      key: Key('history_more_${widget.kind}'),
                      onPressed: _loading ? null : _load,
                      child: const Text('Carregar mais'),
                    ),
                  ),
                );
              }
              final item = _items[i];
              final selected = _selected.contains(item.id);
              return ListTile(
                key: Key('history_${widget.kind}_${item.id}'),
                leading: Checkbox(
                  key: Key('history_check_${item.id}'),
                  value: selected,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selected.add(item.id);
                    } else {
                      _selected.remove(item.id);
                    }
                  }),
                ),
                title: Text(
                  item.body.isEmpty ? '(só fotos)' : item.body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(_context(item)),
                trailing: item.postId == null
                    ? null
                    : const Icon(Icons.chevron_right),
                onTap: item.postId == null ? null : () => _open(item),
              );
            },
          ),
        ),
      ],
    );
  }
}
