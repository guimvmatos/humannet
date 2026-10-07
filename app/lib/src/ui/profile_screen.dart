import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import 'edit_profile_screen.dart';
import 'error_messages.dart';
import 'photos.dart';
import 'post_list.dart';
import 'report_dialog.dart';
import 'settings_screen.dart';
import 'testimonials_screen.dart';

/// Perfil de um usuário. `asTab: true` = aba "Perfil" do próprio usuário
/// (sem botão de voltar).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.session,
    required this.username,
    this.asTab = false,
  });

  final SessionController session;
  final String username;
  final bool asTab;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _listKey = GlobalKey<PagedPostListState>();
  Profile? _profile;
  String? _error;
  bool _busy = false;

  String? get _token => widget.session.token;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfile());
  }

  Future<void> _loadProfile() async {
    final token = _token;
    if (token == null) return;
    try {
      final p = await widget.session.api.profile(token, widget.username);
      if (mounted) setState(() => _profile = p);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  /// Ação principal do botão de amizade, conforme a relação atual.
  Future<void> _friendAction({bool decline = false}) async {
    final p = _profile;
    final token = _token;
    if (p == null || token == null) return;

    if (p.relation == Relation.friends) {
      final ok = await _confirm(
        'Desfazer amizade?',
        'Vocês deixam de ver os posts um do outro. @${p.username} não é avisado.',
        'Desfazer',
      );
      if (!ok) return;
    }

    setState(() => _busy = true);
    try {
      final api = widget.session.api;
      final Relation next;
      if (decline ||
          p.relation == Relation.friends ||
          p.relation == Relation.requestSent) {
        await api.removeFriend(token, p.username);
        next = Relation.none;
      } else {
        next = await api.requestFriend(token, p.username);
      }
      if (mounted) setState(() => _profile = p.copyWith(relation: next));
    } catch (e) {
      _snack(errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _report() async {
    await showReportDialog(
      context,
      session: widget.session,
      username: widget.username,
    );
  }

  Future<void> _block() async {
    final token = _token;
    if (token == null) return;
    final ok = await _confirm(
      'Bloquear @${widget.username}?',
      'Vocês deixam de ser amigos e nenhum dos dois encontra mais o outro. '
          'A pessoa não é avisada. Você pode desbloquear em Configurações.',
      'Bloquear',
    );
    if (!ok) return;
    try {
      await widget.session.api.block(token, widget.username);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('@${widget.username} bloqueado.')));
      if (!widget.asTab) Navigator.of(context).pop();
    } catch (e) {
      _snack(errorMessage(e));
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('confirm_button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _editProfile() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(session: widget.session),
      ),
    );
    if (changed == true) await _loadProfile();
  }

  Future<void> _createInvite() async {
    final token = _token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      final invite = await widget.session.api.createInvite(token);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Convite criado'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                invite.code,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Envie só para alguém que você conhece. '
                'O código vale para uma pessoa.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: invite.code));
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Copiar'),
            ),
          ],
        ),
      );
    } catch (e) {
      _snack(errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Foto de perfil: escolher (envia e define) ou remover.
  Future<void> _avatarMenu() async {
    final p = _profile;
    if (p == null || !p.isSelf) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('pick_avatar'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Escolher foto de perfil'),
              onTap: () => Navigator.of(ctx).pop('pick'),
            ),
            if (p.avatarUrl != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remover foto'),
                onTap: () => Navigator.of(ctx).pop('remove'),
              ),
          ],
        ),
      ),
    );
    final token = _token;
    if (action == null || token == null) return;
    setState(() => _busy = true);
    try {
      final api = widget.session.api;
      if (action == 'remove') {
        await api.deleteAvatar(token);
      } else {
        final photos = await pickPhotos();
        if (photos.isEmpty) return;
        _snack('Enviando foto…');
        final m = await api.uploadMedia(token, 'avatar', photos.first);
        await api.setAvatar(token, m.id);
      }
      await _loadProfile();
    } catch (e) {
      _snack(errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Foto do dia: escolher foto + legenda (substitui a de hoje).
  Future<void> _postDaily() async {
    final token = _token;
    if (token == null) return;
    final photos = await pickPhotos();
    if (photos.isEmpty || !mounted) return;
    final caption = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Foto do dia'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(photos.first, height: 180, fit: BoxFit.cover),
            ),
            TextField(
              key: const Key('daily_caption_field'),
              controller: caption,
              maxLength: 200,
              decoration: const InputDecoration(
                hintText: 'Legenda (opcional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('post_daily_button'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Postar'),
          ),
        ],
      ),
    );
    final text = caption.text.trim();
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final api = widget.session.api;
      _snack('Enviando foto…');
      final m = await api.uploadMedia(token, 'daily', photos.first);
      await api.setDailyPhoto(token, m.id, caption: text);
      await _loadProfile();
    } catch (e) {
      _snack(errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeDaily() async {
    final token = _token;
    if (token == null) return;
    final ok = await _confirm(
      'Apagar a Foto do dia?',
      'Só a de hoje é apagada.',
      'Apagar',
    );
    if (!ok) return;
    try {
      await widget.session.api.deleteDailyPhoto(token);
      await _loadProfile();
    } catch (e) {
      _snack(errorMessage(e));
    }
  }

  Future<void> _openTestimonials() async {
    final p = _profile;
    if (p == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TestimonialsScreen(
          session: widget.session,
          username: p.username,
          isSelf: p.isSelf,
          canWrite: p.relation == Relation.friends,
        ),
      ),
    );
    if (p.isSelf) await _loadProfile();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    final isSelf = p?.isSelf ?? false;
    return Scaffold(
      key: const Key('profile_screen'),
      appBar: AppBar(
        automaticallyImplyLeading: !widget.asTab,
        title: Text('@${widget.username}'),
        actions: [
          if (isSelf) ...[
            IconButton(
              key: const Key('settings_button'),
              tooltip: 'Configurações',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(session: widget.session),
                ),
              ),
            ),
            IconButton(
              key: const Key('logout_button'),
              tooltip: 'Sair',
              icon: const Icon(Icons.logout),
              onPressed: widget.session.logout,
            ),
          ] else if (p != null)
            PopupMenuButton<String>(
              key: const Key('profile_menu'),
              onSelected: (v) => v == 'block' ? _block() : _report(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'report', child: Text('Denunciar perfil')),
                PopupMenuItem(value: 'block', child: Text('Bloquear')),
              ],
            ),
        ],
      ),
      body: _body(p, isSelf),
    );
  }

  Widget _body(Profile? p, bool isSelf) {
    if (_error != null && p == null) return Center(child: Text(_error!));
    if (p == null) return const Center(child: CircularProgressIndicator());

    final header = _Header(
      profile: p,
      busy: _busy,
      onFriendAction: () => _friendAction(),
      onDecline: () => _friendAction(decline: true),
      onEdit: _editProfile,
      onInvite: _createInvite,
      onTestimonials: _openTestimonials,
      onAvatar: _avatarMenu,
      onPostDaily: _postDaily,
      onRemoveDaily: _removeDaily,
    );

    // Posts só para o próprio e amigos (ADR-0006). Sem chamar a API.
    if (!p.relation.canSeePosts) {
      return RefreshIndicator(
        onRefresh: _loadProfile,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            header,
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Os posts de @${p.username} aparecem só para amigos.',
                key: const Key('friends_only'),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return PagedPostList(
      key: _listKey,
      onRefresh: _loadProfile,
      session: widget.session,
      loader: (before) => widget.session.api.userPosts(
        _token ?? '',
        widget.username,
        before: before,
      ),
      header: header,
      emptyText: isSelf ? 'Você ainda não publicou nada.' : 'Nenhum post ainda.',
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.profile,
    required this.busy,
    required this.onFriendAction,
    required this.onDecline,
    required this.onEdit,
    required this.onInvite,
    required this.onTestimonials,
    required this.onAvatar,
    required this.onPostDaily,
    required this.onRemoveDaily,
  });

  final Profile profile;
  final bool busy;
  final VoidCallback onFriendAction;
  final VoidCallback onDecline;
  final VoidCallback onEdit;
  final VoidCallback onInvite;
  final VoidCallback onTestimonials;
  final VoidCallback onAvatar;
  final VoidCallback onPostDaily;
  final VoidCallback onRemoveDaily;

  String get _places => [
    if (profile.hometown.isNotEmpty) 'De ${profile.hometown}',
    if (profile.city.isNotEmpty) 'Mora em ${profile.city}',
    if (profile.school.isNotEmpty) 'Estudou em ${profile.school}',
  ].join(' · ');

  List<Widget> _friendButtons() {
    final onTap = busy ? null : onFriendAction;
    return switch (profile.relation) {
      Relation.self => const [],
      Relation.none => [
        FilledButton.icon(
          key: const Key('friend_button'),
          onPressed: onTap,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Adicionar'),
        ),
      ],
      Relation.requestSent => [
        OutlinedButton.icon(
          key: const Key('friend_button'),
          onPressed: onTap,
          icon: const Icon(Icons.schedule),
          label: const Text('Pedido enviado · cancelar'),
        ),
      ],
      Relation.requestReceived => [
        FilledButton.icon(
          key: const Key('friend_button'),
          onPressed: onTap,
          icon: const Icon(Icons.check),
          label: const Text('Aceitar amizade'),
        ),
        OutlinedButton(
          key: const Key('decline_button'),
          onPressed: busy ? null : onDecline,
          child: const Text('Recusar'),
        ),
      ],
      Relation.friends => [
        OutlinedButton.icon(
          key: const Key('friend_button'),
          onPressed: onTap,
          icon: const Icon(Icons.people),
          label: const Text('Amigos ✓'),
        ),
      ],
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = profile.stats;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                key: const Key('avatar'),
                onTap: profile.isSelf && !busy ? onAvatar : null,
                child: CircleAvatar(
                  radius: 32,
                  backgroundImage: profile.avatarUrl == null
                      ? null
                      : NetworkImage(profile.avatarUrl!),
                  child: profile.avatarUrl == null
                      ? Icon(
                          profile.isSelf
                              ? Icons.add_a_photo_outlined
                              : Icons.person,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName ?? '@${profile.username}',
                      key: const Key('profile_name'),
                      style: theme.textTheme.headlineSmall,
                    ),
                    if (profile.displayName != null)
                      Text(
                        '@${profile.username}',
                        style: theme.textTheme.bodyMedium,
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (profile.bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(profile.bio),
          ],
          if (_places.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _places,
              key: const Key('profile_places'),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (profile.relation == Relation.requestReceived) ...[
            const SizedBox(height: 12),
            Text(
              '@${profile.username} quer ser seu amigo.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (stats != null) ...[
            const SizedBox(height: 12),
            Text(
              '${stats.posts} posts · ${stats.friends} amigos',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              'Só você vê esses números.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: profile.isSelf
                ? [
                    OutlinedButton.icon(
                      key: const Key('edit_profile_button'),
                      onPressed: busy ? null : onEdit,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Editar perfil'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : onInvite,
                      icon: const Icon(Icons.person_add_alt),
                      label: const Text('Gerar convite'),
                    ),
                  ]
                : _friendButtons(),
          ),
          if (profile.dailyPhoto case final d?) ...[
            const SizedBox(height: 12),
            _DailyPhotoCard(
              daily: d,
              isSelf: profile.isSelf,
              onRemove: onRemoveDaily,
            ),
          ],
          if (profile.isSelf) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('daily_photo_button'),
              onPressed: busy ? null : onPostDaily,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(
                profile.dailyPhoto != null && _isToday(profile.dailyPhoto!.day)
                    ? 'Trocar a Foto do dia'
                    : 'Postar a Foto do dia',
              ),
            ),
          ],
          if (profile.relation.canSeePosts) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('testimonials_button'),
              onPressed: onTestimonials,
              icon: const Icon(Icons.format_quote_outlined),
              label: Text(
                (stats?.pendingTestimonials ?? 0) > 0
                    ? 'Depoimentos (${stats!.pendingTestimonials} para aprovar)'
                    : 'Depoimentos',
              ),
            ),
          ],
          const Divider(height: 32),
        ],
      ),
    );
  }
}

bool _isToday(DateTime day) {
  final now = DateTime.now().toUtc().subtract(const Duration(hours: 3));
  return day.year == now.year && day.month == now.month && day.day == now.day;
}

String _dayLabel(DateTime day) {
  if (_isToday(day)) return 'hoje';
  if (_isToday(day.add(const Duration(days: 1)))) return 'ontem';
  return '${day.day.toString().padLeft(2, '0')}/'
      '${day.month.toString().padLeft(2, '0')}';
}

/// "Foto do dia": um espaço especial no perfil (estilo Fotolog).
class _DailyPhotoCard extends StatelessWidget {
  const _DailyPhotoCard({
    required this.daily,
    required this.isSelf,
    required this.onRemove,
  });

  final DailyPhoto daily;
  final bool isSelf;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('daily_photo_card'),
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PhotoViewer(images: [daily.photo]),
              ),
            ),
            child: AspectRatio(
              aspectRatio: daily.photo.aspectRatio.clamp(0.8, 1.8),
              child: NetPhoto(daily.photo.url),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Foto do dia · ${_dayLabel(daily.day)}',
                        style: theme.textTheme.labelMedium,
                      ),
                      if (daily.caption.isNotEmpty) Text(daily.caption),
                    ],
                  ),
                ),
                if (isSelf && _isToday(daily.day))
                  IconButton(
                    tooltip: 'Apagar a de hoje',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onRemove,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
