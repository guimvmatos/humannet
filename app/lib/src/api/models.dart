/// O próprio usuário autenticado (contém e-mail; nunca usar para terceiros).
class User {
  const User({
    required this.id,
    required this.username,
    required this.email,
    required this.createdAt,
    this.displayName,
    this.bio = '',
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    username: json['username'] as String,
    email: json['email'] as String,
    displayName: json['display_name'] as String?,
    bio: (json['bio'] as String?) ?? '',
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final String username;
  final String email;
  final String? displayName;
  final String bio;
  final DateTime createdAt;
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
  });

  factory ProfileStats.fromJson(Map<String, dynamic> json) => ProfileStats(
    friends: json['friends'] as int,
    posts: json['posts'] as int,
    pendingRequests: (json['pending_requests'] as int?) ?? 0,
  );

  final int friends;
  final int posts;
  final int pendingRequests;
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
    );
  }

  final String id;
  final String username;
  final String? displayName;
  final String bio;
  final DateTime createdAt;
  final Relation relation;
  final ProfileStats? stats;

  bool get isSelf => relation == Relation.self;

  Profile copyWith({Relation? relation}) => Profile(
    id: id,
    username: username,
    displayName: displayName,
    bio: bio,
    createdAt: createdAt,
    relation: relation ?? this.relation,
    stats: stats,
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
