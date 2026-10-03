import '../api/api_client.dart';

/// Converte códigos de erro da API em mensagens para o usuário.
String errorMessage(Object error) {
  if (error is! ApiException) {
    return 'Algo deu errado. Tente novamente.';
  }
  return switch (error.code) {
    'invalid_credentials' => 'Usuário ou senha incorretos.',
    'invalid_invite' => 'Convite inválido, expirado ou já utilizado.',
    'invalid_username' =>
      'Nome de usuário deve ter 3–30 caracteres: letras, números ou _.',
    'invalid_email' => 'E-mail inválido.',
    'invalid_password' => 'A senha deve ter entre 12 e 128 caracteres.',
    'username_taken' => 'Esse nome de usuário já está em uso.',
    'email_taken' => 'Esse e-mail já está cadastrado.',
    'invite_limit' => 'Você atingiu o limite de convites ativos.',
    'network_error' => 'Sem conexão com o servidor.',
    _ => 'Algo deu errado. Tente novamente.',
  };
}
