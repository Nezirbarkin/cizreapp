import 'dart:convert';

import 'package:cizreapp/core/models/notification_preferences_model.dart';
import 'package:cizreapp/features/seller/models/cart_insights.dart';
import 'package:cizreapp/features/seller/services/cart_insights_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Görev 3.3 — sepet istatistiği modeli/istemcisi ve müşteri tercihi.

final List<http.Request> _requests = [];

Map<String, dynamic> _statsJson() => {
  'summary': {'users': 4, 'products': 2, 'quantity': 6, 'value': '415.50'},
  'products': [
    {
      'product_id': 'p1', 'name': 'Baklava', 'image': null, 'price': 100, 'discount_price': 90,
      'old_price': null, 'effective_price': 90, 'is_available': true, 'is_digital': false,
      'users': 3, 'quantity': 4, 'first_added_at': '2026-09-20T10:00:00+00:00',
      'last_added_at': '2026-09-28T09:00:00+00:00', 'notified_users': 2,
      'last_notified_at': '2026-09-28T11:00:00+00:00',
    },
    {
      'product_id': 'p2', 'name': 'Künefe', 'price': '47.75', 'discount_price': null,
      'effective_price': '47.75', 'is_available': true, 'is_digital': false,
      'users': 1, 'quantity': 2, 'notified_users': 0,
    },
  ],
};

void main() {
  group('ShopCartStats', () {
    test('özet ve ürünler; numeric metin sayılar okunur', () {
      final stats = ShopCartStats.fromJson(_statsJson());
      expect((stats.users, stats.productCount, stats.quantity, stats.value), (4, 2, 6, 415.5));
      final baklava = stats.products.first;
      expect(baklava.hasDiscount, isTrue);
      expect((baklava.users, baklava.quantity, baklava.notifiedUsers), (3, 4, 2));
      expect(baklava.lastNotifiedAt, DateTime.utc(2026, 9, 28, 11));
      expect(baklava.cartValue, 360);
      final kunefe = stats.products.last;
      expect((kunefe.price, kunefe.effectivePrice, kunefe.hasDiscount), (47.75, 47.75, false));
      expect(ShopCartStats.fromJson({}).isEmpty, isTrue);
    });

    test('yüzde indirim LİSTE fiyatından hesaplanır; mevcut indirimden azsa fiyatı düşürmez', () {
      final baklava = ShopCartStats.fromJson(_statsJson()).products.first; // 100, şimdi 90
      expect(baklava.priceAfterPercent(5), 95);
      expect(baklava.percentLowersPrice(5), isFalse, reason: '95 > şimdiki 90');
      expect(baklava.percentLowersPrice(10), isFalse, reason: 'aynı fiyat bildirim değildir');
      expect(baklava.priceAfterPercent(15), 85);
      expect(baklava.percentLowersPrice(15), isTrue);

      final kunefe = ShopCartStats.fromJson(_statsJson()).products.last; // 47,75
      expect(kunefe.priceAfterPercent(10), 42.98, reason: '2 hane, sunucudaki ROUND ile aynı');
      expect(kunefe.percentLowersPrice(5), isTrue);
    });
  });

  group('CartInsightsService', () {
    SupabaseClient client() => SupabaseClient(
      'https://test.invalid',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((req) async {
        _requests.add(req);
        final body = req.url.pathSegments.last == 'get_shop_cart_stats' ? _statsJson() : 1;
        return http.Response(jsonEncode(body), 200, request: req, headers: {'content-type': 'application/json'});
      }),
    );

    setUp(_requests.clear);

    test('istatistik tek RPC ile, mağaza kimliğiyle', () async {
      final stats = await CartInsightsService(client: client()).fetchStats('shop-1');
      expect(_requests.single.url.path, '/rest/v1/rpc/get_shop_cart_stats');
      expect(jsonDecode(_requests.single.body), {'p_shop_id': 'shop-1'});
      expect(stats.products, hasLength(2));
    });
  });

  group('NotificationPreferences.cartPriceDropEnabled', () {
    Map<String, dynamic> row([Object? value]) => {
      'id': 'x', 'user_id': 'u', 'created_at': '2026-09-28T10:00:00Z', 'updated_at': '2026-09-28T10:00:00Z',
      if (value != null) 'cart_price_drop_enabled': value,
    };

    test('varsayılan açık; kapatılabilir; serileşir ve kopyalanır', () {
      expect(NotificationPreferences.fromJson(row()).cartPriceDropEnabled, isTrue);
      final off = NotificationPreferences.fromJson(row(false));
      expect(off.cartPriceDropEnabled, isFalse);
      expect(off.toJson()['cart_price_drop_enabled'], isFalse);
      expect(off.copyWith(likesEnabled: false).cartPriceDropEnabled, isFalse);
      expect(off.copyWith(cartPriceDropEnabled: true).cartPriceDropEnabled, isTrue);
    });
  });

  group('indirim: mevcut toplu indirim RPC\'si', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(
        url: 'https://test.invalid',
        publishableKey: 'test-key',
        httpClient: MockClient((req) async {
          _requests.add(req);
          return http.Response('1', 200, request: req, headers: {'content-type': 'application/json'});
        }),
        authOptions: const FlutterAuthClientOptions(
          localStorage: EmptyLocalStorage(),
          autoRefreshToken: false,
        ),
      );
    });

    setUp(_requests.clear);

    test('seller_bulk_set_discount yüzde moduyla tek ürün için çağrılır', () async {
      final updated = await CartInsightsService().applyPercentDiscount('p1', 15);
      expect(updated, 1);
      expect(_requests.single.url.path, '/rest/v1/rpc/seller_bulk_set_discount');
      expect(jsonDecode(_requests.single.body), {
        'p_product_ids': ['p1'],
        'p_mode': 'percent',
        'p_value': 15.0,
      });
    });
  });
}
