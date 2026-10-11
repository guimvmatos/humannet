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
    this.needsCpf = false,
    this.needsTerms = false,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    username: json['username'] as String,
    email: json['email'] as String,
    displayName: json['display_name'] as String?,
    bio: (json['bio'] as String?) ?? '',
    role: (json['role'] as String?) ?? 'user',
    createdAt: DateTime.parse(json['created_at'] as String),
    needsCpf: (json['needs_cpf'] as bool?) ?? false,
    needsTerms: (json['needs_terms'] as bool?) ?? false,
  );

  final String id;
  final String username;
  final String email;
  final String? displayName;
  final String bio;
  final String role;
  final DateTime createdAt;

  /// Conta antiga sem CPF: o app pede antes de seguir.
  final bool needsCpf;

  /// Ainda não aceitou a versão vigente dos Termos e da Privacidade.
  final bool needsTerms;

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
  const Author({
    required this.id,
    required this.username,
    this.displayName,
    this.avatarUrl,
    this.status,
  });

  factory Author.fromJson(Map<String, dynamic> json) => Author(
    id: json['id'] as String,
    username: json['username'] as String,
    displayName: json['display_name'] as String?,
    avatarUrl: json['avatar_url'] as String?,
    status: json['status'] as String?,
  );

  final String id;
  final String username;
  final String? displayName;

  /// Foto de perfil (link assinado), quando houver.
  final String? avatarUrl;

  /// Status/subnick (só na lista de amigos).
  final String? status;

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
    this.images = const [],
    this.page,
    this.topics = const [],
    this.hashtags = const [],
    this.inNetwork = true,
    this.tagged = const [],
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
      images: ((json['images'] as List<dynamic>?) ?? const [])
          .map((e) => MediaRef.fromJson(e as Map<String, dynamic>))
          .toList(),
      page: json['page'] == null
          ? null
          : PostPageRef.fromJson(json['page'] as Map<String, dynamic>),
      topics: ((json['topics'] as List<dynamic>?) ?? const []).cast<String>(),
      hashtags: ((json['hashtags'] as List<dynamic>?) ?? const [])
          .cast<String>(),
      inNetwork: (json['in_network'] as bool?) ?? true,
      tagged: [
        for (final t in (json['tagged'] as List<dynamic>?) ?? const [])
          TaggedUser.fromJson(t as Map<String, dynamic>),
      ],
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

  /// Até 4 fotos.
  final List<MediaRef> images;

  /// Post do mural de uma página (o autor é quem publicou por ela).
  final PostPageRef? page;

  /// Temas marcados pelo autor (ex.: "cidade.transito") e hashtags do texto.
  final List<String> topics;
  final List<String> hashtags;

  /// Só nos candidatos do "Para você": `false` = de alguém fora da sua rede,
  /// achado por tema/hashtag (só aparece se bater com um interesse).
  final bool inNetwork;

  /// "Com fulano". Pendentes só aparecem para o autor e para a pessoa.
  final List<TaggedUser> tagged;
}

class TaggedUser {
  const TaggedUser({
    required this.username,
    this.displayName,
    this.pending = false,
  });

  factory TaggedUser.fromJson(Map<String, dynamic> json) => TaggedUser(
    username: json['username'] as String,
    displayName: json['display_name'] as String?,
    pending: (json['pending'] as bool?) ?? false,
  );

  final String username;
  final String? displayName;
  final bool pending;
}

/// Marcação esperando minha aprovação.
class PendingTag {
  const PendingTag({
    required this.postId,
    required this.author,
    required this.excerpt,
  });

  factory PendingTag.fromJson(Map<String, dynamic> json) => PendingTag(
    postId: json['post_id'] as String,
    author: Author.fromJson(json['author'] as Map<String, dynamic>),
    excerpt: json['excerpt'] as String,
  );

  final String postId;
  final Author author;
  final String excerpt;
}

/// Página que publicou um post.
class PostPageRef {
  const PostPageRef({required this.slug, required this.name, this.logoUrl});

  factory PostPageRef.fromJson(Map<String, dynamic> json) => PostPageRef(
    slug: json['slug'] as String,
    name: json['name'] as String,
    logoUrl: json['logo_url'] as String?,
  );

  final String slug;
  final String name;
  final String? logoUrl;
}

/// Foto guardada no servidor (link assinado, vale algumas horas).
class MediaRef {
  const MediaRef({
    required this.id,
    required this.url,
    required this.width,
    required this.height,
  });

  factory MediaRef.fromJson(Map<String, dynamic> json) => MediaRef(
    id: json['id'] as String,
    url: json['url'] as String,
    width: (json['width'] as int?) ?? 1,
    height: (json['height'] as int?) ?? 1,
  );

  final String id;
  final String url;
  final int width;
  final int height;

  double get aspectRatio => height == 0 ? 1 : width / height;
}

/// Foto do dia (a mais recente, até 7 dias).
class DailyPhoto {
  const DailyPhoto({
    required this.photo,
    required this.caption,
    required this.day,
  });

  factory DailyPhoto.fromJson(Map<String, dynamic> json) => DailyPhoto(
    photo: MediaRef.fromJson(json['photo'] as Map<String, dynamic>),
    caption: (json['caption'] as String?) ?? '',
    day: DateTime.parse(json['day'] as String),
  );

  final MediaRef photo;
  final String caption;
  final DateTime day;
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
    this.avatarUrl,
    this.dailyPhoto,
    this.status,
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
      avatarUrl: json['avatar_url'] as String?,
      status: json['status'] as String?,
      dailyPhoto: json['daily_photo'] == null
          ? null
          : DailyPhoto.fromJson(json['daily_photo'] as Map<String, dynamic>),
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
  final String? avatarUrl;
  final DailyPhoto? dailyPhoto;

  /// Status/subnick vigente (só para o próprio e amigos).
  final String? status;

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
    avatarUrl: avatarUrl,
    dailyPhoto: dailyPhoto,
    status: status,
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
    this.unreadMessages = 0,
    this.pendingTags = 0,
  });

  factory Counts.fromJson(Map<String, dynamic> json) => Counts(
    friendRequests: (json['friend_requests'] as int?) ?? 0,
    pendingTestimonials: (json['pending_testimonials'] as int?) ?? 0,
    communityRequests: (json['community_requests'] as int?) ?? 0,
    unreadActivity: (json['unread_activity'] as int?) ?? 0,
    unreadMessages: (json['unread_messages'] as int?) ?? 0,
    pendingTags: (json['pending_tags'] as int?) ?? 0,
  );

  final int friendRequests;
  final int pendingTestimonials;
  final int communityRequests;
  final int unreadActivity;

  /// Conversas com mensagem nova.
  final int unreadMessages;

  /// Marcações ("com fulano") esperando minha aprovação.
  final int pendingTags;
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

/// Recado no perfil (estilo scrap).
class Scrap {
  const Scrap({
    required this.id,
    required this.author,
    required this.body,
    required this.createdAt,
    required this.canDelete,
  });

  factory Scrap.fromJson(Map<String, dynamic> json) => Scrap(
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

// ---------------------------------------------------------------- lugares e eventos

const placeCategories = <String, String>{
  'bar': 'Bar',
  'restaurante': 'Restaurante',
  'cafe': 'Café',
  'casa_de_show': 'Casa de show',
  'balada': 'Balada',
  'teatro': 'Teatro',
  'cinema': 'Cinema',
  'espaco_cultural': 'Espaço cultural',
  'livraria': 'Livraria',
  'esporte': 'Esporte',
  'outro': 'Outro',
};

/// Página de lugar na lista.
class PlaceItem {
  const PlaceItem({
    required this.slug,
    required this.name,
    required this.category,
    required this.city,
    required this.verified,
    required this.following,
    this.myRole,
    this.logoUrl,
  });

  factory PlaceItem.fromJson(Map<String, dynamic> json) => PlaceItem(
    slug: json['slug'] as String,
    name: json['name'] as String,
    category: json['category'] as String,
    city: (json['city'] as String?) ?? '',
    verified: (json['verified'] as bool?) ?? false,
    following: (json['following'] as bool?) ?? false,
    myRole: json['my_role'] as String?,
    logoUrl: json['logo_url'] as String?,
  );

  final String slug;
  final String name;
  final String category;
  final String city;
  final bool verified;
  final bool following;
  final String? myRole;
  final String? logoUrl;

  String get categoryLabel => placeCategories[category] ?? category;
}

/// Página de lugar completa.
class Place {
  const Place({
    required this.slug,
    required this.name,
    required this.category,
    required this.description,
    required this.address,
    required this.city,
    required this.cnpj,
    required this.verified,
    required this.following,
    this.myRole,
    this.followerCount,
    this.cep,
    this.logoUrl,
    this.coverUrl,
    this.lat,
    this.lng,
    this.pinManual = false,
  });

  factory Place.fromJson(Map<String, dynamic> json) => Place(
    slug: json['slug'] as String,
    name: json['name'] as String,
    category: json['category'] as String,
    description: (json['description'] as String?) ?? '',
    address: (json['address'] as String?) ?? '',
    city: (json['city'] as String?) ?? '',
    cnpj: (json['cnpj'] as String?) ?? '',
    verified: (json['verified'] as bool?) ?? false,
    following: (json['following'] as bool?) ?? false,
    myRole: json['my_role'] as String?,
    followerCount: json['follower_count'] as int?,
    cep: json['cep'] as String?,
    logoUrl: json['logo_url'] as String?,
    coverUrl: json['cover_url'] as String?,
    lat: (json['lat'] as num?)?.toDouble(),
    lng: (json['lng'] as num?)?.toDouble(),
    pinManual: (json['pin_manual'] as bool?) ?? false,
  );

  final String slug;
  final String name;
  final String category;
  final String description;
  final String address;
  final String city;
  final String cnpj;
  final bool verified;
  final bool following;

  /// owner | admin | null
  final String? myRole;

  /// Só para quem administra (R3).
  final int? followerCount;

  /// Só dígitos (8).
  final String? cep;
  final String? logoUrl;
  final String? coverUrl;

  /// Ponto no mapa (do endereço ou marcado por quem administra).
  final double? lat;
  final double? lng;
  final bool pinManual;
  bool get hasPin => lat != null && lng != null;

  bool get canManage => myRole != null;
  bool get isOwner => myRole == 'owner';
  String get categoryLabel => placeCategories[category] ?? category;
}

/// Quem administra uma página.
class PlaceAdmin {
  const PlaceAdmin({required this.user, required this.role});

  factory PlaceAdmin.fromJson(Map<String, dynamic> json) => PlaceAdmin(
    user: Author.fromJson(json),
    role: (json['role'] as String?) ?? 'admin',
  );

  final Author user;

  /// owner | admin
  final String role;
  bool get isOwner => role == 'owner';
}

/// Endereço vindo do CEP (base pública dos Correios via ViaCEP).
class CepAddress {
  const CepAddress({
    required this.street,
    required this.district,
    required this.city,
    required this.uf,
  });

  final String street;
  final String district;
  final String city;
  final String uf;
}

class PlaceEvent {
  const PlaceEvent({
    required this.id,
    required this.placeSlug,
    required this.placeName,
    required this.title,
    required this.description,
    required this.startsAt,
    required this.location,
    required this.cancelled,
    required this.friends,
    required this.friendsCount,
    required this.canEdit,
    this.endsAt,
    this.myInterest,
    this.interestedCount,
    this.goingCount,
  });

  factory PlaceEvent.fromJson(Map<String, dynamic> json) {
    final page = json['page'] as Map<String, dynamic>;
    final ends = json['ends_at'] as String?;
    return PlaceEvent(
      id: json['id'] as String,
      placeSlug: page['slug'] as String,
      placeName: page['name'] as String,
      title: json['title'] as String,
      description: (json['description'] as String?) ?? '',
      startsAt: DateTime.parse(json['starts_at'] as String),
      endsAt: ends == null ? null : DateTime.parse(ends),
      location: (json['location'] as String?) ?? '',
      cancelled: (json['cancelled'] as bool?) ?? false,
      myInterest: json['my_interest'] as String?,
      friends: ((json['friends'] as List<dynamic>?) ?? const [])
          .map((e) => Author.fromJson(e as Map<String, dynamic>))
          .toList(),
      friendsCount: (json['friends_count'] as int?) ?? 0,
      interestedCount: json['interested_count'] as int?,
      goingCount: json['going_count'] as int?,
      canEdit: (json['can_edit'] as bool?) ?? false,
    );
  }

  final String id;
  final String placeSlug;
  final String placeName;
  final String title;
  final String description;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String location;
  final bool cancelled;

  /// interested | going | null
  final String? myInterest;
  final List<Author> friends;
  final int friendsCount;

  /// Só para quem administra a página (R3).
  final int? interestedCount;
  final int? goingCount;
  final bool canEdit;
}

// ---------------------------------------------------------------- mensagens

class Conversation {
  const Conversation({
    required this.id,
    required this.kind,
    required this.title,
    required this.memberCount,
    required this.lastMessageAt,
    required this.unread,
    required this.isOwner,
    this.other,
    this.lastMessage,
    this.pageSlug,
    this.asPage = false,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: json['id'] as String,
    kind: json['kind'] as String,
    title: json['title'] as String,
    other: json['other'] == null
        ? null
        : Author.fromJson(json['other'] as Map<String, dynamic>),
    memberCount: (json['member_count'] as int?) ?? 0,
    lastMessage: json['last_message'] as String?,
    lastMessageAt: DateTime.parse(json['last_message_at'] as String),
    unread: (json['unread'] as int?) ?? 0,
    isOwner: (json['is_owner'] as bool?) ?? false,
    pageSlug: json['page_slug'] as String?,
    asPage: (json['as_page'] as bool?) ?? false,
  );

  /// Conversa com uma página: o endereço dela.
  final String? pageSlug;

  /// Eu respondo como a página (administro).
  final bool asPage;

  final String id;

  /// direct | group
  final String kind;
  final String title;
  final Author? other;
  final int memberCount;
  final String? lastMessage;
  final DateTime lastMessageAt;
  final int unread;
  final bool isOwner;

  bool get isGroup => kind == 'group';
  bool get isPage => kind == 'page';

  /// Conversa com página: o nome dela (o título de quem administra é
  /// "Página · pessoa").
  String get pageName => asPage ? title.split(' · ').first : title;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.body,
    required this.createdAt,
    required this.mine,
    required this.deleted,
    this.author,
    this.asPage = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    author: json['author'] == null
        ? null
        : Author.fromJson(json['author'] as Map<String, dynamic>),
    body: (json['body'] as String?) ?? '',
    createdAt: DateTime.parse(json['created_at'] as String),
    mine: (json['mine'] as bool?) ?? false,
    deleted: (json['deleted'] as bool?) ?? false,
    asPage: (json['as_page'] as bool?) ?? false,
  );

  /// Enviada como a página (por quem administra).
  final bool asPage;
  final String id;
  final Author? author;
  final String body;
  final DateTime createdAt;
  final bool mine;
  final bool deleted;
}

/// Evento no mapa (o ponto é o do lugar).
class MapEvent {
  const MapEvent({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.location,
    required this.pageSlug,
    required this.pageName,
    required this.lat,
    required this.lng,
    this.endsAt,
    this.pageLogoUrl,
  });

  factory MapEvent.fromJson(Map<String, dynamic> json) {
    final ends = json['ends_at'] as String?;
    return MapEvent(
      id: json['id'] as String,
      title: json['title'] as String,
      startsAt: DateTime.parse(json['starts_at'] as String),
      endsAt: ends == null ? null : DateTime.parse(ends),
      location: (json['location'] as String?) ?? '',
      pageSlug: json['page_slug'] as String,
      pageName: json['page_name'] as String,
      pageLogoUrl: json['page_logo_url'] as String?,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
    );
  }

  final String id;
  final String title;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String location;
  final String pageSlug;
  final String pageName;
  final String? pageLogoUrl;
  final double lat;
  final double lng;
}

/// Município (código do IBGE).
class Municipality {
  const Municipality({required this.code, required this.name, required this.uf});

  factory Municipality.fromJson(Map<String, dynamic> json) => Municipality(
    code: json['code'] as int,
    name: json['name'] as String,
    uf: json['uf'] as String,
  );

  final int code;
  final String name;
  final String uf;
  String get label => '$name - $uf';
}

/// Escola, faculdade ou empresa do catálogo comum.
class Org {
  const Org({
    required this.id,
    required this.kind,
    required this.name,
    this.municipality,
  });

  factory Org.fromJson(Map<String, dynamic> json) => Org(
    id: json['id'] as String,
    kind: json['kind'] as String,
    name: json['name'] as String,
    municipality: json['municipality'] == null
        ? null
        : Municipality.fromJson(json['municipality'] as Map<String, dynamic>),
  );

  final String id;
  final String kind;
  final String name;
  final Municipality? municipality;
  String get label =>
      municipality == null ? name : '$name · ${municipality!.label}';
}

class Course {
  const Course({required this.id, required this.name});

  factory Course.fromJson(Map<String, dynamic> json) =>
      Course(id: json['id'] as int, name: json['name'] as String);

  final int id;
  final String name;
}

/// Tipos de item da "Minha história".
const lifeKinds = <String, String>{
  'nasceu': 'Onde nasci',
  'morou': 'Cidade onde morei / moro',
  'escola': 'Escola',
  'faculdade': 'Faculdade',
  'trabalho': 'Trabalho',
};

const lifeLevels = <String, String>{
  'fundamental': 'Ensino fundamental',
  'medio': 'Ensino médio',
  'tecnico': 'Técnico',
  'graduacao': 'Graduação',
  'pos': 'Pós-graduação',
};

/// Um item da "Minha história".
class LifeEntry {
  const LifeEntry({
    required this.id,
    required this.kind,
    this.municipality,
    this.org,
    this.course,
    this.level,
    this.startYear,
    this.endYear,
    this.visibility,
    this.discoverable,
  });

  factory LifeEntry.fromJson(Map<String, dynamic> json) => LifeEntry(
    id: json['id'] as String,
    kind: json['kind'] as String,
    municipality: json['municipality'] == null
        ? null
        : Municipality.fromJson(json['municipality'] as Map<String, dynamic>),
    org: json['org'] == null
        ? null
        : Org.fromJson(json['org'] as Map<String, dynamic>),
    course: json['course'] == null
        ? null
        : Course.fromJson(json['course'] as Map<String, dynamic>),
    level: json['level'] as String?,
    startYear: json['start_year'] as int?,
    endYear: json['end_year'] as int?,
    visibility: json['visibility'] as String?,
    discoverable: json['discoverable'] as bool?,
  );

  final String id;
  final String kind;
  final Municipality? municipality;
  final Org? org;
  final Course? course;
  final String? level;
  final int? startYear;
  final int? endYear;

  /// friends | suggestions | private (só o dono recebe).
  final String? visibility;
  final bool? discoverable;

  String get title => switch (kind) {
    'nasceu' => 'Nasceu em ${municipality?.label ?? ''}',
    'morou' => 'Morou em ${municipality?.label ?? ''}',
    'escola' => 'Estudou na ${org?.name ?? ''}',
    'faculdade' => course != null
        ? '${course!.name} · ${org?.name ?? ''}'
        : 'Estudou na ${org?.name ?? ''}',
    'trabalho' => 'Trabalhou na ${org?.name ?? ''}',
    _ => kind,
  };

  String get period {
    final a = startYear;
    final b = endYear;
    if (kind == 'nasceu') return a == null ? '' : 'em $a';
    if (a == null && b == null) return '';
    if (b == null) return a == null ? 'até hoje' : 'desde $a';
    if (a == null) return 'até $b';
    return a == b ? '$a' : '$a–$b';
  }

  Map<String, Object?> toJson() => {
    'kind': kind,
    'municipality_code': municipality?.code,
    'org_id': org?.id,
    'course_id': course?.id,
    'level': level,
    'start_year': startYear,
    'end_year': endYear,
    'visibility': visibility,
    'discoverable': discoverable,
  };
}

/// Um item de "Minha atividade".
class HistoryItem {
  const HistoryItem({
    required this.id,
    required this.body,
    required this.createdAt,
    this.postId,
    this.otherUsername,
  });

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
    id: json['id'] as String,
    postId: json['post_id'] as String?,
    otherUsername: json['other_username'] as String?,
    body: json['body'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  /// O que apagar (em curtidas, o post).
  final String id;
  final String? postId;

  /// Autor do post (comentários/curtidas), destinatário (recados/depoimentos)
  /// ou página (posts no mural).
  final String? otherUsername;
  final String body;
  final DateTime createdAt;
}

class HistoryPage {
  const HistoryPage({required this.items, this.nextCursor});

  factory HistoryPage.fromJson(Map<String, dynamic> json) => HistoryPage(
    items: (json['items'] as List<dynamic>)
        .map((e) => HistoryItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    nextCursor: json['next_cursor'] as String?,
  );

  final List<HistoryItem> items;
  final String? nextCursor;
}

/// Quem visitou meu perfil.
class VisitsInfo {
  const VisitsInfo({required this.enabled, required this.visitors});

  factory VisitsInfo.fromJson(Map<String, dynamic> json) => VisitsInfo(
    enabled: json['enabled'] as bool,
    visitors: [
      for (final v in (json['visitors'] as List<dynamic>))
        (
          author: Author(
            id: (v as Map<String, dynamic>)['username'] as String,
            username: v['username'] as String,
            displayName: v['display_name'] as String?,
            avatarUrl: v['avatar_url'] as String?,
          ),
          day: v['day'] as String,
        ),
    ],
  );

  final bool enabled;

  /// `day` é só a data (AAAA-MM-DD).
  final List<({Author author, String day})> visitors;
}
