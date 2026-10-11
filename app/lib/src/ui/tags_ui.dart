import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'error_messages.dart';
import 'photos.dart';
import 'post_list.dart';
import 'post_screen.dart';
import 'profile_screen.dart';

final _mention = RegExp(r'(?<![A-Za-z0-9_])@([A-Za-z0-9_]{3,30})');

void _openProfile(BuildContext context, SessionController session, String u) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          ProfileScreen(session: session, username: u.toLowerCase()),
    ),
  );
}

/// Texto com @menções destacadas e tocáveis (abrem o perfil).
class MentionText extends StatefulWidget {
  const MentionText(
    this.text, {
    super.key,
    required this.session,
    this.style,
    this.selectable = true,
  });

  final String text;
  final SessionController session;
  final TextStyle? style;
  final bool selectable;

  @override
  State<MentionText> createState() => _MentionTextState();
}

class _MentionTextState extends State<MentionText> {
  final _recognizers = <TapGestureRecognizer>[];

  void _clear() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final text = widget.text;
    final linkStyle = TextStyle(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w600,
    );
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _mention.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final name = m.group(1)!;
      final r = TapGestureRecognizer()
        ..onTap = () => _openProfile(context, widget.session, name);
      _recognizers.add(r);
      spans.add(TextSpan(text: m.group(0), style: linkStyle, recognizer: r));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    final span = TextSpan(style: widget.style, children: spans);
    return widget.selectable ? SelectableText.rich(span) : Text.rich(span);
  }
}

/// "com @bob, @carol" abaixo do post. Pendentes aparecem como "aguardando"
/// (só para o autor e a própria pessoa). Tocar no próprio nome (ou, para o
/// autor, em qualquer um) permite aprovar ou tirar a marcação.
class TaggedLine extends StatefulWidget {
  const TaggedLine({super.key, required this.post, required this.session});

  final Post post;
  final SessionController session;

  @override
  State<TaggedLine> createState() => _TaggedLineState();
}

class _TaggedLineState extends State<TaggedLine> {
  late List<TaggedUser> _tags = widget.post.tagged;

  @override
  void didUpdateWidget(TaggedLine old) {
    super.didUpdateWidget(old);
    if (old.post != widget.post) _tags = widget.post.tagged;
  }

  Future<void> _tapped(TaggedUser t) async {
    final session = widget.session;
    final post = widget.post;
    final me = session.user?.username;
    final mine = t.username == me;
    final isAuthor = post.author.username == me;
    if (!mine && !isAuthor) {
      _openProfile(context, session, t.username);
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text('Ver perfil de @${t.username}'),
              onTap: () => Navigator.of(ctx).pop('profile'),
            ),
            if (mine && t.pending)
              ListTile(
                key: const Key('tag_approve_here'),
                leading: const Icon(Icons.check),
                title: const Text('Aprovar marcação'),
                onTap: () => Navigator.of(ctx).pop('approve'),
              ),
            ListTile(
              key: const Key('tag_remove_here'),
              leading: const Icon(Icons.close),
              title: Text(mine ? 'Tirar minha marcação' : 'Tirar marcação'),
              onTap: () => Navigator.of(ctx).pop('remove'),
            ),
          ],
        ),
      ),
    );
    final token = session.token;
    if (choice == null || token == null || !mounted) return;
    if (choice == 'profile') {
      _openProfile(context, session, t.username);
      return;
    }
    try {
      if (choice == 'approve') {
        await session.api.approveTag(token, post.id);
        if (!mounted) return;
        setState(() {
          _tags = [
            for (final x in _tags)
              x.username == t.username
                  ? TaggedUser(username: x.username, displayName: x.displayName)
                  : x,
          ];
        });
      } else {
        await session.api.removeTag(token, post.id, t.username);
        if (!mounted) return;
        setState(() {
          _tags = [for (final x in _tags) if (x.username != t.username) x];
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_tags.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final post = widget.post;
    return Padding(
      padding: const EdgeInsets.only(top: 4, right: 12),
      child: Wrap(
        key: Key('tagged_${post.id}'),
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          Text('com', style: theme.textTheme.bodySmall),
          for (final t in _tags)
            InkWell(
              key: Key('tag_${post.id}_${t.username}'),
              onTap: () => _tapped(t),
              child: Text(
                t.pending ? '@${t.username} (aguardando)' : '@${t.username}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: t.pending
                      ? theme.colorScheme.outline
                      : theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Sugestões de @menção enquanto se digita (aparecem quando a palavra antes
/// do cursor começa com @). Tocar completa o nome.
class MentionSuggestions extends StatefulWidget {
  const MentionSuggestions({
    super.key,
    required this.session,
    required this.controller,
  });

  final SessionController session;
  final TextEditingController controller;

  @override
  State<MentionSuggestions> createState() => _MentionSuggestionsState();
}

class _MentionSuggestionsState extends State<MentionSuggestions> {
  List<Author> _items = const [];
  String? _query;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _debounce?.cancel();
    super.dispose();
  }

  /// "@gu" logo antes do cursor → "gu".
  String? _currentQuery() {
    final v = widget.controller.value;
    final cursor = v.selection.baseOffset;
    if (cursor < 0 || cursor > v.text.length) return null;
    final before = v.text.substring(0, cursor);
    final m = RegExp(r'(?:^|[^A-Za-z0-9_])@([A-Za-z0-9_]{0,30})$').firstMatch(before);
    return m?.group(1);
  }

  void _changed() {
    final q = _currentQuery();
    if (q == _query) return;
    _query = q;
    _debounce?.cancel();
    if (q == null) {
      if (_items.isNotEmpty) setState(() => _items = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () => _fetch(q));
  }

  Future<void> _fetch(String q) async {
    final token = widget.session.token;
    if (token == null) return;
    try {
      final items = await widget.session.api.suggestMentions(token, q);
      if (mounted && _query == q) setState(() => _items = items);
    } catch (_) {
      // Sugestão é extra: falha de rede não atrapalha a escrita.
    }
  }

  void _pick(Author a) {
    final v = widget.controller.value;
    final cursor = v.selection.baseOffset;
    final before = v.text.substring(0, cursor);
    final at = before.lastIndexOf('@');
    if (at < 0) return;
    final insert = '@${a.username} ';
    final text = v.text.replaceRange(at, cursor, insert);
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: at + insert.length),
    );
    setState(() => _items = const []);
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView(
        key: const Key('mention_suggestions'),
        scrollDirection: Axis.horizontal,
        children: [
          for (final a in _items)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                key: Key('mention_${a.username}'),
                avatar: UserAvatar(a, radius: 10),
                label: Text('@${a.username}'),
                onPressed: () => _pick(a),
              ),
            ),
        ],
      ),
    );
  }
}

/// Escolher amigos para "com fulano". Devolve a nova lista de nomes.
Future<List<String>?> pickTaggedFriends(
  BuildContext context,
  SessionController session,
  List<String> current,
) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _TagPicker(session: session, initial: current),
  );
}

class _TagPicker extends StatefulWidget {
  const _TagPicker({required this.session, required this.initial});

  final SessionController session;
  final List<String> initial;

  @override
  State<_TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends State<_TagPicker> {
  late final List<String> _chosen = [...widget.initial];
  List<Author> _results = const [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final token = widget.session.token;
    if (token == null) return;
    try {
      final r = await widget.session.api.suggestMentions(
        token,
        q,
        friendsOnly: true,
      );
      if (mounted) setState(() => _results = r);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Marcar amigos',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text(
              'Só aparece depois que a pessoa aprovar. Até 10.',
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('tag_search'),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar amigo',
              ),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(
                  const Duration(milliseconds: 250),
                  () => _search(v),
                );
              },
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final a in _results)
                    CheckboxListTile(
                      key: Key('tag_pick_${a.username}'),
                      value: _chosen.contains(a.username),
                      secondary: UserAvatar(a),
                      title: Text(a.label),
                      subtitle: Text('@${a.username}'),
                      onChanged: (v) => setState(() {
                        if (v == true && _chosen.length < 10) {
                          _chosen.add(a.username);
                        } else {
                          _chosen.remove(a.username);
                        }
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('tag_pick_done'),
              onPressed: () => Navigator.of(context).pop(_chosen),
              child: Text(
                _chosen.isEmpty ? 'Pronto' : 'Marcar ${_chosen.length}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Marcações esperando minha aprovação.
class PendingTagsScreen extends StatefulWidget {
  const PendingTagsScreen({super.key, required this.session, this.onChanged});

  final SessionController session;
  final VoidCallback? onChanged;

  @override
  State<PendingTagsScreen> createState() => _PendingTagsScreenState();
}

class _PendingTagsScreenState extends State<PendingTagsScreen> {
  List<PendingTag>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null) return;
    try {
      final items = await widget.session.api.pendingTags(token);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _decide(PendingTag t, bool approve) async {
    final token = widget.session.token;
    final me = widget.session.user?.username;
    if (token == null || me == null) return;
    try {
      if (approve) {
        await widget.session.api.approveTag(token, t.postId);
      } else {
        await widget.session.api.removeTag(token, t.postId, me);
      }
      if (!mounted) return;
      setState(() => _items?.remove(t));
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    }
  }

  Future<void> _open(PendingTag t) async {
    final token = widget.session.token;
    if (token == null) return;
    try {
      final post = await widget.session.api.post(token, t.postId);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PostScreen(session: widget.session, post: post),
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      key: const Key('pending_tags_screen'),
      appBar: AppBar(title: const Text('Marcações para aprovar')),
      body: items == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(_error!),
            )
          : items.isEmpty
          ? const Center(child: Text('Nenhuma marcação esperando você.'))
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Aprovando, você aparece como "com você" no post e ele '
                    'entra na aba Marcado do seu perfil. Dá para tirar depois.',
                  ),
                ),
                for (final t in items)
                  Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          leading: UserAvatar(t.author),
                          title: Text('${t.author.label} marcou você'),
                          subtitle: Text(
                            t.excerpt.isEmpty ? '(só fotos)' : t.excerpt,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _open(t),
                        ),
                        OverflowBar(
                          alignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              key: Key('tag_reject_${t.postId}'),
                              onPressed: () => _decide(t, false),
                              child: const Text('Recusar'),
                            ),
                            FilledButton(
                              key: Key('tag_approve_${t.postId}'),
                              onPressed: () => _decide(t, true),
                              child: const Text('Aprovar'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Aba "Marcado" de um perfil: posts em que a pessoa aprovou a marcação.
class TaggedPostsScreen extends StatelessWidget {
  const TaggedPostsScreen({
    super.key,
    required this.session,
    required this.username,
  });

  final SessionController session;
  final String username;

  @override
  Widget build(BuildContext context) {
    final token = session.token ?? '';
    return Scaffold(
      key: const Key('tagged_posts_screen'),
      appBar: AppBar(title: Text('@$username marcado')),
      body: PagedPostList(
        session: session,
        loader: (before) =>
            session.api.taggedPosts(token, username, before: before),
        emptyText: 'Nenhum post com marcação aprovada.',
      ),
    );
  }
}

/// Quem pode me @mencionar.
Future<void> showMentionPolicyDialog(
  BuildContext context,
  SessionController session,
) async {
  final token = session.token;
  if (token == null) return;
  String current;
  try {
    current = await session.api.mentionPolicy(token);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
    return;
  }
  if (!context.mounted) return;
  final picked = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Quem pode me mencionar'),
      children: [
        for (final (v, label) in const [
          ('everyone', 'Todos'),
          ('friends', 'Só amigos'),
          ('nobody', 'Ninguém'),
        ])
          ListTile(
            key: Key('mention_policy_$v'),
            leading: Icon(
              v == current
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(label),
            onTap: () => Navigator.of(ctx).pop(v),
          ),
      ],
    ),
  );
  if (picked == null || picked == current) return;
  try {
    await session.api.setMentionPolicy(token, picked);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }
}
