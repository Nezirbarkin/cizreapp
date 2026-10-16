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

/// Ürün formu, dijital "Paket" satış şekli: SMM ürünü pakete çevrilince
/// sağlayıcı alanları kaybolur, paket fiyatı istenir ve kayıt isteği
/// `digital_mode: package` + paket fiyatıyla, sağlayıcı alanları OLMADAN gider.
///
/// Görüntü: `PNG_OUT=<klasör> flutter test test/seller/digital_package_form_test.dart`

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
const _category = 'Sosyal Medya';
final _shotKey = GlobalKey();
final List<http.Request> _requests = [];

Map<String, dynamic> _productRow(Map<String, dynamic> patch) => {
  'id': 'p1',
  'shop_id': _shopId,
  'name': 'Instagram Takipçi',
  'description': '1000 gerçek takipçi',
  'price': patch['price'] ?? 12,
  'stock_quantity': 0,
  'image_url': 'https://cdn.invalid/p.webp',
  'category': _category,
  'is_available': true,
  'created_at': '2026-10-16T10:00:00Z',
  'updated_at': '2026-10-16T10:00:00Z',
  'product_type': 'digital',
  'digital_mode': patch['digital_mode'] ?? 'smm',
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

Product _smmProduct() => Product(
  id: 'p1',
  shopId: _shopId,
  name: 'Instagram Takipçi',
  description: '1000 gerçek takipçi',
  price: 12,
  stockQuantity: 0,
  imageUrl: 'https://cdn.invalid/p.webp',
  category: _category,
  isAvailable: true,
  createdAt: DateTime.utc(2026, 10, 16),
  updatedAt: DateTime.utc(2026, 10, 16),
  productType: 'digital',
  smmProviderId: 'prov-1',
  smmServiceId: '77',
  pricePer1000: 12,
  minQuantity: 100,
  maxQuantity: 10000,
);

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

/// PNG_OUT verilmişse dijital bölümü (Satış Şekli'nden itibaren) kaydeder.
Future<void> _capture(WidgetTester tester, String name) async {
  final dir = Platform.environment['PNG_OUT'];
  if (dir == null) return;
  final top = tester.getTopLeft(find.text('Satış Şekli')).dy - 24;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
  await tester.runAsync(() async {
    final full = await boundary.toImage();
    final recorder = ui.PictureRecorder();
    const height = 1500.0;
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

  testWidgets('SMM ürünü pakete çevrilip kaydedilir; sağlayıcı alanları gönderilmez', (
    tester,
  ) async {
    await _pumpForm(tester, _smmProduct());
    expect(find.text('Satış Şekli'), findsOneWidget);
    expect(find.text('SMM Sağlayıcısı *'), findsOneWidget);
    expect(find.text('Paket Fiyatı (₺) *'), findsNothing);

    await tester.tap(find.text('Paket'));
    await tester.pumpAndSettle();
    expect(find.text('SMM Sağlayıcısı *'), findsNothing);
    expect(find.text('1000 Adet Fiyatı (₺) *'), findsNothing);

    await tester.enterText(find.widgetWithText(TextFormField, 'Paket Fiyatı (₺) *'), '49,90');
    // Etiket yukarı kayma animasyonu bitsin (görüntü için).
    await tester.pumpAndSettle();
    expect(find.text('Kazanç Hesaplaması (Paket)'), findsOneWidget);
    expect(find.text('+₺49.90'), findsOneWidget);
    expect(find.text('+₺44.91'), findsOneWidget); // %10 dijital komisyon sonrası
    await _capture(tester, 'digital_package_form.png');

    await tester.tap(find.text('Değişiklikleri Kaydet'));
    await tester.pumpAndSettle();

    final patch = _requests.singleWhere(
      (r) => r.method == 'PATCH' && r.url.pathSegments.last == 'products',
    );
    final body = jsonDecode(patch.body) as Map<String, dynamic>;
    expect(body['digital_mode'], 'package');
    expect(body['price'], 49.9);
    expect(body['product_type'], 'digital');
    for (final k in ['smm_provider_id', 'smm_service_id', 'price_per_1000', 'min_quantity', 'max_quantity']) {
      expect(body.containsKey(k), isFalse, reason: k);
    }
    // Paket için sağlayıcı taban değeri yazılmaz.
    expect(
      _requests.where((r) => r.url.pathSegments.last == 'smm_set_product_baseline'),
      isEmpty,
    );
    await tester.pump(const Duration(seconds: 5)); // SnackBar kapanır
  });

  testWidgets('pakette fiyat zorunlu: boş kayıt istek göndermez', (tester) async {
    await _pumpForm(tester, _smmProduct());
    await tester.tap(find.text('Paket'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Değişiklikleri Kaydet'));
    await tester.pump();
    expect(find.text("Geçerli bir paket fiyatı girin (0'dan büyük)"), findsOneWidget);
    expect(_requests.where((r) => r.method == 'PATCH'), isEmpty);
    await tester.pump(const Duration(seconds: 5));
  });
}
