import 'dart:async';

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'error_messages.dart';
import 'post_list.dart';
import 'report_dialog.dart';
import 'photos.dart';

/// Um post com os comentários (do mais antigo ao mais novo) e o campo de resposta.
class PostScreen extends StatefulWidget {
  const PostScreen({super.key, required this.session, required this.post});

  final SessionController session;
  final Post post;

  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  final _text = TextEditingController();
  List<Comment>? _comments;
  String? _error;
  bool _sending = false;
  bool _postDeleted = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    unawaited(_load());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null) return;
    try {
      final items = await widget.session.api.comments(token, widget.post.id);
      if (mounted) setState(() => _comments = items);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _send() async {
    final token = widget.session.token;
    final body = _text.text.trim();
    if (token == null || body.isEmpty) return;
    setState(() => _sending = true);
    try {
      final c = await widget.session.api.addComment(
        token,
        widget.post.id,
        body,
      );
      unawaited(
        widget.session.interests.learn(
          widget.post,
          weight: 2,
          me: widget.session.user?.username,
        ),
      );
      _text.clear();
      if (mounted) setState(() => _comments = [...?_comments, c]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(Comment c) async {
    final token = widget.session.token;
    if (token == null) return;
    try {
      await widget.session.api.deleteComment(token, c.id);
      if (mounted) {
        setState(
          () => _comments = _comments?.where((x) => x.id != c.id).toList(),
        );
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
    final theme = Theme.of(context);
    final comments = _comments;
    return Scaffold(
      key: const Key('post_screen'),
      appBar: AppBar(title: const Text('Post')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                if (!_postDeleted)
                  PostTile(
                    post: widget.post,
                    session: widget.session,
                    showCommentsButton: false,
                    onDeleted: (_) {
                      setState(() => _postDeleted = true);
                      Navigator.of(context).pop();
                    },
                  ),
                const Divider(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  )
                else if (comments == null)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (comments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Nenhum comentário ainda. Comece a conversa.',
                      key: Key('no_comments'),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  for (final c in comments)
                    ListTile(
                      key: Key('comment_${c.id}'),
                      leading: UserAvatar(c.author),
                      title: Text(
                        '${c.author.label} · ${relativeTime(c.createdAt)}',
                        style: theme.textTheme.bodySmall,
                      ),
                      subtitle: Text(c.body, style: theme.textTheme.bodyMedium),
                      trailing: c.canDelete
                          ? IconButton(
                              key: Key('delete_comment_${c.id}'),
                              tooltip: 'Apagar comentário',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(c),
                            )
                          : IconButton(
                              key: Key('report_comment_${c.id}'),
                              tooltip: 'Denunciar comentário',
                              icon: const Icon(Icons.flag_outlined),
                              onPressed: () => showReportDialog(
                                context,
                                session: widget.session,
                                commentId: c.id,
                              ),
                            ),
                    ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('comment_field'),
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        hintText: 'Escreva um comentário',
                        counterText: '',
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('send_comment_button'),
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
