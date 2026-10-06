import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../../../core/services/location_disclosure_service.dart';
import '../../../core/services/maps_api_key_service.dart';

/// Sohbette paylaşılmak üzere seçilen konum.
class ChatLocationPick {
  const ChatLocationPick({
    required this.latitude,
    required this.longitude,
    this.label,
  });

  final double latitude;
  final double longitude;

  /// Kısa adres ("Ali Bey, Temiz Sk. No:4, Cizre/Şırnak"); bulunamadıysa null.
  final String? label;

  /// Mesajın `attachment` alanı (göç 20260928000004 CHECK'ine uygun).
  Map<String, dynamic> toAttachment() => {
    'lat': latitude,
    'lng': longitude,
    if (label != null && label!.trim().isNotEmpty) 'label': label!.trim(),
  };
}

/// Sohbet konum paylaşımının yardımcıları (Görev 3.1): izinli anlık konum,
/// koordinattan kısa adres ve harita bağlantıları.
class ChatLocationService {
  ChatLocationService({http.Client? httpClient}) : _http = httpClient;

  final http.Client? _http;

  /// Cizre merkezi — konum alınamazsa harita buradan açılır.
  static const double defaultLatitude = 37.3256;
  static const double defaultLongitude = 42.1920;

  /// Anlık konum. Play politikası gereği önce uygulama içi açıklama gösterilir
  /// ([LocationDisclosureService]); kullanıcı reddederse ya da konum
  /// alınamazsa null (çağıran haritayı varsayılan noktada açar).
  Future<({double latitude, double longitude})?> currentLocation(
    BuildContext context,
  ) async {
    try {
      final granted = await LocationDisclosureService.ensure(
        context,
        LocationPurpose.chatShare,
      );
      if (!granted) return null;
      // Paylaşılan konum ANLIK olmalı: önce taze ölçüm; soğuk GPS'te zaman
      // aşımına uğrarsa son bilinen konum.
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 12),
          ),
        );
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }
      if (position == null) return null;
      return (latitude: position.latitude, longitude: position.longitude);
    } catch (e) {
      debugPrint('Sohbet konumu alınamadı: $e');
      return null;
    }
  }

  /// Koordinatın kısa adresi (Google Geocoding; anahtar veritabanından).
  /// Bulunamazsa null — konum adressiz de gönderilebilir.
  Future<String?> reverseGeocode(double latitude, double longitude) async {
    try {
      final key = await MapsApiKeyService.getGoogleMapsApiKey();
      if (key == null || key.isEmpty) return null;
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'latlng': '$latitude,$longitude',
        'language': 'tr',
        'key': key,
      });
      final response = await (_http?.get(uri) ?? http.get(uri))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final data = json.decode(utf8.decode(response.bodyBytes));
      if (data is! Map || data['status'] != 'OK') return null;
      final results = data['results'];
      if (results is! List || results.isEmpty) return null;
      final formatted = (results.first as Map)['formatted_address'];
      if (formatted is! String || formatted.trim().isEmpty) return null;
      return shortAddress(formatted);
    } catch (e) {
      debugPrint('Adres bulunamadı: $e');
      return null;
    }
  }

  /// "Ali Bey, Temiz Sk. No:4, 73200 Cizre/Şırnak, Türkiye" →
  /// "Ali Bey, Temiz Sk. No:4, Cizre/Şırnak" (ülke ve posta kodu atılır).
  static String shortAddress(String formatted) {
    return formatted
        .trim()
        .replaceAll(RegExp(r',\s*(Türkiye|Turkey)\s*$'), '')
        .replaceAll(RegExp(r'\b\d{5}\s+'), '')
        .trim();
  }

  /// Mesajın önizleme metni (liste, bildirim, eski sürümler).
  static String previewText(String? label) {
    final trimmed = label?.trim() ?? '';
    return trimmed.isEmpty ? '📍 Konum' : '📍 Konum: $trimmed';
  }

  static String formatCoordinates(double latitude, double longitude) =>
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

  /// Google Haritalar'da yol tarifi.
  static Uri directionsUri(double latitude, double longitude) => Uri.https(
    'www.google.com',
    '/maps/dir/',
    {'api': '1', 'destination': '$latitude,$longitude'},
  );

  /// Google Haritalar'da nokta.
  static Uri searchUri(double latitude, double longitude) => Uri.https(
    'www.google.com',
    '/maps/search/',
    {'api': '1', 'query': '$latitude,$longitude'},
  );
}
