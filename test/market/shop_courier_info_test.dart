import 'package:cizreapp/features/market/widgets/shop_courier_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Padding(
      padding: const EdgeInsets.all(16),
      child: child,
    )));

void main() {
  testWidgets('platform kuryesi: şerit ve açıklama', (t) async {
    await t.pumpWidget(_host(const ShopCourierInfoStrip(
      ownCourier: false,
      shopName: 'Test Market',
      pickupEnabled: true,
    )));
    expect(find.text('Siparişin CizreApp kuryesiyle teslim edilir'), findsOneWidget);

    await t.tap(find.byType(ShopCourierInfoStrip));
    await t.pumpAndSettle();
    expect(find.text('CizreApp kuryesi'), findsOneWidget);
    expect(find.textContaining('evrakları onaylanmış'), findsOneWidget);
    expect(find.textContaining('Gel Al'), findsOneWidget);
  });

  testWidgets('kendi kuryesi: dükkan adıyla açıklama, Gel Al yoksa not yok', (t) async {
    await t.pumpWidget(_host(const ShopCourierInfoStrip(
      ownCourier: true,
      shopName: 'Kebapçı',
    )));
    expect(find.text('Bu dükkan siparişleri kendi kuryesiyle teslim ediyor'), findsOneWidget);

    await t.tap(find.byType(ShopCourierInfoStrip));
    await t.pumpAndSettle();
    expect(find.text('Kendi kuryesi'), findsOneWidget);
    expect(find.textContaining("Kebapçı'nin kendi kuryesi"), findsOneWidget);
    expect(find.textContaining('Gel Al'), findsNothing);
  });

  testWidgets('dar ekranda taşmaz', (t) async {
    t.view.physicalSize = const Size(320 * 3, 640 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(_host(const ShopCourierInfoStrip(ownCourier: true, shopName: 'X')));
    expect(t.takeException(), isNull);
  });
}
