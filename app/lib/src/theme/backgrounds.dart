import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Fundos ilustrados dos temas. Desenhados no código (arte original, sem
/// imagem de terceiros e sem baixar nada).
enum AppBackground { none, medieval, neon, manga, space, forest, beach }

/// Desenha o fundo escolhido por trás de todas as telas, com um véu da cor
/// da superfície por cima para o texto continuar legível.
class ThemedBackground extends StatelessWidget {
  const ThemedBackground({
    super.key,
    required this.background,
    required this.child,
    this.photoPath,
    this.strength = 0.35,
  });

  final AppBackground background;

  /// Foto da galeria (tem prioridade sobre o fundo ilustrado).
  final String? photoPath;

  /// Quanto o fundo aparece (0 = nada, 1 = tudo).
  final double strength;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final photo = photoPath;
    if (background == AppBackground.none && photo == null) return child;
    final surface = Theme.of(context).colorScheme.surface;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (photo != null)
          Image.file(
            File(photo),
            key: const Key('photo_background'),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          )
        else
          CustomPaint(
            key: const Key('themed_background'),
            painter: BackgroundPainter(background),
          ),
        ColoredBox(
          color: surface.withValues(alpha: 1 - strength.clamp(0.1, 0.8)),
        ),
        child,
      ],
    );
  }
}

class BackgroundPainter extends CustomPainter {
  const BackgroundPainter(this.kind);

  final AppBackground kind;

  @override
  void paint(Canvas canvas, Size size) {
    switch (kind) {
      case AppBackground.none:
        return;
      case AppBackground.medieval:
        _medieval(canvas, size);
      case AppBackground.neon:
        _neon(canvas, size);
      case AppBackground.manga:
        _manga(canvas, size);
      case AppBackground.space:
        _space(canvas, size);
      case AppBackground.forest:
        _forest(canvas, size);
      case AppBackground.beach:
        _beach(canvas, size);
    }
  }

  @override
  bool shouldRepaint(BackgroundPainter old) => old.kind != kind;

  static void _gradient(Canvas c, Size s, List<Color> colors) {
    final rect = Offset.zero & s;
    c.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ).createShader(rect),
    );
  }

  /// Serras, um castelo em silhueta e brasas subindo.
  static void _medieval(Canvas c, Size s) {
    _gradient(c, s, const [
      Color(0xFF1B1F3B),
      Color(0xFF4A2C40),
      Color(0xFF8C3B2A),
    ]);
    final w = s.width, h = s.height;
    final hills = Path()
      ..moveTo(0, h * 0.72)
      ..lineTo(w * 0.18, h * 0.6)
      ..lineTo(w * 0.35, h * 0.7)
      ..lineTo(w * 0.55, h * 0.56)
      ..lineTo(w * 0.78, h * 0.68)
      ..lineTo(w, h * 0.6)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    c.drawPath(hills, Paint()..color = const Color(0xFF2B1A22));
    // Castelo: torres com ameias.
    final castle = Paint()..color = const Color(0xFF140D14);
    final base = h * 0.62;
    final x0 = w * 0.48;
    c.drawRect(Rect.fromLTWH(x0, base - h * 0.06, w * 0.22, h * 0.08), castle);
    for (final (dx, th) in [(0.0, 0.14), (0.08, 0.1), (0.17, 0.16)]) {
      final tx = x0 + w * dx;
      final top = base - h * th;
      c.drawRect(Rect.fromLTWH(tx, top, w * 0.05, h * th), castle);
      for (var i = 0; i < 3; i++) {
        c.drawRect(
          Rect.fromLTWH(tx + i * w * 0.02, top - h * 0.012, w * 0.012, h * 0.012),
          castle,
        );
      }
    }
    final r = math.Random(7);
    for (var i = 0; i < 70; i++) {
      c.drawCircle(
        Offset(r.nextDouble() * w, h * (0.3 + r.nextDouble() * 0.7)),
        0.8 + r.nextDouble() * 1.8,
        Paint()
          ..color = Color.lerp(
            const Color(0xFFFFB74D),
            const Color(0xFFFF5722),
            r.nextDouble(),
          )!.withValues(alpha: 0.5 + r.nextDouble() * 0.5),
      );
    }
  }

  /// Sol listrado e grade em perspectiva (estética retrô dos anos 80).
  static void _neon(Canvas c, Size s) {
    _gradient(c, s, const [
      Color(0xFF12002B),
      Color(0xFF3D0B5C),
      Color(0xFF7A1360),
    ]);
    final w = s.width, h = s.height;
    final horizon = h * 0.6;
    final sun = Offset(w / 2, horizon - h * 0.02);
    final radius = math.min(w, h) * 0.22;
    final sunRect = Rect.fromCircle(center: sun, radius: radius);
    c.save();
    c.clipRect(Rect.fromLTRB(0, 0, w, horizon));
    c.drawCircle(
      sun,
      radius,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE066), Color(0xFFFF2E93)],
        ).createShader(sunRect),
    );
    final gap = Paint()..color = const Color(0xFF3D0B5C);
    for (var i = 0; i < 5; i++) {
      final y = sun.dy + radius * (0.15 + i * 0.18);
      c.drawRect(Rect.fromLTWH(0, y, w, 2.0 + i * 1.5), gap);
    }
    c.restore();
    c.drawRect(
      Rect.fromLTRB(0, horizon, w, h),
      Paint()..color = const Color(0xFF14002E),
    );
    final line = Paint()
      ..color = const Color(0xFF00E5FF)
      ..strokeWidth = 1.4;
    for (var i = 0; i <= 10; i++) {
      final t = i / 10;
      final y = horizon + (h - horizon) * t * t;
      c.drawLine(Offset(0, y), Offset(w, y), line);
    }
    for (var i = -12; i <= 12; i++) {
      c.drawLine(
        Offset(w / 2 + i * w * 0.02, horizon),
        Offset(w / 2 + i * w * 0.2, h),
        line,
      );
    }
  }

  /// Linhas de velocidade e retícula, como página de mangá.
  static void _manga(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFFFF4E0));
    final w = s.width, h = s.height;
    final center = Offset(w * 0.5, h * 0.4);
    final r = math.Random(3);
    final ray = Paint()..color = const Color(0xFFFF6D00);
    for (var i = 0; i < 90; i++) {
      final a = i / 90 * 2 * math.pi + r.nextDouble() * 0.03;
      final inner = math.min(w, h) * (0.18 + r.nextDouble() * 0.12);
      final far = math.max(w, h) * 1.2;
      final spread = 0.006 + r.nextDouble() * 0.01;
      final path = Path()
        ..moveTo(center.dx + math.cos(a) * inner, center.dy + math.sin(a) * inner)
        ..lineTo(
          center.dx + math.cos(a - spread) * far,
          center.dy + math.sin(a - spread) * far,
        )
        ..lineTo(
          center.dx + math.cos(a + spread) * far,
          center.dy + math.sin(a + spread) * far,
        )
        ..close();
      c.drawPath(path, ray..color = (i.isEven
          ? const Color(0xFFFF6D00)
          : const Color(0xFF1565C0)).withValues(alpha: 0.55));
    }
    final dot = Paint()..color = const Color(0x33000000);
    for (var y = h * 0.75; y < h; y += 10) {
      for (var x = 0.0; x < w; x += 10) {
        c.drawCircle(Offset(x, y), 1.2 + (y - h * 0.75) / h * 8, dot);
      }
    }
  }

  /// Céu estrelado com nebulosas.
  static void _space(Canvas c, Size s) {
    _gradient(c, s, const [Color(0xFF05061A), Color(0xFF0D1B3D)]);
    final w = s.width, h = s.height;
    for (final (pos, color, size) in [
      (Offset(w * 0.25, h * 0.3), const Color(0x887E57C2), 0.5),
      (Offset(w * 0.8, h * 0.65), const Color(0x6600BCD4), 0.45),
      (Offset(w * 0.55, h * 0.9), const Color(0x55E91E63), 0.35),
    ]) {
      final radius = math.max(w, h) * size;
      c.drawCircle(
        pos,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: pos, radius: radius)),
      );
    }
    final r = math.Random(11);
    final star = Paint()..color = Colors.white;
    for (var i = 0; i < 220; i++) {
      c.drawCircle(
        Offset(r.nextDouble() * w, r.nextDouble() * h),
        r.nextDouble() * 1.4,
        star..color = Colors.white.withValues(alpha: 0.4 + r.nextDouble() * 0.6),
      );
    }
  }

  /// Morros em camadas, do mais claro ao mais escuro.
  static void _forest(Canvas c, Size s) {
    _gradient(c, s, const [Color(0xFFE8F5E9), Color(0xFFB2DFDB)]);
    final w = s.width, h = s.height;
    const layers = [
      Color(0xFF81C784),
      Color(0xFF4CAF50),
      Color(0xFF2E7D32),
      Color(0xFF1B5E20),
    ];
    for (final (i, color) in layers.indexed) {
      final top = h * (0.45 + i * 0.12);
      final path = Path()..moveTo(0, top);
      for (var x = 0.0; x <= w; x += w / 8) {
        path.lineTo(x, top + math.sin(x / w * math.pi * (2 + i) + i) * h * 0.04);
      }
      path
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      c.drawPath(path, Paint()..color = color);
    }
  }

  /// Sol, mar e areia.
  static void _beach(Canvas c, Size s) {
    final w = s.width, h = s.height;
    _gradient(c, s, const [Color(0xFF81D4FA), Color(0xFFE1F5FE)]);
    c.drawCircle(
      Offset(w * 0.78, h * 0.18),
      math.min(w, h) * 0.1,
      Paint()..color = const Color(0xFFFFD54F),
    );
    final sea = Path()..moveTo(0, h * 0.55);
    for (var x = 0.0; x <= w; x += w / 12) {
      sea.lineTo(x, h * 0.55 + math.sin(x / w * math.pi * 6) * 6);
    }
    sea
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    c.drawPath(sea, Paint()..color = const Color(0xFF0288D1));
    final sand = Path()
      ..moveTo(0, h * 0.78)
      ..quadraticBezierTo(w * 0.5, h * 0.7, w, h * 0.8)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    c.drawPath(sand, Paint()..color = const Color(0xFFFFE0B2));
  }
}
