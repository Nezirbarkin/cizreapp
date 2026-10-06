import 'dart:convert';
import 'dart:io';

import 'package:cizreapp/core/models/product_model.dart';
import 'package:cizreapp/features/seller/screens/manage_product_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/test_fonts.dart';

/// Ürün formu: satıcı ürün adını yazınca görsel kütüphanesinden öneri gelir
/// (adın kelimelerinden biri yeter), dokununca ana resim olarak eklenir.

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
const _category = 'Manav';

final List<http.Request> _requests = [];

Map<String, dynamic> _preset(int i, String name) => {
  'id': 'preset-$i',
  'name': name,
  'description': null,
  'image_url': 'https://cdn.invalid/preset-$i.webp',
  'is_active': true,
  'display_order': i,
  'created_at': '2026-10-01T10:00:00Z',
  'folder_id': 'folder-manav',
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
      'digital_warning_note': null,
    };
    body = single ? row : [row];
  } else if (name == 'search_product_image_presets') {
    body = [_preset(1, 'Salkım Domates'), _preset(2, 'Domates')];
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

List<Map<String, dynamic>> _searchCalls() => [
  for (final r in _requests)
    if (r.url.pathSegments.last == 'search_product_image_presets')
      jsonDecode(r.body) as Map<String, dynamic>,
];

Future<void> _pumpForm(WidgetTester tester, {Product? product}) async {
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

Finder _nameField() => find.widgetWithText(TextFormField, 'Ürün Adı *');

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadTestFonts();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
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

  testWidgets('ad yazılınca öneri gelir; dokununca ana resim olur, şerit kapanır', (
    tester,
  ) async {
    await _pumpForm(tester);
    expect(find.text('0/5'), findsOneWidget);

    await tester.enterText(_nameField(), 'Salkım Domates 1 kg');
    // Yazarken istek atılmaz (bekleme süresi).
    await tester.pump(const Duration(milliseconds: 200));
    expect(_searchCalls(), isEmpty);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump();

    final call = _searchCalls().single;
    expect(call['p_query'], 'Salkım Domates 1 kg');
    expect(call['p_match_any'], isTrue);
    expect(call['p_limit'], 8);
    expect(find.text('Kütüphanede hazır görsel var'), findsOneWidget);

    await tester.tap(find.text('Salkım Domates'));
    await tester.pump();
    expect(find.text('1/5'), findsOneWidget);
    expect(
      find.text('"Salkım Domates" görseli ana resim olarak eklendi'),
      findsOneWidget,
    );
    // Görsel eklendi: öneri şeridi kalkar.
    expect(find.text('Kütüphanede hazır görsel var'), findsNothing);

    // Görsel varken ad değişse de istek atılmaz.
    await tester.enterText(_nameField(), 'Salkım Domates 2 kg');
    await tester.pump(const Duration(milliseconds: 700));
    expect(_searchCalls().length, 1);
    await tester.pump(const Duration(seconds: 3)); // SnackBar kapanır
  });

  testWidgets('"Tümünü gör" seçiciyi ürün adıyla açar', (tester) async {
    await _pumpForm(tester);
    await tester.enterText(_nameField(), 'Domates');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Tümünü gör'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Görsel Kütüphanesi'), findsOneWidget);
    final last = _searchCalls().last;
    expect(last['p_query'], 'Domates');
    expect(last['p_match_any'], isFalse);
    expect(last['p_limit'], 60);
  });

  testWidgets('düzenlemede mevcut ad için öneri istenmez', (tester) async {
    await _pumpForm(
      tester,
      product: Product(
        id: 'product-1',
        shopId: _shopId,
        name: 'Domates',
        description: 'Taze',
        price: 30,
        stockQuantity: 10,
        isAvailable: true,
        category: _category,
        createdAt: DateTime.utc(2026, 9, 1, 10),
        updatedAt: DateTime.utc(2026, 9, 1, 10),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(_searchCalls(), isEmpty);
    expect(find.text('Kütüphanede hazır görsel var'), findsNothing);
  });
}
