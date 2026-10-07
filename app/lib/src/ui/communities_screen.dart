import 'dart:async';

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'community_form_screen.dart';
import 'community_screen.dart';
import 'error_messages.dart';

/// Aba "Comunidades": as minhas e a busca por nome.
class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<CommunitiesScreen> createState() => CommunitiesScreenState();
}

class CommunitiesScreenState extends State<CommunitiesScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<CommunityItem>? _mine;
  List<CommunityItem>? _results;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Recarrega "minhas" (e a busca, se houver).
  Future<void> refresh() async {
    final token = widget.session.token;
    if (token == null) return;
    try {
      final mine = await widget.session.api.communities(token, mine: true);
      if (mounted) {
        setState(() {
          _mine = mine;
          _error = null;
        });
      }
      if (_search.text.trim().isNotEmpty) await _runSearch();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _runSearch);
    setState(() {});
  }

  Future<void> _runSearch() async {
    final token = widget.session.token;
    final q = _search.text.trim();
    if (token == null) return;
    if (q.isEmpty) {
      setState(() => _results = null);
      return;
    }
    try {
      final r = await widget.session.api.communities(token, query: q);
      if (mounted && _search.text.trim() == q) setState(() => _results = r);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  /// Todas as comunidades (busca vazia lista em ordem alfabética).
  Future<void> _explore() async {
    final token = widget.session.token;
    if (token == null) return;
    try {
      final r = await widget.session.api.communities(token);
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _open(String slug) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityScreen(session: widget.session, slug: slug),
      ),
    );
    await refresh();
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<Community>(
      MaterialPageRoute(
        builder: (_) => CommunityFormScreen(session: widget.session),
      ),
    );
    if (created != null) {
      await refresh();
      if (mounted) await _open(created.slug);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = _mine;
    final results = _results;
    return Scaffold(
      key: const Key('communities_screen'),
      appBar: AppBar(title: const Text('Comunidades')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'create_community_fab',
        key: const Key('create_community_button'),
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Criar'),
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                key: const Key('community_search_field'),
                controller: _search,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _runSearch(),
                decoration: InputDecoration(
                  hintText: 'Buscar comunidades',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpar',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _search.clear();
                            setState(() => _results = null);
                          },
                        ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            if (results != null) ...[
              _Header(
                _search.text.trim().isEmpty ? 'Todas' : 'Resultados',
              ),
              if (results.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Nenhuma comunidade encontrada. Que tal criar uma?',
                    key: Key('no_search_results'),
                  ),
                )
              else
                for (final c in results)
                  _CommunityTile(c: c, onTap: () => _open(c.slug)),
            ],
            const _Header('Minhas comunidades'),
            if (mine == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (mine.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Você ainda não participa de nenhuma comunidade.',
                      key: Key('no_communities'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      key: const Key('explore_button'),
                      onPressed: _explore,
                      child: const Text('Ver todas as comunidades'),
                    ),
                  ],
                ),
              )
            else ...[
              for (final c in mine)
                _CommunityTile(c: c, onTap: () => _open(c.slug)),
              if (results == null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const Key('explore_button'),
                      onPressed: _explore,
                      child: const Text('Ver todas as comunidades'),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _CommunityTile extends StatelessWidget {
  const _CommunityTile({required this.c, required this.onTap});

  final CommunityItem c;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = switch (c.myStatus) {
      'pending' => ' · aguardando aprovação',
      'banned' => ' · removido',
      _ => switch (c.myRole) {
        'owner' => ' · dono',
        'moderator' => ' · moderador',
        _ => '',
      },
    };
    return ListTile(
      key: Key('community_${c.slug}'),
      leading: CircleAvatar(
        child: Text(c.name.characters.first.toUpperCase()),
      ),
      title: Text(c.name),
      subtitle: Text(
        '${c.themeLabel}${c.isClosed ? ' · fechada' : ''}$status',
      ),
      trailing: c.isClosed ? const Icon(Icons.lock_outline, size: 18) : null,
      onTap: onTap,
    );
  }
}
