import 'package:cizreapp/okey/widgets/okey_baraj_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// BARAJ ROZETİ — kullanıcı isteği, 2026-09-06: "ekranda baraj rozeti
/// verilsin".
///
/// Baraj ödülü el sonunda cezadan 101 (bitirene 202) düşüyordu ama masada
/// hiçbir izi yoktu: oyuncu skorunun düştüğünü görüyor, NEDEN düştüğünü
/// göremiyordu. Bir kural, sonucu görünüp sebebi görünmediğinde kural değil
/// sürpriz olur.
void main() {
  group('Baraj türü çözümü', () {
    test('sunucu değerleri doğru çözülür', () {
      expect(OkeyBarajKind.parse('pairs'), OkeyBarajKind.pairs);
      expect(OkeyBarajKind.parse('series'), OkeyBarajKind.series);
    });

    test('TANINMAYAN değer rozeti GÖSTERMEZ', () {
      // Eşikler ya da tür adları ileride değişebilir. Masada anlamı belirsiz
      // bir rozet belirmesindense hiç belirmemesi yeğdir.
      expect(OkeyBarajKind.parse('confetti'), isNull);
      expect(OkeyBarajKind.parse(null), isNull);
      expect(OkeyBarajKind.parse(''), isNull);
    });
  });

  group('Rozet görünümü', () {
    testWidgets('çift ve per barajı AYRI okunur', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                OkeyBarajBadge(kind: OkeyBarajKind.pairs),
                OkeyBarajBadge(kind: OkeyBarajKind.series),
              ],
            ),
          ),
        ),
      );

      expect(find.text('ÇİFT BARAJ'), findsOneWidget);
      expect(find.text('PER BARAJ'), findsOneWidget);
      // SERİ AÇ / ÇİFT AÇ düğmeleriyle aynı ikonlar: oyuncu barajı hangi
      // düğmeyle yaptığını ikondan hatırlar.
      expect(find.byIcon(Icons.filter_2), findsOneWidget);
      expect(find.byIcon(Icons.view_week), findsOneWidget);
    });

    testWidgets('dar kenar sütununda TAŞMADAN küçülür', (tester) async {
      // Yan koltukların levhası dar bir sütunda duruyor; rozet oraya sığmak
      // için ölçüsüyle birlikte küçülmeli, taşmamalı.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 120,
                height: 60,
                child: Center(
                  child: OkeyBarajBadge(kind: OkeyBarajKind.series, size: 15),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final rect = tester.getRect(find.byType(OkeyBarajBadge));
      expect(rect.height, lessThan(30));
    });

    testWidgets('sistem yazı tipi büyütülse de rozet BÜYÜMEZ', (tester) async {
      // Rozet sabit ölçülü bir levhanın köşesinde duruyor; büyüyen bir yazı
      // onu taşırırdı.
      Future<Rect> rectAt(double scale) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: const Scaffold(
                body: Center(child: OkeyBarajBadge(kind: OkeyBarajKind.pairs)),
              ),
            ),
          ),
        );
        return tester.getRect(find.byType(OkeyBarajBadge));
      }

      final normal = await rectAt(1.0);
      final huge = await rectAt(2.0);
      expect(huge.size, normal.size);
    });
  });
}
