import 'dart:convert';

import 'package:cizreapp/core/models/product_model.dart';
import 'package:cizreapp/core/widgets/product_extras_widgets.dart';
import 'package:cizreapp/features/seller/screens/manage_product_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/test_fonts.dart';

/// Görev 2.2: teslimat süresi satıcı profilinde (Mağaza Ayarları) zaten
/// olduğundan ürün formundaki "Hazırlık Süresi" (kaç iş günü içinde kargoda)
/// alanı kaldırıldı. Ürün başına eski değer artık gösterilmez ve ürün
/// kaydedilince temizlenir.

class _MemoryAsyncStorage extends GotrueAsyncStorage {
  final Map<String, String> _items = {};

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    _items[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _items.remove(key);
  }
}

const _seller = 'seller-1';
const _shopId = 'shop-1';
const _category = 'Elektronik';

final List<http.Request> _requests = [];

MockClient _http() => MockClient((req) async {
  _requests.add(req);
  final name = req.url.pathSegments.last;
  final single = (req.headers['accept'] ?? '').contains('vnd.pgrst.object');
  Object? body;
  if (name == 'shops') {
    final row = {
      'id': _shopId,
      'seller_categories': [_category],
      'commission_rate': 10,
      'digital_warning_note': null,
    };
    body = single ? row : [row];
  } else if (name == 'products' && req.method == 'PATCH') {
    final patch = jsonDecode(req.body) as Map<String, dynamic>;
    final row = _productJson()..addAll(patch);
    body = single ? row : [row];
  } else {
    body = single ? <String, dynamic>{} : <Object>[];
  }
  return http.Response(
    jsonEncode(body),
    200,
    request: req,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
});

Map<String, dynamic> _productJson() => {
  'id': 'product-1',
  'shop_id': _shopId,
  'name': 'Kulaklık',
  'description': 'Kablosuz kulaklık',
  'price': 250,
  'stock_quantity': 4,
  'image_url': 'https://cdn.invalid/kulaklik.png',
  'is_available': true,
  'category': _category,
  'created_at': '2026-09-01T10:00:00Z',
  'updated_at': '2026-09-01T10:00:00Z',
  'prep_time_min_days': 1,
  'prep_time_max_days': 3,
};

Product _product({int? prepMin = 1, int? prepMax = 3, double? shippingFee}) => Product(
  id: 'product-1',
  shopId: _shopId,
  name: 'Kulaklık',
  description: 'Kablosuz kulaklık',
  price: 250,
  stockQuantity: 4,
  imageUrl: 'https://cdn.invalid/kulaklik.png',
  isAvailable: true,
  category: _category,
  createdAt: DateTime.utc(2026, 9, 1, 10),
  updatedAt: DateTime.utc(2026, 9, 1, 10),
  prepTimeMinDays: prepMin,
  prepTimeMaxDays: prepMax,
  shippingFee: shippingFee,
);

Future<void> _pumpForm(WidgetTester tester, {Product? product}) async {
  // Uzun form (ListView) tek ekranda kurulsun.
  tester.view.physicalSize = const Size(800, 9000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManageProductScreen(product: product),
                ),
              ),
              child: const Text('Formu aç'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Formu aç'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadTestFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: _http(),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryAsyncStorage(),
      ),
    );
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode({
        'access_token': 'token',
        'token_type': 'bearer',
        'refresh_token': 'refresh',
        'user': {
          'id': _seller,
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
        },
      }),
    );
  });

  setUp(_requests.clear);

  testWidgets('ürün başı hazırlık süresi rozeti gösterilmez; kargo bilgisi kalır', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductLogisticsWrap(product: _product(shippingFee: 29.9)),
        ),
      ),
    );

    expect(find.textContaining('kargoda'), findsNothing);
    expect(find.text('Kargo ₺29.90'), findsOneWidget);
  });

  testWidgets('yeni ürün formunda "Hazırlık Süresi" alanı yok', (tester) async {
    await _pumpForm(tester);

    expect(find.text('Ek Özellikler'), findsOneWidget);
    expect(find.text('Rozetler'), findsOneWidget);
    expect(find.text('Hazırlık Süresi'), findsNothing);
    expect(find.text('En az (gün)'), findsNothing);
    expect(find.text('En fazla (gün)'), findsNothing);
  });

  testWidgets('eski hazırlık süresi olan ürün kaydedilince değer TEMİZLENİR', (tester) async {
    await _pumpForm(tester, product: _product());
    expect(find.text('Hazırlık Süresi'), findsNothing);

    await tester.tap(find.text('Değişiklikleri Kaydet'));
    await tester.pumpAndSettle();

    final patch = _requests.singleWhere(
      (r) => r.method == 'PATCH' && r.url.pathSegments.last == 'products',
    );
    final body = jsonDecode(patch.body) as Map<String, dynamic>;
    expect(body.containsKey('prep_time_min_days'), isTrue);
    expect(body['prep_time_min_days'], isNull);
    expect(body['prep_time_max_days'], isNull);
    // Diğer alanlar formdan aynen gider.
    expect(body['name'], 'Kulaklık');
    expect(body['category'], _category);
    expect(find.text('Formu aç'), findsOneWidget, reason: 'kayıttan sonra form kapandı');
  });
}
