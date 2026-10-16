import 'dart:convert';

import 'package:cizreapp/features/seller/screens/products_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ürünlerim → çoklu seçim → toplu sil: önce kuru çalıştırma sayıları onay
/// penceresinde gösterilir, onaydan sonra gerçek çağrı yapılır; siparişli
/// ürün silinmez, satışa kapatılır (kural sunucuda).

const _shop = {'id': 'shop-1', 'name': 'Test Dükkan', 'owner_id': 'seller-1'};

Map<String, dynamic> _product(String id, String name, {bool available = true}) => {
  'id': id,
  'shop_id': 'shop-1',
  'name': name,
  'price': 10,
  'stock_quantity': 5,
  'is_available': available,
  'created_at': '2026-10-15T10:00:00Z',
  'updated_at': '2026-10-15T10:00:00Z',
};

final List<Map<String, dynamic>> _rpcCalls = [];
bool _deletedOnServer = false;

MockClient _client() => MockClient((req) async {
  final name = req.url.pathSegments.last;
  final single = (req.headers['accept'] ?? '').contains('vnd.pgrst.object');
  Object body;
  switch (name) {
    case 'shops':
      body = single ? _shop : [_shop];
    case 'products':
      body = _deletedOnServer
          ? [_product('p-order', 'Siparişli Çay', available: false), _product('p-keep', 'Seçilmeyen Şeker')]
          : [
              _product('p-new', 'Yeni Domates'),
              _product('p-order', 'Siparişli Çay'),
              _product('p-keep', 'Seçilmeyen Şeker'),
            ];
    case 'seller_bulk_delete_products':
      final params = Map<String, dynamic>.from(jsonDecode(req.body) as Map);
      _rpcCalls.add(params);
      if (params['p_dry_run'] != true) _deletedOnServer = true;
      body = {
        'deleted': 1,
        'deactivated': 1,
        'not_found': 0,
        'dry_run': params['p_dry_run'],
        'deleted_ids': ['p-new'],
        'deactivated_ids': ['p-order'],
      };
    case 'get_shop_product_stats':
      body = <Object>[];
    default:
      body = single ? <String, dynamic>{} : <Object>[];
  }
  return http.Response(
    jsonEncode(body),
    200,
    request: req,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
});

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: _client(),
    );
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-access-token',
        'token_type': 'bearer',
        'refresh_token': 'test-refresh-token',
        'user': {
          'id': 'seller-1',
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
        },
      }),
    );
  });

  testWidgets('toplu sil: kuru çalıştırma sayıları → onay → silinen gider, siparişli kapanır', (tester) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: ProductsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Yeni Domates'), findsOneWidget);

    // Uzun basış çoklu seçimi açar; ikinci ürün dokunuşla eklenir.
    await tester.longPress(find.text('Yeni Domates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Siparişli Çay'));
    await tester.pumpAndSettle();
    expect(find.text('2 ürün seçildi'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('bulk-delete')));
    await tester.pumpAndSettle();

    expect(_rpcCalls, hasLength(1));
    expect(_rpcCalls.single['p_dry_run'], isTrue);
    expect((_rpcCalls.single['p_product_ids'] as List).toSet(), {'p-new', 'p-order'});
    expect(find.text('1 ürün kalıcı olarak silinecek. Bu işlem geri alınamaz.'), findsOneWidget);
    expect(find.textContaining('1 ürünün sipariş geçmişi var; silinmeyecek, satışa kapatılacak.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('bulk-delete-confirm')));
    await tester.pumpAndSettle();

    expect(_rpcCalls, hasLength(2));
    expect(_rpcCalls.last['p_dry_run'], isFalse);
    expect(find.text('1 ürün silindi · 1 ürün satışa kapatıldı (sipariş geçmişi var)'), findsOneWidget);
    expect(find.text('Yeni Domates'), findsNothing);
    expect(find.text('Siparişli Çay'), findsOneWidget);
    expect(find.text('2 ürün seçildi'), findsNothing, reason: 'seçim modundan çıkılır');
  });

  testWidgets('vazgeçince gerçek çağrı yapılmaz', (tester) async {
    _rpcCalls.clear();
    _deletedOnServer = false;
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: ProductsScreen()));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Yeni Domates'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bulk-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();

    expect(_rpcCalls, hasLength(1));
    expect(_rpcCalls.single['p_dry_run'], isTrue);
    expect(find.text('Yeni Domates'), findsOneWidget);
    expect(find.text('1 ürün seçildi'), findsOneWidget, reason: 'seçim korunur');
  });
}
