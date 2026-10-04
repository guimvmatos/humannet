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
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    final edited = json['edited_at'] as String?;
    return Post(
      id: json['id'] as String,
      author: Author.fromJson(json['author'] as Map<String, dynamic>),
      body: json['body'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      editedAt: edited == null ? null : DateTime.parse(edited),
    );
  }

  final String id;
  final Author author;
  final String body;
  final DateTime createdAt;
  final DateTime? editedAt;
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

/// Contagens do próprio perfil (privadas, R3).
class ProfileStats {
  const ProfileStats({
    required this.followers,
    required this.following,
    required this.posts,
  });

  factory ProfileStats.fromJson(Map<String, dynamic> json) => ProfileStats(
    followers: json['followers'] as int,
    following: json['following'] as int,
    posts: json['posts'] as int,
  );

  final int followers;
  final int following;
  final int posts;
}

class Profile {
  const Profile({
    required this.id,
    required this.username,
    required this.bio,
    required this.createdAt,
    required this.isSelf,
    required this.isFollowing,
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
      isSelf: json['is_self'] as bool,
      isFollowing: json['is_following'] as bool,
      stats: stats == null ? null : ProfileStats.fromJson(stats),
    );
  }

  final String id;
  final String username;
  final String? displayName;
  final String bio;
  final DateTime createdAt;
  final bool isSelf;
  final bool isFollowing;
  final ProfileStats? stats;

  Profile copyWith({bool? isFollowing}) => Profile(
    id: id,
    username: username,
    displayName: displayName,
    bio: bio,
    createdAt: createdAt,
    isSelf: isSelf,
    isFollowing: isFollowing ?? this.isFollowing,
    stats: stats,
  );
}
