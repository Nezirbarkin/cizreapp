import 'package:cizreapp/okey/okey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Gösterge: 7 Kırmızı -> okey taşı: 8 Kırmızı.
  final okeyTile = OkeyTile.numbered(OkeyColor.red, 8);
  OkeyTile t(OkeyColor c, int n) => OkeyTile.numbered(c, n);

  group('taş değerleri', () {
    test('sayı taşı kendi numarası kadar', () {
      expect(OkeyScoring.tilePenaltyValue(t(OkeyColor.blue, 9), okeyTile), 9);
    });

    test('sahte okey o elin okey numarası kadar', () {
      expect(
        OkeyScoring.tilePenaltyValue(const OkeyTile.falseJoker(), okeyTile),
        8,
      );
    });

    test('handPenaltyValue toplar', () {
      expect(
        OkeyScoring.handPenaltyValue([
          t(OkeyColor.blue, 9),
          t(OkeyColor.black, 3),
          const OkeyTile.falseJoker(),
        ], okeyTile),
        9 + 3 + 8,
      );
    });
  });

  group('çarpanlar — RULES.md §7', () {
    test('normal bitiş x1', () {
      expect(const OkeyFinishType().multiplier, 1);
    });

    test('okey ile bitiş x2', () {
      expect(const OkeyFinishType(withOkey: true).multiplier, 2);
    });

    test('elden bitiş x2', () {
      expect(const OkeyFinishType(elden: true).multiplier, 2);
    });

    test('çiftten bitiş x2', () {
      expect(const OkeyFinishType(withPairs: true).multiplier, 2);
    });

    test('elden + okey x4 (katlanarak)', () {
      expect(const OkeyFinishType(elden: true, withOkey: true).multiplier, 4);
    });

    test('etiketler doğru', () {
      expect(const OkeyFinishType().label, 'normal');
      expect(const OkeyFinishType(withOkey: true).label, 'okey');
      expect(const OkeyFinishType(elden: true).label, 'elden');
      expect(const OkeyFinishType(withPairs: true).label, 'cift');
      expect(
        const OkeyFinishType(elden: true, withOkey: true).label,
        'elden_okey',
      );
    });
  });

  group('basePenalty — RULES.md §7', () {
    test('kazanan -101', () {
      expect(
        OkeyScoring.basePenalty(
          state: OkeyEndState.winner,
          remainingTiles: const [],
          okeyTile: okeyTile,
        ),
        -101,
      );
    });

    test('hiç açmayan 202', () {
      expect(
        OkeyScoring.basePenalty(
          state: OkeyEndState.neverOpened,
          remainingTiles: [t(OkeyColor.blue, 9)],
          okeyTile: okeyTile,
        ),
        202,
      );
    });

    test('çifte gidip açamayan 404', () {
      expect(
        OkeyScoring.basePenalty(
          state: OkeyEndState.pairsAttemptFailed,
          remainingTiles: [t(OkeyColor.blue, 9)],
          okeyTile: okeyTile,
        ),
        404,
      );
    });

    test('seri ile açan: elde kalanların toplamı', () {
      expect(
        OkeyScoring.basePenalty(
          state: OkeyEndState.openedWithSeries,
          remainingTiles: [t(OkeyColor.blue, 9), t(OkeyColor.red, 3)],
          okeyTile: okeyTile,
        ),
        12,
      );
    });

    test('çift ile açan: elde kalanların 2 katı', () {
      expect(
        OkeyScoring.basePenalty(
          state: OkeyEndState.openedWithPairs,
          remainingTiles: [t(OkeyColor.blue, 9), t(OkeyColor.red, 3)],
          okeyTile: okeyTile,
        ),
        24,
      );
    });
  });

  group('computeHandScores', () {
    test('kazanan -101, kaybedenlere çarpanlı ceza', () {
      final scores = OkeyScoring.computeHandScores(
        winnerSeat: 0,
        seatStates: {
          0: OkeyEndState.winner,
          1: OkeyEndState.neverOpened,
          2: OkeyEndState.openedWithSeries,
          3: OkeyEndState.pairsAttemptFailed,
        },
        remainingTiles: {
          1: [t(OkeyColor.blue, 9)],
          2: [t(OkeyColor.blue, 9), t(OkeyColor.red, 3)],
          3: [t(OkeyColor.blue, 5)],
        },
        okeyTile: okeyTile,
        finish: const OkeyFinishType(withOkey: true), // x2
      );

      expect(scores[0], -101);
      expect(scores[1], 404); // 202 x2
      expect(scores[2], 24); // 12 x2
      expect(scores[3], 808); // 404 x2
    });

    test('normal bitişte çarpan uygulanmaz', () {
      final scores = OkeyScoring.computeHandScores(
        winnerSeat: 1,
        seatStates: {0: OkeyEndState.neverOpened, 1: OkeyEndState.winner},
        remainingTiles: const {},
        okeyTile: okeyTile,
        finish: const OkeyFinishType(),
      );
      expect(scores[1], -101);
      expect(scores[0], 202);
    });
  });
}
