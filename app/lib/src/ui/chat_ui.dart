import 'dart:async';

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'error_messages.dart';
import 'photos.dart';
import 'post_list.dart' show relativeTime;
import 'places_ui.dart';
import 'report_dialog.dart';

/// Abre (ou cria) a conversa 1:1 com um amigo.
Future<void> openDirectChat(
  BuildContext context,
  SessionController session,
  String username,
) async {
  final token = session.token;
  if (token == null) return;
  try {
    final c = await session.api.directConversation(token, username);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(session: session, conversation: c),
      ),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }
}

/// Lista de conversas.
class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  List<Conversation>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null) return;
    try {
      final items = await widget.session.api.conversations(token);
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _open(Conversation c) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(session: widget.session, conversation: c),
      ),
    );
    await _load();
  }

  Future<void> _new() async {
    final token = widget.session.token;
    if (token == null) return;
    final List<Author> friends;
    try {
      friends = await widget.session.api.friends(token);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
      return;
    }
    if (!mounted) return;
    final created = await Navigator.of(context).push<Conversation>(
      MaterialPageRoute(
        builder: (_) => NewConversationScreen(
          session: widget.session,
          friends: friends,
        ),
      ),
    );
    if (created != null) {
      await _open(created);
    } else {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('conversations_screen'),
      appBar: AppBar(title: const Text('Mensagens')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new_chat_fab',
        key: const Key('new_chat_button'),
        onPressed: _new,
        icon: const Icon(Icons.edit),
        label: const Text('Nova conversa'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            if (_error != null)
              Padding(padding: const EdgeInsets.all(16), child: Text(_error!))
            else if (items == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nenhuma conversa ainda. Toque em "Nova conversa" para '
                  'falar com um amigo ou criar um grupo.',
                  key: Key('no_conversations'),
                  textAlign: TextAlign.center,
                ),
              )
            else
              for (final c in items)
                ListTile(
                  key: Key('conversation_${c.id}'),
                  leading: c.other != null
                      ? UserAvatar(c.other!)
                      : CircleAvatar(
                          child: Icon(c.isPage ? Icons.storefront : Icons.group),
                        ),
                  title: Text(
                    c.title,
                    style: c.unread > 0
                        ? const TextStyle(fontWeight: FontWeight.bold)
                        : null,
                  ),
                  subtitle: Text(
                    c.lastMessage ?? 'Sem mensagens',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        relativeTime(c.lastMessageAt),
                        style: theme.textTheme.bodySmall,
                      ),
                      if (c.unread > 0)
                        Badge(label: Text('${c.unread}')),
                    ],
                  ),
                  onTap: () => _open(c),
                ),
          ],
        ),
      ),
    );
  }
}

/// Escolher amigo (1:1) ou vários + nome (grupo).
class NewConversationScreen extends StatefulWidget {
  const NewConversationScreen({
    super.key,
    required this.session,
    required this.friends,
    this.addToConversation,
  });

  final SessionController session;
  final List<Author> friends;

  /// Se definido: adicionar pessoas a este grupo.
  final String? addToConversation;

  @override
  State<NewConversationScreen> createState() => _NewConversationScreenState();
}

class _NewConversationScreenState extends State<NewConversationScreen> {
  final _title = TextEditingController();
  final Set<String> _selected = {};
  bool _busy = false;
  String? _error;

  bool get _adding => widget.addToConversation != null;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    final token = widget.session.token;
    if (token == null || _selected.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = widget.session.api;
      Conversation? c;
      if (_adding) {
        await api.addToGroup(token, widget.addToConversation!, _selected.toList());
      } else if (_selected.length == 1) {
        c = await api.directConversation(token, _selected.single);
      } else {
        final title = _title.text.trim();
        if (title.isEmpty) {
          setState(() => _error = 'Dê um nome ao grupo.');
          return;
        }
        c = await api.createGroup(token, title, _selected.toList());
      }
      if (mounted) Navigator.of(context).pop(c);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = !_adding && _selected.length > 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(_adding ? 'Adicionar pessoas' : 'Nova conversa'),
        actions: [
          TextButton(
            key: const Key('start_chat_button'),
            onPressed: _busy || _selected.isEmpty ? null : _done,
            child: Text(
              _adding ? 'Adicionar' : (group ? 'Criar grupo' : 'Conversar'),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          if (group)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                key: const Key('group_title_field'),
                controller: _title,
                maxLength: 60,
                decoration: const InputDecoration(labelText: 'Nome do grupo'),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (widget.friends.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Você ainda não tem amigos aqui. Mensagens são só entre amigos.',
              ),
            ),
          for (final f in widget.friends)
            CheckboxListTile(
              key: Key('pick_${f.username}'),
              value: _selected.contains(f.username),
              onChanged: (v) => setState(() {
                if (v ?? false) {
                  _selected.add(f.username);
                } else {
                  _selected.remove(f.username);
                }
              }),
              secondary: UserAvatar(f),
              title: Text(f.label),
              subtitle: Text('@${f.username}'),
            ),
        ],
      ),
    );
  }
}

/// Conversa. Busca mensagens novas a cada 4 s com a tela aberta (sem push).
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.session,
    required this.conversation,
  });

  final SessionController session;
  final Conversation conversation;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _msgs = [];
  String? _olderCursor;
  bool _loaded = false;
  bool _sending = false;
  Timer? _poll;

  Conversation get _c => widget.conversation;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    unawaited(_initial());
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _newer());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String? get _token => widget.session.token;

  Future<void> _initial() async {
    final token = _token;
    if (token == null) return;
    try {
      final page = await widget.session.api.chatMessages(token, _c.id);
      if (!mounted) return;
      setState(() {
        _msgs
          ..clear()
          ..addAll(page.items);
        _olderCursor = page.nextCursor;
        _loaded = true;
      });
      unawaited(widget.session.api.markRead(token, _c.id).catchError((_) {}));
    } catch (e) {
      _snack(errorMessage(e));
    }
  }

  Future<void> _newer() async {
    final token = _token;
    if (token == null || !_loaded || _msgs.isEmpty) {
      if (_loaded && _msgs.isEmpty) await _initial();
      return;
    }
    try {
      final page = await widget.session.api.chatMessages(
        token,
        _c.id,
        after: _msgs.last.id,
      );
      if (!mounted || page.items.isEmpty) return;
      setState(() => _msgs.addAll(page.items));
      unawaited(widget.session.api.markRead(token, _c.id).catchError((_) {}));
    } catch (_) {
      // Rede instável: tenta de novo no próximo ciclo.
    }
  }

  Future<void> _older() async {
    final token = _token;
    final cursor = _olderCursor;
    if (token == null || cursor == null) return;
    try {
      final page = await widget.session.api.chatMessages(
        token,
        _c.id,
        before: cursor,
      );
      if (!mounted) return;
      setState(() {
        _msgs.insertAll(0, page.items);
        _olderCursor = page.nextCursor;
      });
    } catch (e) {
      _snack(errorMessage(e));
    }
  }

  Future<void> _send() async {
    final token = _token;
    final body = _text.text.trim();
    if (token == null || body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _newer();
      final m = await widget.session.api.sendMessage(token, _c.id, body);
      _text.clear();
      if (mounted && !_msgs.any((x) => x.id == m.id)) {
        setState(() => _msgs.add(m));
      }
    } catch (e) {
      _snack(errorMessage(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _longPress(ChatMessage m) async {
    if (m.deleted) return;
    final token = _token;
    if (token == null) return;
    if (m.mine) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Apagar mensagem?'),
          content: const Text('Ela some para todos da conversa.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Apagar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await widget.session.api.deleteMessage(token, m.id);
        await _initial();
      } catch (e) {
        _snack(errorMessage(e));
      }
    } else {
      await showReportDialog(
        context,
        session: widget.session,
        messageId: m.id,
      );
    }
  }

  Future<void> _menu(String action) async {
    final token = _token;
    if (token == null) return;
    final api = widget.session.api;
    try {
      switch (action) {
        case 'members':
          final members = await api.conversationMembers(token, _c.id);
          if (!mounted) return;
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Pessoas no grupo'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final m in members)
                      ListTile(
                        leading: UserAvatar(m),
                        title: Text(m.label),
                        subtitle: Text('@${m.username}'),
                      ),
                  ],
                ),
              ),
            ),
          );
        case 'add':
          final friends = await api.friends(token);
          if (!mounted) return;
          await Navigator.of(context).push<Conversation>(
            MaterialPageRoute(
              builder: (_) => NewConversationScreen(
                session: widget.session,
                friends: friends,
                addToConversation: _c.id,
              ),
            ),
          );
        case 'leave':
          await api.leaveGroup(token, _c.id);
          if (mounted) Navigator.of(context).pop();
        case 'page':
          final slug = _c.pageSlug;
          if (slug != null) await openPlace(context, widget.session, slug);
      }
    } catch (e) {
      _snack(errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('chat_screen'),
      appBar: AppBar(
        title: Text(_c.title),
        actions: [
          if (_c.isPage)
            PopupMenuButton<String>(
              key: const Key('page_chat_menu'),
              onSelected: _menu,
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'page', child: Text('Ver página')),
                if (!_c.asPage)
                  const PopupMenuItem(
                    value: 'leave',
                    child: Text('Tirar da lista'),
                  ),
              ],
            ),
          if (_c.isGroup)
            PopupMenuButton<String>(
              onSelected: _menu,
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'members', child: Text('Pessoas')),
                if (_c.isOwner)
                  const PopupMenuItem(
                    value: 'add',
                    child: Text('Adicionar pessoas'),
                  ),
                const PopupMenuItem(value: 'leave', child: Text('Sair do grupo')),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: !_loaded
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.all(8),
                    itemCount: _msgs.length + (_olderCursor != null ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == _msgs.length) {
                        return Center(
                          child: TextButton(
                            onPressed: _older,
                            child: const Text('Mensagens anteriores'),
                          ),
                        );
                      }
                      final m = _msgs[_msgs.length - 1 - i];
                      return _Bubble(
                        key: Key('msg_${m.id}'),
                        message: m,
                        showAuthor: (_c.isGroup || _c.isPage) && !m.mine,
                        authorLabel: m.asPage && m.author != null
                            ? '${_c.pageName} · @${m.author!.username}'
                            : null,
                        theme: theme,
                        onLongPress: () => _longPress(m),
                      );
                    },
                  ),
          ),
          if (_loaded && _msgs.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Diga oi!', key: Key('empty_chat')),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('message_field'),
                      controller: _text,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 4000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Mensagem',
                        counterText: '',
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('send_message_button'),
                    tooltip: 'Enviar',
                    icon: const Icon(Icons.send),
                    onPressed: _sending || _text.text.trim().isEmpty
                        ? null
                        : _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.message,
    required this.showAuthor,
    required this.theme,
    required this.onLongPress,
    this.authorLabel,
  });

  final ChatMessage message;
  final bool showAuthor;

  /// Mensagem da página: "Página · @quem enviou".
  final String? authorLabel;
  final ThemeData theme;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final scheme = theme.colorScheme;
    final bg = m.mine ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final t = m.createdAt.toLocal();
    final hhmm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.78,
          ),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showAuthor && m.author != null)
                Text(
                  authorLabel ?? m.author!.label,
                  style: theme.textTheme.labelSmall,
                ),
              Text(
                m.deleted ? 'Mensagem apagada' : m.body,
                style: m.deleted
                    ? const TextStyle(fontStyle: FontStyle.italic)
                    : null,
              ),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(hhmm, style: theme.textTheme.labelSmall),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
