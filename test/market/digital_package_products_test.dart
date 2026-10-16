import 'dart:io';

import 'package:cizreapp/core/models/digital_order_model.dart';
import 'package:cizreapp/core/models/product_model.dart';
import 'package:cizreapp/core/services/smm_service.dart';
import 'package:cizreapp/core/utils/digital_order_pricing.dart';
import 'package:cizreapp/core/widgets/package_order_status_dialog.dart';
import 'package:cizreapp/features/market/widgets/digital_order_total_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dijital "Paket" satış şekli (2026-10-16): sabit fiyat, adet 1, satıcı elle
/// teslim eder. Sunucu tarafı canlı testi:
/// supabase/tests/manual/digital_package_products_test.sql
void main() {
  Map<String, dynamic> productJson({
    String type = 'digital',
    String? mode,
    num price = 49.9,
  }) => {
    'id': 'p1',
    'shop_id': 's1',
    'name': '1000 Takipçi Paketi',
    'price': price,
    'stock_quantity': 0,
    'is_available': true,
    'created_at': '2026-10-16T10:00:00Z',
    'updated_at': '2026-10-16T10:00:00Z',
    'product_type': type,
    if (mode != null) 'digital_mode': mode,
  };

  Map<String, dynamic> orderJson({
    String? providerId,
    String? deliveryMode,
    String status = 'pending',
  }) => {
    'id': 'o1',
    'user_id': 'u1',
    'product_id': 'p1',
    'provider_id': providerId,
    if (deliveryMode != null) 'delivery_mode': deliveryMode,
    'target_url': 'https://instagram.com/test',
    'quantity': 1,
    'unit_price': 49.9,
    'total_price': 49.9,
    'gross_total_try': 49.9,
    'cash_balance_paid_try': 49.9,
    'status': status,
    'created_at': '2026-10-16T10:00:00Z',
  };

  group('Product.digitalMode', () {
    test('paket okunur; alan yoksa smm', () {
      expect(Product.fromJson(productJson(mode: 'package')).isDigitalPackage, isTrue);
      final legacy = Product.fromJson(productJson());
      expect(legacy.digitalMode, 'smm');
      expect(legacy.isDigitalPackage, isFalse);
      // Fiziksel üründe mod anlamsız: paket sayılmaz.
      expect(
        Product.fromJson(productJson(type: 'normal', mode: 'package')).isDigitalPackage,
        isFalse,
      );
      expect(Product.fromJson(productJson(mode: 'package')).toJson()['digital_mode'], 'package');
    });
  });

  group('DigitalOrderPricing.quotePackage', () {
    test('toplam = round(price, 2), adet 1; puan kapsamı uygulanır', () {
      final q = DigitalOrderPricing.quotePackage(price: 49.9)!;
      expect(q.totalCents, 4990);
      expect(q.quantity, 1);
      expect(q.maxPointsCents, 0);
      expect(
        DigitalOrderPricing.quotePackage(
          price: 19.99,
          pointsEligible: true,
          maxPointsCoveragePercent: 60,
        )!.maxPointsCents,
        1199,
      );
      // Kayan nokta: 0.1 + 0.2 gibi değerler kuruşa doğru yuvarlanır.
      expect(DigitalOrderPricing.quotePackage(price: 0.1 + 0.2)!.totalCents, 30);
    });

    test('fiyatsız / sıfır / negatif paket fiyatlanmaz', () {
      expect(DigitalOrderPricing.quotePackage(price: null), isNull);
      expect(DigitalOrderPricing.quotePackage(price: 0), isNull);
      expect(DigitalOrderPricing.quotePackage(price: -5), isNull);
    });
  });

  group('DigitalOrder teslim şekli', () {
    test('sağlayıcısız sipariş manuel; bekleyen paket "Teslim bekliyor"', () {
      final o = DigitalOrder.fromJson(orderJson(deliveryMode: 'manual'));
      expect(o.providerId, isNull);
      expect(o.isManualDelivery, isTrue);
      expect(o.awaitingSellerDelivery, isTrue);
      expect(o.statusLabel, 'Teslim bekliyor');

      final done = DigitalOrder.fromJson(orderJson(deliveryMode: 'manual', status: 'completed'));
      expect(done.awaitingSellerDelivery, isFalse);
      expect(done.statusLabel, 'Tamamlandı');
    });

    test('delivery_mode sütunu gelmezse provider_id belirler', () {
      expect(DigitalOrder.fromJson(orderJson()).isManualDelivery, isTrue);
      final smm = DigitalOrder.fromJson(orderJson(providerId: 'prov-1'));
      expect(smm.isManualDelivery, isFalse);
      expect(smm.statusLabel, 'Bekliyor');
    });

    test('sipariş yanıtı paket olduğunu bildirir', () {
      final r = DigitalOrderCreateResult.fromJson({
        'status': 'success',
        'digital_order_id': 'o1',
        'delivery_mode': 'manual',
        'gross_total_try': 49.9,
        'points_spent': 0,
        'points_discount_try': 0,
        'cash_paid_try': 49.9,
      });
      expect(r.isManualDelivery, isTrue);
      expect(r.reconciliationPending, isFalse);
    });
  });

  testWidgets('paket toplam kartı sabit tutarı ve 1 paketi gösterir', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DigitalOrderTotalCard.package(price: 49.9)),
      ),
    );
    expect(find.text('₺49,90'), findsOneWidget);
    expect(find.textContaining('1 paket'), findsOneWidget);
  });

  group('closePackageOrderFlow', () {
    Future<void> pumpHost(WidgetTester tester, DigitalOrder order, _FakeSmm smm) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => closePackageOrderFlow(context, order: order, service: smm),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
    }

    testWidgets('iptal seçilince sunucuya canceled gider, iade yazılır', (tester) async {
      final smm = _FakeSmm();
      await pumpHost(tester, DigitalOrder.fromJson(orderJson(deliveryMode: 'manual')), smm);
      expect(find.text('Paket Siparişi'), findsOneWidget);
      await tester.tap(find.text('İptal et'));
      await tester.pump();
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(smm.calls, ['o1:canceled']);
      expect(find.textContaining('İade: 0 puan + 49.90 TL'), findsOneWidget);
    });

    testWidgets('varsayılan seçim teslim edildi', (tester) async {
      final smm = _FakeSmm();
      await pumpHost(tester, DigitalOrder.fromJson(orderJson(deliveryMode: 'manual')), smm);
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(smm.calls, ['o1:completed']);
      expect(find.text('Paket teslim edildi olarak işaretlendi'), findsOneWidget);
    });

    testWidgets('kapanmış pakette pencere açılmaz', (tester) async {
      final smm = _FakeSmm();
      await pumpHost(
        tester,
        DigitalOrder.fromJson(orderJson(deliveryMode: 'manual', status: 'completed')),
        smm,
      );
      expect(find.text('Paket Siparişi'), findsNothing);
      expect(find.text('Bu paket siparişi zaten kapanmış'), findsOneWidget);
      expect(smm.calls, isEmpty);
    });
  });

  group('sözleşme', () {
    String read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

    test('göç: paket dalı, RLS, bildirim ve eski RPC kapatma', () {
      final m = read('supabase/migrations/20261016000001_digital_package_products.sql');
      expect(m, contains("CHECK (digital_mode IN ('smm', 'package'))"));
      expect(m, contains("OR (digital_mode = 'package' AND smm_provider_id IS NULL AND price > 0)"));
      expect(m, contains('ALTER COLUMN provider_id DROP NOT NULL'));
      expect(m, contains("v_is_package := v_product.digital_mode = 'package';"));
      expect(m, contains('IF p_quantity <> 1 OR v_product.price IS NULL OR v_product.price <= 0 THEN'));
      expect(m, contains('v_gross := round(v_product.price, 2);'));
      expect(m, contains("OR (delivery_mode = 'manual' AND product_id IN ("));
      expect(m, contains("WHEN (NEW.delivery_mode = 'manual')"));
      expect(m, contains('REVOKE ALL ON FUNCTION public.create_digital_order(uuid, uuid, text, integer)'));
    });

    test('Edge: paket sağlayıcıya gitmez; kapatma ayrı fonksiyonda', () {
      final create = read('supabase/functions/smm-order-create/index.ts');
      final manual = create.indexOf('if (orderData.delivery_mode === "manual") {');
      expect(manual, greaterThan(0));
      expect(manual, lessThan(create.indexOf('fetch(provider.api_url')));

      final pkg = read('supabase/functions/digital-package-order-status/index.ts');
      expect(pkg, contains('const ALLOWED = new Set(["completed", "canceled"]);'));
      expect(pkg, contains('order.delivery_mode !== "manual" || order.provider_id != null'));
      expect(pkg, contains('await creditSellerOnce(supabase, order, 1);'));
      expect(pkg, contains('refundComposition('));

      final old = read('supabase/functions/smm-order-manual-status/index.ts');
      expect(old, contains('USE_PACKAGE_ORDER_STATUS'));
    });

    test('satıcı formu pakette sağlayıcı alanlarını göndermez', () {
      final form = read('lib/features/seller/screens/manage_product_screen.dart');
      expect(form, contains("final isSmm = _productType == 'digital' && !_isDigitalPackage;"));
      expect(form, contains('smmProviderId: isSmm ? _selectedSmmProviderId : null,'));
      expect(form, contains("digitalMode: _productType == 'digital' ? _digitalMode : 'smm',"));
      expect(form, contains('if (isSmm) {\n          await _productService.setSmmBaseline('));
    });

    test('ürün detayı pakette adet 1 gönderir', () {
      final screen = read('lib/features/market/screens/product_detail_screen.dart');
      expect(screen, contains('quantity: isPackage ? 1 : _digitalQuantity,'));
      expect(screen, contains('if (product.isDigitalPackage) return _buildDigitalPackageForm(product);'));
    });
  });
}

class _FakeSmm extends SmmService {
  final calls = <String>[];

  @override
  Future<DigitalOrderStatusUpdateResult> setPackageOrderStatus({
    required String digitalOrderId,
    required String newStatus,
  }) async {
    calls.add('$digitalOrderId:$newStatus');
    return DigitalOrderStatusUpdateResult(
      newStatus: newStatus,
      cashRefundedTry: newStatus == 'canceled' ? 49.9 : 0,
    );
  }
}
