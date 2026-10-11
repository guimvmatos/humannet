import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humannet/src/theme/theme_controller.dart';

void main() {
  test('fonte escolhida vale no app inteiro e fica salva', () async {
    final store = InMemoryPrefsStore();
    final themes = ThemeController(store);
    await themes.load();
    expect(themes.light.textTheme.bodyMedium?.fontFamily, isNot('VT323'));

    final pixel = appFonts.firstWhere((f) => f.id == 'pixel');
    final before =
        Typography.material2021().englishLike.bodyMedium!.fontSize!;
    await themes.setFont(pixel);
    expect(themes.light.textTheme.bodyMedium?.fontFamily, 'VT323');
    expect(themes.dark.textTheme.titleLarge?.fontFamily, 'VT323');
    expect(themes.light.textTheme.bodyMedium!.fontSize, closeTo(before * 1.3, 0.01));

    final again = ThemeController(store);
    await again.load();
    expect(again.font.id, 'pixel');
  });
}
