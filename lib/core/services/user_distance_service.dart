import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'location_disclosure_service.dart';

/// Kullanıcının konumu ile bir dükkan/nokta arasındaki mesafeyi hesaplar ve
/// "1,2 km" biçiminde gösterime hazır hale getirir.
///
/// Konum izni **asla doğrudan istenmez**: pasif kullanım için
/// [positionIfAllowed] yalnızca kullanıcı daha önce Prominent Disclosure
/// ekranını kabul edip izin verdiyse konum döndürür. Kullanıcı açıkça
/// "uzaklığımı göster" derse [requestPosition] disclosure akışını çalıştırır.
/// (Bkz. [LocationDisclosureService] - Play "Prominent Disclosure" şartı.)
class UserDistanceService {
  UserDistanceService._();

  /// Kısa ömürlü konum önbelleği. Dükkan listesi her yeniden çizildiğinde ve
  /// dükkanlar arasında gezinirken tekrar tekrar GPS uyandırmamak için.
  static Position? _cached;
  static DateTime? _cachedAt;
  static const Duration _cacheTtl = Duration(minutes: 5);

  static bool get _cacheValid =>
      _cached != null &&
      _cachedAt != null &&
      DateTime.now().difference(_cachedAt!) < _cacheTtl;

  /// İzin ZATEN verilmişse konumu döndürür; verilmemişse kullanıcıya hiçbir
  /// şey sormadan `null` döner.
  static Future<Position?> positionIfAllowed() async {
    if (_cacheValid) return _cached;
    try {
      if (!await LocationDisclosureService.isReady(LocationPurpose.nearby)) {
        return null;
      }
      return await _read();
    } catch (e) {
      debugPrint('Mesafe için konum alınamadı: $e');
      return null;
    }
  }

  /// Kullanıcı açıkça istediğinde çağrılır: önce disclosure + izin akışı,
  /// ardından konum. Kullanıcı reddederse `null` döner.
  static Future<Position?> requestPosition(BuildContext context) async {
    try {
      final granted = await LocationDisclosureService.ensure(
        context,
        LocationPurpose.nearby,
      );
      if (!granted) return null;
      return await _read();
    } catch (e) {
      debugPrint('Konum isteği başarısız: $e');
      return null;
    }
  }

  /// Soğuk GPS'te `getCurrentPosition` uzun süre askıda kalabildiği için önce
  /// son bilinen konum denenir; yoksa zaman sınırlı gerçek ölçüm yapılır.
  static Future<Position?> _read() async {
    Position? position;
    try {
      position = await Geolocator.getLastKnownPosition();
    } catch (_) {
      position = null;
    }

    position ??= await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 0,
        timeLimit: Duration(seconds: 10),
      ),
    );

    _cached = position;
    _cachedAt = DateTime.now();
    return position;
  }

  /// [from] ile hedef koordinat arasındaki metre cinsinden mesafe.
  /// Konum ya da hedef koordinat eksikse `null` döner.
  static double? distanceMeters({
    required Position? from,
    required double? targetLat,
    required double? targetLng,
  }) {
    if (from == null || targetLat == null || targetLng == null) return null;
    return Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      targetLat,
      targetLng,
    );
  }

  /// "850 m" / "1,2 km" / "12 km" biçiminde kısa gösterim.
  static String format(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    final km = meters / 1000;
    // 10 km altında tek ondalık anlamlı; üstünde yuvarlak sayı daha okunur.
    final text = km < 10 ? km.toStringAsFixed(1) : km.toStringAsFixed(0);
    return '${text.replaceAll('.', ',')} km';
  }
}
