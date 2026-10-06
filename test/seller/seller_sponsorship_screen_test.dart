import 'package:cizreapp/core/models/product_model.dart';
import 'package:cizreapp/core/models/sponsorship_model.dart';
import 'package:cizreapp/features/seller/screens/seller_sponsorship_screen.dart';
import 'package:cizreapp/features/seller/services/sponsorship_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_fonts.dart';

/// Görev 3.2 — satıcı "Öne Çıkar" ekranı: bakiye, dört vitrin, paketler,
/// onaylı satın alma, yetersiz bakiye, indirimsiz ürün engeli, geçmiş.

final _now = DateTime.utc(2026, 9, 28, 12);

const _packages = [
  SponsorshipPackage(id: 'sl1', placement: SponsorPlacement.shopList, name: 'Günlük', durationDays: 1, price: 30, sortOrder: 10),
  SponsorshipPackage(id: 'sl7', placement: SponsorPlacement.shopList, name: 'Haftalık', durationDays: 7, price: 150, sortOrder: 20),
  SponsorshipPackage(id: 'sc1', placement: SponsorPlacement.shopCategory, name: 'Günlük', durationDays: 1, price: 20, sortOrder: 10),
  SponsorshipPackage(id: 'pc7', placement: SponsorPlacement.productCategory, name: 'Haftalık', durationDays: 7, price: 75, sortOrder: 20),
  SponsorshipPackage(id: 'pd1', placement: SponsorPlacement.productDiscount, name: 'Günlük', durationDays: 1, price: 12, sortOrder: 10),
];

Product _product(String id, String name, {bool discounted = false}) => Product.fromJson({
  'id': id,
  'shop_id': 'shop-1',
  'name': name,
  'price': 100,
  'old_price': discounted ? 130 : null,
  'stock_quantity': 3,
  'is_available': true,
  'created_at': _now.toIso8601String(),
  'updated_at': _now.toIso8601String(),
});

class _FakeService extends SponsorshipService {
  _FakeService({this.balance = 100});

  double balance;
  SponsorshipException? failWith;
  bool failLoad = false;
  List<ShopSponsorship> history = [];
  final List<({String packageId, String? productId})> purchases = [];

  @override
  Future<List<SponsorshipPackage>> fetchPackages() async {
    if (failLoad) throw Exception('ağ yok');
    return _packages;
  }

  @override
  Future<List<ShopSponsorship>> fetchShopSponsorships(String shopId, {int limit = 50}) async => history;

  @override
  Future<double> fetchMyBalance() async => balance;

  @override
  Future<SponsorshipPurchase> purchase({required String shopId, required String packageId, String? productId}) async {
    purchases.add((packageId: packageId, productId: productId));
    final failure = failWith;
    if (failure != null) throw failure;
    final package = _packages.firstWhere((p) => p.id == packageId);
    balance -= package.price;
    final end = _now.add(Duration(days: package.durationDays));
    history = [
      ShopSponsorship(
        id: 'new-${purchases.length}',
        shopId: shopId,
        productId: productId,
        placement: package.placement,
        packageName: package.name,
        durationDays: package.durationDays,
        pricePaid: package.price,
        status: SponsorshipStatus.active,
        createdAt: _now,
        startsAt: _now,
        endsAt: end,
      ),
      ...history,
    ];
    return SponsorshipPurchase(
      id: 'new',
      status: SponsorshipStatus.active,
      placement: package.placement,
      price: package.price,
      balanceAfter: balance,
      startsAt: _now,
      endsAt: end,
    );
  }
}

void main() {
  setUpAll(loadTestFonts);

  Future<_FakeService> open(WidgetTester tester, {_FakeService? service, List<Product>? products}) async {
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = service ?? _FakeService();
    await tester.pumpWidget(
      MaterialApp(
        home: SellerSponsorshipScreen(
          shopId: 'shop-1',
          shopName: 'Deniz Market',
          service: fake,
          productLoader: (_) async =>
              products ?? [_product('p1', 'Baklava', discounted: true), _product('p2', 'Künefe')],
          now: () => _now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('bakiye, dört vitrin ve paketler (süre · fiyat)', (tester) async {
    await open(tester);
    expect(find.text('₺100'), findsOneWidget);
    expect(find.text('Bakiye Yükle'), findsOneWidget);
    for (final placement in SponsorPlacement.values) {
      expect(find.text(placement.label), findsOneWidget, reason: placement.label);
    }
    for (final label in ['1 gün · ₺30', '7 gün · ₺150', '1 gün · ₺20', '7 gün · ₺75', '1 gün · ₺12']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Baklava'), findsOneWidget, reason: 'ilk ürün seçili');
    expect(find.text('Henüz öne çıkarma satın almadın.'), findsOneWidget);
  });

  testWidgets('onaylı satın alma: RPC çağrılır, bakiye düşer, vitrin "Yayında"', (tester) async {
    final service = await open(tester);

    await tester.tap(find.text('1 gün · ₺30'));
    await tester.pumpAndSettle();
    expect(find.text('Öne çıkarmayı onayla'), findsOneWidget);
    expect(find.text('Dükkanlar listesi · Günlük (1 gün)'), findsOneWidget);
    expect(find.text('Ücret: ₺30 — bakiyenden düşülür.'), findsOneWidget);

    await tester.tap(find.text('Satın Al'));
    await tester.pumpAndSettle();

    expect(service.purchases.single, (packageId: 'sl1', productId: null));
    expect(find.text('₺70'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Öne çıkarıldı!'), findsOneWidget);
    expect(find.textContaining('Yayında ·'), findsOneWidget);
    expect(find.text('Dükkanlar listesi · Günlük'), findsOneWidget, reason: 'geçmişte');
  });

  testWidgets('vazgeçilirse satın alınmaz', (tester) async {
    final service = await open(tester);
    await tester.tap(find.text('1 gün · ₺20'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(service.purchases, isEmpty);
  });

  testWidgets('ürün vitrini seçili ürünle satın alınır; indirimsiz ürün İndirimdekiler\'e çıkamaz', (tester) async {
    final service = await open(tester);

    await tester.tap(find.text('1 gün · ₺12'));
    await tester.pumpAndSettle();
    expect(find.text('Baklava'), findsNWidgets(2), reason: 'onay penceresinde hedef ürün');
    await tester.tap(find.text('Satın Al'));
    await tester.pumpAndSettle();
    expect(service.purchases.single, (packageId: 'pd1', productId: 'p1'));

    // İndirimsiz ürünü seç
    await tester.tap(find.text('Baklava').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Künefe'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bu ürün indirimde değil'), findsOneWidget);
    expect(find.text('1 gün · ₺12'), findsNothing);
    expect(find.text('7 gün · ₺75'), findsOneWidget, reason: 'Ürünler vitrini indirimsiz ürüne açık');
  });

  testWidgets('yetersiz bakiye: bakiye yükleme önerilir', (tester) async {
    final service = _FakeService(balance: 5)
      ..failWith = const SponsorshipException(SponsorshipFailure.insufficientBalance, 'Yetersiz bakiye: bu paket 30.00 TL');
    await open(tester, service: service);

    await tester.tap(find.text('1 gün · ₺30'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Satın Al'));
    await tester.pumpAndSettle();

    expect(find.text('Bakiye yetersiz'), findsOneWidget);
    expect(find.text('Bu paket ₺30; bakiyen ₺5. Bakiye yükleyip tekrar deneyebilirsin.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Bakiye Yükle'), findsNWidgets(2), reason: 'kart + pencere');
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(find.text('Bakiye yetersiz'), findsNothing);
  });

  testWidgets('diğer sunucu hataları mesajıyla gösterilir', (tester) async {
    final service = _FakeService()
      ..failWith = const SponsorshipException(SponsorshipFailure.disabled, 'Öne çıkarma şu anda kapalı');
    await open(tester, service: service);
    await tester.tap(find.text('7 gün · ₺150'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Satın Al'));
    await tester.pumpAndSettle();
    expect(find.text('Öne çıkarma şu anda kapalı'), findsOneWidget);
  });

  testWidgets('geçmiş: onay bekleyen ve süresi dolan satırlar', (tester) async {
    final service = _FakeService()
      ..history = [
        ShopSponsorship(
          id: 'a', shopId: 'shop-1', placement: SponsorPlacement.shopCategory, packageName: 'Günlük',
          durationDays: 1, pricePaid: 20, status: SponsorshipStatus.pending, createdAt: _now,
        ),
        ShopSponsorship(
          id: 'b', shopId: 'shop-1', placement: SponsorPlacement.shopList, packageName: 'Haftalık',
          durationDays: 7, pricePaid: 150, status: SponsorshipStatus.active, createdAt: _now,
          startsAt: _now.subtract(const Duration(days: 8)), endsAt: _now.subtract(const Duration(days: 1)),
        ),
      ];
    await open(tester, service: service);
    expect(find.text('Onay bekliyor'), findsNWidgets(2), reason: 'vitrin kartı + geçmiş');
    expect(find.text('Sona erdi'), findsOneWidget);
    expect(find.textContaining('Yayında ·'), findsNothing);
  });

  testWidgets('yüklenemezse hata ve tekrar dene', (tester) async {
    final service = _FakeService()..failLoad = true;
    await open(tester, service: service);
    expect(find.text('Öne çıkarma bilgileri yüklenemedi.'), findsOneWidget);
    service.failLoad = false;
    await tester.tap(find.text('Tekrar dene'));
    await tester.pumpAndSettle();
    expect(find.text('Dükkanlar listesi'), findsOneWidget);
  });
}
