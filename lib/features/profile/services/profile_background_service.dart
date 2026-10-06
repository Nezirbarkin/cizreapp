import 'package:supabase_flutter/supabase_flutter.dart';

/// Hazır profil arka planı (kapak) — Görev 2.7.
///
/// Görseller herkese açık `profile-backgrounds` kovasında; liste
/// `profile_background_presets` tablosundan gelir (göç 20260928000001).
class ProfileBackgroundPreset {
  const ProfileBackgroundPreset({
    required this.code,
    required this.name,
    required this.category,
    required this.imageUrl,
    required this.thumbUrl,
  });

  /// `bg_NN` — sıra = dosya adı (append-only).
  final String code;
  final String name;
  final String category;

  /// 1600×900 kapak görseli (kapak URL'si olarak saklanan adres).
  final String imageUrl;

  /// 480×270 küçük resim (seçici ızgarası için).
  final String thumbUrl;
}

/// Hazır arka planları listeler ve kapağı onlardan birine ayarlar.
///
/// Seçimde dosya KOPYALANMAZ: kapak doğrudan paylaşılan dosyanın herkese açık
/// URL'si olur. Liste oturum boyunca bellekte tutulur (nadiren değişir).
class ProfileBackgroundService {
  ProfileBackgroundService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _db => _client ?? Supabase.instance.client;

  static const String bucket = 'profile-backgrounds';

  static List<ProfileBackgroundPreset>? _cache;

  /// Testler için bellek önbelleğini boşaltır.
  static void clearCache() => _cache = null;

  Future<List<ProfileBackgroundPreset>> fetchPresets({bool forceRefresh = false}) async {
    final cached = _cache;
    if (!forceRefresh && cached != null) return cached;
    final rows = await _db
        .from('profile_background_presets')
        .select('code, name, category, image_path, thumb_path')
        // DİKKAT: postgrest-dart'ta order() varsayılanı AZALAN sıradır.
        .order('sort_order', ascending: true);
    final storage = _db.storage.from(bucket);
    final presets = <ProfileBackgroundPreset>[
      for (final row in rows as List)
        ProfileBackgroundPreset(
          code: row['code'] as String,
          name: row['name'] as String,
          category: row['category'] as String,
          imageUrl: storage.getPublicUrl(row['image_path'] as String),
          thumbUrl: storage.getPublicUrl(row['thumb_path'] as String),
        ),
    ];
    _cache = presets;
    return presets;
  }

  /// Kapağı [preset]'e ayarlar (profil RPC'si; RLS'li doğrudan UPDATE değil).
  Future<void> applyAsCover(ProfileBackgroundPreset preset) async {
    await _db.rpc(
      'update_my_public_profile',
      params: {'p_cover_url': preset.imageUrl},
    );
  }
}
