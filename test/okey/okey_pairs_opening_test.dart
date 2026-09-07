import 'package:cizreapp/okey/okey.dart';
import 'package:cizreapp/okey/widgets/okey_action_panel_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// "NEDEN ÇİFT AÇAMIYORUM" — 2026-09-05
///
/// İki ayrı kusur birleşince çiftle açmak pratikte imkânsız hale geliyordu:
///
///  1. ÇİFT DİZ, gösterge çiftini (RULES.md §8) ve joker çiftlerini KENDİ
///     öbeklerine ayırmıyordu. Per sayımı [OkeyRackLayout.contiguousGroups]
///     üzerine kurulu olduğu için, ayrı bir öbek olmayan hiçbir şey çift
///     sayılamaz — yani kural kâğıt üzerinde vardı, masada yoktu.
///
///  2. ÇİFT AÇ düğmesi kapalıyken sebebini söylemiyordu; rozette "5/5"
///     yazarken düğmenin sönük kalması oyuncunun çözemeyeceği bir kilitti.
///
/// Bu dosya ikisinin de geri gelmesini engeller.
void main() {
  // Gösterge: Kırmızı 7 → okey taşı: Kırmızı 8
  final indicator = OkeyTile.numbered(OkeyColor.red, 7);
  final okeyTile = OkeyTile.numbered(OkeyColor.red, 8);
  OkeyTile t(OkeyColor c, int n) => OkeyTile.numbered(c, n);

  /// Istaka yerleşiminden ÇİFT sayılabilecek öbekleri çıkarır — masadaki
  /// sayımın (OkeyGameProvider.detectedPairGroups) birebir aynısı.
  int countPairs(List<OkeyTile?> slots) =>
      OkeyRackLayout.contiguousGroups(slots)
          .where(
            (g) =>
                OkeyMeldValidator.isValidPairEx(g.tiles, okeyTile, indicator),
          )
          .length;

  group('ÇİFT DİZ — gösterge çifti', () {
    test('gösterge taşı KENDİ öbeğine ayrılır', () {
      final groups = OkeyRackLayout.groupByPairs(
        [t(OkeyColor.blue, 3), indicator, t(OkeyColor.black, 12)],
        okeyTile,
        indicatorTile: indicator,
      );
      expect(
        groups.any((g) => g.length == 1 && g.first == indicator),
        isTrue,
        reason: 'gösterge tek başına bir çifttir (RULES.md §8)',
      );
    });

    test('4 gerçek çift + gösterge = 5 çift sayılır', () {
      // 101 Okey barajı 5 çift. Bu el TAM SINIRDA: gösterge sayılmazsa
      // oyuncu açamaz, sayılırsa açar. Hatanın oyuncuya göründüğü yer burası.
      final hand = <OkeyTile>[
        t(OkeyColor.blue, 3), t(OkeyColor.blue, 3),
        t(OkeyColor.black, 12), t(OkeyColor.black, 12),
        t(OkeyColor.yellow, 5), t(OkeyColor.yellow, 5),
        t(OkeyColor.red, 11), t(OkeyColor.red, 11),
        indicator, // 5. çift: göstergenin tek kopyası
        t(OkeyColor.blue, 1), // eşsiz artık
        t(OkeyColor.black, 6),
      ];

      final slots = OkeyRackLayout.buildSorted(
        hand,
        okeyTile,
        byPairs: true,
        indicatorTile: indicator,
      );

      expect(countPairs(slots), 5);
    });

    test('gösterge verilmezse eski davranış: 4 çift (regresyon tanığı)', () {
      // indicatorTile geçilmezse gösterge taşı eşsizler yığınına gömülür.
      // Bu testin AMACI hatayı korumak değil, ÇAĞIRANIN göstergeyi geçmek
      // ZORUNDA olduğunu belgelemek (bkz. OkeyGameProvider.setSortMode).
      final hand = <OkeyTile>[
        t(OkeyColor.blue, 3),
        t(OkeyColor.blue, 3),
        t(OkeyColor.black, 12),
        t(OkeyColor.black, 12),
        t(OkeyColor.yellow, 5),
        t(OkeyColor.yellow, 5),
        t(OkeyColor.red, 11),
        t(OkeyColor.red, 11),
        indicator,
        t(OkeyColor.blue, 1),
      ];
      final slots = OkeyRackLayout.buildSorted(hand, okeyTile, byPairs: true);
      expect(countPairs(slots), 4);
    });
  });

  group('ÇİFT DİZ — jokerler', () {
    test('iki okey taşı bir çift olarak ayrılır', () {
      final hand = <OkeyTile>[
        okeyTile, okeyTile, // okeyin iki kopyası = geçerli çift
        t(OkeyColor.blue, 1),
      ];
      final slots = OkeyRackLayout.buildSorted(
        hand,
        okeyTile,
        byPairs: true,
        indicatorTile: indicator,
      );
      expect(countPairs(slots), 1);
    });

    test('dört joker İKİ çift olur (tek yığında kalmaz)', () {
      // Eskiden dördü tek bir öbekte toplanıyordu; dört taşlık bir öbek
      // çift DEĞİLDİR, dolayısıyla hiçbiri sayılmıyordu.
      final hand = <OkeyTile>[
        okeyTile,
        okeyTile,
        const OkeyTile.falseJoker(),
        const OkeyTile.falseJoker(),
        t(OkeyColor.blue, 1),
      ];
      final slots = OkeyRackLayout.buildSorted(
        hand,
        okeyTile,
        byPairs: true,
        indicatorTile: indicator,
      );
      expect(countPairs(slots), 2);
    });

    test('tek joker çift sayılmaz, eşsizlere düşer', () {
      final hand = <OkeyTile>[
        okeyTile,
        t(OkeyColor.blue, 1),
        t(OkeyColor.blue, 2),
      ];
      final slots = OkeyRackLayout.buildSorted(
        hand,
        okeyTile,
        byPairs: true,
        indicatorTile: indicator,
      );
      expect(countPairs(slots), 0);
      expect(OkeyRackLayout.tilesOf(slots).length, 3, reason: 'taş kaybolmaz');
    });
  });

  group('ÇİFT DİZ — taşlar kaybolmaz', () {
    test('22 taşlık tam el eksiksiz yerleşir', () {
      final hand = <OkeyTile>[
        for (var n = 1; n <= 11; n++) ...[
          t(OkeyColor.blue, n),
          t(OkeyColor.blue, n),
        ],
      ];
      final slots = OkeyRackLayout.buildSorted(
        hand,
        okeyTile,
        byPairs: true,
        indicatorTile: indicator,
      );
      expect(OkeyRackLayout.tilesOf(slots).length, 22);
    });
  });

  group('Kapalı düğme sebebini söyler', () {
    testWidgets('KAPALI düğmeye dokunmak onBlockedTap tetikler', (
      tester,
    ) async {
      var explained = 0;
      var pressed = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 120,
                height: 46,
                child: OkeyActionButton(
                  title: 'ÇİFT AÇ',
                  icon: Icons.filter_2,
                  badge: '5/5',
                  enabled: false,
                  onPressed: () => pressed++,
                  onBlockedTap: () => explained++,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('ÇİFT AÇ'));
      await tester.pump();

      expect(explained, 1, reason: 'sebep sorulmuş olmalı');
      expect(pressed, 0, reason: 'kapalı düğme hamleyi DENEMEZ');
    });

    testWidgets('AÇIK düğme normal hamleyi yapar, sebep sormaz', (
      tester,
    ) async {
      var explained = 0;
      var pressed = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 120,
                height: 46,
                child: OkeyActionButton(
                  title: 'ÇİFT AÇ',
                  icon: Icons.filter_2,
                  enabled: true,
                  onPressed: () => pressed++,
                  onBlockedTap: () => explained++,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('ÇİFT AÇ'));
      await tester.pump();

      expect(pressed, 1);
      expect(explained, 0);
    });
  });
}
