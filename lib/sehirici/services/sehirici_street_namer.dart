import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:http/http.dart' as http;

import '../../core/services/maps_api_key_service.dart';
import '../utils/sehirici_stop_naming.dart';

/// Bir koordinat için durak adı önerisi (sokak / mahalle).
@immutable
class SehiriciStreetSuggestion {
  const SehiriciStreetSuggestion({
    this.street,
    this.alternatives = const [],
    this.neighborhood,
  });

  /// Pinin üstünde durduğu yolun kısa adı ("Yafes Cad."); bulunamadıysa null.
  final String? street;

  /// Yakındaki diğer yollar, kısa adlarıyla ([street] hariç).
  final List<String> alternatives;

  /// Mahalle tabanı ("Nur Mah."); bulunamadıysa null.
  final String? neighborhood;

  /// Ad tabanı: önce sokak, yoksa mahalle.
  String? get base => street ?? neighborhood;

  /// Admin'e sunulacak tüm tabanlar (sırası korunur, tekrarsız).
  List<String> get bases => <String>{
        if (street != null) street!,
        ...alternatives,
        if (neighborhood != null) neighborhood!,
      }.toList();

  /// Durağın adres alanı için kısa adres ("Nur Mah., Yafes Cad.").
  String? get address {
    final parts = [if (neighborhood != null) neighborhood!, if (street != null) street!];
    return parts.isEmpty ? null : parts.join(', ');
  }

  bool get isEmpty => base == null;
}

/// Haritada seçilen durak konumundan sokak adını bulur; durak adı
/// "Yafes Cad. 1", "Yafes Cad. 2" … biçiminde bundan üretilir.
///
/// Önce Google Geocoding (anahtar veritabanından, [MapsApiKeyService]):
/// `result_type=route` pinin üstündeki yolu verir (adres sorgusu en yakın
/// BİNANIN ara sokağını döndürüp ana caddeyi kaçırıyordu); aynı anda atılan
/// düz sorgu mahalleyi ve yakındaki diğer yolları (seçenek) getirir. Google
/// sonuç vermezse OSRM `nearest` (OpenStreetMap yol adı) denenir. Hiçbiri
/// bulamazsa null — çağıran "Durak N" adına düşer, kayıt hiç engellenmez.
class SehiriciStreetNamer {
  SehiriciStreetNamer({
    http.Client? client,
    Future<String?> Function()? apiKey,
  })  : _client = client,
        _apiKey = apiKey ?? MapsApiKeyService.getGoogleMapsApiKey;

  /// Admin ekranlarının paylaştığı örnek (testler sahte istemciyle değiştirir).
  static SehiriciStreetNamer instance = SehiriciStreetNamer();

  final http.Client? _client;
  final Future<String?> Function() _apiKey;

  static const Duration _timeout = Duration(seconds: 8);

  /// OSRM'de pin yola bundan uzaksa ad güvenilmez sayılır.
  static const double _osrmMaxDistanceMeters = 60;

  /// ~11 m'lik ızgarada önbellek (aynı noktaya ikinci istek atılmaz; uçuştaki
  /// istek de paylaşılır). Başarısız sonuç tutulmaz, sonraki deneme yeniden sorar.
  final Map<String, Future<SehiriciStreetSuggestion?>> _cache = {};

  Future<SehiriciStreetSuggestion?> lookup(LatLng point) {
    final key = '${point.latitude.toStringAsFixed(4)},'
        '${point.longitude.toStringAsFixed(4)}';
    final cached = _cache[key];
    if (cached != null) return cached;
    final future = _lookup(point).then((result) {
      if (result == null) _cache.remove(key);
      return result;
    });
    _cache[key] = future;
    return future;
  }

  Future<SehiriciStreetSuggestion?> _lookup(LatLng point) async {
    try {
      final google = await _fromGoogle(point);
      if (google != null && google.street != null) return google;
      final osm = await _fromOsrm(point);
      if (osm != null) {
        return SehiriciStreetSuggestion(
          street: osm,
          neighborhood: google?.neighborhood,
        );
      }
      return google;
    } catch (e) {
      debugPrint('Şehiriçi sokak adı bulunamadı: $e');
      return null;
    }
  }

  Future<http.Response> _get(Uri uri) =>
      (_client?.get(uri) ?? http.get(uri)).timeout(_timeout);

  Future<SehiriciStreetSuggestion?> _fromGoogle(LatLng point) async {
    final key = await _apiKey();
    if (key == null || key.isEmpty) return null;
    Future<List<Map>?> geocode({required bool routeOnly}) async {
      try {
        final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
          'latlng': '${point.latitude},${point.longitude}',
          'language': 'tr',
          if (routeOnly) 'result_type': 'route',
          'key': key,
        });
        final response = await _get(uri);
        if (response.statusCode != 200) return null;
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data is! Map || data['status'] != 'OK') return null;
        final results = data['results'];
        return results is List ? results.whereType<Map>().toList() : null;
      } catch (_) {
        return null;
      }
    }

    final both = await Future.wait([
      geocode(routeOnly: true),
      geocode(routeOnly: false),
    ]);
    return parseGoogleResults(
      routeResults: both[0] ?? const [],
      addressResults: both[1] ?? const [],
    );
  }

  /// Google yanıtlarını öneriye çevirir (test edilebilsin diye ayrı).
  @visibleForTesting
  static SehiriciStreetSuggestion? parseGoogleResults({
    required List<Map> routeResults,
    required List<Map> addressResults,
  }) {
    final streets = <String>[];
    String? neighborhood;
    for (final result in [...routeResults, ...addressResults]) {
      final components = result['address_components'];
      if (components is! List) continue;
      for (final c in components.whereType<Map>()) {
        final types = c['types'];
        final name = c['long_name'];
        if (types is! List || name is! String) continue;
        if (types.contains('route')) {
          final street = _usableStreet(name);
          if (street != null && !streets.contains(street)) streets.add(street);
        } else if (neighborhood == null &&
            (types.contains('neighborhood') ||
                types.contains('administrative_area_level_4') ||
                types.contains('sublocality_level_1') ||
                types.contains('sublocality'))) {
          final base = sehiriciNeighborhoodBase(name);
          if (base.isNotEmpty) neighborhood = base;
        }
      }
    }
    if (streets.isEmpty && neighborhood == null) return null;
    return SehiriciStreetSuggestion(
      street: streets.isEmpty ? null : streets.first,
      alternatives: streets.skip(1).take(4).toList(),
      neighborhood: neighborhood,
    );
  }

  /// "Unnamed Road" ve yalnız yol numarası olan adlar ("D400") durak adı olmaz.
  static String? _usableStreet(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return null;
    final folded = sehiriciFold(name);
    if (folded == 'unnamed road' ||
        folded == 'isimsiz yol' ||
        folded == 'adsiz yol') {
      return null;
    }
    if (RegExp(r'^[A-Za-z]{1,2}[- ]?\d{1,4}$').hasMatch(name)) return null;
    final short = sehiriciAbbreviateStreet(name);
    return short.isEmpty ? null : short;
  }

  Future<String?> _fromOsrm(LatLng point) async {
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/nearest/v1/driving/'
        '${point.longitude},${point.latitude}?number=1',
      );
      final response = await _get(uri);
      if (response.statusCode != 200) return null;
      final data = json.decode(utf8.decode(response.bodyBytes));
      if (data is! Map || data['code'] != 'Ok') return null;
      final waypoints = data['waypoints'];
      if (waypoints is! List || waypoints.isEmpty || waypoints.first is! Map) {
        return null;
      }
      final wp = waypoints.first as Map;
      final name = wp['name'];
      final distance = (wp['distance'] as num?)?.toDouble() ?? 0;
      if (name is! String || distance > _osrmMaxDistanceMeters) return null;
      return _usableStreet(name);
    } catch (_) {
      return null;
    }
  }
}
