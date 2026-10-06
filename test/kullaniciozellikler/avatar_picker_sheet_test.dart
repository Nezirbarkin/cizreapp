import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cizreapp/features/profile/models/character_avatar_recipes.dart';
import 'package:cizreapp/features/profile/widgets/avatar_picker_sheet.dart';

/// Hazır avatar seçici (Görev 2.6 sonrası): iki sekme (Kız & Erkek /
/// Hareketli). Klasik düz illüstrasyonlar ve eski geometrik GIF'ler kaldırıldı;
/// gerçekçi karakter seti 140'a çıktı ve yeni 40'lık set "Hepsi"nde öne alınır.
/// Listelenen her dosya diskte gerçekten bulunmalı, kaldırılanlar paketten
/// çıkmış olmalı.
void main() {
  Finder assetImage(String path) => find.byWidgetPredicate(
    (w) =>
        w is Image &&
        w.image is AssetImage &&
        (w.image as AssetImage).assetName == path,
  );

  Future<String?> Function() openPicker(
    WidgetTester tester, {
    String? selected,
  }) {
    String? picked;
    return () async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  picked = await showPresetAvatarPicker(
                    context,
                    selected: selected,
                  );
                },
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      return picked;
    };
  }

  test('avatar listeleri: beklenen sayı, benzersiz yol, doğru klasör', () {
    expect(kCharacterAvatars.length, 140);
    expect(kAnimatedAvatars.length, kAnimatedAvatarLast - kAnimatedAvatarFirst + 1);
    expect(kAnimatedAvatars.first, 'assets/avatars_animated/avatar_anim_56.gif');
    expect(
      kAllPresetAvatars.length,
      kCharacterAvatars.length + kAnimatedAvatars.length,
    );
    expect(
      kAllPresetAvatars.toSet().length,
      kAllPresetAvatars.length,
      reason: 'tüm hazır avatar yolları benzersiz olmalı',
    );

    for (final p in kCharacterAvatars) {
      expect(p, startsWith('assets/avatars_characters/'));
      expect(p, endsWith('.png'));
      expect(isAnimatedAvatarAsset(p), isFalse);
    }
    for (final p in kAnimatedAvatars) {
      expect(p, startsWith('assets/avatars_animated/'));
      expect(isAnimatedAvatarAsset(p), isTrue);
    }
  });

  test('listelenen her avatar diskte var; kaldırılan setler paketten çıktı', () {
    for (final p in kAllPresetAvatars) {
      expect(File(p).existsSync(), isTrue, reason: '$p diskte yok');
    }

    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final dir in const ['assets/avatars_animated/', 'assets/avatars_characters/']) {
      expect(pubspec, contains('- $dir'), reason: '$dir pubspec.yaml assets listesinde yok');
    }
    // Klasik düz illüstrasyonlar ve geometrik GIF'ler artık uygulamada yok.
    expect(pubspec, isNot(contains('- assets/avatars/\n')));
    expect(pubspec, isNot(contains('- assets/avatars/\r\n')));
    expect(Directory('assets/avatars').existsSync(), isFalse);
    for (var i = 1; i < kAnimatedAvatarFirst; i++) {
      final old = 'assets/avatars_animated/avatar_anim_${i.toString().padLeft(2, '0')}.gif';
      expect(File(old).existsSync(), isFalse, reason: '$old kaldırılmalıydı');
    }
  });

  test('tarifler: 70 erkek + 70 kadın, yeni set dengeli', () {
    expect(kCharacterRecipes.length, kCharacterAvatarCount);
    expect(kCharacterRecipes.where((r) => r.female).length, 70);
    final fresh = kCharacterRecipes.sublist(kNewCharacterFirst - 1);
    expect(fresh.length, 40);
    expect(fresh.where((r) => r.female).length, 20);
    // Yeni sette tarifler birbirinden farklı (aynı karakter iki kez yok).
    expect(fresh.map((r) => r.config).toSet().length, fresh.length);
  });

  testWidgets('seçici iki sekme gösterir; yeni gerçekçi set önde açılır', (tester) async {
    await openPicker(tester)();

    expect(find.text('Hazır Avatar Seç'), findsOneWidget);
    expect(find.text('Kız & Erkek (${kCharacterAvatars.length})'), findsOneWidget);
    expect(find.text('Hareketli (${kAnimatedAvatars.length})'), findsOneWidget);
    expect(find.textContaining('Klasik'), findsNothing);

    expect(assetImage(kCharacterAvatars[kNewCharacterFirst - 1]), findsOneWidget);
    expect(find.text('Yeni (40)'), findsOneWidget);
  });

  testWidgets('karakter seçimi asset yolunu döndürür', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => picked = await showPresetAvatarPicker(context),
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();

    final first = assetImage(kCharacterAvatars[kNewCharacterFirst - 1]);
    await tester.tap(find.ancestor(of: first, matching: find.byType(InkWell)));
    await tester.pumpAndSettle();

    expect(picked, kCharacterAvatars[kNewCharacterFirst - 1]);
    expect(find.text('Hazır Avatar Seç'), findsNothing);
  });

  testWidgets('hareketli sekmesine geçilip seçim yapılabilir', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => picked = await showPresetAvatarPicker(context),
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hareketli (${kAnimatedAvatars.length})'));
    await tester.pumpAndSettle();

    final firstAnimated = assetImage(kAnimatedAvatars.first);
    expect(firstAnimated, findsOneWidget);
    await tester.tap(find.ancestor(of: firstAnimated, matching: find.byType(InkWell)));
    await tester.pumpAndSettle();

    expect(picked, kAnimatedAvatars.first);
  });

  testWidgets('hareketli avatar seçiliyken hareketli sekmesi açık gelir', (tester) async {
    await openPicker(tester, selected: kAnimatedAvatars.first)();
    expect(assetImage(kAnimatedAvatars.first), findsOneWidget);
    expect(assetImage(kCharacterAvatars[kNewCharacterFirst - 1]), findsNothing);
  });

  testWidgets('kız & erkek sekmesi yeni sete ve cinsiyete göre süzülür', (tester) async {
    await openPicker(tester)();

    // İlk karakter erkek, 13. karakter kadın (bkz. character_avatar_recipes).
    expect(isFemaleCharacter(0), isFalse);
    expect(isFemaleCharacter(12), isTrue);

    await tester.tap(find.text('Kadın'));
    await tester.pumpAndSettle();
    expect(assetImage(kCharacterAvatars[12]), findsOneWidget);
    expect(assetImage(kCharacterAvatars[0]), findsNothing);

    await tester.tap(find.text('Erkek'));
    await tester.pumpAndSettle();
    expect(assetImage(kCharacterAvatars[0]), findsOneWidget);
    expect(assetImage(kCharacterAvatars[12]), findsNothing);

    await tester.tap(find.text('Yeni (40)'));
    await tester.pumpAndSettle();
    expect(assetImage(kCharacterAvatars[kNewCharacterFirst - 1]), findsOneWidget);
    expect(assetImage(kCharacterAvatars[0]), findsNothing);
  });
}
