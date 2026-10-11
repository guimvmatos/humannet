import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import 'error_messages.dart';

/// Versão dos Termos/Privacidade que este app mostra e manda no aceite
/// (igual a `TERMS_VERSION` do servidor).
const termsVersion = 2;

/// Link para abrir os Termos ou a Política (usado no cadastro e no aceite).
class LegalLink extends StatelessWidget {
  const LegalLink.terms({super.key, required this.api})
    : kind = 'termos',
      label = 'Termos de Uso';
  const LegalLink.privacy({super.key, required this.api})
    : kind = 'privacidade',
      label = 'Privacidade';

  final ApiClient api;
  final String kind;
  final String label;

  @override
  Widget build(BuildContext context) => TextButton(
    key: Key('read_$kind'),
    style: TextButton.styleFrom(padding: EdgeInsets.zero),
    onPressed: () => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => LegalScreen(api: api, kind: kind)),
    ),
    child: Text(label),
  );
}

/// Mostra o texto público do servidor (`/legal/termos` ou
/// `/legal/privacidade`), em Markdown simples.
class LegalScreen extends StatefulWidget {
  const LegalScreen({super.key, required this.api, required this.kind});

  final ApiClient api;
  final String kind;

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  late Future<String> _text = widget.api.legalText(widget.kind);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: Key('legal_${widget.kind}'),
      appBar: AppBar(
        title: Text(
          widget.kind == 'termos' ? 'Termos de Uso' : 'Política de Privacidade',
        ),
      ),
      body: FutureBuilder<String>(
        future: _text,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(errorMessage(snap.error!)),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => setState(
                        () => _text = widget.api.legalText(widget.kind),
                      ),
                      child: const Text('Tentar de novo'),
                    ),
                  ],
                ),
              ),
            );
          }
          final text = snap.data;
          if (text == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return SelectionArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: markdownBlocks(context, text),
            ),
          );
        },
      ),
    );
  }
}

/// Markdown mínimo dos nossos textos: títulos (#, ##), listas (-), tabelas
/// (viram itens "a — b") e **negrito**.
List<Widget> markdownBlocks(BuildContext context, String md) {
  final t = Theme.of(context).textTheme;
  final out = <Widget>[];
  List<String>? header;
  for (final raw in md.split('\n')) {
    final line = raw.trimRight();
    if (line.isEmpty) {
      header = null;
      continue;
    }
    if (line.startsWith('|')) {
      final cells = line
          .split('|')
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty)
          .toList();
      if (cells.every((c) => RegExp(r'^:?-+:?$').hasMatch(c))) continue;
      if (header == null) {
        header = cells;
        continue;
      }
      out.add(
        _bullet(
          context,
          [
            for (final (i, c) in cells.indexed)
              i == 0 ? '**$c**' : '${header.elementAtOrNull(i) ?? ''}: $c',
          ].join(' — '),
        ),
      );
      continue;
    }
    if (line.startsWith('# ')) {
      out.add(
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(line.substring(2), style: t.headlineSmall),
        ),
      );
    } else if (line.startsWith('## ')) {
      out.add(
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(line.substring(3), style: t.titleMedium),
        ),
      );
    } else if (line.startsWith('- ')) {
      out.add(_bullet(context, line.substring(2)));
    } else {
      out.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text.rich(_rich(line, t.bodyMedium)),
        ),
      );
    }
  }
  return out;
}

Widget _bullet(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('•  '),
      Expanded(
        child: Text.rich(_rich(text, Theme.of(context).textTheme.bodyMedium)),
      ),
    ],
  ),
);

TextSpan _rich(String text, TextStyle? style) {
  final parts = text.split('**');
  return TextSpan(
    style: style,
    children: [
      for (final (i, p) in parts.indexed)
        TextSpan(
          text: p,
          style: i.isOdd ? const TextStyle(fontWeight: FontWeight.bold) : null,
        ),
    ],
  );
}

/// Contas que ainda não aceitaram a versão vigente veem esta tela antes de
/// seguir (como a do CPF).
class TermsGateScreen extends StatefulWidget {
  const TermsGateScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<TermsGateScreen> createState() => _TermsGateScreenState();
}

class _TermsGateScreenState extends State<TermsGateScreen> {
  bool _checked = false;
  bool _busy = false;
  String? _error;

  Future<void> _accept() async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.api.acceptTerms(token, termsVersion);
      await widget.session.refreshUser();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = widget.session.api;
    return Scaffold(
      key: const Key('terms_gate'),
      appBar: AppBar(
        title: const Text('Termos e privacidade'),
        actions: [
          TextButton(
            onPressed: widget.session.logout,
            child: const Text('Sair'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'A HumanNet publicou os Termos de Uso e a Política de '
            'Privacidade. Resumo: posts são públicos; o post leva só uma '
            'área aproximada (desviada até ~1,5 km); não vendemos dados nem '
            'mostramos anúncios; o beta é só para maiores de 18 anos.',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            children: [LegalLink.terms(api: api), LegalLink.privacy(api: api)],
          ),
          CheckboxListTile(
            key: const Key('terms_gate_check'),
            value: _checked,
            onChanged: (v) => setState(() => _checked = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Tenho 18 anos ou mais e aceito os Termos de Uso e a Política '
              'de Privacidade',
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('terms_gate_accept'),
            onPressed: _busy || !_checked ? null : _accept,
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }
}
