import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keşfet (sosyal akış) erişim ayarını okuyup yazar.
///
/// Ayar `app_settings` tablosunda `explore_public_access` anahtarında tutulur;
/// bu tablonun SELECT policy'si herkese açıktır, yani giriş yapmamış ziyaretçi
/// de değeri okuyabilir.
///
/// ÖNEMLİ: Bu sınıf yalnızca ARAYÜZ kapısıdır. Asıl kapı sunucudadır —
/// misafir akışı `public_explore_feed()` RPC'sinden gelir ve o RPC ayar
/// kapalıyken boş liste döner (bkz. 20260908130003_explore_public_access.sql).
/// Yani istemci tarafını kurcalayan biri kapalı bir Keşfet'i açamaz.
class SocialAccessService {
  static const String settingKey = 'explore_public_access';

  /// Ayar okunamazsa (ağ hatası, eski sürüm DB) uygulanan varsayılan:
  /// Keşfet yalnız üyelere açık. Güvenli taraf budur.
  static const bool defaultIsPublic = false;

  static bool? _cache;

  static SupabaseClient get _client => Supabase.instance.client;

  /// Bellekteki son bilinen değer. Ekranların ilk karede senkron karar
  /// verebilmesi için vardır; henüz okunmadıysa varsayılana düşer.
  static bool get cachedIsPublic => _cache ?? defaultIsPublic;

  static bool get isLoaded => _cache != null;

  /// Ayarı sunucudan okur ve önbelleğe alır.
  static Future<bool> fetchIsPublic({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null) return _cache!;

    try {
      final row = await _client
          .from('app_settings')
          .select('value')
          .eq('key', settingKey)
          .maybeSingle();

      _cache = _parseFlag(row?['value']);
    } catch (e) {
      debugPrint('⚠️ Keşfet erişim ayarı okunamadı: $e');
      _cache ??= defaultIsPublic;
    }

    return _cache!;
  }

  /// Admin: ayarı günceller. `app_settings` UPDATE/INSERT policy'leri
  /// `auth_is_admin()` ister, yani admin olmayan çağrı DB tarafında reddedilir.
  static Future<void> setIsPublic(bool value) async {
    await _client.from('app_settings').upsert({
      'key': settingKey,
      // Mevcut konvansiyon: jsonb kolonuna JSON string yazılır
      // (bkz. web_promo_service.dart).
      'value': value ? 'true' : 'false',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'key');
    _cache = value;
  }

  static void invalidate() => _cache = null;

  /// `value` jsonb kolonu; migration `true` (JSON boolean) yazmış olabilir,
  /// admin paneli ise `"true"` (JSON string) yazar. İkisini de kabul ediyoruz.
  static bool _parseFlag(dynamic raw) {
    if (raw == null) return defaultIsPublic;
    if (raw is bool) return raw;
    final text = raw.toString().replaceAll('"', '').trim().toLowerCase();
    return text == 'true' || text == '1';
  }
}
