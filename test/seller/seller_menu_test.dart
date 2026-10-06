import 'dart:convert';

import 'package:cizreapp/features/seller/screens/coupons_screen.dart';
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

/// Görev 2.4 — satıcı menüsü yeni tasarımla: "Diğer" sekmesinde ve sağdan
/// açılan yan menüde AYNI menü. Yan menüden açılan araç "Diğer" sekmesinin
/// iç yığınında açılır (alt bar görünür), geri tuşu önce yan menüyü kapatır.

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

MockClient _client() => MockClient((req) async {
  final name = req.url.pathSegments.last;
  if (req.method == 'HEAD') {
    return http.Response('', 200, request: req, headers: {'content-range': '*/0'});
  }
  final single = (req.headers['accept'] ?? '').contains('vnd.pgrst.object');
  final Object body = switch (name) {
    'shops' => single ? _shop : [_shop],
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

Future<void> _openPanel(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 1400);
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
                MaterialPageRoute<void>(builder: (_) => const SellerDashboardScreen()),
              ),
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
}

Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
  await tester.pumpAndSettle();
}

Future<void> _tapNav(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(SellerBottomNav), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

Future<void> _openSideMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Menü'));
  await tester.pumpAndSettle();
  expect(find.byType(Drawer), findsOneWidget);
}

Finder get _drawerMenu =>
    find.descendant(of: find.byType(Drawer), matching: find.byType(SellerMenu));

int _currentTab(WidgetTester tester) =>
    tester.widget<SellerBottomNav>(find.byType(SellerBottomNav)).currentIndex;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadTestFonts();
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

  testWidgets('"Diğer" sekmesi yeni menüyü gösterir: kimlik kartı, hızlı işlemler, bölümler', (tester) async {
    await _openPanel(tester);
    await _tapNav(tester, 'Diğer');

    expect(find.byType(SellerMenu), findsOneWidget);
    expect(find.text('Test Dükkan'), findsOneWidget);
    expect(find.text('Sipariş alıyor'), findsOneWidget);
    for (final title in [
      'Kuponlar', 'Flash Satış', 'Canlı Yayın', 'İade Talepleri', 'Yorumlar',
      'Mağaza Ayarları', 'Öne Çıkar', 'Sepet Takibi', 'Kategori Ekle', 'SMM Ayarları', 'Dijital Siparişler', 'Yardım',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('yan menü sağdan açılır; geri oku yerinde kalır; bölüm seçince sekme değişir', (tester) async {
    await _openPanel(tester);
    expect(
      find.descendant(of: find.widgetWithText(AppBar, 'Satıcı Paneli'), matching: find.byType(BackButton)),
      findsOneWidget,
    );

    await _openSideMenu(tester);
    expect(_drawerMenu, findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(Drawer), matching: find.text('Siparişler')));
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsNothing);
    expect(_currentTab(tester), 2);
  });

  testWidgets('yan menüden açılan araç "Diğer" sekmesinin iç yığınında; geri önce onu kapatır', (tester) async {
    await _openPanel(tester);
    await _openSideMenu(tester);

    await tester.tap(find.descendant(of: find.byType(Drawer), matching: find.text('Kuponlar')));
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsNothing);
    expect(find.byType(CouponsScreen), findsOneWidget);
    expect(find.byType(SellerBottomNav), findsOneWidget, reason: 'alt bar görünür kalır');
    expect(_currentTab(tester), 4);

    await _systemBack(tester);
    expect(find.byType(CouponsScreen), findsNothing);
    expect(find.byType(SellerMenu), findsOneWidget, reason: '"Diğer" sekmesinin kökü');
    expect(find.text('Satıcı Paneli'), findsOneWidget);
  });

  testWidgets('yan menü açıkken geri tuşu yalnız menüyü kapatır', (tester) async {
    await _openPanel(tester);
    await _openSideMenu(tester);

    await _systemBack(tester);

    expect(find.byType(Drawer), findsNothing);
    expect(find.text('Satıcı Paneli'), findsOneWidget, reason: 'panel açık kalır');
  });

  testWidgets('sipariş alma kapatılınca "Diğer" menüsü canlı güncellenir', (tester) async {
    await _openPanel(tester);
    await _tapNav(tester, 'Diğer');
    expect(find.text('Sipariş alıyor'), findsOneWidget);

    await _tapNav(tester, 'Genel Bakış');
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    await _tapNav(tester, 'Diğer');
    expect(find.text('Siparişler kapalı'), findsOneWidget);
    expect(find.text('Sipariş alıyor'), findsNothing);
  });
}
