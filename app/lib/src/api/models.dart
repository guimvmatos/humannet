/// O próprio usuário autenticado (contém e-mail; nunca usar para terceiros).
class User {
  const User({
    required this.id,
    required this.username,
    required this.email,
    required this.createdAt,
    this.displayName,
    this.bio = '',
    this.role = 'user',
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    username: json['username'] as String,
    email: json['email'] as String,
    displayName: json['display_name'] as String?,
    bio: (json['bio'] as String?) ?? '',
    role: (json['role'] as String?) ?? 'user',
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final String username;
  final String email;
  final String? displayName;
  final String bio;
  final String role;
  final DateTime createdAt;

  bool get isAdmin => role == 'admin';
}

class AuthResult {
  const AuthResult({required this.token, required this.user});

  factory AuthResult.fromJson(Map<String, dynamic> json) => AuthResult(
    token: json['token'] as String,
    user: User.fromJson(json['user'] as Map<String, dynamic>),
  );

  final String token;
  final User user;
}

class InviteCreated {
  const InviteCreated({required this.code, required this.expiresAt});

  factory InviteCreated.fromJson(Map<String, dynamic> json) => InviteCreated(
    code: json['code'] as String,
    expiresAt: DateTime.parse(json['expires_at'] as String),
  );

  final String code;
  final DateTime expiresAt;
}

/// Autor de um post (dados públicos).
class Author {
  const Author({required this.id, required this.username, this.displayName});

  factory Author.fromJson(Map<String, dynamic> json) => Author(
    id: json['id'] as String,
    username: json['username'] as String,
    displayName: json['display_name'] as String?,
  );

  final String id;
  final String username;
  final String? displayName;

  String get label => displayName ?? '@$username';
}

class Post {
  const Post({
    required this.id,
    required this.author,
    required this.body,
    required this.createdAt,
    this.editedAt,
    this.commentCount = 0,
    this.likedByMe = false,
    this.likeCount,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    final edited = json['edited_at'] as String?;
    return Post(
      id: json['id'] as String,
      author: Author.fromJson(json['author'] as Map<String, dynamic>),
      body: json['body'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      editedAt: edited == null ? null : DateTime.parse(edited),
      commentCount: (json['comment_count'] as int?) ?? 0,
      likedByMe: (json['liked_by_me'] as bool?) ?? false,
      likeCount: json['like_count'] as int?,
    );
  }

  final String id;
  final Author author;
  final String body;
  final DateTime createdAt;
  final DateTime? editedAt;
  final int commentCount;
  final bool likedByMe;

  /// Só presente para o autor (R3: curtidas são privadas).
  final int? likeCount;
}

class Comment {
  const Comment({
    required this.id,
    required this.author,
    required this.body,
    required this.createdAt,
    required this.canDelete,
  });

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
    id: json['id'] as String,
    author: Author.fromJson(json['author'] as Map<String, dynamic>),
    body: json['body'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    canDelete: (json['can_delete'] as bool?) ?? false,
  );

  final String id;
  final Author author;
  final String body;
  final DateTime createdAt;
  final bool canDelete;
}

/// Página de posts. `nextCursor == null` = fim (sem rolagem infinita).
class PostPage {
  const PostPage({required this.items, this.nextCursor});

  factory PostPage.fromJson(Map<String, dynamic> json) => PostPage(
    items: (json['items'] as List<dynamic>)
        .map((e) => Post.fromJson(e as Map<String, dynamic>))
        .toList(),
    nextCursor: json['next_cursor'] as String?,
  );

  final List<Post> items;
  final String? nextCursor;
}

/// Relação entre quem vê e o dono do perfil (ADR-0006: amizade mútua).
enum Relation {
  self,
  none,
  friends,
  requestSent,
  requestReceived;

  static Relation parse(String? v) => switch (v) {
    'self' => Relation.self,
    'friends' => Relation.friends,
    'request_sent' => Relation.requestSent,
    'request_received' => Relation.requestReceived,
    _ => Relation.none,
  };

  /// Posts do perfil só aparecem para o próprio e para amigos.
  bool get canSeePosts => this == Relation.self || this == Relation.friends;
}

/// Contagens do próprio perfil (privadas, R3).
class ProfileStats {
  const ProfileStats({
    required this.friends,
    required this.posts,
    required this.pendingRequests,
    this.pendingTestimonials = 0,
  });

  factory ProfileStats.fromJson(Map<String, dynamic> json) => ProfileStats(
    friends: json['friends'] as int,
    posts: json['posts'] as int,
    pendingRequests: (json['pending_requests'] as int?) ?? 0,
    pendingTestimonials: (json['pending_testimonials'] as int?) ?? 0,
  );

  final int friends;
  final int posts;
  final int pendingRequests;
  final int pendingTestimonials;
}

class Profile {
  const Profile({
    required this.id,
    required this.username,
    required this.bio,
    required this.createdAt,
    required this.relation,
    this.displayName,
    this.stats,
    this.hometown = '',
    this.city = '',
    this.school = '',
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] as Map<String, dynamic>?;
    return Profile(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String?,
      bio: (json['bio'] as String?) ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      relation: Relation.parse(json['relation'] as String?),
      stats: stats == null ? null : ProfileStats.fromJson(stats),
      hometown: (json['hometown'] as String?) ?? '',
      city: (json['city'] as String?) ?? '',
      school: (json['school'] as String?) ?? '',
    );
  }

  final String id;
  final String username;
  final String? displayName;
  final String bio;
  final DateTime createdAt;
  final Relation relation;
  final ProfileStats? stats;
  final String hometown;
  final String city;
  final String school;

  bool get isSelf => relation == Relation.self;

  Profile copyWith({Relation? relation}) => Profile(
    id: id,
    username: username,
    displayName: displayName,
    bio: bio,
    createdAt: createdAt,
    relation: relation ?? this.relation,
    stats: stats,
    hometown: hometown,
    city: city,
    school: school,
  );
}

/// Pedido de amizade recebido.
class FriendRequest {
  const FriendRequest({required this.user, required this.createdAt});

  factory FriendRequest.fromJson(Map<String, dynamic> json) => FriendRequest(
    user: Author.fromJson(json['user'] as Map<String, dynamic>),
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final Author user;
  final DateTime createdAt;
}

/// Denúncia vista pela moderação.
class AdminReport {
  const AdminReport({
    required this.id,
    required this.kind,
    required this.reason,
    required this.snapshot,
    required this.details,
    required this.createdAt,
    required this.targetSuspended,
    this.targetUsername,
    this.reporterUsername,
  });

  factory AdminReport.fromJson(Map<String, dynamic> json) => AdminReport(
    id: json['id'] as String,
    kind: json['kind'] as String,
    reason: json['reason'] as String,
    snapshot: (json['snapshot'] as String?) ?? '',
    details: (json['details'] as String?) ?? '',
    createdAt: DateTime.parse(json['created_at'] as String),
    targetSuspended: (json['target_suspended'] as bool?) ?? false,
    targetUsername: json['target_username'] as String?,
    reporterUsername: json['reporter_username'] as String?,
  );

  final String id;

  /// post, user, comment, topic, reply ou community.
  final String kind;
  final String reason;
  final String snapshot;
  final String details;
  final DateTime createdAt;
  final bool targetSuspended;
  final String? targetUsername;
  final String? reporterUsername;
}

class ResetCode {
  const ResetCode({required this.code, required this.expiresAt});

  factory ResetCode.fromJson(Map<String, dynamic> json) => ResetCode(
    code: json['code'] as String,
    expiresAt: DateTime.parse(json['expires_at'] as String),
  );

  final String code;
  final DateTime expiresAt;
}

// ---------------------------------------------------------------- comunidades

/// Temas de comunidade (códigos da API → texto).
const communityThemes = <String, String>{
  'tecnologia': 'Tecnologia',
  'musica': 'Música',
  'cinema': 'Cinema',
  'series': 'Séries',
  'livros': 'Livros',
  'games': 'Games',
  'esportes': 'Esportes',
  'arte': 'Arte',
  'culinaria': 'Culinária',
  'viagens': 'Viagens',
  'ciencia': 'Ciência',
  'humor': 'Humor',
  'cidade': 'Cidade e bairro',
  'educacao': 'Educação',
  'trabalho': 'Trabalho',
  'familia': 'Família',
  'outros': 'Outros',
};

/// Comunidade na lista (busca ou "minhas").
class CommunityItem {
  const CommunityItem({
    required this.slug,
    required this.name,
    required this.description,
    required this.theme,
    required this.visibility,
    this.myRole,
    this.myStatus,
  });

  factory CommunityItem.fromJson(Map<String, dynamic> json) => CommunityItem(
    slug: json['slug'] as String,
    name: json['name'] as String,
    description: (json['description'] as String?) ?? '',
    theme: json['theme'] as String,
    visibility: json['visibility'] as String,
    myRole: json['my_role'] as String?,
    myStatus: json['my_status'] as String?,
  );

  final String slug;
  final String name;
  final String description;
  final String theme;

  /// public | closed
  final String visibility;
  final String? myRole;

  /// active | pending | banned | null (não participa)
  final String? myStatus;

  bool get isClosed => visibility == 'closed';
  String get themeLabel => communityThemes[theme] ?? theme;
}

/// Comunidade com as permissões de quem está vendo.
class Community {
  const Community({
    required this.slug,
    required this.name,
    required this.description,
    required this.rules,
    required this.theme,
    required this.visibility,
    required this.canRead,
    required this.canPost,
    required this.canModerate,
    this.myRole,
    this.myStatus,
    this.memberCount,
    this.pendingCount,
  });

  factory Community.fromJson(Map<String, dynamic> json) => Community(
    slug: json['slug'] as String,
    name: json['name'] as String,
    description: (json['description'] as String?) ?? '',
    rules: (json['rules'] as String?) ?? '',
    theme: json['theme'] as String,
    visibility: json['visibility'] as String,
    canRead: (json['can_read'] as bool?) ?? false,
    canPost: (json['can_post'] as bool?) ?? false,
    canModerate: (json['can_moderate'] as bool?) ?? false,
    myRole: json['my_role'] as String?,
    myStatus: json['my_status'] as String?,
    memberCount: json['member_count'] as int?,
    pendingCount: json['pending_count'] as int?,
  );

  final String slug;
  final String name;
  final String description;
  final String rules;
  final String theme;
  final String visibility;
  final bool canRead;
  final bool canPost;
  final bool canModerate;
  final String? myRole;
  final String? myStatus;

  /// Só para quem modera (R3).
  final int? memberCount;
  final int? pendingCount;

  bool get isClosed => visibility == 'closed';
  bool get isOwner => myRole == 'owner' && myStatus == 'active';
  bool get isMember => myStatus == 'active';
  bool get isPending => myStatus == 'pending';
  bool get isBanned => myStatus == 'banned';
  String get themeLabel => communityThemes[theme] ?? theme;
}

class Topic {
  const Topic({
    required this.id,
    required this.communitySlug,
    required this.communityName,
    required this.author,
    required this.title,
    required this.body,
    required this.pinned,
    required this.locked,
    required this.replyCount,
    required this.createdAt,
    required this.lastActivityAt,
    required this.canReply,
    required this.canDelete,
    required this.canModerate,
  });

  factory Topic.fromJson(Map<String, dynamic> json) => Topic(
    id: json['id'] as String,
    communitySlug: json['community_slug'] as String,
    communityName: json['community_name'] as String,
    author: Author.fromJson(json['author'] as Map<String, dynamic>),
    title: json['title'] as String,
    body: (json['body'] as String?) ?? '',
    pinned: (json['pinned'] as bool?) ?? false,
    locked: (json['locked'] as bool?) ?? false,
    replyCount: (json['reply_count'] as int?) ?? 0,
    createdAt: DateTime.parse(json['created_at'] as String),
    lastActivityAt: DateTime.parse(json['last_activity_at'] as String),
    canReply: (json['can_reply'] as bool?) ?? false,
    canDelete: (json['can_delete'] as bool?) ?? false,
    canModerate: (json['can_moderate'] as bool?) ?? false,
  );

  final String id;
  final String communitySlug;
  final String communityName;
  final Author author;
  final String title;
  final String body;
  final bool pinned;
  final bool locked;
  final int replyCount;
  final DateTime createdAt;
  final DateTime lastActivityAt;
  final bool canReply;
  final bool canDelete;
  final bool canModerate;
}

class Reply {
  const Reply({
    required this.id,
    required this.author,
    required this.body,
    required this.createdAt,
    required this.canDelete,
  });

  factory Reply.fromJson(Map<String, dynamic> json) => Reply(
    id: json['id'] as String,
    author: Author.fromJson(json['author'] as Map<String, dynamic>),
    body: json['body'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    canDelete: (json['can_delete'] as bool?) ?? false,
  );

  final String id;
  final Author author;
  final String body;
  final DateTime createdAt;
  final bool canDelete;
}

class Member {
  const Member({
    required this.user,
    required this.role,
    required this.status,
  });

  factory Member.fromJson(Map<String, dynamic> json) => Member(
    user: Author.fromJson(json['user'] as Map<String, dynamic>),
    role: json['role'] as String,
    status: json['status'] as String,
  );

  final Author user;

  /// owner | moderator | member
  final String role;

  /// active | pending | banned
  final String status;

  String get roleLabel => switch (role) {
    'owner' => 'Dono',
    'moderator' => 'Moderador',
    _ => 'Membro',
  };
}

/// Página genérica com cursor (`nextCursor == null` = fim).
class Paged<T> {
  const Paged({required this.items, this.nextCursor});

  factory Paged.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) item,
  ) => Paged(
    items: (json['items'] as List<dynamic>)
        .map((e) => item(e as Map<String, dynamic>))
        .toList(),
    nextCursor: json['next_cursor'] as String?,
  );

  final List<T> items;
  final String? nextCursor;
}

/// Depoimento (estilo Orkut): um amigo escreve, o dono do perfil aprova.
class Testimonial {
  const Testimonial({
    required this.id,
    required this.author,
    required this.recipient,
    required this.body,
    required this.status,
    required this.createdAt,
    required this.canDelete,
  });

  factory Testimonial.fromJson(Map<String, dynamic> json) => Testimonial(
    id: json['id'] as String,
    author: Author.fromJson(json['author'] as Map<String, dynamic>),
    recipient: Author.fromJson(json['recipient'] as Map<String, dynamic>),
    body: json['body'] as String,
    status: json['status'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    canDelete: (json['can_delete'] as bool?) ?? false,
  );

  final String id;
  final Author author;
  final Author recipient;
  final String body;

  /// pending | approved
  final String status;
  final DateTime createdAt;
  final bool canDelete;

  bool get isPending => status == 'pending';
}

/// Contadores para as bolinhas das abas.
class Counts {
  const Counts({
    this.friendRequests = 0,
    this.pendingTestimonials = 0,
    this.communityRequests = 0,
    this.unreadActivity = 0,
  });

  factory Counts.fromJson(Map<String, dynamic> json) => Counts(
    friendRequests: (json['friend_requests'] as int?) ?? 0,
    pendingTestimonials: (json['pending_testimonials'] as int?) ?? 0,
    communityRequests: (json['community_requests'] as int?) ?? 0,
    unreadActivity: (json['unread_activity'] as int?) ?? 0,
  );

  final int friendRequests;
  final int pendingTestimonials;
  final int communityRequests;
  final int unreadActivity;
}

/// Novidade: comentário num post meu ou resposta num tópico em que participo.
class ActivityItem {
  const ActivityItem({
    required this.kind,
    required this.actor,
    required this.targetId,
    required this.targetTitle,
    required this.excerpt,
    required this.createdAt,
    required this.unread,
  });

  factory ActivityItem.fromJson(Map<String, dynamic> json) => ActivityItem(
    kind: json['kind'] as String,
    actor: Author.fromJson(json['actor'] as Map<String, dynamic>),
    targetId: json['target_id'] as String,
    targetTitle: (json['target_title'] as String?) ?? '',
    excerpt: (json['excerpt'] as String?) ?? '',
    createdAt: DateTime.parse(json['created_at'] as String),
    unread: (json['unread'] as bool?) ?? false,
  );

  /// comment | reply
  final String kind;
  final Author actor;
  final String targetId;
  final String targetTitle;
  final String excerpt;
  final DateTime createdAt;
  final bool unread;
}

/// Sugestão de amizade, sempre com o motivo (R2).
class Suggestion {
  const Suggestion({required this.user, required this.reasons});

  factory Suggestion.fromJson(Map<String, dynamic> json) => Suggestion(
    user: Author.fromJson(json['user'] as Map<String, dynamic>),
    reasons: (json['reasons'] as List<dynamic>).cast<String>(),
  );

  final Author user;
  final List<String> reasons;
}
