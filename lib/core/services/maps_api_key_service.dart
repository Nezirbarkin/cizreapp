import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Google Maps API Key servisi
/// API key'i veritabanından çeker ve runtime'da kullanır
class MapsApiKeyService {
  static String? _cachedApiKey;
  
  /// API Key'i veritabanından al
  static Future<String?> getGoogleMapsApiKey() async {
    // Cache'den kontrol et
    if (_cachedApiKey != null) {
      return _cachedApiKey;
    }
    
    try {
      final response = await Supabase.instance.client
          .from('app_about_settings')
          .select('google_maps_api_key')
          .single();
      
      final apiKey = response['google_maps_api_key'] as String?;
      if (apiKey != null && apiKey.isNotEmpty) {
        _cachedApiKey = apiKey;
        return apiKey;
      }
    } catch (e) {
      debugPrint('❌ Google Maps API Key alınamadı: $e');
    }
    
    return null;
  }
  
  /// API Key cache'ini temizle
  static void clearCache() {
    _cachedApiKey = null;
  }
  
  /// API Key geçerli mi kontrol et
  static bool isValidApiKey(String? apiKey) {
    if (apiKey == null || apiKey.isEmpty) {
      return false;
    }
    // Google Maps API key formatı kontrolü
    // Genellikle 39 karakter uzunluğunda ve AIza... ile başlar
    return apiKey.length >= 35 && apiKey.startsWith('AIza');
  }
  
  /// Fallback API Key (geliştirme için)
  /// NOT: Üretimde kullanmayın, sadece development için
  static const String fallbackApiKey = 'AIzaSyBi120_sBg5IEgzaugQ-FgRAbZaW18267I';
}