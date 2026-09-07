import 'package:cizreapp/okey/engine/okey_tile.dart';
import 'package:cizreapp/okey/models/okey_models.dart';
import 'package:cizreapp/okey/widgets/okey_board_widget.dart';
import 'package:cizreapp/okey/widgets/okey_tile_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// MASA = TABLO
///
/// Kullanıcı isteği (2026-09): "masa tablo şeklinde olsun; 2·3·4 per ise
/// SOLDA boşluk olsun, çünkü o kutucuğa 1 geliyor."
///
/// Yani masadaki bir per, taşları kadar değil, TAŞ ALABİLECEĞİ kadar yer
/// kaplar. Boş hücre hem "buraya bir taş gelir" der hem de bırakma hedefidir.

OkeyTile t(OkeyColor c, int n) => OkeyTile.numbered(c, n);

/// Okey taşı Sarı 13 — testlerdeki hiçbir taşla çakışmaz, yanlışlıkla
/// joker yaratmaz.
final okeyTile = t(OkeyColor.yellow, 13);

OkeyTableMeld meld(String type, List<OkeyTile> tiles) => OkeyTableMeld(
  id: 1,
  matchId: 'm',
  laidBySeat: 0,
  meldType: type,
  tiles: tiles,
);

void main() {
  group('OkeyMeldSlots — perin uçlarındaki boş hücreler', () {
    test('2·3·4 serisinin SOLUNDA bir hücre açılır (oraya 1 gelir)', () {
      final s = OkeyMeldSlots.of(
        meld('run', [
          t(OkeyColor.red, 2),
          t(OkeyColor.red, 3),
          t(OkeyColor.red, 4),
        ]),
        okeyTile,
      );
      expect(s.leading, 1);
      expect(s.trailing, 1);
      expect(s.total, 5);
    });

    test('1 ile başlayan seride SOL hücre AÇILMAZ (1\'in altı yok)', () {
      final s = OkeyMeldSlots.of(
        meld('run', [
          t(OkeyColor.blue, 1),
          t(OkeyColor.blue, 2),
          t(OkeyColor.blue, 3),
        ]),
        okeyTile,
      );
      expect(s.leading, 0);
      expect(s.trailing, 1);
    });

    test('13 ile biten seride SAĞ hücre AÇILMAZ', () {
      final s = OkeyMeldSlots.of(
        meld('run', [
          t(OkeyColor.black, 11),
          t(OkeyColor.black, 12),
          t(OkeyColor.black, 13),
        ]),
        okeyTile,
      );
      expect(s.leading, 1);
      expect(s.trailing, 0);
    });

    test('üç renkli grupta DÖRDÜNCÜ renge yer açılır', () {
      final s = OkeyMeldSlots.of(
        meld('set', [
          t(OkeyColor.red, 7),
          t(OkeyColor.black, 7),
          t(OkeyColor.blue, 7),
        ]),
        okeyTile,
      );
      expect(s.leading, 0);
      expect(s.trailing, 1);
    });

    test('dört renkli grup büyüyemez — hiç hücre açılmaz', () {
      final s = OkeyMeldSlots.of(
        meld('set', [
          t(OkeyColor.red, 7),
          t(OkeyColor.black, 7),
          t(OkeyColor.blue, 7),
          t(OkeyColor.yellow, 7),
        ]),
        okeyTile,
      );
      expect(s.trailing, 0);
      expect(s.total, 4);
    });

    test('ÇİFTE taş işlenemez — hiç hücre açılmaz', () {
      for (final type in ['pair', 'gosterge']) {
        final s = OkeyMeldSlots.of(
          meld(type, [t(OkeyColor.red, 5), t(OkeyColor.red, 5)]),
          okeyTile,
        );
        expect(s.leading, 0, reason: '$type solda hücre açmış');
        expect(s.trailing, 0, reason: '$type sağda hücre açmış');
      }
    });

    test('okey taşı bilinmiyorsa genişleme hesaplanmaz', () {
      final s = OkeyMeldSlots.of(
        meld('run', [
          t(OkeyColor.red, 2),
          t(OkeyColor.red, 3),
          t(OkeyColor.red, 4),
        ]),
        null,
      );
      expect(s.total, 3);
    });
  });

  group('Tahta çizimi', () {
    Future<void> pump(WidgetTester tester, OkeyBoardWidget board) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 600, height: 240, child: board),
            ),
          ),
        ),
      );
    }

    testWidgets('2·3·4 perinin SOLUNDA boş bir hücre çizilir', (tester) async {
      await pump(
        tester,
        OkeyBoardWidget(
          okeyTile: okeyTile,
          melds: [
            meld('run', [
              t(OkeyColor.red, 2),
              t(OkeyColor.red, 3),
              t(OkeyColor.red, 4),
            ]),
          ],
        ),
      );
      expect(tester.takeException(), isNull);

      // İki boş hücre: solda (1 gelir) ve sağda (5 gelir).
      final cells = find.byIcon(Icons.add);
      expect(cells, findsNWidgets(2));

      final firstTile = tester.getRect(find.byType(OkeyTileWidget).first);
      final leftCell = tester.getRect(cells.first);
      expect(
        leftCell.center.dx,
        lessThan(firstTile.left),
        reason: 'boş hücre perin solunda değil',
      );
    });

    testWidgets('1·2·3 perinde SOLDA boş hücre YOK', (tester) async {
      await pump(
        tester,
        OkeyBoardWidget(
          okeyTile: okeyTile,
          melds: [
            meld('run', [
              t(OkeyColor.blue, 1),
              t(OkeyColor.blue, 2),
              t(OkeyColor.blue, 3),
            ]),
          ],
        ),
      );
      expect(tester.takeException(), isNull);

      final cells = find.byIcon(Icons.add);
      expect(cells, findsOneWidget);

      final firstTile = tester.getRect(find.byType(OkeyTileWidget).first);
      expect(
        tester.getRect(cells).center.dx,
        greaterThan(firstTile.left),
        reason: '1 ile başlayan perin soluna hücre açılmış',
      );
    });

    testWidgets('çift tablosunda genişleme hücresi çizilmez', (tester) async {
      await pump(
        tester,
        OkeyBoardWidget(
          okeyTile: okeyTile,
          melds: [
            meld('pair', [t(OkeyColor.red, 5), t(OkeyColor.red, 5)]),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.add), findsNothing);
      expect(find.byType(OkeyTileWidget), findsNWidgets(2));
    });

    testWidgets('boş tabloda ipucu yazısı gösterilir', (tester) async {
      await pump(
        tester,
        const OkeyBoardWidget(melds: [], emptyHint: 'buraya serilir'),
      );
      expect(find.text('buraya serilir'), findsOneWidget);
    });
  });
}
