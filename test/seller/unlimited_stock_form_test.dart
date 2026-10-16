import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cizreapp/core/models/product_model.dart';
import 'package:cizreapp/features/seller/screens/manage_product_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/test_fonts.dart';

/// Ürün formu, stok alanı: boş = sınırsız (kayıtta `stock_quantity: null`),
/// 0 = "Tükendi" uyarısı, adet = takipli stok. "Müşteri kaç adet alabilir?"
/// alanı stoğun hemen altında ve `max_order_quantity` olarak kaydedilir.
///
/// Görüntü: `PNG_OUT=<klasör> flutter test test/seller/unlimited_stock_form_test.dart`

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
const _category = 'Gıda';
final _shotKey = GlobalKey();
final List<http.Request> _requests = [];

Map<String, dynamic> _productRow(Map<String, dynamic> patch) => {
  'id': 'p1',
  'shop_id': _shopId,
  'name': 'Ev yapımı reçel',
  'description': 'Kayısı reçeli',
  'price': patch['price'] ?? 120,
  'stock_quantity': patch['stock_quantity'] ?? Product.unlimitedStockValue,
  'stock_unlimited': patch['stock_quantity'] == null,
  'image_url': 'https://cdn.invalid/p.webp',
  'category': _category,
  'is_available': true,
  'created_at': '2026-10-16T10:00:00Z',
  'updated_at': '2026-10-16T10:00:00Z',
  'product_type': 'normal',
};

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
      'digital_commission_rate': 10,
      'digital_warning_note': null,
    };
    body = single ? row : [row];
  } else if (name == 'products' && req.method == 'PATCH') {
    final row = _productRow(jsonDecode(req.body) as Map<String, dynamic>);
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

Product _product({required int stock, bool unlimited = false}) => Product(
  id: 'p1',
  shopId: _shopId,
  name: 'Ev yapımı reçel',
  description: 'Kayısı reçeli',
  price: 120,
  stockQuantity: stock,
  stockUnlimited: unlimited,
  imageUrl: 'https://cdn.invalid/p.webp',
  category: _category,
  isAvailable: true,
  createdAt: DateTime.utc(2026, 10, 16),
  updatedAt: DateTime.utc(2026, 10, 16),
);

Finder get _stockField => find.widgetWithText(TextFormField, 'Stok');

Future<void> _pumpForm(WidgetTester tester, Product product) async {
  tester.view.physicalSize = const Size(390, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => RepaintBoundary(key: _shotKey, child: child),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ManageProductScreen(product: product)),
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

/// PNG_OUT verilmişse Fiyatlandırma kartını kaydeder.
Future<void> _capture(WidgetTester tester, String name) async {
  final dir = Platform.environment['PNG_OUT'];
  if (dir == null) return;
  final top = tester.getTopLeft(find.text('Fiyatlandırma')).dy - 24;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
  await tester.runAsync(() async {
    final full = await boundary.toImage();
    final recorder = ui.PictureRecorder();
    const height = 900.0;
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      full,
      Rect.fromLTWH(0, top, full.width.toDouble(), height),
      Rect.fromLTWH(0, 0, full.width.toDouble(), height),
      Paint(),
    );
    final cropped = await recorder.endRecording().toImage(full.width, height.toInt());
    final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Map<String, dynamic> _savedPatch() {
  final patch = _requests.singleWhere(
    (r) => r.method == 'PATCH' && r.url.pathSegments.last == 'products',
  );
  return jsonDecode(patch.body) as Map<String, dynamic>;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadTestFonts();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path,
    );
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

  testWidgets('sınırsız ürün boş stokla açılır, boş kayıt stock_quantity: null gönderir', (
    tester,
  ) async {
    await _pumpForm(
      tester,
      _product(stock: Product.unlimitedStockValue, unlimited: true),
    );
    final field = tester.widget<TextFormField>(_stockField);
    expect(field.controller!.text, isEmpty);
    expect(find.textContaining('ürün SINIRSIZ satılır'), findsOneWidget);
    expect(find.text('Müşteri kaç adet alabilir?'), findsOneWidget);
    expect(find.textContaining('EN FAZLA 2 adet alabilir'), findsOneWidget);
    // Sunucunun koyduğu 2 sınırı alanda boş görünür (ipucu "2").
    final maxField = find.widgetWithText(TextFormField, 'En fazla adet');
    expect(tester.widget<TextFormField>(maxField).controller!.text, isEmpty);

    await tester.enterText(maxField, '1');
    await tester.pumpAndSettle();
    await _capture(tester, 'unlimited_stock_form.png');

    await tester.tap(find.text('Değişiklikleri Kaydet'));
    await tester.pumpAndSettle();

    final body = _savedPatch();
    expect(body.containsKey('stock_quantity'), isTrue);
    expect(body['stock_quantity'], isNull);
    expect(body['max_order_quantity'], 1);
    await tester.pump(const Duration(seconds: 5)); // SnackBar kapanır
  });

  testWidgets('stok boşken en fazla adet 2\'yi aşamaz; stok girilince aşabilir', (
    tester,
  ) async {
    await _pumpForm(
      tester,
      _product(stock: Product.unlimitedStockValue, unlimited: true),
    );
    final maxField = find.widgetWithText(TextFormField, 'En fazla adet');
    await tester.enterText(maxField, '5');
    await tester.tap(find.text('Değişiklikleri Kaydet'));
    await tester.pump();
    expect(find.text('Stok yokken en fazla 2'), findsOneWidget);
    expect(_requests.where((r) => r.method == 'PATCH'), isEmpty);

    await tester.enterText(_stockField, '20');
    await tester.pumpAndSettle();
    expect(find.textContaining('müşteri stok kadar alabilir'), findsOneWidget);
    await tester.tap(find.text('Değişiklikleri Kaydet'));
    await tester.pumpAndSettle();
    final body = _savedPatch();
    expect(body['stock_quantity'], 20);
    expect(body['max_order_quantity'], 5);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('0 yazınca "Tükendi" uyarısı, adet yazınca takipli stok kaydedilir', (
    tester,
  ) async {
    await _pumpForm(tester, _product(stock: 4));
    expect(tester.widget<TextFormField>(_stockField).controller!.text, '4');
    expect(find.textContaining('size bildirim gelir'), findsOneWidget);

    await tester.enterText(_stockField, '0');
    await tester.pumpAndSettle();
    expect(find.textContaining('müşterilere "Tükendi" görünür'), findsOneWidget);
    await _capture(tester, 'zero_stock_form.png');

    await tester.enterText(_stockField, '12');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Değişiklikleri Kaydet'));
    await tester.pumpAndSettle();
    expect(_savedPatch()['stock_quantity'], 12);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('sabit değer elle yazılamaz', (tester) async {
    await _pumpForm(tester, _product(stock: 4));
    await tester.enterText(_stockField, '999999');
    await tester.tap(find.text('Değişiklikleri Kaydet'));
    await tester.pump();
    expect(find.text('Sınırsız için boş bırakın'), findsOneWidget);
    expect(_requests.where((r) => r.method == 'PATCH'), isEmpty);
    await tester.pump(const Duration(seconds: 5));
  });

  group('Product stok yardımcıları', () {
    test('bayrak ya da sabit değer sınırsız sayılır', () {
      expect(_product(stock: 5).isStockUnlimited, isFalse);
      expect(_product(stock: 5).stockLabel, '5');
      expect(_product(stock: 0, unlimited: true).isStockUnlimited, isTrue);
      expect(_product(stock: Product.unlimitedStockValue).stockLabel, 'Sınırsız');
      expect(_product(stock: Product.unlimitedStockValue).inStock, isTrue);
      expect(_product(stock: 0).inStock, isFalse);
    });

    test('sınırsızda sepet en fazla 2, stokluda stok kadar', () {
      final unl = _product(stock: Product.unlimitedStockValue, unlimited: true);
      expect(unl.maxOrderQty, 2);
      expect(unl.maxCartQuantity, 2);
      expect(unl.orderQuantityLabel, 'En fazla 2 adet alınabilir');
      expect(unl.copyWith(maxOrderQuantity: 1).maxCartQuantity, 1);
      expect(unl.copyWith(maxOrderQuantity: 9).maxCartQuantity, 2);

      final lim = _product(stock: 7);
      expect(lim.maxOrderQty, isNull);
      expect(lim.maxCartQuantity, 7);
      expect(lim.copyWith(maxOrderQuantity: 3).maxCartQuantity, 3);
      expect(lim.copyWith(maxOrderQuantity: 30).maxCartQuantity, 7);
    });

    test('fromJson / toJson stock_unlimited taşır', () {
      final p = Product.fromJson(_productRow({'stock_quantity': null}));
      expect(p.stockUnlimited, isTrue);
      expect(p.toJson()['stock_unlimited'], isTrue);
      expect(Product.stockLabelFor(999999), 'Sınırsız');
      expect(Product.stockLabelFor(null), '0');
      expect(Product.stockLabelFor(7), '7');
    });
  });
}
