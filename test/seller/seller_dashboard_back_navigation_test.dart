import 'dart:convert';

import 'package:cizreapp/features/seller/screens/seller_dashboard_screen.dart';
import 'package:cizreapp/features/seller/widgets/common/seller_bottom_nav.dart';
import 'package:cizreapp/features/seller/widgets/dashboard/seller_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/test_fonts.dart';

/// Satıcı paneli geri gezinmesi. Eskiden panelin PopScope'u `canPop: false`
/// iken kendi geri işleyicisinden `Navigator.maybePop()` çağırıyordu; bu da
/// aynı işleyiciyi yeniden tetikleyip sonsuz bir mikro-görev döngüsüne
/// giriyordu: geri oka / Android geri tuşuna basınca uygulama tamamen
/// donuyordu. Bu testler donma olursa asılı kalır (zaman aşımına düşer).

const _shopId = 'shop-1';

const _shop = {
  'id': _shopId,
  'name': 'Test Dükkan',
  'owner_id': 'seller-1',
  'commission_rate': 10.0,
  'has_own_courier': true,
  'is_accepting_orders': true,
  'delivery_fee': 0,
};

const _product = {
  'id': 'product-1',
  'shop_id': _shopId,
  'name': 'Deneme Ürünü',
  'price': 100,
  'stock_quantity': 5,
  'created_at': '2026-09-01T10:00:00Z',
  'updated_at': '2026-09-01T10:00:00Z',
};

/// Her isteğe boş ama geçerli yanıt veren sahte PostgREST. [delay] verilirse
/// yanıtlar gecikir; böylece yükleme sürerken ekranın durumu görülebilir.
class _FakeServer {
  Duration delay = Duration.zero;
  int shopLoads = 0;
  int _inFlight = 0;

  /// Aynı anda yanıt bekleyen en çok istek (paralel yükleme ölçüsü).
  int maxInFlight = 0;

  MockClient client() => MockClient((req) async {
    final name = req.url.pathSegments.last;
    // Panelin kendi yüklemesi (_loadDashboardData) mağazayı bu sütunla ister
    // (PayoutService.getShopInfo'nun sorgularında bu sütun yok).
    if (name == 'shops' && req.url.queryParameters['select']?.contains('is_accepting_orders') == true) {
      shopLoads++;
    }
    _inFlight++;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    try {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
    } finally {
      _inFlight--;
    }
    // Sayım (HEAD + count=exact): gövde yok, sayı content-range'de.
    if (req.method == 'HEAD') {
      return http.Response(
        '',
        200,
        request: req,
        headers: {'content-range': name == 'products' ? '0-0/1' : '*/0'},
      );
    }
    final single = (req.headers['accept'] ?? '').contains('vnd.pgrst.object');
    final Object body = switch (name) {
      'shops' => single ? _shop : [_shop],
      'products' => single ? _product : [_product],
      'get_shop_total_views' || 'get_shop_total_favorites' => 0,
      _ => single ? <String, dynamic>{} : <Object>[],
    };
    return http.Response(
      jsonEncode(body),
      200,
      request: req,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

late _FakeServer _server;

/// Paneli, ayarlar menüsündeki gibi bir önceki ekranın üstüne açar.
/// [asRoot]: satıcı girişindeki gibi tüm yığını silip KÖK sayfa olarak açar.
Future<void> _openPanel(WidgetTester tester, {bool asRoot = false}) async {
  tester.view.physicalSize = const Size(430, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () {
                final panel = MaterialPageRoute<void>(
                  builder: (_) => const SellerDashboardScreen(),
                );
                if (asRoot) {
                  Navigator.pushAndRemoveUntil(context, panel, (_) => false);
                } else {
                  Navigator.push(context, panel);
                }
              },
              child: const Text('Paneli aç'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Paneli aç'));
  await tester.pumpAndSettle();
  expect(find.text('Satıcı Paneli'), findsOneWidget);
  expect(find.byType(SellerBottomNav), findsOneWidget);
}

/// Android geri tuşu: motorun `flutter/navigation` kanalına gönderdiği
/// `popRoute` mesajının aynısı.
Future<void> _systemBack(WidgetTester tester, {bool settle = true}) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
  if (settle) await tester.pumpAndSettle();
}

/// Panelin kendi AppBar'ındaki geri oku (sekme içi sayfanın AppBar'ında da
/// bir geri oku olabilir; onu değil, paneli hedefler).
Finder get _panelBackButton => find.descendant(
  of: find.widgetWithText(AppBar, 'Satıcı Paneli'),
  matching: find.byType(BackButton),
);

Future<void> _tapNav(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(SellerBottomNav), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

void _expectPanelClosed() {
  expect(find.text('Satıcı Paneli'), findsNothing);
  expect(find.text('Paneli aç'), findsOneWidget);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Gerçek glif ölçüleri: test fontunda (her harf kare) alt bar etiketleri
    // birkaç satıra kırılıp cihazda olmayan taşma hatası veriyordu.
    await loadTestFonts();
    SharedPreferences.setMockInitialValues({});
    _server = _FakeServer();
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: _server.client(),
    );
    // Ağsız oturum: JWT olmayan erişim anahtarının süresi yoktur, yenilenmez.
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

  setUp(() {
    _server.delay = Duration.zero;
    _server.shopLoads = 0;
    _server.maxInFlight = 0;
  });

  testWidgets('Genel Bakış: üstteki geri oku paneli kapatır (donmaz)', (tester) async {
    await _openPanel(tester);
    await tester.tap(_panelBackButton);
    await tester.pumpAndSettle();
    _expectPanelClosed();
  });

  testWidgets('Genel Bakış: Android geri tuşu paneli kapatır (donmaz)', (tester) async {
    await _openPanel(tester);
    await _systemBack(tester);
    _expectPanelClosed();
  });

  testWidgets('Girişten sonra KÖK sayfa olan panel: Android geri tuşu ana sayfaya döner (donmaz)', (tester) async {
    await _openPanel(tester, asRoot: true);
    expect(find.text('Paneli aç'), findsNothing, reason: 'altında sayfa kalmamalı');
    expect(_panelBackButton, findsNothing, reason: 'kökte geri oku yok');

    await _systemBack(tester);
    _expectPanelClosed();
  });

  testWidgets('Diğer > Kuponlar: geri önce sekme içindeki sayfayı kapatır', (tester) async {
    await _openPanel(tester);
    await _tapNav(tester, 'Diğer');
    await tester.tap(find.text('Kuponlar'));
    await tester.pumpAndSettle();
    expect(find.byType(SellerMenu), findsNothing);

    await _systemBack(tester);
    expect(find.text('Satıcı Paneli'), findsOneWidget, reason: 'panel açık kalmalı');
    expect(find.byType(SellerMenu), findsOneWidget);

    await _systemBack(tester);
    _expectPanelClosed();
  });

  testWidgets('Üstteki geri oku da önce sekme içindeki sayfayı kapatır', (tester) async {
    await _openPanel(tester);
    await _tapNav(tester, 'Diğer');
    await tester.tap(find.text('Kuponlar'));
    await tester.pumpAndSettle();

    await tester.tap(_panelBackButton);
    await tester.pumpAndSettle();
    expect(find.text('Satıcı Paneli'), findsOneWidget);
    expect(find.byType(SellerMenu), findsOneWidget);
  });

  testWidgets('Gizli sekmede açık kalan sayfa, görünen sekmede geriyi yutmaz', (tester) async {
    await _openPanel(tester);
    await _tapNav(tester, 'Diğer');
    await tester.tap(find.text('Kuponlar'));
    await tester.pumpAndSettle();
    await _tapNav(tester, 'Genel Bakış');

    await _systemBack(tester);
    _expectPanelClosed();
  });

  testWidgets('Ürünler çoklu seçim: geri seçimden çıkar, panel açık kalır', (tester) async {
    await _openPanel(tester);
    await _tapNav(tester, 'Ürünler');
    expect(find.text('Deneme Ürünü'), findsOneWidget);

    await tester.tap(find.byTooltip('Çoklu seçim'));
    await tester.pumpAndSettle();
    expect(find.text('Ürün seçin'), findsOneWidget);

    await _systemBack(tester);
    expect(find.text('Ürün seçin'), findsNothing);
    expect(find.text('Ürünlerim'), findsOneWidget);
    expect(find.text('Satıcı Paneli'), findsOneWidget);

    await _systemBack(tester);
    _expectPanelClosed();
  });

  testWidgets('Açılışta mağaza bulunduktan sonraki istekler PARALEL gider', (tester) async {
    _server.delay = const Duration(milliseconds: 40);
    await _openPanel(tester);
    // Eskiden ~15 istek tek tek bekleniyordu (en çok 1 istek yolda).
    expect(_server.maxInFlight, greaterThanOrEqualTo(8));
    // Sayılar satır indirilmeden (HEAD) geldi.
    expect(find.text('Satıcı Paneli'), findsOneWidget);
  });

  testWidgets("Yenileme paneli söküp spinner'a çevirmez: alt bar ve sekme yerinde kalır", (tester) async {
    await _openPanel(tester);
    await _tapNav(tester, 'Diğer');
    await tester.tap(find.text('Kuponlar'));
    await tester.pumpAndSettle();
    final loadsBefore = _server.shopLoads;

    // Kuponlar'dan dönüş paneli yeniler (onReturnRefresh); yanıtlar gecikir.
    _server.delay = const Duration(milliseconds: 600);
    await _systemBack(tester, settle: false);
    await tester.pump(const Duration(milliseconds: 400)); // geri geçişi bitsin
    expect(_server.shopLoads, loadsBefore + 1, reason: 'yenileme başladı');

    // Yükleme sürerken: tam ekran spinner YOK, alt bar ve Diğer sekmesi yerinde.
    expect(find.byType(SellerBottomNav), findsOneWidget);
    expect(find.byType(SellerMenu), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Geciken yanıtlar (mağaza, sonra paralel parti) tamamlansın.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(_server.shopLoads, loadsBefore + 1);
    expect(find.byType(SellerMenu), findsOneWidget);
    expect(find.text('Satıcı Paneli'), findsOneWidget);
  });
}
