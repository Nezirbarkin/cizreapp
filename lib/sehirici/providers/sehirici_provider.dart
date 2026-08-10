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

  // State
  SehiriciSettings _settings = const SehiriciSettings();
  List<SehiriciCity> _cities = [];
  String? _selectedCityId;
  List<SehiriciLine> _lines = const [];
  List<SehiriciActiveTrip> _activeTrips = const [];
  Set<String> _favoriteStopIds = {};
  bool _isLoading = false;
  String? _errorMessage;

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
      _cities = await _cityService.getCities();
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

  Future<void> selectCity(String cityId) async {
    if (_selectedCityId == cityId) return;
    _selectedCityId = cityId;
    notifyListeners();
    await loadLinesAndTrips(cityId);
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
  // Realtime callback — SehiriciTripService.watchActiveTrips için
  // ─────────────────────────────────────────────

  void onTripRealtimeUpdate(SehiriciActiveTrip trip) {
    final idx = _activeTrips.indexWhere((t) => t.tripId == trip.tripId);
    if (idx >= 0) {
      // Eski verinin zengin alanlarını koru (line adı/kodu/renk vs.)
      _activeTrips[idx] = _activeTrips[idx].copyWithLocation(
        lat: trip.currentLat,
        lng: trip.currentLng,
        heading: trip.currentHeading,
        speed: trip.currentSpeed,
        etaMinutes: trip.etaMinutes,
        nextStopId: trip.nextStopId,
      );
    } else {
      _activeTrips = [..._activeTrips, trip];
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