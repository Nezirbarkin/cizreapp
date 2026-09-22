// ignore_for_file: depend_on_referenced_packages, deprecated_member_use

import 'dart:io';
import 'dart:ui' as ui;

import 'package:cizreapp/core/theme/app_map_style.dart';
import 'package:cizreapp/core/utils/map_marker_icons.dart';
import 'package:cizreapp/sehirici/models/sehirici_icon_models.dart';
import 'package:cizreapp/sehirici/models/sehirici_models.dart';
import 'package:cizreapp/sehirici/services/sehirici_icon_catalog.dart';
import 'package:cizreapp/sehirici/utils/sehirici_marker_bitmaps.dart';
import 'package:cizreapp/sehirici/widgets/sehirici_live_map.dart';
import 'package:cizreapp/sehirici/widgets/sehirici_map_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/fake_google_maps_platform.dart';
import '../helpers/sehirici_test_data.dart';
import '../helpers/test_fonts.dart';

/// Şehiriçi canlı harita: marker / çizgi kurulumu, yakınlık düzeyleri, vurgu,
/// dokunuşlar ve alt sayfalar. Gerçek harita yerine sahte platform kullanılır
/// (bkz. test/helpers/fake_google_maps_platform.dart).
///
/// SEHIRICI_PREVIEW_DIR ortam değişkeni verilirse görsel doğrulama için
/// PNG çıktıları o klasöre yazılır.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeGoogleMapsPlatform platform;
  final rootKey = GlobalKey();
  final previewDir = Platform.environment['SEHIRICI_PREVIEW_DIR'];

  setUpAll(() async {
    await loadTestFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      anonKey: 'test-anon-key',
      httpClient: MockClient((request) async => http.Response(
            '[]',
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          )),
    );
  });

  setUp(() {
    platform = FakeGoogleMapsPlatform();
    GoogleMapsFlutterPlatform.instance = platform;
    SharedPreferences.setMockInitialValues({});
    MapMarkerIcons.clearCache();
    SehiriciMarkerBitmaps.clearCache();
    MapThemePreference.choice.value = MapThemeChoice.light;
    MapTypePreference.choice.value = MapBaseType.standard;
    SehiriciIconCatalog.instance.seed(SehiriciMarkerIcon.builtinDefaults);
  });

  /// Bitmap üretimi gerçek (eşzamansız) motor işidir; sahte zaman içinde
  /// ilerlemez. Gerçek zamanda bekleyip kareyi yeniler.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 16; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpMap(
    WidgetTester tester, {
    List<SehiriciLine>? lines,
    List<SehiriciActiveTrip>? trips,
    String? highlight,
    double height = 560,
    bool chips = true,
    int zoom = 16,
    Brightness brightness = Brightness.light,
    Key? key,
  }) async {
    tester.view.physicalSize = Size(390, height + 40);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: brightness),
      // Alt sayfalar (modal) Navigator katmanında çizilir; ekran görüntüsü
      // hepsini kapsasın diye kök sınır burada.
      builder: (context, child) => RepaintBoundary(key: rootKey, child: child),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.only(top: 20),
          child: SehiriciLiveMap(
            key: key,
            lines: lines ?? [SehiriciTestData.lineBlue(), SehiriciTestData.lineRed()],
            activeTrips: trips ??
                [SehiriciTestData.tripBlue(), SehiriciTestData.tripRed()],
            center: SehiriciTestData.city,
            zoomLevel: zoom,
            height: height,
            showCouriers: false,
            highlightLineId: highlight,
            showLineChips: chips,
            borderRadius: 0,
          ),
        ),
      ),
    ));
    await tester.pump();
    await settle(tester);
  }

  Future<void> snapshot(WidgetTester tester, String name) async {
    if (previewDir == null) return;
    await tester.runAsync(() async {
      final boundary = rootKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$previewDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  Iterable<String> ids(Iterable<Object> keys, String prefix) => keys
      .map((k) => k is MarkerId ? k.value : (k as PolylineId).value)
      .where((v) => v.startsWith(prefix));

  group('SehiriciLiveMap', () {
    testWidgets('durak, sefer, etiket ve rota çizgilerini kurar', (tester) async {
      await pumpMap(tester);

      final stopIds = ids(platform.markers.keys, 'stop_').toSet();
      // 4A: s1..s6, 7B: s2,s3 (ortak) + s7,s8 → toplam 8 benzersiz durak.
      expect(stopIds, {
        'stop_s1', 'stop_s2', 'stop_s3', 'stop_s4',
        'stop_s5', 'stop_s6', 'stop_s7', 'stop_s8',
      });
      expect(platform.markers.containsKey(const MarkerId('trip_t1')), isTrue);
      expect(platform.markers.containsKey(const MarkerId('trip_t1_label')), isTrue);
      expect(platform.markers.containsKey(const MarkerId('trip_t2')), isTrue);

      // Her hat için kasing + ana çizgi.
      expect(platform.polylines.containsKey(const PolylineId('route_casing_L1')), isTrue);
      expect(platform.polylines.containsKey(const PolylineId('admin_route_L1')), isTrue);
      expect(platform.polylines.containsKey(const PolylineId('route_casing_L2')), isTrue);

      // Kasing ana çizgiden kalın ve altta.
      final casing = platform.polylines[const PolylineId('route_casing_L1')]!;
      final main = platform.polylines[const PolylineId('admin_route_L1')]!;
      expect(casing.width, greaterThan(main.width));
      expect(casing.zIndex, lessThan(main.zIndex));

      await snapshot(tester, 'live_default');
    });

    testWidgets('araç marker\'ı yön (heading) ile döner ve düz (flat) çizilir',
        (tester) async {
      await pumpMap(tester);
      final trip = platform.markers[const MarkerId('trip_t1')]!;
      expect(trip.rotation, 62);
      expect(trip.flat, isTrue);
      expect(trip.anchor, const Offset(0.5, 0.5));
      // Etiket dönmez, aracın tam üstünde (alt-orta çapa).
      final label = platform.markers[const MarkerId('trip_t1_label')]!;
      expect(label.rotation, 0);
      expect(label.flat, isFalse);
      expect(label.anchor, const Offset(0.5, 1.0));
    });

    testWidgets('ikon bitmap\'leri yüksek çözünürlüklü ve dp boyutlu verilir',
        (tester) async {
      await pumpMap(tester);
      final trip = platform.markers[const MarkerId('trip_t1')]!;
      final bmp = trip.icon as BytesMapBitmap;
      // Minibüs: 32×72 dp (32*72 mantıksal boyut), 3× piksel.
      expect(bmp.width, 32);
      expect(bmp.height, 72);
      final decoded = await tester.runAsync(
          () => ui.instantiateImageCodec(bmp.byteData).then((c) => c.getNextFrame()));
      expect(decoded!.image.width, 96); // 32 × 3
      expect(decoded.image.height, 216); // 72 × 3
    });

    testWidgets('durak marker\'ları alt-orta çapalı (levha) ve tıklanabilir',
        (tester) async {
      await pumpMap(tester);
      final stop = platform.markers[const MarkerId('stop_s3')]!;
      expect(stop.anchor.dx, 0.5);
      expect(stop.anchor.dy, 1.0);
      expect(stop.consumeTapEvents, isTrue);
    });

    testWidgets('vurgulu hat: çizgi kalınlaşır, diğer hat ve duraklar solar, oklar çıkar',
        (tester) async {
      await pumpMap(tester, highlight: 'L1');
      final hl = platform.polylines[const PolylineId('admin_route_L1')]!;
      final other = platform.polylines[const PolylineId('admin_route_L2')]!;
      expect(hl.width, 7);
      expect(other.width, 3);
      expect(other.color.a, lessThan(hl.color.a));

      // 4A dışındaki durak (7B'ye özgü) soluk çizilir; 4A durakları tam opak.
      expect(platform.markers[const MarkerId('stop_s7')]!.alpha, lessThan(1));
      expect(platform.markers[const MarkerId('stop_s5')]!.alpha, 1);

      // Yön okları yalnız vurgulu hatta ve rota boyunca.
      final arrows = ids(platform.markers.keys, 'arrow_L1_').toList();
      expect(arrows, isNotEmpty);
      expect(ids(platform.markers.keys, 'arrow_L2_'), isEmpty);
      expect(platform.markers[MarkerId(arrows.first)]!.flat, isTrue);

      await snapshot(tester, 'live_highlight');
    });

    testWidgets('vurgulu hattın ilk/son durağı işaretlenir ve adları yazılır',
        (tester) async {
      await pumpMap(tester, highlight: 'L1');
      // Vurgulu hattın durak adı etiketleri.
      final labels = ids(platform.markers.keys, 'stoplbl_').toSet();
      expect(labels, containsAll(<String>['stoplbl_s1', 'stoplbl_s5', 'stoplbl_s6']));
      // Vurgulu hatta olmayan durağın etiketi yok.
      expect(labels.contains('stoplbl_s7'), isFalse);
    });

    testWidgets('uzaktan bakışta duraklar sade noktaya, araçlar küçüğe döner',
        (tester) async {
      await pumpMap(tester, zoom: 16);
      final nearStop = platform.markers[const MarkerId('stop_s3')]!;
      final nearBmp = nearStop.icon as BytesMapBitmap;
      final nearVehicle = (platform.markers[const MarkerId('trip_t1')]!.icon as BytesMapBitmap);

      platform.zoomTo(12.5);
      await settle(tester);

      final farStop = platform.markers[const MarkerId('stop_s3')]!;
      final farBmp = farStop.icon as BytesMapBitmap;
      expect(farBmp.height!, lessThan(nearBmp.height!));
      // Nokta merkezden yerleşir.
      expect(farStop.anchor, const Offset(0.5, 0.5));
      final farVehicle = (platform.markers[const MarkerId('trip_t1')]!.icon as BytesMapBitmap);
      expect(farVehicle.height!, lessThan(nearVehicle.height!));
      // Uzak zoom'da durak adı ve ok yok.
      expect(ids(platform.markers.keys, 'stoplbl_'), isEmpty);
      expect(ids(platform.markers.keys, 'arrow_'), isEmpty);

      await snapshot(tester, 'live_far');
    });

    testWidgets('durağa dokununca varış süreli alt sayfa açılır', (tester) async {
      await pumpMap(tester);
      platform.tapMarker('stop_s4');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SehiriciStopSheet), findsOneWidget);
      expect(find.text('Şehir Parkı'), findsWidgets);
      expect(find.text('YAKLAŞAN ARAÇLAR'), findsOneWidget);
      // 4A'nın sıradaki durağı s4 → 3 dk.
      expect(find.text('3 dk'), findsOneWidget);
      // Seçili durak turuncu (seçili çizim) — yeni bitmap üretimi bekler.
      await snapshot(tester, 'live_stop_sheet');
    });

    testWidgets('araca dokununca araç sayfası ve takip düğmesi açılır', (tester) async {
      await pumpMap(tester);
      platform.tapMarker('trip_t1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SehiriciTripSheet), findsOneWidget);
      expect(find.text('Ahmet Yılmaz'), findsNothing);
      expect(find.textContaining('Ahmet Yılmaz'), findsOneWidget);
      expect(find.text('Takip et'), findsOneWidget);
      expect(find.text('Hattı göster'), findsOneWidget);
      expect(find.text('31 km/sa'), findsOneWidget);
      await snapshot(tester, 'live_trip_sheet');
    });

    testWidgets('birden çok hatta hat çipleri gösterilir ve dokununca hat vurgulanır',
        (tester) async {
      await pumpMap(tester, chips: true);
      expect(find.text('CANLI'), findsOneWidget);
      expect(find.text('2 araç'), findsOneWidget);
      // Çip: hat adı.
      expect(find.text('Merkez – Hastane'), findsOneWidget);

      await tester.tap(find.text('Çarşı – Sanayi'));
      await tester.pump();
      await settle(tester);
      final hl = platform.polylines[const PolylineId('admin_route_L2')]!;
      final other = platform.polylines[const PolylineId('admin_route_L1')]!;
      expect(hl.width, 7);
      expect(other.width, 3);

      // Aynı çipe tekrar dokunmak vurguyu kaldırır.
      await tester.tap(find.text('Çarşı – Sanayi'));
      await tester.pump();
      await settle(tester);
      expect(platform.polylines[const PolylineId('admin_route_L2')]!.width, 5);
    });

    testWidgets('aktif sefer yokken durum hapı "SEFER YOK" der ama durak ve rota görünür',
        (tester) async {
      await pumpMap(tester, trips: const []);
      expect(find.text('SEFER YOK'), findsOneWidget);
      expect(ids(platform.markers.keys, 'stop_'), isNotEmpty);
      expect(ids(platform.markers.keys, 'trip_'), isEmpty);
      expect(platform.polylines.containsKey(const PolylineId('admin_route_L1')), isTrue);
    });

    testWidgets('rotası olmayan hat için çizgi çizilmez (kuş uçuşu yedek yok)',
        (tester) async {
      final noRoute = SehiriciTestData.lineBlue().copyWith();
      final bare = SehiriciLine(
        id: noRoute.id,
        code: noRoute.code,
        name: noRoute.name,
        colorHex: noRoute.colorHex,
        stops: noRoute.stops,
      );
      await pumpMap(tester, lines: [bare], trips: const []);
      expect(ids(platform.polylines.keys, 'admin_route_'), isEmpty);
      expect(ids(platform.markers.keys, 'stop_'), hasLength(6));
    });

    testWidgets('uydu seçilince harita türü hibrit olur, koyu yüzey ikonları yeniler',
        (tester) async {
      await pumpMap(tester);
      expect(platform.mapType, MapType.normal);
      await MapTypePreference.set(MapBaseType.satellite);
      await tester.pump();
      await settle(tester);
      expect(platform.mapType, MapType.hybrid);
      await snapshot(tester, 'live_satellite');
    });

    testWidgets('koyu görünüm: koyu stil uygulanır', (tester) async {
      MapThemePreference.choice.value = MapThemeChoice.dark;
      await pumpMap(tester, brightness: Brightness.dark, highlight: 'L1');
      expect(platform.style, AppMapStyle.dark);
      await snapshot(tester, 'live_dark');
    });

    testWidgets('küçük haritada zoom düğmeleri gizlenir, katmanlar düğmesi kalır',
        (tester) async {
      await pumpMap(tester, height: 240, chips: false);
      expect(find.byIcon(Icons.layers_rounded), findsOneWidget);
      expect(find.byIcon(Icons.add), findsNothing);
      await snapshot(tester, 'live_compact');
    });
  });
}
