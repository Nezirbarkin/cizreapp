import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/sehirici_icon_models.dart';
import '../models/sehirici_models.dart';
import '../services/sehirici_city_service.dart';
import '../services/sehirici_driver_service.dart';
import '../services/sehirici_errors.dart';
import '../services/sehirici_icon_catalog.dart';
import '../services/sehirici_icon_service.dart';
import '../services/sehirici_line_service.dart';
import '../services/sehirici_road_snap_service.dart';
import '../utils/sehirici_route_geometry.dart';

/// Bir hattın rotasının durumu (admin listesinde rozet olarak gösterilir).
enum SehiriciRouteState {
  /// Rota yok: haritada çizgi görünmez.
  missing,

  /// Rota var ve kaydedildiği andaki durak sırasıyla uyumlu.
  current,

  /// Rota var ama duraklar sonradan değişmiş — çizgi eski duraklardan geçiyor.
  stale,
}

/// Şehiriçi admin ekranlarının ortak durumu ve işlemleri.
///
/// Sekmeler eskiden kendi listelerini ayrı ayrı yüklüyordu; bu yüzden aynı hat
/// listesi üç ekranda üç kez çekiliyor, bir sekmede yapılan değişiklik
/// diğerlerinde ancak elle yenilenince görünüyordu. Şimdi tek denetleyici:
/// şehir seçimi, hatlar, duraklar, şoförler, ikonlar, ayarlar burada tutulur
/// ve her işlemden sonra ilgili veri yeniden yüklenir.
class SehiriciAdminController extends ChangeNotifier {
  SehiriciAdminController({
    SupabaseClient? client,
    SehiriciCityService? cityService,
    SehiriciLineService? lineService,
    SehiriciDriverService? driverService,
    SehiriciIconService? iconService,
    SehiriciRoadSnapService? roadSnapService,
    SehiriciIconCatalog? catalog,
  })  : cityService = cityService ?? SehiriciCityService(client: client),
        lineService = lineService ?? SehiriciLineService(client: client),
        driverService = driverService ?? SehiriciDriverService(client: client),
        iconService = iconService ?? SehiriciIconService(client: client),
        roadSnapService = roadSnapService ?? SehiriciRoadSnapService(),
        catalog = catalog ?? SehiriciIconCatalog.instance;

  final SehiriciCityService cityService;
  final SehiriciLineService lineService;
  final SehiriciDriverService driverService;
  final SehiriciIconService iconService;
  final SehiriciRoadSnapService roadSnapService;
  final SehiriciIconCatalog catalog;

  // ── Durum ────────────────────────────────────────────────────
  List<SehiriciCity> cities = const [];
  String? cityId;
  List<SehiriciLine> lines = const [];
  List<SehiriciStop> stops = const [];
  List<SehiriciDriver> drivers = const [];
  List<SehiriciMarkerIcon> icons = SehiriciMarkerIcon.builtinDefaults;
  SehiriciSettings? settings;

  bool loadingCities = true;
  bool loadingCity = false;
  bool loadingDrivers = true;
  bool loadingIcons = true;
  bool loadingSettings = true;
  String? cityError;
  String? driversError;
  String? iconsError;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  SehiriciCity? get city {
    for (final c in cities) {
      if (c.id == cityId) return c;
    }
    return null;
  }

  // ── Türetilmiş veriler ───────────────────────────────────────

  /// Durak → o durağı kullanan hatlar.
  Map<String, List<SehiriciLine>> get linesByStop {
    final map = <String, List<SehiriciLine>>{};
    for (final line in lines) {
      for (final s in line.stops) {
        map.putIfAbsent(s.stopId, () => []).add(line);
      }
    }
    return map;
  }

  /// Hiçbir hatta bağlı olmayan duraklar.
  List<SehiriciStop> get unlinkedStops {
    final used = linesByStop.keys.toSet();
    return stops.where((s) => !used.contains(s.id)).toList();
  }

  SehiriciRouteState routeStateOf(SehiriciLine line) {
    if (!line.hasRoute) return SehiriciRouteState.missing;
    final sig = line.routeSignature;
    if (sig == null || line.stops.isEmpty) return SehiriciRouteState.current;
    return sig == SehiriciLineService.computeStopsSignature(line.stops)
        ? SehiriciRouteState.current
        : SehiriciRouteState.stale;
  }

  SehiriciLine? lineById(String? id) {
    if (id == null) return null;
    for (final l in lines) {
      if (l.id == id) return l;
    }
    return null;
  }

  /// Hatta atanmış şoför (yoksa null).
  SehiriciDriver? driverOfLine(String lineId) {
    for (final d in drivers) {
      if (d.assignedLineId == lineId) return d;
    }
    return null;
  }

  // ── Yükleme ──────────────────────────────────────────────────

  /// Açılışta her şeyi yükler: önce şehirler, sonra şehre bağlı veriler ve
  /// şehirden bağımsız olanlar (şoför, ikon, ayar) paralel.
  Future<void> loadAll({String? preferredCityId}) async {
    await Future.wait([
      reloadCities(selectId: preferredCityId),
      reloadDrivers(),
      reloadIcons(),
      reloadSettings(),
    ]);
  }

  Future<void> reloadCities({String? selectId}) async {
    loadingCities = true;
    _notify();
    try {
      cities = await cityService.getAllCitiesAdmin();
      if (cities.isEmpty) {
        cityId = null;
        lines = const [];
        stops = const [];
        cityError = null;
      } else {
        final wanted = selectId ?? cityId;
        cityId = cities.any((c) => c.id == wanted) ? wanted : cities.first.id;
        loadingCities = false;
        _notify();
        await reloadCityData();
      }
    } catch (e) {
      cityError = sehiriciErrorMessage(e);
    } finally {
      loadingCities = false;
      _notify();
    }
  }

  /// Seçili şehrin hat ve duraklarını yükler.
  Future<void> reloadCityData() async {
    final id = cityId;
    if (id == null) return;
    loadingCity = true;
    cityError = null;
    _notify();
    try {
      final results = await Future.wait([
        lineService.getAllLinesAdmin(id),
        lineService.getStopsByCity(id),
      ]);
      // Yükleme sürerken şehir değiştiyse eski sonucu yazma.
      if (cityId != id) return;
      lines = results[0] as List<SehiriciLine>;
      stops = results[1] as List<SehiriciStop>;
    } catch (e) {
      cityError = sehiriciErrorMessage(e);
    } finally {
      loadingCity = false;
      _notify();
    }
  }

  Future<void> selectCity(String id) async {
    if (id == cityId) return;
    cityId = id;
    lines = const [];
    stops = const [];
    _notify();
    await reloadCityData();
  }

  Future<void> reloadDrivers() async {
    loadingDrivers = true;
    _notify();
    try {
      drivers = await driverService.getDriversAdmin();
      driversError = null;
    } catch (e) {
      driversError = sehiriciErrorMessage(e);
    } finally {
      loadingDrivers = false;
      _notify();
    }
  }

  Future<void> reloadIcons() async {
    loadingIcons = true;
    _notify();
    try {
      final fetched = await iconService.fetchAll();
      if (fetched.isNotEmpty) icons = fetched;
      iconsError = null;
      // Haritalar/listeler de aynı güncel katalogu görsün.
      await catalog.refresh();
    } catch (e) {
      iconsError = sehiriciErrorMessage(e);
    } finally {
      loadingIcons = false;
      _notify();
    }
  }

  Future<void> reloadSettings() async {
    loadingSettings = true;
    _notify();
    try {
      settings = await cityService.getSettings(forceRefresh: true);
    } finally {
      loadingSettings = false;
      _notify();
    }
  }

  // ── Ayarlar ──────────────────────────────────────────────────

  /// Ayarı yazar ve güncel hâli yeniden okur. Hata olursa fırlatır.
  Future<void> updateSetting(String key, String value) async {
    await cityService.updateSettingOrThrow(key, value);
    await reloadSettings();
  }

  // ── Rota ─────────────────────────────────────────────────────

  /// Hattın duraklarını gerçek yollardan geçen bir rotaya çevirir ve kaydeder.
  /// Başarılıysa nokta sayısını döner; yol bulunamazsa istisna fırlatır.
  Future<int> createRouteFromStops(SehiriciLine line) async {
    if (line.stops.length < 2) {
      throw const SehiriciAdminException(
        'Rota için hatta en az 2 durak eklenmiş olmalı.',
      );
    }
    final waypoints =
        line.stops.map((s) => LatLng(s.lat, s.lng)).toList(growable: false);
    final routed = await roadSnapService.routeThroughWaypoints(waypoints);
    if (routed.length < 2) {
      throw const SehiriciAdminException(
        'Duraklar arasında gerçek yol bulunamadı. Rotayı elle çizmeyi deneyin.',
      );
    }
    final simplified = simplifyToMaxPoints(routed, maxPoints: 1500);
    final ok = await lineService.cacheRoutePolyline(
      lineId: line.id,
      lineStopsInOrder: line.stops,
      points: simplified
          .map((p) => <double>[p.latitude, p.longitude])
          .toList(growable: false),
      source: 'osrm_stops',
    );
    if (!ok) {
      throw const SehiriciAdminException('Rota kaydedilemedi.');
    }
    await reloadCityData();
    return simplified.length;
  }

  /// Rotası olmayan ya da duraklar değiştiği için eski kalan (ve en az 2
  /// durağı olan) hatlar.
  List<SehiriciLine> get linesNeedingRoute => lines
      .where((l) =>
          l.stops.length >= 2 && routeStateOf(l) != SehiriciRouteState.current)
      .toList();

  /// [linesNeedingRoute] için sırayla rota üretir. Hatalar toplanır (bir hattın
  /// yol bulamaması diğerlerini durdurmaz). Sonuç: (üretilen hat sayısı,
  /// "KOD: neden" hata listesi).
  Future<({int done, List<String> failed})> createMissingRoutes() async {
    var done = 0;
    final failed = <String>[];
    for (final line in linesNeedingRoute) {
      try {
        await createRouteFromStops(line);
        done++;
      } catch (e) {
        failed.add('${line.code}: ${sehiriciErrorMessage(e)}');
      }
    }
    return (done: done, failed: failed);
  }
}
