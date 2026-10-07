import 'package:flutter/material.dart';

/// Regras de convivência (mesmo texto de docs/REGRAS.md).
const communityRules = <(String, String)>[
  (
    'Uma pessoa, uma conta',
    'Use seu nome de verdade ou um apelido pelo qual seus amigos te '
        'reconhecem. Nada de perfil falso, robô ou se passar por outra pessoa.',
  ),
  (
    'Respeito sempre',
    'Sem assédio, ameaça, humilhação ou discurso de ódio (raça, religião, '
        'gênero, orientação, deficiência, origem). Discordar pode; atacar a '
        'pessoa, não.',
  ),
  (
    'Nada de conteúdo sexual explícito',
    'E nunca, em hipótese alguma, nada que envolva criança ou adolescente. '
        'Isso é denunciado às autoridades.',
  ),
  (
    'Privacidade dos outros',
    'Não publique foto, endereço, telefone ou conversa de ninguém sem '
        'permissão.',
  ),
  (
    'Sem golpe nem spam',
    'Nada de corrente, pirâmide, link suspeito ou propaganda repetida.',
  ),
  (
    'Informação com responsabilidade',
    'Antes de espalhar notícia, confira a fonte. Saúde e eleições, mais '
        'ainda.',
  ),
  (
    'Cuidado com quem está mal',
    'Se alguém parecer em risco, ofereça ajuda e use "Denunciar → Risco à '
        'própria vida": a moderação olha com prioridade.',
  ),
  (
    'Denúncia e moderação',
    'Qualquer pessoa pode denunciar. A moderação pode apagar conteúdo e '
        'suspender contas. Quem convidou alguém ajuda a cuidar da rede.',
  ),
];

class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('rules_screen'),
      appBar: AppBar(title: const Text('Regras de convivência')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'A HumanNet é uma rede de gente que se conhece. Estas regras '
            'valem para posts, comentários, comunidades, recados, depoimentos '
            'e fotos.',
          ),
          const SizedBox(height: 16),
          for (final (i, (title, body)) in communityRules.indexed) ...[
            Text('${i + 1}. $title', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(body),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}
