import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Müzik özelliğinin admin anahtarları.
///
/// Altı anahtarın hepsi TEK RPC çağrısıyla (`music_settings`) alınır ve oturum
/// boyunca önbellekte tutulur — her ekranın ayrı ayrı `app_settings` sorgulaması
/// akışa ölçülebilir bir gecikme eklerdi.
///
/// ## Bu sınıf bir güvenlik sınırı DEĞİL
///
/// [SocialAccessService] ile aynı desen: burası yalnızca ARAYÜZ kapısıdır.
/// Asıl kapılar sunucuda:
/// * katalog araması bayrak kapalıyken boş döner (`music_search_catalog`),
/// * başvuru RPC'si reddeder (`music_submit_track`),
/// * gönderi/hikaye tetikleyicisi iliştirmeyi düşürür (`music_attach_guard`).
///
/// Tek istisna [deviceAdd]: kullanıcının kendi telefonundaki dosyayı kendi
/// kitaplığına kopyalaması sunucuya hiç uğramaz, dolayısıyla sunucuda
/// uygulanacak bir karşılığı da yoktur. Bunu gizlemiyoruz — o anahtar
/// gerçekten yalnızca arayüzü kapatır.
class MusicSettings {
  final bool feature;
  final bool catalog;
  final bool deviceAdd;
  final bool attach;
  final bool artistUpload;
  final int maxUploadMb;

  const MusicSettings({
    required this.feature,
    required this.catalog,
    required this.deviceAdd,
    required this.attach,
    required this.artistUpload,
    required this.maxUploadMb,
  });

  /// Ayar okunamadığında uygulanan varsayılan.
  ///
  /// Müzik ÇALMA açık kalır (ağ hatası yüzünden kullanıcının kitaplığı
  /// kaybolmasın), ama sunucuya bir şey YAZAN iki yol — iliştirme ve sanatçı
  /// başvurusu — kapalı başlar. Emin olunamayan durumda yazmamak, okumamaktan
  /// daha güvenli taraftır.
  static const MusicSettings fallback = MusicSettings(
    feature: true,
    catalog: true,
    deviceAdd: true,
    attach: false,
    artistUpload: false,
    maxUploadMb: 10,
  );

  factory MusicSettings.fromJson(Map<String, dynamic> json) => MusicSettings(
    feature: json['feature'] == true,
    catalog: json['catalog'] == true,
    deviceAdd: json['device_add'] == true,
    attach: json['attach'] == true,
    artistUpload: json['artist_upload'] == true,
    maxUploadMb: (json['max_upload_mb'] as num?)?.toInt() ?? 10,
  );
}

class MusicSettingsService {
  MusicSettingsService._();

  static MusicSettings? _cache;

  /// Henüz okunmadıysa varsayılana düşen senkron erişim.
  ///
  /// Yan menü gibi ilk karede karar vermesi gereken yerler için var: menü
  /// açılırken bir RPC'yi beklemek menünün boş açılması demek olurdu.
  static MusicSettings get cached => _cache ?? MusicSettings.fallback;

  static bool get isLoaded => _cache != null;

  /// Anahtarları sunucudan okur. ASLA hata fırlatmaz.
  static Future<MusicSettings> fetch({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null) return _cache!;

    try {
      final raw = await Supabase.instance.client.rpc('music_settings');
      if (raw is Map) {
        _cache = MusicSettings.fromJson(Map<String, dynamic>.from(raw));
      } else {
        _cache ??= MusicSettings.fallback;
      }
    } catch (e) {
      debugPrint('⚠️ Müzik ayarları okunamadı: $e');
      _cache ??= MusicSettings.fallback;
    }

    return _cache!;
  }

  static void invalidate() => _cache = null;

  /// Admin bir anahtarı değiştirdi — hem sunucuya yaz hem önbelleği tazele.
  ///
  /// `app_settings` INSERT/UPDATE politikaları `auth_is_admin()` istiyor, yani
  /// admin olmayan çağrı veritabanı tarafında reddedilir.
  static Future<void> setFlag(String key, bool value) async {
    await Supabase.instance.client.from('app_settings').upsert({
      'key': key,
      // DÜZ metin yazılır. PostgREST Dart string'ini zaten JSON string olarak
      // kodlar ('true' → jsonb "true"). '"true"' yazmak jsonb'de TIRNAKLI
      // metin bırakıyordu ve sunucudaki okuyucular çevrimde patlıyordu
      // (bkz. 20260921000004). Doğru örnek: SocialAccessService.setIsPublic.
      'value': value ? 'true' : 'false',
    }, onConflict: 'key');
    await fetch(forceRefresh: true);
  }

  static Future<void> setMaxUploadMb(int mb) async {
    final clamped = mb.clamp(1, 50);
    await Supabase.instance.client.from('app_settings').upsert({
      'key': 'music_max_upload_mb',
      'value': '$clamped',
    }, onConflict: 'key');
    await fetch(forceRefresh: true);
  }
}
