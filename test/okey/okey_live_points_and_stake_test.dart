import 'package:cizreapp/okey/engine/okey_board_layout.dart';
import 'package:cizreapp/okey/models/okey_models.dart';
import 'package:cizreapp/okey/widgets/okey_corner_pile_widget.dart';
import 'package:cizreapp/okey/widgets/okey_hud_chrome.dart';
import 'package:cizreapp/okey/widgets/okey_table_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// ANLIK PER PUANI, MASA PUANI ÇARPANI ve KÜÇÜLEN MASA TAŞI (2026-09-05)
///
/// Üçü de kolayca geri alınabilecek türden değişiklikler: biri bir sayı
/// sabiti, ikisi tek satırlık bir hesap. Bu dosya, hepsinin masada
/// GÖRÜLEBİLİR karşılığını sabitler.

Map<String, dynamic> _tile(String color, int number) => {
  'color': color,
  'number': number,
  'isFalseJoker': false,
};

Map<String, dynamic> _matchMap({Map<String, dynamic>? openPoints}) => {
  'id': 'm1',
  'room_id': 'r1',
  'status': 'in_progress',
  'hand_no': 1,
  'dealer_seat': 0,
  'turn_seat': 0,
  'turn_phase': 'draw',
  'turn_token': 't',
  'indicator_tile': _tile('blue', 7),
  'okey_tile': _tile('blue', 8),
  'deck_remaining': 20,
  'discard_piles': <String, dynamic>{},
  'scores': {'0': 0, '1': 0, '2': 0, '3': 0},
  if (openPoints != null) 'open_points': openPoints,
};

OkeyRoom _room({int entryFee = 500, int totalHands = 3}) => OkeyRoom(
  id: 'r1',
  createdBy: 'u1',
  status: 'waiting',
  isPrivate: false,
  maxScore: 101,
  turnSeconds: 20,
  gameMode: 'katlamasiz',
  teamMode: 'essiz',
  assistMode: 'yardimli',
  entryFee: entryFee,
  totalHands: totalHands,
  createdAt: DateTime(2026, 9, 5),
);

void main() {
  group('Anlık per puanı — model', () {
    test('open_points koltuk sayacı olarak okunur', () {
      final m = OkeyMatch.fromMap(
        _matchMap(openPoints: {'0': 101, '1': 0, '2': 47, '3': 0}),
      );
      expect(m.openPoints[0], 101);
      expect(m.openPoints[2], 47);
    });

    test('open_points hiç gelmezse boş kalır, çökmez', () {
      // Göç uygulanmadan önce açılmış bir maç satırı bu alanı taşımaz.
      final m = OkeyMatch.fromMap(_matchMap());
      expect(m.openPoints, isEmpty);
      expect(m.openPoints[0] ?? 0, 0);
    });
  });

  group('Masa puanı = giriş × el', () {
    test('çarpım sunucudaki table_stake ile aynı formül', () {
      expect(_room(entryFee: 500, totalHands: 3).tableStake, 1500);
      expect(_room(entryFee: 100, totalHands: 1).tableStake, 100);
      expect(_room(entryFee: 1000, totalHands: 10).tableStake, 10000);
    });

    test('el başına puan ile masa puanı KARIŞTIRILMAZ', () {
      final r = _room(entryFee: 250, totalHands: 5);
      expect(r.entryFee, 250, reason: 'entry_fee el başına puandır');
      expect(r.tableStake, 1250, reason: 'ödenen tutar çarpımdır');
    });
  });

  group('Masa taşı ve per boşlukları küçüldü', () {
    test('per satırları arasındaki boşluk kapandı', () {
      expect(OkeyBoardLayout.rowGap, lessThanOrEqualTo(2));
      expect(OkeyBoardLayout.meldPadding, lessThanOrEqualTo(2));
      // Sıfır DEĞİL: per zeminleri tümüyle bitişirse yan yana iki per tek
      // bir taş dizisi gibi okunur.
      expect(OkeyBoardLayout.meldPadding, greaterThan(0));
    });

    test('masadaki taş ıstakadakinden BELİRGİN biçimde küçük', () {
      for (final size in const [Size(892, 412), Size(1280, 800)]) {
        final m = OkeyTableMetrics.from(BoxConstraints.tight(size));
        expect(
          m.meldTileWidth,
          lessThan(m.rackTileWidth * 0.8),
          reason: '$size: masadaki taş ıstaka taşına yaklaşmış',
        );
      }
    });
  });

  group('Levha ve konsol sayaçları', () {
    testWidgets('oyuncu levhası anlık per puanını gösterir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 220,
                child: OkeyCornerPileWidget(
                  seat: OkeyRoomSeat(
                    roomId: 'r',
                    seatNo: 1,
                    userId: 'u1',
                    isReady: true,
                    displayName: 'Ayşe',
                  ),
                  seatNo: 1,
                  tileCount: 14,
                  score: 44,
                  openPoints: 137,
                  isCurrentTurn: false,
                  size: 26,
                  parts: OkeySeatParts.identity,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('137'), findsOneWidget, reason: 'anlık per puanı');
      expect(find.text('44'), findsOneWidget, reason: 'kümülatif ceza');
      expect(find.text('14'), findsOneWidget, reason: 'kalan taş');
    });

    testWidgets('skor balonu bu elin cezasını ANINDA yazar', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: OkeyScoreBubble(score: 44, pendingPenalty: 101),
            ),
          ),
        ),
      );

      expect(find.text('44'), findsOneWidget);
      expect(find.text('+101', skipOffstage: false), findsOneWidget);
    });

    testWidgets('ceza yokken balonda fazladan sayı çıkmaz', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: OkeyScoreBubble(score: 44))),
        ),
      );

      expect(find.text('44'), findsOneWidget);
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('masa puanı çipi çarpanı da yazar', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: OkeyStakePill(stake: 1500, perHand: 500, hands: 3),
            ),
          ),
        ),
      );

      expect(find.text('MASA 1.500'), findsOneWidget);
      expect(find.text('500 × 3 el'), findsOneWidget);
    });

    testWidgets('anlık puan ARTINCA vurgu animasyonu oynar', (tester) async {
      Widget chip(int points) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: OkeyOpenPointsText(points: points, color: Colors.amber),
          ),
        ),
      );

      await tester.pumpWidget(chip(0));
      await tester.pumpWidget(chip(101));
      // Animasyon başladı: bir kare sonra ölçek 1'in üzerinde olmalı.
      await tester.pump(const Duration(milliseconds: 90));
      final transform = tester.widget<Transform>(
        find
            .ancestor(of: find.text('101'), matching: find.byType(Transform))
            .first,
      );
      expect(transform.transform.getMaxScaleOnAxis(), greaterThan(1.0));

      // Ve kendiliğinden durur — asılı kalan bir zamanlayıcı bırakmaz.
      await tester.pumpAndSettle();
      expect(find.text('101'), findsOneWidget);
    });
  });
}
