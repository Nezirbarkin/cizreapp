import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// www.cizreapp.com açılışında gösterilen tanıtım (promo) ekranının ayarları.
///
/// Ekranın kendisi Flutter değil, `web/index.html` içindeki statik HTML'dir —
/// böylece ziyaretçi Flutter bundle'ı inmeden ilk saniyede tanıtımı görür.
/// O ekran buradaki değerleri Supabase REST üzerinden anon anahtarla okur;
/// bu yüzden ayarlar `app_settings` tablosunda (SELECT herkese açık) tutulur.
@immutable
class WebPromoSettings {
  /// Tanıtım ekranı açık mı? Kapalıysa web doğrudan uygulamaya girer.
  final bool enabled;

  /// Tanıtım videosu (mp4/webm). Boşsa animasyonlu marka sahnesi gösterilir.
  final String videoUrl;

  /// Video yüklenene kadar gösterilen kapak görseli.
  final String posterUrl;

  final String headline;
  final String tagline;
  final String playStoreUrl;
  final String appStoreUrl;
  final String continueText;

  /// "Webte devam et" düğmesi gösterilsin mi? Kapalıysa tanıtım ekranı kalıcı
  /// bir iniş sayfası gibi durur: ziyaretçi yalnızca mağazalara yönlendirilir
  /// (derin bağlantılar ve `?promo=0` yine web uygulamasını açar).
  final bool continueEnabled;

  /// Sloganın altında SIRAYLA DÖNEN tanıtım maddeleri.
  ///
  /// Tek bir ayar satırında, her satır bir madde olarak saklanır; madde
  /// eklemek/çıkarmak böylece satır ekleyip silmeyi gerektirmez.
  /// Liste boşsa şerit tanıtım ekranında hiç gösterilmez.
  final List<String> rotatingLines;

  /// Bir maddenin ekranda kalma süresi (ms).
  final int rotateMs;

  /// true → her açılışta göster, false → ziyaretçiye yalnızca bir kez.
  final bool showAlways;

  /// Artırıldığında tanıtımı daha önce kapatmış ziyaretçilere yeniden gösterir.
  final int version;

  const WebPromoSettings({
    required this.enabled,
    required this.videoUrl,
    required this.posterUrl,
    required this.headline,
    required this.tagline,
    required this.playStoreUrl,
    required this.appStoreUrl,
    required this.continueText,
    required this.continueEnabled,
    required this.rotatingLines,
    required this.rotateMs,
    required this.showAlways,
    required this.version,
  });

  /// Ayarlar okunamazsa kullanılan varsayılanlar — index.html içindeki
  /// DEFAULTS bloğuyla aynı değerler olmalı.
  static const WebPromoSettings defaults = WebPromoSettings(
    enabled: true,
    videoUrl: '',
    posterUrl: '',
    headline: 'CizreApp',
    tagline: 'Her an, her kapıda!',
    playStoreUrl:
        'https://play.google.com/store/apps/details?id=com.cizreapp.com',
    appStoreUrl: '',
    continueText: 'Webte devam et',
    continueEnabled: true,
    rotatingLines: [
      'İlan ver, alıcını bul',
      'Alışveriş yap, kapına gelsin',
      'Kurye çağır, paketin yola çıksın',
      'Şehiriçi otobüsü canlı takip et',
      'Komşunla paylaş, sohbete katıl',
    ],
    rotateMs: 2600,
    showAlways: false,
    version: 1,
  );

  WebPromoSettings copyWith({
    bool? enabled,
    String? videoUrl,
    String? posterUrl,
    String? headline,
    String? tagline,
    String? playStoreUrl,
    String? appStoreUrl,
    String? continueText,
    bool? continueEnabled,
    List<String>? rotatingLines,
    int? rotateMs,
    bool? showAlways,
    int? version,
  }) {
    return WebPromoSettings(
      enabled: enabled ?? this.enabled,
      videoUrl: videoUrl ?? this.videoUrl,
      posterUrl: posterUrl ?? this.posterUrl,
      headline: headline ?? this.headline,
      tagline: tagline ?? this.tagline,
      playStoreUrl: playStoreUrl ?? this.playStoreUrl,
      appStoreUrl: appStoreUrl ?? this.appStoreUrl,
      continueText: continueText ?? this.continueText,
      continueEnabled: continueEnabled ?? this.continueEnabled,
      rotatingLines: rotatingLines ?? this.rotatingLines,
      rotateMs: rotateMs ?? this.rotateMs,
      showAlways: showAlways ?? this.showAlways,
      version: version ?? this.version,
    );
  }

  /// `app_settings` satırlarından (key/value) okur.
  factory WebPromoSettings.fromRows(List<Map<String, dynamic>> rows) {
    final map = <String, String>{};
    for (final row in rows) {
      final key = row['key']?.toString();
      if (key == null || !key.startsWith(WebPromoService.keyPrefix)) continue;
      final value = row['value'];
      map[key.substring(WebPromoService.keyPrefix.length)] = value == null
          ? ''
          : value.toString();
    }

    String str(String key, String fallback) {
      final value = map[key];
      return (value == null || value.isEmpty) ? fallback : value;
    }

    bool flag(String key, bool fallback) {
      final value = map[key];
      if (value == null || value.isEmpty) return fallback;
      return value == 'true' || value == '1';
    }

    return WebPromoSettings(
      enabled: flag('enabled', defaults.enabled),
      // Video/kapak/App Store için "boş" geçerli bir değerdir; str() boşu
      // varsayılana çevirdiği için bunlar doğrudan okunur.
      videoUrl: map['video_url'] ?? '',
      posterUrl: map['poster_url'] ?? '',
      headline: str('headline', defaults.headline),
      tagline: str('tagline', defaults.tagline),
      playStoreUrl: map['playstore_url'] ?? defaults.playStoreUrl,
      appStoreUrl: map['appstore_url'] ?? '',
      continueText: str('continue_text', defaults.continueText),
      continueEnabled: flag('continue_enabled', defaults.continueEnabled),
      // Maddeler tek ayar satırında, satır sonlarıyla ayrılmış gelir.
      // Anahtar HİÇ yoksa varsayılan liste kullanılır; VARSA ama boşsa
      // admin maddeleri bilerek kaldırmış demektir, boş liste saygı görür.
      rotatingLines: map.containsKey('rotating_lines')
          ? splitLines(map['rotating_lines'] ?? '')
          : defaults.rotatingLines,
      rotateMs: _clampRotateMs(
        int.tryParse(str('rotate_ms', '')) ?? defaults.rotateMs,
      ),
      showAlways: str('show_mode', 'once') == 'always',
      version: int.tryParse(str('version', '1')) ?? 1,
    );
  }

  /// Çok satırlı metni maddelere böler: boş satırlar ve baştaki/sondaki
  /// boşluklar atılır, böylece admin metin kutusunda bıraktığı boş satır
  /// tanıtımda boş bir madde olarak dönmez.
  static List<String> splitLines(String raw) {
    return raw
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  /// Süre sınırı: çok kısa olursa madde okunmadan geçer, çok uzun olursa
  /// şerit durmuş görünür.
  static int _clampRotateMs(int value) => value.clamp(1200, 10000);

  /// `app_settings` upsert gövdesi. Değerler jsonb kolonuna JSON string
  /// olarak yazılır ("true", "1", "https://..."), mevcut konvansiyonla aynı.
  Map<String, String> toSettingsMap() {
    return {
      'enabled': enabled ? 'true' : 'false',
      'video_url': videoUrl.trim(),
      'poster_url': posterUrl.trim(),
      'headline': headline.trim(),
      'tagline': tagline.trim(),
      'playstore_url': playStoreUrl.trim(),
      'appstore_url': appStoreUrl.trim(),
      'continue_text': continueText.trim(),
      'continue_enabled': continueEnabled ? 'true' : 'false',
      'rotating_lines': rotatingLines.join('\n'),
      'rotate_ms': _clampRotateMs(rotateMs).toString(),
      'show_mode': showAlways ? 'always' : 'once',
      'version': version.toString(),
    };
  }
}

/// Tanıtım ekranı ayarlarını ve medyasını yöneten admin servisi.
class WebPromoService {
  static const String keyPrefix = 'web_promo_';
  static const String bucket = 'promo-media';

  /// Bucket 100 MB'a kadar kabul ediyor ama tanıtım videosu açılış ekranında
  /// oynadığı için pratik sınırı daha düşük tutup admini uyarıyoruz.
  static const int recommendedVideoMb = 25;
  static const int maxVideoMb = 100;

  final SupabaseClient _client;

  WebPromoService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Future<WebPromoSettings> getSettings() async {
    final response = await _client
        .from('app_settings')
        .select('key,value')
        .like('key', '$keyPrefix%');
    return WebPromoSettings.fromRows(
      (response as List).cast<Map<String, dynamic>>(),
    );
  }

  /// Tüm anahtarları tek istekte yazar. Satırlar migration ile seed edildiği
  /// için normalde UPDATE yolu çalışır; upsert, ileride eklenecek yeni bir
  /// anahtarın da tek çağrıda oluşabilmesi için tercih edildi.
  Future<void> saveSettings(WebPromoSettings settings) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = settings
        .toSettingsMap()
        .entries
        .map(
          (e) => {
            'key': '$keyPrefix${e.key}',
            'value': e.value,
            'updated_at': now,
          },
        )
        .toList();
    await _client.from('app_settings').upsert(rows, onConflict: 'key');
  }

  /// Tanıtım medyasını (video ya da kapak görseli) yükler ve public URL döner.
  Future<String> uploadMedia({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final safeName = fileName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]'), '_');
    final path = '${DateTime.now().millisecondsSinceEpoch}_$safeName';

    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return _client.storage.from(bucket).getPublicUrl(path);
  }

  /// Bucket'taki eski dosyayı siler. Yalnızca `promo-media` altındaki
  /// adresler silinir; dışarıdan girilen bir URL'ye dokunulmaz.
  Future<void> deleteMediaIfOwned(String publicUrl) async {
    final marker = '/$bucket/';
    final index = publicUrl.indexOf(marker);
    if (index < 0) return;
    final path = publicUrl.substring(index + marker.length).split('?').first;
    if (path.isEmpty) return;
    try {
      await _client.storage.from(bucket).remove([path]);
    } catch (error) {
      // Silme başarısız olsa da ayar kaydı sürmeli; sadece çöp dosya kalır.
      debugPrint('[WebPromoService] media_delete_failed path=$path $error');
    }
  }
}
