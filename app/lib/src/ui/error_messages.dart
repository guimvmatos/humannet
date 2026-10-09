import '../api/api_client.dart';

/// Converte códigos de erro da API em mensagens para o usuário.
String errorMessage(Object error) {
  if (error is! ApiException) {
    return 'Algo deu errado. Tente novamente.';
  }
  return switch (error.code) {
    'invalid_credentials' => 'Usuário ou senha incorretos.',
    'invalid_cep' => 'CEP inválido: use 8 dígitos.',
    'follow_page_first' =>
      'Acompanhe a página para mandar mensagem para ela.',
    'cannot_message_own_page' =>
      'Você administra esta página: as mensagens dela chegam para você.',
    'invalid_invite' => 'Convite inválido, expirado ou já utilizado.',
    'invalid_username' =>
      'Nome de usuário deve ter 3–30 caracteres: letras, números ou _.',
    'invalid_email' => 'E-mail inválido.',
    'invalid_password' => 'A senha deve ter entre 12 e 128 caracteres.',
    'username_taken' => 'Esse nome de usuário já está em uso.',
    'email_taken' => 'Esse e-mail já está cadastrado.',
    'invite_limit' => 'Você atingiu o limite de convites ativos.',
    'invalid_display_name' => 'Nome de exibição deve ter até 50 caracteres.',
    'invalid_bio' => 'A bio deve ter até 300 caracteres.',
    'invalid_post_body' => 'O post deve ter entre 1 e 5.000 caracteres.',
    'cannot_befriend_self' => 'Você não pode adicionar a si mesmo.',
    'friend_request_limit' =>
      'Você tem muitos pedidos de amizade pendentes. Espere algumas respostas.',
    'cannot_block_self' => 'Você não pode bloquear a si mesmo.',
    'cannot_report_self' => 'Você não pode denunciar a si mesmo.',
    'invalid_report_reason' => 'Escolha um motivo para a denúncia.',
    'invalid_report_details' => 'Os detalhes devem ter até 1.000 caracteres.',
    'report_limit' => 'Você fez muitas denúncias hoje. Tente amanhã.',
    'invalid_comment_body' => 'O comentário deve ter entre 1 e 2.000 caracteres.',
    'too_many_attempts' =>
      'Muitas tentativas erradas. Espere 15 minutos e tente de novo.',
    'account_suspended' =>
      'Esta conta está suspensa. Fale com a administração da HumanNet.',
    'invalid_reset_code' =>
      'Código inválido, expirado ou já usado. Peça um novo à administração.',
    'invalid_moderation_action' => 'Ação de moderação inválida.',
    'invalid_community_name' =>
      'O nome da comunidade deve ter entre 3 e 60 caracteres.',
    'invalid_community_slug' =>
      'Não deu para gerar um endereço com esse nome. Use letras ou números.',
    'invalid_community_text' =>
      'Descrição e regras devem ter até 2.000 caracteres cada.',
    'invalid_community_theme' => 'Escolha um tema.',
    'invalid_visibility' => 'Escolha se a comunidade é aberta ou fechada.',
    'slug_taken' => 'Já existe uma comunidade com esse nome.',
    'community_limit' => 'Você já é dono de 10 comunidades.',
    'community_join_limit' => 'Você participa de comunidades demais.',
    'owner_cannot_leave' =>
      'O dono não pode sair. Transfira a comunidade para alguém ou apague.',
    'invalid_topic_title' => 'O título deve ter entre 3 e 150 caracteres.',
    'invalid_topic_body' => 'O texto deve ter até 5.000 caracteres.',
    'invalid_reply_body' => 'A resposta deve ter entre 1 e 5.000 caracteres.',
    'topic_locked' => 'Este tópico está trancado.',
    'invalid_member_state' => 'Essa pessoa não está na situação certa para isso.',
    'invalid_member_action' => 'Ação inválida.',
    'cannot_target_self' => 'Você não pode fazer isso consigo mesmo.',
    'invalid_testimonial_body' =>
      'O depoimento deve ter entre 1 e 1.000 caracteres.',
    'cannot_testify_self' => 'Você não pode escrever um depoimento para si.',
    'invalid_place' => 'Cidade e escola devem ter até 80 caracteres.',
    'invalid_image' =>
      'Não deu para usar essa imagem. Envie uma foto JPEG, PNG ou WebP.',
    'invalid_media' => 'Foto inválida ou já usada. Escolha de novo.',
    'too_many_images' => 'No máximo 4 fotos por post.',
    'invalid_caption' => 'A legenda deve ter até 200 caracteres.',
    'upload_limit' => 'Muitas fotos em pouco tempo. Tente daqui a pouco.',
    'media_unavailable' => 'Fotos ainda não estão ligadas no servidor.',
    'invalid_scrap_body' => 'O recado deve ter entre 1 e 1.000 caracteres.',
    'cannot_scrap_self' => 'Você não pode deixar recado para si mesmo.',
    'scrap_limit' => 'Muitos recados hoje. Tente amanhã.',
    'invalid_status' => 'O status deve ter até 80 caracteres.',
    'cpf_required' => 'Informe seu CPF.',
    'invalid_cpf' => 'CPF inválido. Confira os números.',
    'cpf_taken' =>
      'Esse CPF já tem uma conta. Se não foi você, fale com a administração.',
    'cpf_already_set' => 'Seu CPF já está cadastrado.',
    'invalid_cnpj' => 'CNPJ inválido. Confira os números.',
    'cnpj_taken' => 'Esse CNPJ já tem uma página. Fale com a administração.',
    'invalid_page_name' => 'O nome deve ter entre 2 e 80 caracteres.',
    'invalid_page_category' => 'Escolha uma categoria.',
    'invalid_page_description' => 'A descrição deve ter até 2.000 caracteres.',
    'invalid_address' => 'O endereço deve ter até 200 caracteres.',
    'page_limit' => 'Você já é dono de 3 páginas.',
    'invalid_event_title' => 'O título deve ter entre 3 e 120 caracteres.',
    'invalid_event_description' => 'A descrição deve ter até 3.000 caracteres.',
    'invalid_event_time' =>
      'Confira a data: o evento não pode ser no passado e o fim vem depois do começo.',
    'event_limit' => 'Muitos eventos criados hoje. Tente amanhã.',
    'event_cancelled' => 'Este evento foi cancelado.',
    'cannot_message_self' => 'Você não pode mandar mensagem para si mesmo.',
    'not_friends' => 'Só dá para incluir amigos.',
    'invalid_group_title' => 'O nome do grupo deve ter até 60 caracteres.',
    'group_needs_members' => 'Escolha pelo menos um amigo.',
    'group_too_big' => 'O grupo pode ter no máximo 50 pessoas.',
    'invalid_message' => 'A mensagem deve ter entre 1 e 4.000 caracteres.',
    'message_limit' => 'Muitas mensagens em pouco tempo. Espere um pouco.',
    'cannot_leave_direct' => 'Não dá para sair de uma conversa 1:1.',
    'not_found' => 'Não encontrado.',
    'forbidden' => 'Você não tem permissão para isso.',
    'network_error' =>
      'Sem conexão com o servidor. Se ele estava parado, pode levar até '
          '1 minuto para acordar: tente de novo.',
    _ => 'Algo deu errado. Tente novamente.',
  };
}
