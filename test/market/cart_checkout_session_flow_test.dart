import 'dart:convert';

import 'package:cizreapp/features/market/providers/address_provider.dart';
import 'package:cizreapp/features/market/providers/cart_provider.dart';
import 'package:cizreapp/features/market/screens/checkout_screen.dart';
import 'package:cizreapp/features/market/screens/multi_shop_checkout_screen.dart';
import 'package:cizreapp/models/checkout_session_model.dart';
import 'package:cizreapp/services/checkout_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ana sepet ödemesi artık yalnız sunucu oturumu üzerinden sipariş açar:
/// `prepare_checkout_session` (tutarları sunucu hesaplar) → `commit_*_order`.
/// Bu testler iki ödeme ekranının istemciden orders/order_items yazmadığını,
/// tutar göndermediğini, onay penceresinde SUNUCU toplamını gösterdiğini ve
/// başarılı siparişten sonra flaş talebini geri vermediğini doğrular.

const _userId = 'user-1';

class _Backend {
  final List<http.Request> requests = [];
  List<Map<String, dynamic>> cartRows = [];
  double balance = 1000;

  /// prepare_checkout_session yanıtındaki teslimat ücreti (istemcinin
  /// hesabından bilerek farklı: ekran sunucu değerini göstermeli).
  double serverDeliveryFee = 9.99;

  /// commit_balance_order bu hatayla düşsün (null → başarılı).
  String? balanceCommitError;

  static const _json = {'content-type': 'application/json; charset=utf-8'};

  Map<String, dynamic> get aboutSettings => {
        'id': 1,
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
        'order_cod_enabled': true,
        'order_card_on_delivery_enabled': true,
        'online_payment_enabled': false,
        'order_balance_enabled': true,
        'order_approval_code_enabled': false,
        'balance_enabled': true,
      };

  Map<String, dynamic> shopRow(String id) => {
        'id': id,
        'name': id == 's1' ? 'Dükkan A' : 'Dükkan B',
        'delivery_fee': 15,
        'free_delivery_min_amount': 0,
        'pickup_enabled': false,
        'min_order_amount': 0,
      };

  List<http.Request> calls(String pathSuffix) =>
      requests.where((r) => r.url.path.endsWith(pathSuffix)).toList();

  Map<String, dynamic> bodyOf(http.Request r) =>
      r.body.isEmpty ? {} : jsonDecode(r.body) as Map<String, dynamic>;

  Map<String, dynamic> _prepareRow(Map<String, dynamic> body) {
    final items = (body['p_items'] as List).cast<Map<String, dynamic>>();
    final lines = <Map<String, dynamic>>[];
    final byShop = <String, double>{};
    for (final it in items) {
      final row = cartRows.firstWhere((c) => c['product_id'] == it['product_id']);
      final product = row['products'] as Map<String, dynamic>;
      final shopId = product['shop_id'] as String;
      final unit = it['flash_sale_id'] != null ? 80.0 : 100.0;
      final qty = it['quantity'] as int;
      byShop[shopId] = (byShop[shopId] ?? 0) + unit * qty;
      lines.add({
        'product_id': it['product_id'],
        'product_name': product['name'],
        'shop_id': shopId,
        'shop_name': shopId == 's1' ? 'Dükkan A' : 'Dükkan B',
        'quantity': qty,
        'unit_price': unit,
        'subtotal': unit * qty,
        'line_total': unit * qty,
        'flash_sale_id': it['flash_sale_id'],
        'is_flash_sale': it['flash_sale_id'] != null,
      });
    }
    final subOrders = [
      for (final e in byShop.entries)
        {
          'shop_id': e.key,
          'shop_name': e.key == 's1' ? 'Dükkan A' : 'Dükkan B',
          'subtotal': e.value,
          'delivery_fee': serverDeliveryFee,
          'coupon_id': null,
          'coupon_discount': 0,
          'total': e.value + serverDeliveryFee,
          'is_pickup': false,
        },
    ];
    final subtotal = byShop.values.fold<double>(0, (a, b) => a + b);
    final fee = serverDeliveryFee * byShop.length;
    return {
      'session_id': 'sess-1',
      'idempotency_key': body['p_idempotency_key'],
      'payment_method': body['p_payment_method'],
      'currency': 'TRY',
      'status': 'pending',
      'expires_at': '2099-01-01T00:00:00Z',
      'server_subtotal': subtotal,
      'server_delivery_fee': fee,
      'server_discount': 0,
      'server_coupon_discount': 0,
      'server_commission_amount': subtotal * 0.1,
      'server_total': subtotal + fee,
      'items': lines,
      'sub_orders': subOrders,
      'delivery_address': {'id': 'addr-1'},
      'notes': body['p_notes'],
      'warnings': <dynamic>[],
    };
  }

  MockClient client() => MockClient((req) async {
        requests.add(req);
        final path = req.url.path;
        final accept = req.headers['Accept'] ?? req.headers['accept'] ?? '';
        final wantsObject = accept.contains('vnd.pgrst.object');

        http.Response ok(Object? data) =>
            http.Response(jsonEncode(data), 200, request: req, headers: _json);

        if (path.endsWith('/rpc/prepare_checkout_session')) {
          return ok([_prepareRow(bodyOf(req))]);
        }
        if (path.endsWith('/rpc/commit_cod_order')) {
          final shops = cartRows
              .map((c) => (c['products'] as Map)['shop_id'])
              .toSet()
              .length;
          return ok([
            {
              'order_id': 'o1',
              'order_number': 'ORD00000001',
              'order_group_id': shops > 1 ? 'grp-1' : null,
              'status': 'committed',
              'total': 209.99,
              'order_count': shops,
              'group_order_number': shops > 1 ? 'GRP1700000000000' : null,
              'order_ids': ['o1', if (shops > 1) 'o2'],
            }
          ]);
        }
        if (path.endsWith('/rpc/commit_balance_order')) {
          if (balanceCommitError != null) {
            return http.Response(
              jsonEncode({
                'code': 'P0001',
                'message': balanceCommitError,
                'details': null,
                'hint': null,
              }),
              400,
              request: req,
              headers: _json,
            );
          }
          return ok([
            {
              'order_id': 'o1',
              'order_number': 'ORD00000001',
              'status': 'committed',
              'total': 209.99,
              'order_count': 1,
              'order_ids': ['o1'],
              'new_balance': balance - 209.99,
            }
          ]);
        }
        if (path.endsWith('/rpc/cancel_checkout_session')) return ok(true);
        if (path.endsWith('/rpc/release_flash_sale')) {
          return ok({'success': true, 'released': 0});
        }
        if (path.endsWith('/rpc/get_my_invoice_profile')) {
          return ok({'invoice_full_name': null});
        }
        if (path.endsWith('/functions/v1/get-balance')) {
          return ok({
            'balance': {'user_id': _userId, 'balance': balance, 'locked_balance': 0},
          });
        }
        if (path.endsWith('/rest/v1/cart')) {
          if (req.method == 'DELETE') {
            return http.Response('', 204, request: req);
          }
          return ok(cartRows);
        }
        if (path.endsWith('/rest/v1/app_about_settings')) {
          return ok(wantsObject ? aboutSettings : [aboutSettings]);
        }
        if (path.endsWith('/rest/v1/shops')) {
          final idFilter = req.url.queryParameters['id'] ?? 'eq.s1';
          final row = shopRow(idFilter.replaceFirst('eq.', ''));
          return ok(wantsObject ? row : [row]);
        }
        if (path.endsWith('/rest/v1/addresses')) {
          return ok([
            {
              'id': 'addr-1',
              'user_id': _userId,
              'title': 'Ev',
              'full_name': 'Test Musteri',
              'phone': '05550000000',
              'address_line1': 'Cudi Mah. 1. Sok',
              'city': 'Cizre',
              'is_default': true,
              'created_at': '2026-01-01T00:00:00Z',
              'updated_at': '2026-01-01T00:00:00Z',
            }
          ]);
        }
        return ok(wantsObject ? <String, dynamic>{} : <dynamic>[]);
      });
}

Map<String, dynamic> _cartRow({
  required String id,
  required String productId,
  required String shopId,
  int quantity = 1,
  String? flashSaleId,
}) {
  return {
    'id': id,
    'user_id': _userId,
    'product_id': productId,
    'quantity': quantity,
    'created_at': '2026-10-17T10:00:00Z',
    'updated_at': '2026-10-17T10:00:00Z',
    'variant_data': null,
    'flash_sale_id': flashSaleId,
    'flash_price': flashSaleId != null ? 80 : null,
    'products': {
      'name': 'Ürün $productId',
      'price': 100,
      'old_price': null,
      'discount_price': null,
      'image_url': null,
      'shop_id': shopId,
      'is_available': true,
      'stock_quantity': 10,
      'shipping_fee': null,
      'free_shipping': false,
      'min_order_quantity': null,
      'max_order_quantity': null,
      'shops': {'name': shopId == 's1' ? 'Dükkan A' : 'Dükkan B'},
    },
  };
}

late _Backend _backend;

/// Sunucuya gidip istemcinin sipariş/para yazdığı eski yollar.
void _expectNoLegacyOrderWrites() {
  for (final legacy in [
    '/rest/v1/orders',
    '/rest/v1/order_items',
    '/rpc/use_coupon',
    '/rpc/apply_campaign_rewards_for_order',
    '/functions/v1/use-balance-for-order',
    '/functions/v1/iyzico-payment-init',
  ]) {
    expect(
      _backend.calls(legacy).where((r) => r.method != 'GET'),
      isEmpty,
      reason: 'eski akış çağrısı: $legacy',
    );
  }
}

void _expectNoAmountsSent(http.Request prepare) {
  final body = _backend.bodyOf(prepare);
  final items = body['p_items'];
  expect(items, isA<List>(), reason: 'p_items JSON dizisi olmalı (metin değil)');
  final text = jsonEncode(body);
  for (final forbidden in ['price', 'total', 'subtotal', 'delivery_fee', 'discount', 'amount']) {
    expect(text.contains(forbidden), isFalse, reason: '$forbidden gönderilmemeli');
  }
}

Future<void> _settle(WidgetTester tester, [int frames = 30]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Ekranı ana sayfanın üstüne açar (başarıda popUntil(isFirst) için).
Future<void> _open(WidgetTester tester, WidgetBuilder builder) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: builder),
              ),
              child: const Text('ödemeye git'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ödemeye git'));
  await _settle(tester);
}

Future<void> _tapConfirm(WidgetTester tester) async {
  final button = find.widgetWithText(ElevatedButton, 'Siparişi Onayla').first;
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await _settle(tester);
}

Future<void> _tapDialogConfirm(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(ElevatedButton, 'Siparişi Onayla'),
    ),
  );
  await _settle(tester);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    _backend = _Backend();
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: _backend.client(),
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
      ),
    );
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-access-token',
        'token_type': 'bearer',
        'refresh_token': 'test-refresh-token',
        'user': {
          'id': _userId,
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
        },
      }),
    );
  });

  setUp(() {
    _backend.requests.clear();
    _backend.cartRows = [];
    _backend.balance = 1000;
    _backend.serverDeliveryFee = 9.99;
    _backend.balanceCommitError = null;
  });

  group('CheckoutService', () {
    test('sunucu oturum satiri (session_id/items/sub_orders) okunur', () async {
      _backend.cartRows = [
        _cartRow(id: 'c1', productId: 'p1', shopId: 's1', quantity: 2),
      ];
      final session = await CheckoutService(Supabase.instance.client).prepareCheckout(
        const CheckoutSessionRequest(
          items: [CheckoutItemRequest(productId: 'p1', quantity: 2)],
          addressId: 'addr-1',
          paymentMethod: 'cash',
          idempotencyKey: 'cart_test_key',
          couponIds: ['k1'],
          pickupShopIds: ['s1'],
        ),
      );

      expect(session.id, 'sess-1');
      expect(session.serverTotal, closeTo(209.99, 0.001));
      expect(session.items.single.lineTotal, 200);
      expect(session.subOrders.single.shopName, 'Dükkan A');
      expect(session.isCod, isTrue);

      final body = _backend.bodyOf(_backend.calls('/rpc/prepare_checkout_session').single);
      expect(body['p_coupon_ids'], ['k1']);
      expect(body['p_pickup_shop_ids'], ['s1']);
      _expectNoAmountsSent(_backend.calls('/rpc/prepare_checkout_session').single);
    });

    test('APP hata mesaji kod ve kullanici metnine ayrilir', () async {
      _backend.balanceCommitError =
          'APP: insufficient_balance | Yetersiz bakiye! Mevcut: ₺50.00, Gerekli: ₺115.00';
      await expectLater(
        CheckoutService(Supabase.instance.client).commitBalanceOrder('sess-1'),
        throwsA(
          isA<CheckoutException>()
              .having((e) => e.code, 'code', 'insufficient_balance')
              .having((e) => e.userMessage, 'userMessage',
                  'Yetersiz bakiye! Mevcut: ₺50.00, Gerekli: ₺115.00'),
        ),
      );
    });

    test('commit sonucu coklu siparis bilgisini tasir', () async {
      _backend.cartRows = [
        _cartRow(id: 'c1', productId: 'p1', shopId: 's1'),
        _cartRow(id: 'c2', productId: 'p2', shopId: 's2'),
      ];
      final result =
          await CheckoutService(Supabase.instance.client).commitCodOrder('sess-1');
      expect(result.orderCount, 2);
      expect(result.orderIds, ['o1', 'o2']);
      expect(result.groupOrderNumber, 'GRP1700000000000');
    });
  });

  group('CartProvider flaş talebi', () {
    test('siparis sonrasi temizlik talebi geri vermez, elle temizlik verir', () async {
      _backend.cartRows = [
        _cartRow(id: 'c1', productId: 'p1', shopId: 's1', flashSaleId: 'sale-1'),
      ];
      final provider = CartProvider();
      await provider.loadCart();

      await provider.clearCart(releaseFlashSales: false);
      expect(_backend.calls('/rpc/release_flash_sale'), isEmpty);
      expect(_backend.calls('/rest/v1/cart').where((r) => r.method == 'DELETE'), hasLength(1));

      await provider.loadCart();
      await provider.clearCart();
      expect(_backend.calls('/rpc/release_flash_sale'), hasLength(1));
      provider.dispose();
    });
  });

  group('CheckoutScreen (tek dükkan)', () {
    testWidgets('kapida nakit: sunucu toplami gosterilir, siparis commit ile acilir',
        (tester) async {
      _backend.cartRows = [
        _cartRow(id: 'c1', productId: 'p1', shopId: 's1', quantity: 2),
        // Mağaza içi sepetten gelindiğinde ana sepette başka dükkan da olabilir.
        _cartRow(id: 'c2', productId: 'p2', shopId: 's2'),
      ];

      await _open(
        tester,
        (_) => const CheckoutScreen(shopId: 's1', shopName: 'Dükkan A'),
      );
      await _tapConfirm(tester);

      // Onay penceresi SUNUCU tutarlarını gösterir (200 + 9.99).
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('₺209.99')),
        findsOneWidget,
      );

      final prepare = _backend.calls('/rpc/prepare_checkout_session').single;
      final body = _backend.bodyOf(prepare);
      expect(body['p_items'], [
        {'product_id': 'p1', 'quantity': 2},
      ], reason: 'yalnız bu dükkanın satırları gider');
      expect(body['p_payment_method'], 'cash');
      expect(body['p_address_id'], 'addr-1');
      _expectNoAmountsSent(prepare);

      await _tapDialogConfirm(tester);

      final commit = _backend.calls('/rpc/commit_cod_order').single;
      expect(_backend.bodyOf(commit), {'p_session_id': 'sess-1'});
      expect(find.text('Siparişiniz başarıyla oluşturuldu!'), findsOneWidget);

      // Yalnız siparişe giren satır silinir; flaş/diğer dükkan korunur.
      final deletes = _backend.calls('/rest/v1/cart').where((r) => r.method == 'DELETE').toList();
      expect(deletes, hasLength(1));
      expect(deletes.single.url.query, contains('id=eq.c1'));
      expect(_backend.calls('/rpc/release_flash_sale'), isEmpty);
      _expectNoLegacyOrderWrites();
    });
  });

  group('MultiShopCheckoutScreen', () {
    testWidgets('iki dukkan + flas: tek oturum, sunucu dokumu, talep geri verilmez',
        (tester) async {
      _backend.cartRows = [
        _cartRow(id: 'c1', productId: 'p1', shopId: 's1'),
        _cartRow(id: 'c2', productId: 'p2', shopId: 's2', flashSaleId: 'sale-1'),
      ];
      final cart = CartProvider();
      await tester.runAsync(cart.loadCart);
      addTearDown(cart.dispose);

      await _open(
        tester,
        (_) => MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AddressProvider(_userId)),
            ChangeNotifierProvider.value(value: cart),
          ],
          child: const MultiShopCheckoutScreen(),
        ),
      );
      await _tapConfirm(tester);

      final prepare = _backend.calls('/rpc/prepare_checkout_session').single;
      expect(_backend.bodyOf(prepare)['p_items'], [
        {'product_id': 'p1', 'quantity': 1},
        {'product_id': 'p2', 'quantity': 1, 'flash_sale_id': 'sale-1'},
      ]);
      _expectNoAmountsSent(prepare);

      // Sunucu dökümü: A 100 + 9.99, B 80 + 9.99 → 199.98
      final dialog = find.byType(AlertDialog);
      expect(find.descendant(of: dialog, matching: find.text('₺109.99')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('₺89.99')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('₺199.98')), findsOneWidget);

      await _tapDialogConfirm(tester);

      expect(_backend.calls('/rpc/commit_cod_order'), hasLength(1));
      expect(find.text('2 dükkan için sipariş oluşturuldu.'), findsOneWidget);
      expect(find.text('Sipariş Grup No: GRP1700000000000'), findsOneWidget);
      expect(_backend.calls('/rpc/release_flash_sale'), isEmpty);
      final deletes = _backend.calls('/rest/v1/cart').where((r) => r.method == 'DELETE').toList();
      expect(deletes, hasLength(1));
      expect(deletes.single.url.query, contains('user_id=eq.$_userId'));
      _expectNoLegacyOrderWrites();
    });
  });
}
