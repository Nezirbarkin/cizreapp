import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 101 Okey modülünün admin anahtarı (`app_settings.okey_module_enabled`,
/// Görev 4.1).
///
/// ## Bu sınıf bir güvenlik sınırı DEĞİL
///
/// [MusicSettingsService] ile aynı desen: burası yalnızca ARAYÜZ kapısıdır
/// (menü düğmesi, lobi, davet bildirimi, liderler tablosundaki Okey kartları).
/// Asıl kapı sunucuda: modül kapalıyken yeni oda / koltuk / izleyici / davet
/// kayıtları tetikleyiciyle reddedilir (`private.okey_module_guard`).
class OkeyModuleService {
  OkeyModuleService._();

  static bool? _cache;

  /// Okunmadıysa AÇIK kabul edilir (ağ hatası yüzünden modül kaybolmasın;
  /// kapalıysa sunucu zaten yeni oyun açtırmaz).
  static bool get cachedEnabled => _cache ?? true;

  static bool get isLoaded => _cache != null;

  /// Anahtarı sunucudan okur. ASLA hata fırlatmaz.
  static Future<bool> fetch({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null) return _cache!;
    try {
      final raw = await Supabase.instance.client.rpc('okey_module_enabled');
      _cache = raw != false;
    } catch (e) {
      debugPrint('⚠️ Okey modül anahtarı okunamadı: $e');
      _cache ??= true;
    }
    return _cache!;
  }

  /// Admin anahtarı değiştirir (app_settings yazma politikası admin ister).
  static Future<void> setEnabled(bool value) async {
    await Supabase.instance.client.from('app_settings').upsert({
      'key': 'okey_module_enabled',
      // Düz metin: PostgREST jsonb "true"/"false" yazar (bkz. MusicSettingsService).
      'value': value ? 'true' : 'false',
    }, onConflict: 'key');
    _cache = value;
  }

  @visibleForTesting
  static void setCacheForTesting(bool? value) => _cache = value;
}
