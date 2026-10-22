import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sesli okuma sesi. Anahtarlar sunucudaki `voice_gender` / `voice_announce_gender`
/// değerleriyle aynıdır; değişmemeli.
enum VoiceGender {
  female('female', 'Kadın'),
  male('male', 'Erkek');

  const VoiceGender(this.key, this.label);

  final String key;
  final String label;

  /// Bilinmeyen/boş değer → null (çağıran varsayılana düşer).
  static VoiceGender? tryParse(String? key) {
    final k = key?.trim().toLowerCase();
    for (final g in VoiceGender.values) {
      if (g.key == k) return g;
    }
    return null;
  }
}

/// Otomatik sesli okunabilen bölümler. Anahtarlar `voice_announce_areas`
/// (virgülle ayrılmış) değerindeki parçalarla aynıdır.
enum VoiceArea {
  adminNotifications('admin_notifications', 'Admin bildirimleri', 'Uygulama açıkken gelen yönetici bildirimleri'),
  startup('startup', 'Açılış duyurusu', 'Uygulama açılınca çıkan duyuru penceresi'),
  seller('seller', 'Satıcı duyuruları', 'Satıcı panelindeki yönetim duyuru kartları'),
  courier('courier', 'Kurye duyuruları', 'Paket Gönder ekranı ve kurye panelindeki duyurular');

  const VoiceArea(this.key, this.label, this.description);

  final String key;
  final String label;
  final String description;

  static VoiceArea? tryParse(String? key) {
    final k = key?.trim().toLowerCase();
    for (final a in VoiceArea.values) {
      if (a.key == k) return a;
    }
    return null;
  }
}

/// Admin'in belirlediği sesli duyuru ayarları (`voice_announce_settings()` RPC'si).
@immutable
class VoiceAnnounceSettings {
  const VoiceAnnounceSettings({
    this.enabled = true,
    this.gender = VoiceGender.female,
    this.areas = const {
      VoiceArea.adminNotifications,
      VoiceArea.startup,
      VoiceArea.seller,
      VoiceArea.courier,
    },
    this.greeting = true,
  });

  /// Ana anahtar. Kapalıysa hiçbir yerde okunmaz ve "Dinle" düğmeleri gizlenir.
  final bool enabled;

  /// Kampanya kendi sesini seçmediyse kullanılan ses.
  final VoiceGender gender;

  /// Otomatik okunan bölümler ("Dinle" bunlardan bağımsız çalışır).
  final Set<VoiceArea> areas;

  /// Okumaya "Merhaba Ahmet," gibi kullanıcının adıyla başla.
  final bool greeting;

  static const VoiceAnnounceSettings defaults = VoiceAnnounceSettings();

  bool allowsAuto(VoiceArea area) => enabled && areas.contains(area);

  factory VoiceAnnounceSettings.fromJson(Map<String, dynamic> j) {
    bool flag(dynamic v, bool fallback) {
      if (v is bool) return v;
      final s = '$v'.trim().toLowerCase();
      if (const ['true', 't', '1', 'yes', 'on'].contains(s)) return true;
      if (const ['false', 'f', '0', 'no', 'off'].contains(s)) return false;
      return fallback;
    }

    final rawAreas = j['areas'];
    final Set<VoiceArea> areas;
    if (rawAreas == null) {
      areas = defaults.areas;
    } else {
      areas = '$rawAreas'
          .split(',')
          .map(VoiceArea.tryParse)
          .whereType<VoiceArea>()
          .toSet();
    }
    return VoiceAnnounceSettings(
      enabled: flag(j['enabled'], true),
      gender: VoiceGender.tryParse(j['gender'] as String?) ?? VoiceGender.female,
      areas: areas,
      greeting: flag(j['greeting'], true),
    );
  }

  /// `voice_announce_areas` değeri: boş küme "none" yazılır (boş metin sunucuda
  /// "ayar yok → varsayılan" anlamına geldiği için).
  String get areasValue {
    if (areas.isEmpty) return 'none';
    return VoiceArea.values
        .where(areas.contains)
        .map((a) => a.key)
        .join(',');
  }

  VoiceAnnounceSettings copyWith({
    bool? enabled,
    VoiceGender? gender,
    Set<VoiceArea>? areas,
    bool? greeting,
  }) {
    return VoiceAnnounceSettings(
      enabled: enabled ?? this.enabled,
      gender: gender ?? this.gender,
      areas: areas ?? this.areas,
      greeting: greeting ?? this.greeting,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VoiceAnnounceSettings &&
      other.enabled == enabled &&
      other.gender == gender &&
      setEquals(other.areas, areas) &&
      other.greeting == greeting;

  @override
  int get hashCode => Object.hash(
        enabled,
        gender,
        Object.hashAllUnordered(areas),
        greeting,
      );
}

/// Sesli duyuru ayarlarını okur (önbellekli, ASLA hata fırlatmaz) ve admin
/// için yazar. Okuma: `voice_announce_settings()` (anon dahil açık).
/// Yazma: `app_settings` (INSERT/UPDATE politikası admin ister).
class VoiceAnnounceSettingsService {
  VoiceAnnounceSettingsService._();

  static const Duration _ttl = Duration(minutes: 10);

  static VoiceAnnounceSettings? _cache;
  static DateTime? _fetchedAt;
  static Future<VoiceAnnounceSettings>? _inFlight;

  /// Son bilinen ayar (henüz okunmadıysa varsayılan).
  static VoiceAnnounceSettings get current => _cache ?? VoiceAnnounceSettings.defaults;

  /// Testlerde önbelleği doğrudan ayarlamak için.
  @visibleForTesting
  static void debugSet(VoiceAnnounceSettings? value) {
    _cache = value;
    _fetchedAt = value == null ? null : DateTime.now();
    _inFlight = null;
  }

  static Future<VoiceAnnounceSettings> fetch({bool forceRefresh = false}) {
    final cached = _cache;
    final at = _fetchedAt;
    if (!forceRefresh &&
        cached != null &&
        at != null &&
        DateTime.now().difference(at) < _ttl) {
      return Future.value(cached);
    }
    return _inFlight ??= _load().whenComplete(() {
      _inFlight = null;
    });
  }

  static Future<VoiceAnnounceSettings> _load() async {
    try {
      final res = await Supabase.instance.client.rpc('voice_announce_settings');
      if (res is Map) {
        final parsed = VoiceAnnounceSettings.fromJson(Map<String, dynamic>.from(res));
        _cache = parsed;
        _fetchedAt = DateTime.now();
        return parsed;
      }
    } catch (e) {
      debugPrint('⚠️ Sesli duyuru ayarları okunamadı: $e');
    }
    return current;
  }

  /// Admin: tüm ayarları yazar ve önbelleği tazeler.
  static Future<void> save(VoiceAnnounceSettings s) async {
    // DÜZ metin yazılır (bkz. MusicSettingsService.setFlag açıklaması).
    await Supabase.instance.client.from('app_settings').upsert(
      [
        {'key': 'voice_announce_enabled', 'value': s.enabled ? 'true' : 'false'},
        {'key': 'voice_announce_gender', 'value': s.gender.key},
        {'key': 'voice_announce_areas', 'value': s.areasValue},
        {'key': 'voice_announce_greeting', 'value': s.greeting ? 'true' : 'false'},
      ],
      onConflict: 'key',
    );
    _cache = s;
    _fetchedAt = DateTime.now();
  }
}
