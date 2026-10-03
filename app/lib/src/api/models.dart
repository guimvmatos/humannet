/// O próprio usuário autenticado (contém e-mail; nunca usar para terceiros).
class User {
  const User({
    required this.id,
    required this.username,
    required this.email,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    username: json['username'] as String,
    email: json['email'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final String username;
  final String email;
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
