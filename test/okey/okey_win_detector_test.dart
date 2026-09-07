import 'package:cizreapp/okey/okey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Gösterge: 7 Kırmızı -> okey taşı: 8 Kırmızı.
  final okeyTile = OkeyTile.numbered(OkeyColor.red, 8);
  OkeyTile t(OkeyColor c, int n) => OkeyTile.numbered(c, n);

  // 46 + 39 + 18 = 103 puanlık geçerli açılış
  List<List<OkeyTile>> validOpening() => [
    [
      t(OkeyColor.red, 10),
      t(OkeyColor.red, 11),
      t(OkeyColor.red, 12),
      t(OkeyColor.red, 13),
    ],
    [t(OkeyColor.blue, 13), t(OkeyColor.black, 13), t(OkeyColor.yellow, 13)],
    [t(OkeyColor.blue, 5), t(OkeyColor.blue, 6), t(OkeyColor.blue, 7)],
  ];

  group('validateSeriesOpening — RULES.md §3', () {
    test('103 puan ile 101 barajı geçilir', () {
      final r = OkeyWinDetector.validateSeriesOpening(
        groups: validOpening(),
        okeyTile: okeyTile,
        requiredMinPoints: 101,
      );
      expect(r.isValid, isTrue);
      expect(r.points, 103);
    });

    test('baraj altında reddedilir', () {
      final r = OkeyWinDetector.validateSeriesOpening(
        groups: [
          [t(OkeyColor.black, 2), t(OkeyColor.black, 3), t(OkeyColor.black, 4)],
        ],
        okeyTile: okeyTile,
        requiredMinPoints: 101,
      );
      expect(r.isValid, isFalse);
      expect(r.invalidReason, contains('101'));
    });

    test('katlamalı modda yükselen baraj uygulanır', () {
      final r = OkeyWinDetector.validateSeriesOpening(
        groups: validOpening(), // 103
        okeyTile: okeyTile,
        requiredMinPoints: 104,
      );
      expect(r.isValid, isFalse);
    });

    test('geçersiz grup varsa reddedilir', () {
      final r = OkeyWinDetector.validateSeriesOpening(
        groups: [
          [t(OkeyColor.blue, 1), t(OkeyColor.blue, 2), t(OkeyColor.blue, 9)],
        ],
        okeyTile: okeyTile,
        requiredMinPoints: 0,
      );
      expect(r.isValid, isFalse);
    });

    test('boş liste reddedilir', () {
      final r = OkeyWinDetector.validateSeriesOpening(
        groups: const [],
        okeyTile: okeyTile,
        requiredMinPoints: 0,
      );
      expect(r.isValid, isFalse);
    });
  });

  group('validatePairsOpening — RULES.md §3', () {
    List<List<OkeyTile>> pairs(int n) => List.generate(
      n,
      (i) => [
        t(OkeyColor.values[i % 4], (i % 13) + 1),
        t(OkeyColor.values[i % 4], (i % 13) + 1),
      ],
    );

    test('5 çift ile açılır', () {
      final r = OkeyWinDetector.validatePairsOpening(
        groups: pairs(5),
        okeyTile: okeyTile,
        requiredMinPairs: 5,
      );
      expect(r.isValid, isTrue);
      expect(r.pairCount, 5);
      expect(r.isPairsOpening, isTrue);
    });

    test('4 çift yetersiz', () {
      final r = OkeyWinDetector.validatePairsOpening(
        groups: pairs(4),
        okeyTile: okeyTile,
        requiredMinPairs: 5,
      );
      expect(r.isValid, isFalse);
    });

    test('katlamalı modda 6 çift gerekir', () {
      final r = OkeyWinDetector.validatePairsOpening(
        groups: pairs(5),
        okeyTile: okeyTile,
        requiredMinPairs: 6,
      );
      expect(r.isValid, isFalse);
    });

    test('geçersiz çift varsa reddedilir', () {
      final r = OkeyWinDetector.validatePairsOpening(
        groups: [
          [t(OkeyColor.red, 1), t(OkeyColor.blue, 1)], // farklı renk
        ],
        okeyTile: okeyTile,
        requiredMinPairs: 1,
      );
      expect(r.isValid, isFalse);
    });
  });

  group('detectFinishType — RULES.md §6/§7', () {
    test('normal bitiş', () {
      final f = OkeyWinDetector.detectFinishType(
        lastDiscardedTile: t(OkeyColor.blue, 3),
        okeyTile: okeyTile,
        openedThisTurnOnly: false,
        openedWithPairs: false,
      );
      expect(f.label, 'normal');
      expect(f.multiplier, 1);
    });

    test('okey atarak bitiş x2', () {
      final f = OkeyWinDetector.detectFinishType(
        lastDiscardedTile: t(OkeyColor.red, 8), // = okey taşı
        okeyTile: okeyTile,
        openedThisTurnOnly: false,
        openedWithPairs: false,
      );
      expect(f.withOkey, isTrue);
      expect(f.multiplier, 2);
    });

    test('elden + okey x4', () {
      final f = OkeyWinDetector.detectFinishType(
        lastDiscardedTile: t(OkeyColor.red, 8),
        okeyTile: okeyTile,
        openedThisTurnOnly: true,
        openedWithPairs: false,
      );
      expect(f.multiplier, 4);
      expect(f.label, 'elden_okey');
    });

    test('SAHTE okey atarak bitiş x2 SAYILMAZ', () {
      // Sahte okey artık serbest joker değil, okey taşının sayı değeriyle
      // oynayan normal bir taştır (RULES.md §1). Dolayısıyla onu atarak
      // bitirmek "okey atarak bitiş" sayılmaz — yalnızca GERÇEK okey sayar.
      final f = OkeyWinDetector.detectFinishType(
        lastDiscardedTile: const OkeyTile.falseJoker(),
        okeyTile: okeyTile,
        openedThisTurnOnly: false,
        openedWithPairs: false,
      );
      expect(
        f.withOkey,
        isFalse,
        reason: 'sahte okey gerçek okey gibi sayılırsa çarpan haksız verilir',
      );
    });

    test('GERÇEK okey atarak bitiş x2 sayılır', () {
      final f = OkeyWinDetector.detectFinishType(
        lastDiscardedTile: okeyTile,
        okeyTile: okeyTile,
        openedThisTurnOnly: false,
        openedWithPairs: false,
      );
      expect(f.withOkey, isTrue);
    });
  });
}
