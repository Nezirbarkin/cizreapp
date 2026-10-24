import 'dart:convert';

import 'package:cizreapp/features/market/services/cart_service.dart';
import 'package:cizreapp/features/market/services/product_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sepet / ürün listesi istek bütçesi (2026-10-23 performans turu):
/// * sepete eklemede ürün + sepet okuması aynı anda; mevcut satır
///   güncellenince güncel satır aynı istekte döner (eskiden ayrı okuma),
/// * Ürünler sekmesi listesinde güvenlik üst sınırı.

const _me = '11111111-1111-4111-8111-111111111111';

final List<http.Request> _requests = [];
Object? Function(http.Request req) _respond = (_) => <Object>[];

class _MemoryAsyncStorage extends GotrueAsyncStorage {
  final Map<String, String> _items = {};

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> removeItem({required String key}) async => _items.remove(key);

  @override
  Future<void> setItem({required String key, required String value}) async =>
      _items[key] = value;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: MockClient((req) async {
        _requests.add(req);
        return http.Response(
          jsonEncode(_respond(req)),
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
  });

  setUp(() {
    _requests.clear();
    _respond = (_) => <Object>[];
  });

  test('mevcut satıra ekleme: 3 istek, güncel satır güncellemeyle döner', () async {
    _respond = (req) => switch ((req.url.path, req.method)) {
          ('/rest/v1/products', _) => {
              'stock_quantity': 10,
              'is_available': true,
              'product_type': 'physical',
              'stock_unlimited': false,
              'max_order_quantity': null,
            },
          ('/rest/v1/cart', 'GET') => [
              {
                'id': 'c1',
                'quantity': 1,
                'variant_data': null,
                'flash_sale_id': null,
                'flash_price': null,
              },
            ],
          ('/rest/v1/cart', 'PATCH') => {
              'id': 'c1',
              'user_id': _me,
              'product_id': 'p1',
              'quantity': 2,
              'created_at': '2026-10-23T10:00:00Z',
              'updated_at': '2026-10-23T10:01:00Z',
              'products': {'name': 'Çay', 'price': 10, 'shop_id': 's1'},
            },
          _ => <Object>[],
        };

    final item = await CartService().addToCart(userId: _me, productId: 'p1');

    expect(_requests.map((r) => '${r.method} ${r.url.path}'), [
      'GET /rest/v1/products',
      'GET /rest/v1/cart',
      'PATCH /rest/v1/cart',
    ]);
    // Güncelleme isteği satırı ürün bilgisiyle geri istiyor.
    expect(_requests.last.url.queryParameters['select'], contains('products'));
    expect(item.quantity, 2);
    expect(item.productName, 'Çay');
  });

  test('Ürünler sekmesi listesi üst sınırlı', () async {
    await ProductService().getAllProducts();
    expect(_requests.single.url.queryParameters['limit'], '1000');
  });

  test('toplu sepet silme tek istek', () async {
    await CartService().removeManyFromCart(['a', 'b']);
    expect(_requests, hasLength(1));
    expect(_requests.single.method, 'DELETE');
    expect(_requests.single.url.queryParameters['id'], 'in.("a","b")');
  });
}
