// ignore_for_file: depend_on_referenced_packages, deprecated_member_use

import 'dart:convert';

import 'package:cizreapp/core/services/location_disclosure_service.dart';
import 'package:cizreapp/core/services/maps_api_key_service.dart';
import 'package:cizreapp/features/market/screens/address_picker_screen.dart';
import 'package:cizreapp/features/user_courier/screens/package_tracking_screen.dart';
import 'package:cizreapp/sehirici/providers/sehirici_provider.dart';
import 'package:cizreapp/sehirici/screens/sehirici_driver_panel_screen.dart';
import 'package:cizreapp/sehirici/services/sehirici_auto_trip_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/fake_google_maps_platform.dart';
import '../helpers/test_fonts.dart';

/// Konum izni YALNIZ kullanıcı bir eylem yaptığında istenir.
///
/// Hata: uygulama konum iznini kullanıcı hiçbir şeye dokunmadan, ekran
/// açılırken ve uygulamaya her dönüşte soruyordu (adres seçici, paket takibi,
/// şoför paneli). Reddeden kullanıcı bu ekranlara her girişinde açıklama
/// diyaloğunu yeniden görüyordu. Kural: otomatik tetikleyiciler
/// (`initState`, zamanlayıcı, yaşam döngüsü) yalnız `isReady` ile durumu OKUR;
/// diyalog ve sistem izni yalnız düğme/anahtar gibi açık bir eylemle açılır.

/// Onay kaydının kalıcı anahtarı (LocationDisclosureService._consentKey).
/// Kullanıcıların kayıtlı onayları bu anahtara bağlı olduğundan sessizce
/// değişmemelidir; değişirse bu test bilerek güncellenmelidir.
const _nearbyConsent = 'location_disclosure_v1_nearby';
const _driverConsent = 'location_disclosure_v1_driverTrip';

const _mapsKey = 'AIzaSyTestKeyTestKeyTestKeyTestKeyTest1';

/// Sistem izni ve konum okumalarını taklit eden sahte Geolocator platformu.
class _FakeGeolocator extends GeolocatorPlatform {
  LocationPermission permission = LocationPermission.denied;

  /// Sistem izin diyaloğunda kullanıcının vereceği cevap.
  LocationPermission answerToRequest = LocationPermission.whileInUse;

  int requestCalls = 0;
  int positionCalls = 0;

  static Position get here => Position(
    latitude: 37.33,
    longitude: 42.19,
    timestamp: DateTime(2026, 10, 4),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requestCalls++;
    permission = answerToRequest;
    return permission;
  }

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => null;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    positionCalls++;
    return here;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      const Stream<Position>.empty();

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

/// Bellek içi PKCE deposu (varsayılanı testte asılı kalır).
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

/// Üç ekranın ihtiyaç duyduğu tabloları/RPC'leri sunan sahte Supabase.
class _Backend {
  late Map<String, dynamic> package;
  late Map<String, dynamic>? courier;
  late Map<String, dynamic> driver;

  void reset() {
    package = {
      'id': 'pkg-1',
      'status': 'accepted',
      'pickup_address': 'Alım Sk. 1',
      'pickup_lat': 37.330,
      'pickup_lng': 42.190,
      'delivery_address': 'Teslim Sk. 2',
      'delivery_lat': 37.340,
      'delivery_lng': 42.200,
    };
    courier = {
      'r_request_status': 'accepted',
      'r_courier_id': 'c1',
      'r_full_name': 'Ali Kurye',
      'r_lat': 37.335,
      'r_lng': 42.195,
    };
    driver = {
      'id': 'd1',
      'profile_id': 'user-1',
      'license_number': '34ABC123',
      'phone': null,
      'assigned_line_id': 'L1',
      'is_on_duty': true,
      'working_hours_start': '07:00:00',
      'working_hours_end': '19:00:00',
      'auto_location_enabled': true,
      'auto_route_from_traveled_path': false,
      'auto_trip_enabled': true,
      'sehirici_lines': {
        'id': 'L1',
        'code': '4A',
        'name': 'Merkez – Hastane',
        'color_hex': '#1976D2',
        'vehicle_type': 'minibus',
        'route_polyline': null,
      },
    };
  }

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    // `.single()` / `.maybeSingle()` nesne, diğerleri liste bekler.
    final wantsObject = (req.headers['Accept'] ?? '').contains('vnd.pgrst.object');
    http.Response ok(Object? body) => http.Response(
      jsonEncode(body),
      200,
      request: req,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

    if (path.endsWith('/courier_requests')) {
      return ok(wantsObject ? package : [package]);
    }
    if (path.endsWith('/rpc/get_assigned_courier_location')) {
      return ok(courier == null ? [] : [courier]);
    }
    if (path.endsWith('/app_about_settings')) {
      const row = {'google_maps_api_key': _mapsKey};
      return ok(wantsObject ? row : [row]);
    }
    if (path.endsWith('/sehirici_drivers')) {
      if (req.method == 'PATCH') {
        // Ayarlar kaydedilince sonraki okuma yeni değerleri görsün.
        driver.addAll(Map<String, dynamic>.from(jsonDecode(req.body) as Map));
        return http.Response('', 204, request: req);
      }
      return ok(wantsObject ? driver : [driver]);
    }
    return ok(path.contains('/rpc/') ? null : <Object>[]);
  }
}

void main() {
  final backend = _Backend();
  late _FakeGeolocator geo;
  late FakeGoogleMapsPlatform maps;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadTestFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      // REST istekleri MockClient'a gider; adres yalnız Realtime (websocket)
      // içindir. Kapalı bir yerel port bağlantıyı anında reddeder — gerçek bir
      // alan adı DNS çözümünü beklerken testi dakikalarca asabilir.
      url: 'http://127.0.0.1:1',
      anonKey: 'test-anon-key',
      httpClient: MockClient(backend.handle),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryAsyncStorage(),
      ),
    );
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-access-token',
        'token_type': 'bearer',
        'refresh_token': 'test-refresh-token',
        'user': {
          'id': 'user-1',
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
        },
      }),
    );
  });

  setUp(() {
    backend.reset();
    geo = _FakeGeolocator();
    GeolocatorPlatform.instance = geo;
    maps = FakeGoogleMapsPlatform();
    GoogleMapsFlutterPlatform.instance = maps;
    SharedPreferences.setMockInitialValues({});
    MapsApiKeyService.clearCache();
    // rootBundle başarısız `.env` yüklemesini testler arasında önbellekler; önceki
    // testin FakeAsync bölgesinde kalan o Future yenisinde asla tamamlanmaz ve
    // AddressPickerScreen "Harita yükleniyor"da kalır.
    rootBundle.evict('.env');
  });

  /// Ağ yanıtları gerçek (eşzamansız) işlerdir; sahte zaman içinde ilerlemezler.
  Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  void phoneScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Açıklama diyaloğu ekranda mı?
  Finder disclosure() => find.text('Kabul Ediyorum');

  // ───────────────────────────────────────────────────────────────────
  // Merkezi servis
  // ───────────────────────────────────────────────────────────────────
  group('LocationDisclosureService', () {
    Future<BuildContext> host(WidgetTester tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              captured = context;
              return const Scaffold();
            },
          ),
        ),
      );
      return captured;
    }

    testWidgets('isReady izin ve onay yokken false döner, hiçbir şey istemez', (
      tester,
    ) async {
      expect(await LocationDisclosureService.isReady(LocationPurpose.nearby), isFalse);
      expect(geo.requestCalls, 0);
    });

    testWidgets('isReady yalnız onay VE izin birlikte varsa true döner', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({_nearbyConsent: true});
      expect(await LocationDisclosureService.isReady(LocationPurpose.nearby), isFalse);

      geo.permission = LocationPermission.whileInUse;
      expect(await LocationDisclosureService.isReady(LocationPurpose.nearby), isTrue);
      expect(geo.requestCalls, 0);
    });

    testWidgets('ensure aynı amaç için eşzamanlı çağrılarda TEK diyalog açar', (
      tester,
    ) async {
      final context = await host(tester);

      // Sistem izin diyaloğu kapanınca uygulama `resumed` olur ve ekranlar
      // ensure'ı yeniden çağırabilir: ikinci çağrı yeni diyalog açmamalı.
      final first = LocationDisclosureService.ensure(context, LocationPurpose.nearby);
      final second = LocationDisclosureService.ensure(context, LocationPurpose.nearby);
      await tester.pumpAndSettle();

      expect(disclosure(), findsOneWidget);
      await tester.tap(disclosure());
      await tester.pumpAndSettle();

      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(geo.requestCalls, 1);
    });

    testWidgets('Vazgeç → false; sistem izni hiç istenmez', (tester) async {
      final context = await host(tester);

      final result = LocationDisclosureService.ensure(context, LocationPurpose.nearby);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();

      expect(await result, isFalse);
      expect(geo.requestCalls, 0);
    });

    testWidgets('onay ve izin varsa ensure diyalog göstermeden true döner', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({_nearbyConsent: true});
      geo.permission = LocationPermission.whileInUse;
      final context = await host(tester);

      final result = await LocationDisclosureService.ensure(
        context,
        LocationPurpose.nearby,
      );
      await tester.pump();

      expect(result, isTrue);
      expect(disclosure(), findsNothing);
      expect(geo.requestCalls, 0);
    });
  });

  // ───────────────────────────────────────────────────────────────────
  // Paket takibi
  // ───────────────────────────────────────────────────────────────────
  group('PackageTrackingScreen', () {
    Future<void> open(WidgetTester tester) async {
      phoneScreen(tester);
      await tester.pumpWidget(
        const MaterialApp(
          home: PackageTrackingScreen(packageId: 'pkg-1', packageTitle: 'Test paket'),
        ),
      );
      await settle(tester);
    }

    Future<void> close(WidgetTester tester) async {
      // Harita oluşunca ekran 500 ms sonra kamerayı sığdırır; o zamanlayıcı bitsin.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      // Ekranın Realtime aboneliği sahte sunucuda bağlanamaz ve yeniden bağlanma
      // zamanlayıcısı kurar; testin sonunda bekleyen zamanlayıcı kalmasın.
      await tester.runAsync(
        () => Supabase.instance.client.realtime
            .disconnect()
            .timeout(const Duration(seconds: 3), onTimeout: () {}),
      );
      await settle(tester, rounds: 2);
    }

    const showButton = 'Uzaklığı ve varış süresini göster';

    testWidgets('açılışta izin SORMAZ, GPS\'e dokunmaz, sahte konum uydurmaz', (
      tester,
    ) async {
      await open(tester);
      // 10 sn'lik konum zamanlayıcısı da tetiklensin.
      await tester.pump(const Duration(seconds: 11));
      await settle(tester, rounds: 2);

      expect(disclosure(), findsNothing);
      expect(geo.requestCalls, 0);
      expect(geo.positionCalls, 0);
      expect(maps.markers.containsKey(const MarkerId('user_location')), isFalse);
      // Kurye hâlâ görünür; yalnız kullanıcıya göre hesaplar yoktur.
      expect(maps.markers.containsKey(const MarkerId('courier_location')), isTrue);
      expect(find.textContaining('Sizden uzaklığı'), findsNothing);
      expect(find.text(showButton), findsOneWidget);

      await close(tester);
    });

    testWidgets('düğmeye dokunulunca açıklama + izin istenir, sonra konum gösterilir', (
      tester,
    ) async {
      await open(tester);

      await tester.tap(find.text(showButton));
      await settle(tester, rounds: 2);
      expect(disclosure(), findsOneWidget);
      expect(geo.requestCalls, 0, reason: 'sistem izni açıklamadan önce istenmez');

      await tester.tap(disclosure());
      await settle(tester);

      expect(geo.requestCalls, 1);
      expect(maps.markers.containsKey(const MarkerId('user_location')), isTrue);
      expect(find.textContaining('Sizden uzaklığı'), findsOneWidget);
      expect(find.text(showButton), findsNothing);

      await close(tester);
    });

    testWidgets('reddedilirse hiçbir konum okunmaz ve düğme yerinde kalır', (
      tester,
    ) async {
      await open(tester);

      await tester.tap(find.text(showButton));
      await settle(tester, rounds: 2);
      await tester.tap(find.text('Vazgeç'));
      await settle(tester, rounds: 2);

      expect(geo.requestCalls, 0);
      expect(geo.positionCalls, 0);
      expect(find.text(showButton), findsOneWidget);

      await close(tester);
    });

    testWidgets('izin daha önce verilmişse konum sessizce okunur', (tester) async {
      SharedPreferences.setMockInitialValues({_nearbyConsent: true});
      geo.permission = LocationPermission.whileInUse;
      await open(tester);

      expect(disclosure(), findsNothing);
      expect(geo.requestCalls, 0);
      expect(maps.markers.containsKey(const MarkerId('user_location')), isTrue);
      expect(find.textContaining('Sizden uzaklığı'), findsOneWidget);
      expect(find.text(showButton), findsNothing);

      await close(tester);
    });
  });

  // ───────────────────────────────────────────────────────────────────
  // Adres seçici
  // ───────────────────────────────────────────────────────────────────
  group('AddressPickerScreen', () {
    Future<void> open(WidgetTester tester, {bool withInitialPoint = false}) async {
      phoneScreen(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: AddressPickerScreen(
            initialLatitude: withInitialPoint ? 37.31 : null,
            initialLongitude: withInitialPoint ? 42.18 : null,
          ),
        ),
      );
      await settle(tester);
      // Eski kod haritadan 400 ms sonra konumu otomatik istiyordu.
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester, rounds: 3);
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await settle(tester, rounds: 2);
    }

    testWidgets('açılışta izin SORMAZ ve mavi konum katmanını açmaz', (tester) async {
      await open(tester);

      expect(disclosure(), findsNothing);
      expect(geo.requestCalls, 0);
      expect(geo.positionCalls, 0);
      expect(maps.myLocationEnabled, isFalse);

      await close(tester);
    });

    testWidgets('"Mevcut konumum"a dokunulunca açıklama + izin istenir, harita konuma gider', (
      tester,
    ) async {
      await open(tester);

      await tester.tap(find.byTooltip('Mevcut konumum'));
      await settle(tester, rounds: 2);
      expect(disclosure(), findsOneWidget);
      expect(geo.requestCalls, 0);

      await tester.tap(disclosure());
      await settle(tester);

      expect(geo.requestCalls, 1);
      expect(
        maps.markers[const MarkerId('selected_location')]?.position,
        const LatLng(37.33, 42.19),
      );
      expect(maps.myLocationEnabled, isTrue);

      await close(tester);
    });

    testWidgets('reddedilirse konum alınmaz ve elle seçime devam edilir', (
      tester,
    ) async {
      await open(tester);

      await tester.tap(find.byTooltip('Mevcut konumum'));
      await settle(tester, rounds: 2);
      await tester.tap(find.text('Vazgeç'));
      await settle(tester, rounds: 2);

      expect(geo.requestCalls, 0);
      expect(geo.positionCalls, 0);
      expect(find.textContaining('Konum izni verilmedi'), findsOneWidget);

      await close(tester);
    });

    testWidgets('izin daha önce verilmişse harita sessizce mevcut konuma gider', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({_nearbyConsent: true});
      geo.permission = LocationPermission.whileInUse;
      await open(tester);

      expect(disclosure(), findsNothing);
      expect(geo.requestCalls, 0);
      expect(
        maps.markers[const MarkerId('selected_location')]?.position,
        const LatLng(37.33, 42.19),
      );
      expect(maps.myLocationEnabled, isTrue);

      await close(tester);
    });

    testWidgets('başlangıç noktası verilmişse izin yokken hiçbir şey sorulmaz', (
      tester,
    ) async {
      await open(tester, withInitialPoint: true);

      expect(disclosure(), findsNothing);
      expect(geo.requestCalls, 0);
      expect(geo.positionCalls, 0);
      expect(maps.markers[const MarkerId('selected_location')]?.position, const LatLng(37.31, 42.18));

      await close(tester);
    });
  });

  // ───────────────────────────────────────────────────────────────────
  // Şoför paneli — otomatik sefer
  // ───────────────────────────────────────────────────────────────────
  group('SehiriciDriverPanelScreen', () {
    const bannerTitle = 'Otomatik sefer için konum izni gerekli';

    Future<void> open(WidgetTester tester) async {
      phoneScreen(tester);
      await tester.pumpWidget(
        ChangeNotifierProvider<SehiriciProvider>.value(
          value: SehiriciProvider(),
          child: const MaterialApp(home: SehiriciDriverPanelScreen()),
        ),
      );
      await settle(tester, rounds: 8);
    }

    Future<void> close(WidgetTester tester) async {
      await tester.runAsync(() => SehiriciAutoTripController.instance.stop());
      await tester.pumpWidget(const SizedBox());
      await settle(tester, rounds: 2);
    }

    testWidgets('açılışta ve uygulamaya dönüşte izin SORMAZ; uyarı bandı çıkar', (
      tester,
    ) async {
      await open(tester);

      expect(disclosure(), findsNothing);
      expect(geo.requestCalls, 0);
      expect(find.text(bannerTitle), findsOneWidget);
      expect(find.text('İzin Ver'), findsOneWidget);
      expect(SehiriciAutoTripController.instance.isActive, isFalse);

      // Sistem izin diyaloğu kapanırken olduğu gibi: uygulama ön plana döner.
      // (Yalnız panelin gözlemcisine bildirilir; global bağlama göndermek
      // Supabase'in oturum yenileme zamanlayıcısını da başlatırdı.)
      final observer =
          tester.state(find.byType(SehiriciDriverPanelScreen))
              as WidgetsBindingObserver;
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle(tester, rounds: 4);

      expect(disclosure(), findsNothing);
      expect(geo.requestCalls, 0);
      expect(find.text(bannerTitle), findsOneWidget);

      await close(tester);
    });

    testWidgets('"İzin Ver"e dokunulunca açıklama + izin istenir ve otomasyon başlar', (
      tester,
    ) async {
      await open(tester);

      await tester.tap(find.text('İzin Ver'));
      await settle(tester, rounds: 4);
      expect(disclosure(), findsOneWidget);
      expect(geo.requestCalls, 0);

      await tester.tap(disclosure());
      await settle(tester, rounds: 6);

      expect(geo.requestCalls, 1);
      expect(find.text(bannerTitle), findsNothing);
      expect(SehiriciAutoTripController.instance.isWatching, isTrue);

      await close(tester);
    });

    testWidgets('reddedilirse otomasyon başlamaz ve bant yerinde kalır', (tester) async {
      await open(tester);

      await tester.tap(find.text('İzin Ver'));
      await settle(tester, rounds: 4);
      await tester.tap(find.text('Vazgeç'));
      await settle(tester, rounds: 4);

      expect(geo.requestCalls, 0);
      expect(find.text(bannerTitle), findsOneWidget);
      expect(SehiriciAutoTripController.instance.isActive, isFalse);

      await close(tester);
    });

    testWidgets('izin daha önce verilmişse hiçbir şey sorulmadan izleme başlar', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({_driverConsent: true});
      geo.permission = LocationPermission.whileInUse;
      await open(tester);

      expect(disclosure(), findsNothing);
      expect(geo.requestCalls, 0);
      expect(find.text(bannerTitle), findsNothing);
      expect(SehiriciAutoTripController.instance.isWatching, isTrue);

      await close(tester);
    });

    testWidgets('otomatik sefer kapalıysa izinle ilgili hiçbir şey gösterilmez', (
      tester,
    ) async {
      backend.driver['auto_trip_enabled'] = false;
      await open(tester);

      expect(disclosure(), findsNothing);
      expect(geo.requestCalls, 0);
      expect(find.text(bannerTitle), findsNothing);

      await close(tester);
    });

    /// Şoför ayarlarını açar, istenirse "Seferleri kendiliğinden başlat/bitir"
    /// anahtarını çevirir ve "Kaydet"e basar.
    Future<void> saveSettings(WidgetTester tester, {bool toggleAuto = false}) async {
      await tester.tap(find.byIcon(Icons.settings));
      await settle(tester, rounds: 3);
      if (toggleAuto) {
        final toggle = find.widgetWithText(
          SwitchListTile,
          'Seferleri kendiliğinden başlat/bitir',
        );
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pump();
      }
      await tester.tap(find.text('Kaydet'));
      await settle(tester, rounds: 8);
    }

    testWidgets('ayarda Otomatik Sefer yeni açılıp kaydedilince izin O ANDA istenir', (
      tester,
    ) async {
      backend.driver['auto_trip_enabled'] = false;
      await open(tester);
      expect(disclosure(), findsNothing);

      await saveSettings(tester, toggleAuto: true);

      // Kullanıcının eyleminin hemen ardından açıklama gelir; sistem izni
      // onaydan önce istenmez.
      expect(disclosure(), findsOneWidget);
      expect(geo.requestCalls, 0);

      await tester.tap(disclosure());
      await settle(tester, rounds: 6);

      expect(geo.requestCalls, 1);
      expect(find.text(bannerTitle), findsNothing);
      expect(SehiriciAutoTripController.instance.isWatching, isTrue);

      await close(tester);
    });

    testWidgets('Otomatik Sefer zaten açıkken başka bir ayar kaydedilince izin sorulmaz', (
      tester,
    ) async {
      await open(tester);
      expect(find.text(bannerTitle), findsOneWidget);

      await saveSettings(tester);

      expect(disclosure(), findsNothing);
      expect(geo.requestCalls, 0);
      expect(find.text(bannerTitle), findsOneWidget);

      await close(tester);
    });
  });
}
