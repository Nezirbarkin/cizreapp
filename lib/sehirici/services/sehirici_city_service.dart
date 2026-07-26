import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/sehirici_models.dart';

/// Şehirler ve ayarlar servisi.
class SehiriciCityService {
  final SupabaseClient _client;
  SehiriciCityService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // ─────────────────────────────────────────────
  // Cache (basit bellek içi)
  // ─────────────────────────────────────────────
  static List<SehiriciCity>? _cachedCities;
  static SehiriciSettings? _cachedSettings;

  static void clearCache() {
    _cachedCities = null;
    _cachedSettings = null;
  }

  /// Aktif şehirleri getir (cache'li).
  Future<List<SehiriciCity>> getCities({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedCities != null) return _cachedCities!;
    try {
      final response = await _client
          .from('sehirici_cities')
          .select()
          .eq('is_active', true)
          .order('name', ascending: true);
      final cities = (response as List)
          .map((e) => SehiriciCity.fromJson(e as Map<String, dynamic>))
          .toList();
      _cachedCities = cities;
      return cities;
    } catch (e) {
      debugPrint('SehiriciCityService.getCities hata: $e');
      return _cachedCities ?? const [];
    }
  }

  /// Modül ayarlarını getir (cache'li).
  Future<SehiriciSettings> getSettings({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedSettings != null) return _cachedSettings!;
    try {
      final response = await _client
          .from('app_settings')
          .select('key,value')
          .like('key', 'sehirici_%');
      final map = <String, dynamic>{};
      for (final row in (response as List)) {
        map[row['key'] as String] = row['value'];
      }
      _cachedSettings = SehiriciSettings.fromSettingsMap(map);
      return _cachedSettings!;
    } catch (e) {
      debugPrint('SehiriciCityService.getSettings hata: $e');
      return _cachedSettings ??
          const SehiriciSettings(moduleEnabled: true);
    }
  }

  // ─────────────────────────────────────────────
  // Admin CRUD
  // ─────────────────────────────────────────────

  /// Tüm şehirleri getir (admin için — pasif dahil).
  Future<List<SehiriciCity>> getAllCitiesAdmin() async {
    try {
      final response = await _client
          .from('sehirici_cities')
          .select()
          .order('name', ascending: true);
      return (response as List)
          .map((e) => SehiriciCity.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('SehiriciCityService.getAllCitiesAdmin hata: $e');
      return [];
    }
  }

  Future<bool> upsertCity(SehiriciCity city) async {
    try {
      final cityId = city.id.isEmpty ? const Uuid().v4() : city.id;
      await _client.rpc('admin_upsert_sehirici_city', params: {
        'p_id': cityId,
        'p_name': city.name,
        'p_slug': city.slug,
        'p_center_lat': city.centerLat,
        'p_center_lng': city.centerLng,
        'p_zoom_level': city.zoomLevel,
        'p_is_active': city.isActive,
      });
      clearCache();
      return true;
    } catch (e) {
      debugPrint('SehiriciCityService.upsertCity hata: $e');
      return false;
    }
  }

  Future<bool> deleteCity(String cityId) async {
    try {
      await _client.rpc('admin_delete_sehirici_city', params: {'p_id': cityId});
      clearCache();
      return true;
    } catch (e) {
      debugPrint('deleteCity hata: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────
  // Ayarları güncelle (admin)
  // ─────────────────────────────────────────────
  Future<bool> updateSetting(String key, String value) async {
    try {
      await _client
          .from('app_settings')
          .update({'value': value})
          .eq('key', key);
      clearCache();
      return true;
    } catch (e) {
      debugPrint('updateSetting hata: $e');
      return false;
    }
  }
}
