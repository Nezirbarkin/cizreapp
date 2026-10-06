import 'dart:convert';

import 'package:cizreapp/core/models/product_model.dart';
import 'package:cizreapp/features/market/services/flash_sale_service.dart';
import 'package:cizreapp/features/market/widgets/flash_aware_price_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ürün kartlarındaki flaş fiyat/rozet artık ortak önbellekten gelir.
///
/// Eskiden her kart `build` içinde ürün başına iki sorgu atıyordu (fiyat
/// satırı + rozet) ve kart her yeniden çizildiğinde tekrar ediyordu —
/// canlıda en çok çağrılan sorgu buydu (~916 bin çağrı). Burada 30 kartlık
/// liste TEK istekle dolmalı ve yeniden çizimler ağa gitmemeli.
final List<http.Request> _flashRequests = [];

Map<String, dynamic> _sale({
  required String productId,
  required DateTime startAt,
  required DateTime endAt,
  double flashPrice = 80,
}) {
  final now = DateTime.now().toUtc().toIso8601String();
  return {
    'id': 'sale-$productId',
    'product_id': productId,
    'shop_id': 'shop-1',
    'original_price': 100,
    'flash_price': flashPrice,
    'stock_limit': 10,
    'sold_count': 2,
    'start_at': startAt.toUtc().toIso8601String(),
    'end_at': endAt.toUtc().toIso8601String(),
    'is_active': true,
    'created_at': now,
    'updated_at': now,
    'products': {'id': productId, 'name': 'Ürün', 'image_url': null},
    'shops': {'id': 'shop-1', 'name': 'Dükkan'},
  };
}

Product _product(String id, {double price = 100}) => Product(
  id: id,
  shopId: 'shop-1',
  name: 'Ürün $id',
  price: price,
  stockQuantity: 5,
  isAvailable: true,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: MockClient((req) async {
        Object body = const <Object>[];
        if (req.url.path == '/rest/v1/flash_sales') {
          _flashRequests.add(req);
          body = [
            // p1: şu an aktif
            _sale(
              productId: 'p1',
              startAt: now.subtract(const Duration(hours: 1)),
              endAt: now.add(const Duration(hours: 2)),
            ),
            // p1 için daha geç biten ikinci kampanya: en erken biten seçilmeli
            _sale(
              productId: 'p1',
              startAt: now.subtract(const Duration(hours: 1)),
              endAt: now.add(const Duration(hours: 5)),
              flashPrice: 70,
            ),
            // p2: henüz başlamamış (sunucu döndürse bile gösterilmez)
            _sale(
              productId: 'p2',
              startAt: now.add(const Duration(hours: 1)),
              endAt: now.add(const Duration(hours: 3)),
            ),
          ];
        }
        return http.Response(
          jsonEncode(body),
          200,
          request: req,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
  });

  setUp(() {
    _flashRequests.clear();
    ActiveFlashSaleCache.instance.invalidate();
    ActiveFlashSaleCache.instance.byProduct.value = const {};
  });

  Future<StateSetter> pumpCards(WidgetTester tester) async {
    late StateSetter rebuild;
    final products = List.generate(30, (i) => _product('p${i + 1}'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return ListView(
                children: [
                  for (final p in products)
                    Row(
                      key: ValueKey(p.id),
                      children: [
                        FlashAwarePriceRow(product: p),
                        FlashAwareDiscountBadge(product: p),
                      ],
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return rebuild;
  }

  testWidgets('30 kart tek istekle dolar, flaş fiyat doğru ürüne düşer', (
    tester,
  ) async {
    await pumpCards(tester);

    expect(_flashRequests, hasLength(1));
    final query = _flashRequests.single.url.queryParameters;
    expect(query['is_active'], 'eq.true');
    expect(query.containsKey('product_id'), isFalse,
        reason: 'ürün başına değil, tüm aktif kampanyalar tek seferde');

    // p1: en erken biten kampanyanın fiyatı (80), geç biteninki (70) değil
    expect(find.text('₺80.00'), findsOneWidget);
    expect(find.text('₺70.00'), findsNothing);
    expect(find.text('%20'), findsOneWidget, reason: 'flaş rozeti yalnız p1');
    // p2: başlamamış kampanya gösterilmez → normal fiyat
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('p2')),
        matching: find.text('₺100.00'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('yeniden çizimler ağa gitmez; invalidate bir kez yeniler', (
    tester,
  ) async {
    final rebuild = await pumpCards(tester);
    expect(_flashRequests, hasLength(1));

    for (var i = 0; i < 5; i++) {
      rebuild(() {});
      await tester.pump();
    }
    expect(_flashRequests, hasLength(1), reason: 'TTL içinde istek yok');

    ActiveFlashSaleCache.instance.invalidate();
    for (var i = 0; i < 3; i++) {
      rebuild(() {});
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 50));
    expect(_flashRequests, hasLength(2),
        reason: 'aynı anda çizilen kartlar tek yenileme isteğine iner');
    expect(find.text('₺80.00'), findsOneWidget);
  });
}
