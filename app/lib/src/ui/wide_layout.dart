import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

/// A partir desta largura (notebook, tablet deitado) o app usa o layout
/// largo: menu lateral e conteúdo numa coluna central.
const wideBreakpoint = 900.0;

/// Largura máxima da coluna de conteúdo no layout largo.
const contentMaxWidth = 680.0;

bool isWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= wideBreakpoint;

/// No layout largo, centraliza a tela numa coluna com uma borda discreta; o
/// que sobra dos lados mostra o fundo do app. Em telas estreitas, não faz
/// nada.
class WideFrame extends StatelessWidget {
  const WideFrame({super.key, required this.child, this.maxWidth});

  final Widget child;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    if (!isWide(context)) return child;
    final scheme = Theme.of(context).colorScheme;
    final width = maxWidth ?? contentMaxWidth + 40;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border.symmetric(
              vertical: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          child: MediaQuery.removePadding(
            context: context,
            removeLeft: true,
            removeRight: true,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Aplica o `WideFrame` em todas as telas abertas por cima da principal
/// (post, perfil, conversa...), mantendo a animação de cada plataforma.
class WidePageTransitionsBuilder extends PageTransitionsBuilder {
  const WidePageTransitionsBuilder(this.inner);

  final PageTransitionsBuilder inner;

  @override
  Duration get transitionDuration => inner.transitionDuration;

  @override
  Duration get reverseTransitionDuration => inner.reverseTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      inner.delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => inner.buildTransitions(
    route,
    context,
    animation,
    secondaryAnimation,
    route.isFirst ? child : WideFrame(child: child),
  );
}

/// Transições padrão de cada plataforma, com o `WideFrame`.
PageTransitionsTheme widePageTransitions() => PageTransitionsTheme(
  builders: {
    for (final e in const PageTransitionsTheme().builders.entries)
      e.key: WidePageTransitionsBuilder(e.value),
  },
);

/// Deixa arrastar com o mouse (ex.: passar fotos no notebook).
const mouseDragScroll = _MouseDragScroll();

class _MouseDragScroll extends MaterialScrollBehavior {
  const _MouseDragScroll();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}
