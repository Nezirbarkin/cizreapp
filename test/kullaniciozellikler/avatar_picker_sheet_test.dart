import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cizreapp/features/profile/models/character_avatar_recipes.dart';
import 'package:cizreapp/features/profile/widgets/avatar_picker_sheet.dart';

/// Hazır avatar seçici: üç sekme (Kız & Erkek / Hareketli / Klasik) listelenmeli,
/// her sekmeden seçim asset yolunu döndürmeli ve listelenen her dosya diskte
/// gerçekten bulunmalı.
///
/// NOT: Bu test daha önce tek listeli seçici için yazılmıştı; "Hareketli" sekmesi
/// öne alındığında güncellenmediği için kırık kalmıştı (TabBarView yalnız aktif
/// sekmeyi kurar, dolayısıyla klasik listenin ilk avatarı ağaçta olmuyordu).
/// Artık hangi sekmenin açık olduğu testin parçası.
void main() {
  Finder assetImage(String path) => find.byWidgetPredicate(
    (w) =>
        w is Image &&
        w.image is AssetImage &&
        (w.image as AssetImage).assetName == path,
  );

  Future<String?> openPicker(WidgetTester tester, {String? selected}) async {
    String? picked;
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
  }

  test('avatar listeleri: beklenen sayı, benzersiz yol, doğru klasör', () {
    expect(kCharacterAvatars.length, 100);
    expect(kAnimatedAvatars.length, 79);
    expect(kPresetAvatars.length, 20);

    expect(
      kAllPresetAvatars.length,
      kCharacterAvatars.length + kAnimatedAvatars.length + kPresetAvatars.length,
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
    for (final p in kPresetAvatars) {
      expect(p, startsWith('assets/avatars/'));
      expect(isAnimatedAvatarAsset(p), isFalse);
    }
  });

  test('listelenen her avatar dosyası diskte var ve pubspec\'te tanımlı', () {
    for (final p in kAllPresetAvatars) {
      expect(File(p).existsSync(), isTrue, reason: '$p diskte yok');
    }

    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final dir in <String>{
      'assets/avatars/',
      'assets/avatars_animated/',
      'assets/avatars_characters/',
    }) {
      expect(
        pubspec,
        contains('- $dir'),
        reason: '$dir pubspec.yaml assets listesinde yok',
      );
    }
  });

  testWidgets('seçici üç sekme gösterir ve kız/erkek sekmesiyle açılır', (
    tester,
  ) async {
    await openPicker(tester);

    expect(find.text('Hazır Avatar Seç'), findsOneWidget);
    expect(find.text('Kız & Erkek (${kCharacterAvatars.length})'), findsOneWidget);
    expect(find.text('Hareketli (${kAnimatedAvatars.length})'), findsOneWidget);
    expect(find.text('Klasik (${kPresetAvatars.length})'), findsOneWidget);

    // Seçim yoksa yeni karakter seti önde açılır.
    expect(assetImage(kCharacterAvatars.first), findsOneWidget);
  });

  testWidgets('kız/erkek avatarı seçimi asset yolunu döndürür', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                picked = await showPresetAvatarPicker(context);
              },
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();

    final first = assetImage(kCharacterAvatars.first);
    expect(first, findsOneWidget);

    await tester.tap(find.ancestor(of: first, matching: find.byType(InkWell)));
    await tester.pumpAndSettle();

    expect(picked, kCharacterAvatars.first);
    expect(find.text('Hazır Avatar Seç'), findsNothing);
  });

  testWidgets('klasik sekmesine geçilip seçim yapılabilir', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                picked = await showPresetAvatarPicker(context);
              },
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Klasik (${kPresetAvatars.length})'));
    await tester.pumpAndSettle();

    final firstClassic = assetImage(kPresetAvatars.first);
    expect(firstClassic, findsOneWidget);

    await tester.tap(
      find.ancestor(of: firstClassic, matching: find.byType(InkWell)),
    );
    await tester.pumpAndSettle();

    expect(picked, kPresetAvatars.first);
  });

  testWidgets('seçili avatar hangi sekmedeyse o sekmeyle açılır', (
    tester,
  ) async {
    // Klasik listeden seçiliyken klasik sekmesi açık gelir. (Grid tembel
    // kurulur; ekranda olmayan alt satırlar ağaçta bulunmaz, bu yüzden
    // görünür olduğu kesin olan ilk avatar üzerinden doğrulanır.)
    await openPicker(tester, selected: kPresetAvatars.first);
    expect(assetImage(kPresetAvatars.first), findsOneWidget);
    expect(assetImage(kCharacterAvatars.first), findsNothing);
  });

  testWidgets('hareketli avatar seçiliyken hareketli sekmesi açık gelir', (
    tester,
  ) async {
    await openPicker(tester, selected: kAnimatedAvatars.first);
    // "Şık" avatarlar sekmede öne alınır; ilk görünen onlardan biridir.
    expect(assetImage(kAnimatedAvatars[kElegantAnimatedFirst - 1]), findsOneWidget);
    expect(assetImage(kPresetAvatars.first), findsNothing);
    expect(assetImage(kCharacterAvatars.first), findsNothing);
  });

  testWidgets('kız & erkek sekmesi cinsiyete göre süzülür', (tester) async {
    await openPicker(tester);

    // İlk karakter erkek, 13. karakter kadın (bkz. character_avatar_recipes).
    expect(isFemaleCharacter(0), isFalse);
    expect(isFemaleCharacter(12), isTrue);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Kadın'));
    await tester.pumpAndSettle();
    expect(assetImage(kCharacterAvatars[0]), findsNothing, reason: 'erkek gizlenmeli');
    expect(assetImage(kCharacterAvatars[12]), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Erkek'));
    await tester.pumpAndSettle();
    expect(assetImage(kCharacterAvatars[0]), findsOneWidget);
    expect(assetImage(kCharacterAvatars[12]), findsNothing);

    // Süzülen listelerin toplamı tüm listeyi verir (50 + 50).
    final females = [for (var i = 0; i < kCharacterAvatars.length; i++) isFemaleCharacter(i)];
    expect(females.where((f) => f).length, 50);
    expect(females.where((f) => !f).length, 50);
  });
}
