import 'package:flutter/material.dart';

import '../feed/interests.dart';

/// "Meus interesses": o que o "Para você" aprendeu, tudo editável. Fica só
/// neste aparelho (ADR-0004).
class InterestsScreen extends StatelessWidget {
  const InterestsScreen({super.key, required this.profile});

  final InterestProfile profile;

  Future<void> _politicsConsent(BuildContext context, bool on) async {
    if (!on) {
      await profile.setPoliticsDetail(false);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aprender detalhes de Política?'),
        content: const Text(
          'Com isto ligado, o "Para você" aprende também as hashtags e as '
          'pessoas dos posts de Política que você curte e comenta. Na prática '
          'ele passa a refletir a sua inclinação política.\n\n'
          'Opinião política é dado sensível (LGPD). Por isso este aprendizado '
          'fica só no seu celular: a HumanNet não recebe nem guarda. Você pode '
          'desligar quando quiser, e o que foi aprendido em Política é apagado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Agora não'),
          ),
          FilledButton(
            key: const Key('politics_consent_yes'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Concordo, ligar'),
          ),
        ],
      ),
    );
    if (ok == true) await profile.setPoliticsDetail(true);
  }

  Widget _section(
    BuildContext context,
    String title,
    Map<String, double> m,
    String Function(String) label,
  ) {
    final entries = m.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(title, style: theme.textTheme.titleSmall),
        ),
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('Nada ainda.'),
          ),
        for (final e in entries)
          ListTile(
            key: Key('interest_${e.key}'),
            dense: true,
            title: Text(label(e.key)),
            subtitle: Slider(
              value: e.value.clamp(0, 20),
              max: 20,
              onChanged: (v) => profile.setWeight(m, e.key, v),
            ),
            trailing: IconButton(
              key: Key('remove_interest_${e.key}'),
              tooltip: 'Apagar',
              icon: const Icon(Icons.close),
              onPressed: () => profile.remove(m, e.key),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: profile,
      builder: (context, _) => Scaffold(
        key: const Key('interests_screen'),
        appBar: AppBar(title: const Text('Meus interesses')),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'É isto que ordena o "Para você". Aprende só quando você curte '
                '(peso 1) ou comenta (peso 2), nunca pelo tempo de tela. Fica '
                'só neste celular. Ajuste, apague ou pause quando quiser.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            SwitchListTile(
              key: const Key('interests_paused'),
              value: profile.paused,
              onChanged: profile.setPaused,
              title: const Text('Pausar o aprendizado'),
            ),
            SwitchListTile(
              key: const Key('politics_detail'),
              value: profile.politicsDetail,
              onChanged: (v) => _politicsConsent(context, v),
              title: const Text('Aprender detalhes de Política'),
              subtitle: const Text(
                'Desligado: aprende só que você curte "Política". Ligado: '
                'aprende também hashtags e pessoas desses posts.',
              ),
            ),
            _section(context, 'Temas', profile.topics, topicLabel),
            _section(context, 'Hashtags', profile.tags, (t) => '#$t'),
            _section(context, 'Pessoas', profile.people, (u) => '@$u'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                'Temas que você não quer ver no "Para você"',
                style: theme.textTheme.titleSmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 6,
                children: [
                  for (final t in appTopics)
                    FilterChip(
                      key: Key('hide_${t.id}'),
                      label: Text(t.label),
                      selected: profile.hiddenTopics.contains(t.id),
                      onSelected: (v) => profile.setHidden(t.id, v),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                key: const Key('interests_reset'),
                onPressed: profile.isEmpty ? null : profile.reset,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Zerar o que foi aprendido'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
