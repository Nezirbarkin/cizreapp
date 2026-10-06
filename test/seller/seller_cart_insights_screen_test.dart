import 'package:cizreapp/features/seller/models/cart_insights.dart';
import 'package:cizreapp/features/seller/screens/seller_cart_insights_screen.dart';
import 'package:cizreapp/features/seller/services/cart_insights_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_fonts.dart';

/// Görev 3.3 — satıcı "Sepet Takibi": özet, ürün satırları, indirim
/// penceresinin önizlemesi ve uygulanması, boş/hata durumları.

final _now = DateTime.utc(2026, 9, 28, 12);

ShopCartStats _stats({bool digital = false}) => ShopCartStats(
  users: 4,
  productCount: 2,
  quantity: 6,
  value: 455.5,
  products: [
    CartProductStat(
      productId: 'p1', name: 'Baklava', price: 100, effectivePrice: 90, discountPrice: 90,
      users: 3, quantity: 4, lastAddedAt: _now.subtract(const Duration(hours: 3)),
      notifiedUsers: 2, lastNotifiedAt: _now.subtract(const Duration(days: 1)),
    ),
    CartProductStat(
      productId: 'p2', name: 'Künefe', price: 47.75, effectivePrice: 47.75,
      users: 1, quantity: 2, isDigital: digital, lastAddedAt: _now.subtract(const Duration(minutes: 20)),
    ),
  ],
);

class _FakeService extends CartInsightsService {
  _FakeService(this.stats);

  ShopCartStats stats;
  bool fail = false;
  int loads = 0;
  final List<(String, double)> discounts = [];
  int discountResult = 1;

  @override
  Future<ShopCartStats> fetchStats(String shopId) async {
    loads++;
    if (fail) throw Exception('ağ yok');
    return stats;
  }

  @override
  Future<int> applyPercentDiscount(String productId, double percent) async {
    discounts.add((productId, percent));
    return discountResult;
  }
}

void main() {
  setUpAll(loadTestFonts);

  Future<_FakeService> open(WidgetTester tester, _FakeService service) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SellerCartInsightsScreen(shopId: 'shop-1', service: service, now: () => _now),
      ),
    );
    await tester.pumpAndSettle();
    return service;
  }

  testWidgets('özet, ürün satırları ve bildirim geçmişi', (tester) async {
    await open(tester, _FakeService(_stats()));
    expect(find.text('4'), findsOneWidget);
    expect(find.text('Müşteri'), findsOneWidget);
    expect(find.text('₺455,50'), findsOneWidget);
    expect(find.text('3 müşterinin sepetinde · 4 adet'), findsOneWidget);
    expect(find.text('1 müşterinin sepetinde · 2 adet'), findsOneWidget);
    expect(find.text('Son eklenme: 3 sa önce'), findsOneWidget);
    expect(find.text('Son eklenme: 20 dk önce'), findsOneWidget);
    expect(find.text('İndirim bildirimi: dün · 2 kişi'), findsOneWidget);
    // İndirimli ürünün eski fiyatı üstü çizili, yenisi yanında
    expect(find.text('₺100'), findsOneWidget);
    expect(find.text('₺90'), findsOneWidget);
    expect(find.textContaining('Müşterilerin kimliği gizlidir'), findsOneWidget);
  });

  testWidgets('indirim: önizleme, onay, servis çağrısı ve yenileme', (tester) async {
    final service = await open(tester, _FakeService(_stats()));

    await tester.tap(find.text('İndirim Yap').last); // Künefe
    await tester.pumpAndSettle();
    expect(find.text('İndirim uygula'), findsOneWidget);
    expect(find.text('Yeni fiyat: ₺42,98 (şimdi ₺47,75)'), findsOneWidget, reason: 'varsayılan %10');
    expect(find.textContaining('1 müşteriye bildirim gidecek'), findsOneWidget);

    await tester.tap(find.text('%20'));
    await tester.pumpAndSettle();
    expect(find.text('Yeni fiyat: ₺38,20 (şimdi ₺47,75)'), findsOneWidget);

    await tester.tap(find.text('İndirimi Uygula'));
    await tester.pumpAndSettle();
    expect(service.discounts.single, ('p2', 20.0));
    expect(find.textContaining('İndirim uygulandı'), findsOneWidget);
    expect(service.loads, 2, reason: 'uygulanınca istatistik tazelenir');
  });

  testWidgets('mevcut indirimi azaltan oran: uyarı, düğme kapalı', (tester) async {
    final service = await open(tester, _FakeService(_stats()));
    await tester.tap(find.text('İndirim Yap').first); // Baklava: 100 → şimdi 90
    await tester.pumpAndSettle();
    await tester.tap(find.text('%5'));
    await tester.pumpAndSettle();
    expect(find.text('Bu oran mevcut fiyatı düşürmüyor; daha yüksek bir oran seç.'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'İndirimi Uygula'));
    expect(button.onPressed, isNull);
    expect(service.discounts, isEmpty);
  });

  testWidgets('sunucu indirimi geçersiz sayarsa kullanıcıya söylenir', (tester) async {
    final service = _FakeService(_stats())..discountResult = 0;
    await open(tester, service);
    await tester.tap(find.text('İndirim Yap').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('İndirimi Uygula'));
    await tester.pumpAndSettle();
    expect(find.textContaining('İndirim uygulanamadı'), findsOneWidget);
  });

  testWidgets('dijital üründe indirim düğmesi yok', (tester) async {
    await open(tester, _FakeService(_stats(digital: true)));
    expect(find.text('İndirim Yap'), findsOneWidget, reason: 'yalnız fiziksel ürün');
    expect(find.text('Dijital üründe indirim buradan yapılmaz'), findsOneWidget);
  });

  testWidgets('boş ve hata durumları', (tester) async {
    final service = _FakeService(ShopCartStats.empty)..fail = true;
    await open(tester, service);
    expect(find.text('Sepet istatistiği yüklenemedi.'), findsOneWidget);
    service.fail = false;
    await tester.tap(find.text('Tekrar dene'));
    await tester.pumpAndSettle();
    expect(find.text('Henüz müşterilerinin sepetinde ürünün yok.'), findsOneWidget);
  });
}
