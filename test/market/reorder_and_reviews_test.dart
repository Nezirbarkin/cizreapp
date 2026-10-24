import 'dart:convert';
import 'dart:io';

import 'package:cizreapp/core/models/order_model.dart';
import 'package:cizreapp/core/models/product_model.dart';
import 'package:cizreapp/core/models/product_review_model.dart';
import 'package:cizreapp/core/services/favorite_service.dart';
import 'package:cizreapp/features/market/services/product_review_service.dart';
import 'package:cizreapp/features/market/services/reorder_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tekrar sipariş planlayıcısı, ürün yorumu "Yararlı" / satıcı cevabı ve
/// favori dükkân istekleri + göç sözleşmesi (20261024000005).

const _me = '11111111-1111-4111-8111-111111111111';
final List<http.Request> _requests = [];
Object _nextBody = <Object>[];

class _MemoryAsyncStorage extends GotrueAsyncStorage {
  final Map<String, String> _items = {};

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> removeItem({required String key}) async => _items.remove(key);

  @override
  Future<void> setItem({required String key, required String value}) async => _items[key] = value;
}

Product _product(
  String id, {
  double price = 10,
  int stock = 10,
  bool unlimited = false,
  bool available = true,
  String type = 'normal',
  int? max,
}) =>
    Product.fromJson({
      'id': id,
      'shop_id': 's1',
      'name': 'Ürün $id',
      'price': price,
      'stock_quantity': stock,
      'stock_unlimited': unlimited,
      'is_available': available,
      'product_type': type,
      'max_order_quantity': max,
      'created_at': '2026-10-01T00:00:00Z',
      'updated_at': '2026-10-01T00:00:00Z',
    });

OrderItem _item(String productId, int qty, {double price = 10}) => OrderItem(
      id: 'i-$productId',
      orderId: 'o1',
      productId: productId,
      productName: 'Eski $productId',
      price: price,
      quantity: qty,
      createdAt: DateTime(2026, 10, 1),
    );

void main() {
  group('ReorderService.plan', () {
    test('uygun kalemler eklenir; satıştan kalkan, seçenekli, fiyatı değişen ayrılır', () {
      final plan = ReorderService.plan(
        [
          _item('a', 2),
          _item('a', 1), // aynı ürün iki satır → 3
          _item('gone', 1),
          _item('off', 1),
          _item('shirt', 1),
          _item('pricey', 1, price: 10),
        ],
        {
          'a': _product('a'),
          'off': _product('off', available: false),
          'shirt': _product('shirt', type: 'clothing'),
          'pricey': _product('pricey', price: 12.5),
        },
        const {},
      );
      expect(plan.lines.map((l) => '${l.productId}:${l.quantity}'), ['a:3', 'pricey:1']);
      expect(plan.unavailable, ['Eski gone', 'Ürün off']);
      expect(plan.needsOptions.single.id, 'shirt');
      expect(plan.priceChanged, ['Ürün pricey']);
    });

    test('sınırsız stokta en fazla 2; sepetteki adet düşülür; doluysa atlanır', () {
      final plan = ReorderService.plan(
        [_item('u', 5), _item('s', 4), _item('full', 1)],
        {
          'u': _product('u', unlimited: true, stock: 999999),
          's': _product('s', stock: 3),
          'full': _product('full', unlimited: true, stock: 999999),
        },
        const {'s': 1, 'full': 2},
      );
      final byId = {for (final l in plan.lines) l.productId: l};
      expect(byId['u']!.quantity, 2);
      expect(byId['u']!.reducedFrom, 5);
      expect(byId['s']!.quantity, 2); // stok 3 − sepette 1
      expect(plan.alreadyInCart, ['Ürün full']);
    });
  });

  group('istekler', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(
        url: 'https://test.invalid',
        publishableKey: 'test-publishable-key',
        httpClient: MockClient((req) async {
          _requests.add(req);
          return http.Response(
            jsonEncode(_nextBody),
            200,
            request: req,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
        authOptions: FlutterAuthClientOptions(
          localStorage: const EmptyLocalStorage(),
          pkceAsyncStorage: _MemoryAsyncStorage(),
          autoRefreshToken: false,
        ),
      );
      await Supabase.instance.client.auth.recoverSession(
        jsonEncode({
          'access_token': 'token',
          'token_type': 'bearer',
          'refresh_token': 'refresh',
          'user': {
            'id': _me,
            'aud': 'authenticated',
            'created_at': '2026-01-01T00:00:00Z',
            'app_metadata': <String, dynamic>{},
            'user_metadata': <String, dynamic>{},
          },
        }),
      );
    });

    setUp(() {
      _requests.clear();
      _nextBody = <Object>[];
    });

    test('Yararlı: tek idempotent istek, yorum satırına PATCH yok', () async {
      final s = ProductReviewService();
      await s.setHelpful('r1', _me, true);
      expect(_requests.single.method, 'POST');
      expect(_requests.single.url.path, '/rest/v1/product_review_helpful');
      expect(_requests.single.url.queryParameters['on_conflict'], 'review_id,user_id');
      _requests.clear();
      await s.setHelpful('r1', _me, false);
      expect(_requests.single.method, 'DELETE');
      expect(_requests.where((r) => r.url.path == '/rest/v1/product_reviews'), isEmpty);
    });

    test('satıcı cevabı RPC ile (boş metin = sil)', () async {
      _nextBody = {
        'id': 'r1',
        'product_id': 'p1',
        'user_id': 'u1',
        'rating': 5,
        'created_at': '2026-10-24T10:00:00Z',
        'updated_at': '2026-10-24T10:00:00Z',
        'seller_reply': 'Teşekkürler',
        'seller_replied_at': '2026-10-24T11:00:00Z',
      };
      final r = await ProductReviewService().addSellerReply(reviewId: 'r1', reply: '  Teşekkürler ');
      expect(r.sellerReply, 'Teşekkürler');
      expect(_requests.single.url.path, '/rest/v1/rpc/seller_reply_product_review');
      expect(jsonDecode(_requests.single.body), {'p_review_id': 'r1', 'p_reply': 'Teşekkürler'});
      _requests.clear();
      await ProductReviewService().deleteSellerReply('r1');
      expect(jsonDecode(_requests.single.body), {'p_review_id': 'r1', 'p_reply': ''});
    });

    test('ProductReview: products(name) embed\'inden ürün adı', () {
      final r = ProductReview.fromJson({
        'id': 'r1',
        'product_id': 'p1',
        'user_id': 'u1',
        'rating': 4,
        'created_at': '2026-10-24T10:00:00Z',
        'updated_at': '2026-10-24T10:00:00Z',
        'products': {'name': 'Çay', 'image_url': null},
      });
      expect(r.productName, 'Çay');
    });

    test('favori dükkân: tek idempotent upsert / delete', () async {
      await FavoriteService().setShopFavorite('s1', true);
      expect(_requests.single.url.path, '/rest/v1/shop_subscribers');
      expect(_requests.single.url.queryParameters['on_conflict'], 'shop_id,user_id');
      expect(jsonDecode(_requests.single.body), {'shop_id': 's1', 'user_id': _me});
      _requests.clear();
      await FavoriteService().setShopFavorite('s1', false);
      expect(_requests.single.method, 'DELETE');
      expect(_requests.single.url.queryParameters['shop_id'], 'eq.s1');
    });
  });

  test('göç sözleşmesi: DEFINER sayaç/puan, koruma, satıcı RPC', () {
    final sql = File('supabase/migrations/20261024000005_shop_favorites_and_review_fixes.sql')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect('SECURITY DEFINER'.allMatches(sql).length, greaterThanOrEqualTo(2));
    expect(sql, contains('create trigger a_product_reviews_guard_client_write'));
    expect(sql, contains('NEW.seller_reply      := OLD.seller_reply;'));
    expect(sql, contains('r.id = review_id and r.user_id = (select auth.uid())'));
    expect(sql, contains("v_shop.owner_id is distinct from v_uid and not public.auth_is_admin()"));
    expect(sql, contains("'product_review_reply'"));
  });
}
