import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/sehirici_models.dart';
import 'sehirici_errors.dart';

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
      await saveCity(city);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Şehri kaydeder; başarısız olursa nedenini içeren [SehiriciAdminException]
  /// fırlatır. Sunucu, boş bağlantı adından (slug) Türkçe karakterleri
  /// bozarak ürettiği için slug istemcide üretilip gönderilir.
  Future<String> saveCity(SehiriciCity city) async {
    final name = city.name.trim();
    if (name.isEmpty) {
      throw const SehiriciAdminException('Şehir adı boş olamaz.');
    }
    if (!city.centerLat.isFinite ||
        !city.centerLng.isFinite ||
        city.centerLat.abs() > 90 ||
        city.centerLng.abs() > 180 ||
        (city.centerLat == 0 && city.centerLng == 0)) {
      throw const SehiriciAdminException(
        'Merkez konumu geçerli değil. Haritadan seçin ya da enlem/boylam girin.',
      );
    }
    if (city.zoomLevel < 3 || city.zoomLevel > 20) {
      throw const SehiriciAdminException('Yakınlık 3 ile 20 arasında olmalı.');
    }
    try {
      final cityId = city.id.isEmpty ? const Uuid().v4() : city.id;
      final slug = city.slug.trim().isEmpty ? slugify(name) : city.slug.trim();
      await _client.rpc('admin_upsert_sehirici_city', params: {
        'p_id': cityId,
        'p_name': name,
        'p_slug': slug,
        'p_center_lat': city.centerLat,
        'p_center_lng': city.centerLng,
        'p_zoom_level': city.zoomLevel,
        'p_is_active': city.isActive,
      });
      clearCache();
      return cityId;
    } catch (e) {
      debugPrint('SehiriciCityService.saveCity hata: $e');
      throw SehiriciAdminException(sehiriciErrorMessage(e));
    }
  }

  /// "Şırnak Merkez" → "sirnak-merkez". Türkçe harfler sadeleştirilir.
  static String slugify(String input) {
    const fold = {
      'ç': 'c', 'ğ': 'g', 'ı': 'i', 'i̇': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u',
      'Ç': 'c', 'Ğ': 'g', 'İ': 'i', 'I': 'i', 'Ö': 'o', 'Ş': 's', 'Ü': 'u',
    };
    final buf = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      buf.write(fold[ch] ?? ch.toLowerCase());
    }
    final slug = buf
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'sehir' : slug;
  }

  Future<bool> deleteCity(String cityId) async {
    try {
      await deleteCityOrThrow(cityId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Şehri ve (CASCADE ile) tüm hat/duraklarını siler.
  Future<void> deleteCityOrThrow(String cityId) async {
    try {
      await _client.rpc('admin_delete_sehirici_city', params: {'p_id': cityId});
      clearCache();
    } catch (e) {
      debugPrint('deleteCity hata: $e');
      throw SehiriciAdminException(sehiriciErrorMessage(e));
    }
  }

  // ─────────────────────────────────────────────
  // Ayarları güncelle (admin)
  // ─────────────────────────────────────────────
  Future<bool> updateSetting(String key, String value) async {
    try {
      await updateSettingOrThrow(key, value);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Ayarı yazar. Anahtar hiç yoksa OLUŞTURUR: eskiden `update().eq('key')`
  /// kayıt yoksa 0 satırı etkileyip sessizce "başarılı" dönüyordu; yeni bir
  /// kurulumda ayar anahtarları henüz yokken admin'in değişikliği kaybolurdu.
  ///
  /// [value] düz metin verilir ("true", "15"); jsonb kolonuna JSON string
  /// olarak yazılır (`"true"`) — okuyucular `#>> '{}'` ile çözer.
  Future<void> updateSettingOrThrow(String key, String value) async {
    try {
      await _client.from('app_settings').upsert({
        'key': key,
        'value': value,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'key');
      clearCache();
    } catch (e) {
      debugPrint('updateSetting hata: $e');
      throw SehiriciAdminException(sehiriciErrorMessage(e));
    }
  }
}
