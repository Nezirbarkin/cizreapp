import 'package:cizreapp/features/market/widgets/price_alert_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fiyat alarmı diyaloğu ucuz üründe çöküyordu: `clamp(1, fiyat - 1)`
/// fiyat < 2 ₺ iken ArgumentError, tam 2 ₺'de sıfır genişlikli slider.
void main() {
  group('PriceAlertDialog.targetRange', () {
    test('10 ₺ ve üstünde eski aralık korunur (en çok 1 ₺ altı, en az %30)', () {
      final r = PriceAlertDialog.targetRange(100);
      expect(r.min, closeTo(30, 1e-9));
      expect(r.max, closeTo(99, 1e-9));
    });

    for (final price in [0.5, 1.0, 1.99, 2.0, 3.0, 9.99]) {
      test('$price ₺ için aralık geçerli ve fiyatın altında', () {
        final r = PriceAlertDialog.targetRange(price);
        expect(r.min, greaterThan(0));
        expect(r.max, greaterThan(r.min));
        expect(r.max, lessThan(price));
      });
    }
  });

  Future<void> pumpDialog(WidgetTester tester, double price) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PriceAlertDialog(
            productId: 'p1',
            productName: 'Test ürünü',
            currentPrice: price,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  for (final price in [1.5, 2.0, 100.0]) {
    testWidgets('$price ₺ üründe diyalog hatasız açılır, slider sınırlar içinde',
        (tester) async {
      await pumpDialog(tester, price);
      expect(tester.takeException(), isNull);

      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.max, greaterThan(slider.min));
      expect(slider.value, inInclusiveRange(slider.min, slider.max));
      expect(slider.value, lessThan(price));
    });
  }

  testWidgets('fiyatı 0 olan üründe slider yerine bilgi gösterilir',
      (tester) async {
    await pumpDialog(tester, 0);
    expect(tester.takeException(), isNull);
    expect(find.byType(Slider), findsNothing);
    expect(find.text('Bu ürün için fiyat alarmı kurulamıyor.'), findsOneWidget);
  });
}
