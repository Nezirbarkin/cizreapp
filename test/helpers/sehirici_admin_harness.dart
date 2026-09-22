// ignore_for_file: depend_on_referenced_packages, deprecated_member_use

import 'dart:io';
import 'dart:ui' as ui;

import 'package:cizreapp/core/theme/app_map_style.dart';
import 'package:cizreapp/core/utils/map_marker_icons.dart';
import 'package:cizreapp/sehirici/admin/sehirici_admin_controller.dart';
import 'package:cizreapp/sehirici/admin/sehirici_admin_management_content.dart';
import 'package:cizreapp/sehirici/models/sehirici_icon_models.dart';
import 'package:cizreapp/sehirici/providers/sehirici_provider.dart';
import 'package:cizreapp/sehirici/services/sehirici_city_service.dart';
import 'package:cizreapp/sehirici/services/sehirici_icon_catalog.dart';
import 'package:cizreapp/sehirici/utils/sehirici_marker_bitmaps.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_google_maps_platform.dart';
import 'sehirici_fake_backend.dart';
import 'sehirici_test_data.dart';
import 'test_fonts.dart';

/// Şehiriçi yönetim paneli widget testlerinin ortak düzeneği: sahte Supabase
/// ([SehiriciFakeBackend]), sahte harita platformu, gerçek zamanlı bekleme
/// yardımcıları ve PNG önizleme alma.
///
/// Kullanım (test dosyasında `main()` içinde):
/// ```dart
/// final h = SehiriciAdminHarness()..register();
/// h.adminTest('...', (tester) async { await h.pumpAdmin(tester); ... });
/// ```
///
/// SEHIRICI_PREVIEW_DIR ortam değişkeni verilirse [snapshot] o klasöre PNG yazar.
class SehiriciAdminHarness {
  final SehiriciFakeBackend backend = SehiriciFakeBackend();
  final GlobalKey rootKey = GlobalKey();
  final String? previewDir = Platform.environment['SEHIRICI_PREVIEW_DIR'];
  late FakeGoogleMapsPlatform platform;

  /// `setUpAll` / `setUp` / `tearDown` kancalarını kurar.
  void register() {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUpAll(() async {
      await loadTestFonts();
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(
        url: 'https://test.supabase.co',
        anonKey: 'test-anon-key',
        httpClient: MockClient(backend.handle),
      );
    });

    setUp(() {
      backend.reset();
      platform = FakeGoogleMapsPlatform();
      GoogleMapsFlutterPlatform.instance = platform;
      SharedPreferences.setMockInitialValues({});
      MapMarkerIcons.clearCache();
      SehiriciMarkerBitmaps.clearCache();
      MapThemePreference.choice.value = MapThemeChoice.light;
      MapTypePreference.choice.value = MapBaseType.standard;
      SehiriciIconCatalog.instance.seed(SehiriciMarkerIcon.builtinDefaults);
      SehiriciCityService.clearCache();
    });

    tearDown(() {
      final provider = SehiriciProvider();
      for (final t in List.of(provider.activeTrips)) {
        provider.onTripRealtimeDelete(t.tripId);
      }
    });
  }

  /// Ağ yanıtları ve bitmap üretimi gerçek (eşzamansız) işlerdir; sahte zaman
  /// içinde ilerlemezler. Gerçek zamanda bekleyip kareyi yeniler.
  Future<void> settle(WidgetTester tester, {int rounds = 10}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> openTab(WidgetTester tester, int tab) async {
    final chip = find.byKey(ValueKey('sehirici-nav-$tab'));
    // Sağdaki çipler ekran dışında olabilir (yatay kaydırmalı çubuk).
    await tester.ensureVisible(chip);
    await tester.pump();
    await tester.tap(chip);
    await tester.pump();
    await settle(tester, rounds: 6);
  }

  Future<void> pumpAdmin(
    WidgetTester tester, {
    int tab = 0,
    bool withTrips = false,
    double height = 900,
    SehiriciAdminController? controller,
  }) async {
    tester.view.physicalSize = Size(390, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final provider = SehiriciProvider();
    if (withTrips) {
      await tester.runAsync(() => provider.selectCity('city-1'));
      provider.onTripRealtimeUpdate(SehiriciTestData.tripBlue());
      provider.onTripRealtimeUpdate(SehiriciTestData.tripRed());
    }
    await tester.pumpWidget(ChangeNotifierProvider<SehiriciProvider>.value(
      value: provider,
      child: MaterialApp(
        // Alt sayfalar Navigator katmanında çizilir; ekran görüntüsü hepsini
        // kapsasın diye kök sınır burada.
        builder: (context, child) => RepaintBoundary(key: rootKey, child: child),
        home: Scaffold(
          body: SafeArea(
            child: SehiriciAdminManagementContent(controller: controller),
          ),
        ),
      ),
    ));
    await tester.pump();
    await settle(tester);
    if (tab != 0) await openTab(tester, tab);
  }

  Future<void> snapshot(WidgetTester tester, String name) async {
    final dir = previewDir;
    if (dir == null) return;
    await tester.runAsync(() async {
      final boundary =
          rootKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  /// Gölgeler testte varsayılan olarak simsiyah çizilir; PNG doğru görünsün
  /// diye kapatıp gövdenin sonunda geri alıyoruz.
  void adminTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      final old = debugDisableShadows;
      debugDisableShadows = false;
      try {
        await body(tester);
      } finally {
        debugDisableShadows = old;
        // Kaydetme sonrası kullanıcı tarafı sağlayıcı yenilenir ve canlı sefer
        // kanalını açar; bağlantı/yeniden bağlanma zamanlayıcıları test
        // bitince bekliyor olmasın.
        await tester.runAsync(() => Supabase.instance.client
            .removeAllChannels()
            .timeout(const Duration(seconds: 5), onTimeout: () => const []));
      }
    });
  }

  /// [opener]'a dokunup açılan alt sayfa / diyaloğun oturmasını bekler.
  Future<void> openSheet(WidgetTester tester, Finder opener) async {
    await tester.tap(opener);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester, rounds: 3);
  }
}
