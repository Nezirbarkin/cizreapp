import 'package:flutter/foundation.dart';
import '../models/sehirici_models.dart';
import '../services/sehirici_city_service.dart';
import '../services/sehirici_line_service.dart';
import '../services/sehirici_trip_service.dart';
import '../services/sehirici_favorite_service.dart';

/// Şehir içi servis modülü için tek bir ChangeNotifier provider.
/// Tüm ekranlar aynı instance'ı kullanır (singleton) — performans için önemli.
class SehiriciProvider extends ChangeNotifier {
  static final SehiriciProvider _instance = SehiriciProvider._internal();
  factory SehiriciProvider() => _instance;
  SehiriciProvider._internal();

  // Servisler (lazy)
  final SehiriciCityService _cityService = SehiriciCityService();
  final SehiriciLineService _lineService = SehiriciLineService();
  final SehiriciFavoriteService _favoriteService =
      SehiriciFavoriteService();
  final SehiriciTripService _tripService = SehiriciTripService();

  // State
  SehiriciSettings _settings = const SehiriciSettings();
  List<SehiriciCity> _cities = [];
  String? _selectedCityId;
  List<SehiriciLine> _lines = const [];
  List<SehiriciActiveTrip> _activeTrips = const [];
  Set<String> _favoriteStopIds = {};
  bool _isLoading = false;
  String? _errorMessage;

  /// Realtime aktif-sefer kanalının şu an açık olduğu şehir. Kanal yönetimi
  /// tamamen burada toplanır — widget'lar kendi SehiriciTripService
  /// instance'ını oluşturmaz (aksi hâlde her widget mount'unda kapatılmayan
  /// yeni bir kanal sızdırılırdı).
  String? _realtimeCityId;

  /// Kullanıcının haritada vurgulamak istediği hat (chip ile gösterilir).
  /// null = tüm hatlar eşit. Kullanıcı "haritada göster" ikonuna tıkladığında
  /// setlenir, chip'in [×] butonuyla veya başka hat seçildiğinde temizlenir.
  String? _highlightedLineId;

  // Getters
  SehiriciSettings get settings => _settings;
  List<SehiriciCity> get cities => _cities;
  String? get selectedCityId => _selectedCityId;
  SehiriciCity? get selectedCity {
    if (_selectedCityId == null) return null;
    for (final c in _cities) {
      if (c.id == _selectedCityId) return c;
    }
    return null;
  }
  List<SehiriciLine> get lines => _lines;
  List<SehiriciActiveTrip> get activeTrips => _activeTrips;
  Set<String> get favoriteStopIds => _favoriteStopIds;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get moduleEnabled => _settings.moduleEnabled;
  String? get highlightedLineId => _highlightedLineId;

  /// Haritada bir hattı vurgula (veya null ile temizle). Aynı hat zaten
  /// seçiliyse ikinci çağrı temizler — toggle davranışı.
  void highlightLine(String? lineId) {
    if (_highlightedLineId == lineId) {
      _highlightedLineId = null;
    } else {
      _highlightedLineId = lineId;
    }
    notifyListeners();
  }

  /// Uygulama açılışında çağrılır. Ayarlar + şehirleri yükler.
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      _settings = await _cityService.getSettings();
      if (!_settings.moduleEnabled) {
        _isLoading = false;
        notifyListeners();
        return;
      }
      _cities = await _loadCitiesWithRetry();
      if (_selectedCityId == null &&
          _settings.defaultCityId != null &&
          _settings.defaultCityId!.isNotEmpty) {
        _selectedCityId = _settings.defaultCityId;
      }
      if (_selectedCityId == null && _cities.isNotEmpty) {
        _selectedCityId = _cities.first.id;
      }
      if (_selectedCityId != null) {
        await loadLinesAndTrips(_selectedCityId!);
        ensureRealtimeWatching();
      }
      _favoriteStopIds =
          (await _favoriteService.getFavorites()).map((f) => f.stopId).toSet();
    } catch (e) {
      _errorMessage = 'Modül başlatılamadı: $e';
      debugPrint('SehiriciProvider.initialize hata: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Soğuk başlangıçta geçici bir ağ hatası olursa (bağlantı hazır olmadan
  /// ilk istek atılması yaygın bir durumdur) tek seferlik başarısızlık,
  /// modül açıkken şehir listesini kalıcı olarak boş bırakmasın diye kısa
  /// bir yeniden deneme uygular. Gerçekten hiç şehir yoksa (idempotent)
  /// sonuçta yine boş liste döner.
  Future<List<SehiriciCity>> _loadCitiesWithRetry() async {
    var cities = await _cityService.getCities();
    for (final delay in const [
      Duration(milliseconds: 800),
      Duration(seconds: 2),
    ]) {
      if (cities.isNotEmpty) break;
      await Future.delayed(delay);
      cities = await _cityService.getCities(forceRefresh: true);
    }
    return cities;
  }

  /// Kart/ekran göründüğünde çağrılır: modül açık ama şehir listesi boşsa
  /// (ör. initialize() ilk denemede ağ hatası aldıysa) sessizce yeniden
  /// dener. Zaten yükleniyorsa veya dolu ise no-op.
  Future<void> ensureFresh() async {
    if (_isLoading) return;
    if (_settings.moduleEnabled && _cities.isEmpty) {
      await initialize();
    }
  }

  Future<void> selectCity(String cityId) async {
    if (_selectedCityId == cityId) return;
    _selectedCityId = cityId;
    notifyListeners();
    await loadLinesAndTrips(cityId);
    ensureRealtimeWatching();
  }

  Future<void> loadLinesAndTrips(String cityId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _lineService.getLinesWithStops(cityId),
        _lineService.getActiveTrips(cityId: cityId),
      ]);
      _lines = results[0] as List<SehiriciLine>;
      _activeTrips = results[1] as List<SehiriciActiveTrip>;
    } catch (e) {
      _errorMessage = 'Veriler yüklenemedi: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshActiveTrips() async {
    if (_selectedCityId == null) return;
    try {
      _activeTrips = await _lineService.getActiveTrips(cityId: _selectedCityId);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Sefer güncelleme hatası: $e';
      debugPrint('refreshActiveTrips hata: $e');
    }
  }

  // ─────────────────────────────────────────────
  // Realtime — tek kanal burada yönetilir. Widget'lar kendi
  // SehiriciTripService instance'ını OLUŞTURMAZ: aksi hâlde her widget
  // mount'unda (CompactCard, StoryCard, ...) kapatılmayan yeni bir kanal
  // sızdırılırdı. Bunun yerine ensureRealtimeWatching() çağırırlar.
  // ─────────────────────────────────────────────

  /// Seçili şehir için realtime aktif-sefer kanalının açık olduğundan emin
  /// olur. Zaten doğru şehir için açıksa no-op — birden fazla widget güvenle
  /// tekrar tekrar çağırabilir. watchActiveTrips kendi eski kanalını zaten
  /// kapatıyor (sehirici_trip_service.dart), bu yüzden şehir değişince tek
  /// bir kanal kalmaya devam eder.
  void ensureRealtimeWatching() {
    if (!_settings.moduleEnabled) return;
    if (_realtimeCityId == _selectedCityId) return;
    _realtimeCityId = _selectedCityId;
    _tripService.watchActiveTrips(
      cityId: _selectedCityId,
      onTripUpdate: onTripRealtimeUpdate,
      onTripDelete: onTripRealtimeDelete,
    );
  }

  void onTripRealtimeUpdate(SehiriciActiveTrip trip) {
    final idx = _activeTrips.indexWhere((t) => t.tripId == trip.tripId);
    if (idx >= 0) {
      // DİKKAT: listeyi YERİNDE değiştirmeyin. Tüketiciler (SehiriciLiveMap)
      // `oldWidget.activeTrips != widget.activeTrips` kimlik karşılaştırması
      // yapıyor; aynı List instance'ını mutasyona uğratmak bu kontrolü hep
      // false yapıyordu ve canlı konum haritaya ancak 30 sn'lik yedek
      // timer'da yansıyordu. Her güncellemede yeni bir liste üretiyoruz.
      final next = List<SehiriciActiveTrip>.of(_activeTrips);
      // Eski verinin zengin alanlarını koru (line adı/kodu/renk vs.)
      next[idx] = next[idx].copyWithLocation(
        lat: trip.currentLat,
        lng: trip.currentLng,
        heading: trip.currentHeading,
        speed: trip.currentSpeed,
        etaMinutes: trip.etaMinutes,
        nextStopId: trip.nextStopId,
      );
      _activeTrips = next;
    } else {
      // Yeni sefer: realtime satırında hat join'i yok (lineCode/lineName
      // boş gelir) — zaten yüklü hat listesinden zenginleştir.
      var newTrip = trip;
      if (trip.lineCode.isEmpty) {
        for (final line in _lines) {
          if (line.id == trip.lineId) {
            newTrip = trip.copyWithLine(line);
            break;
          }
        }
      }
      _activeTrips = [..._activeTrips, newTrip];
    }
    notifyListeners();
  }

  void onTripRealtimeDelete(String tripId) {
    _activeTrips = _activeTrips.where((t) => t.tripId != tripId).toList();
    notifyListeners();
  }

  // ─────────────────────────────────────────────
  // Favoriler (optimistic + rate-limited)
  // ─────────────────────────────────────────────
  final Map<String, DateTime> _lastFavToggleAt = {};
  static const Duration _favCooldown = Duration(milliseconds: 600);

  Future<void> toggleFavorite(String stopId) async {
    // Rate limit: aynı durağa kısa aralıklarla tıklamayı engelle
    final last = _lastFavToggleAt[stopId];
    if (last != null &&
        DateTime.now().difference(last) < _favCooldown) {
      return;
    }
    _lastFavToggleAt[stopId] = DateTime.now();

    final wasFavorite = _favoriteStopIds.contains(stopId);

    // Optimistik: UI anında güncellenir (ağ bekletilmez)
    _favoriteStopIds = {..._favoriteStopIds};
    if (wasFavorite) {
      _favoriteStopIds.remove(stopId);
    } else {
      _favoriteStopIds.add(stopId);
    }
    notifyListeners();

    // Arka planda API çağrısı — başarısızsa geri al
    final ok = wasFavorite
        ? await _favoriteService.removeFavorite(stopId)
        : await _favoriteService.addFavorite(stopId);
    if (!ok) {
      _favoriteStopIds = {..._favoriteStopIds};
      if (wasFavorite) {
        _favoriteStopIds.add(stopId);
      } else {
        _favoriteStopIds.remove(stopId);
      }
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────────
  // Admin cache invalidation
  // ─────────────────────────────────────────────

  void invalidateAllCaches() {
    SehiriciCityService.clearCache();
    _lineService.clearCache();
    // Yeniden yükle
    initialize();
  }
}