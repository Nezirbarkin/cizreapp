import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/post_model.dart';
import '../models/leaderboard_models.dart';

/// Liderler Tablosu'nun sunucu erişimi.
///
/// ## Bu sınıf bir güvenlik sınırı DEĞİL
///
/// Anahtarlar ve gizleme sunucuda da uygulanır: ana anahtar ya da kartın
/// anahtarı kapalıyken `get_leaderboards` o kartı hiç döndürmez; gizli bir
/// kullanıcı sunucuda listeden çıkarılır. Buradaki denetimler yalnızca gereksiz
/// çağrıyı ve boş kartı önler.
class LeaderboardService {
  LeaderboardService._();

  static SupabaseClient get _client => Supabase.instance.client;

  /// Admin ekranı için anahtarlar; okunamazsa hata fırlatır — "okunamadı" ile
  /// "kapalı" birbirine karışmamalı.
  static Future<LeaderboardSettings> loadSettings() async {
    final raw = await _client.rpc('leaderboard_settings');
    if (raw is! Map) {
      throw StateError('leaderboard_settings beklenmeyen yanıt döndürdü');
    }
    return LeaderboardSettings.fromJson(Map<String, dynamic>.from(raw));
  }

  /// Anlık görüntünün önbellekte kalma süresi. Ana sayfaya her dönüşte sunucuyu
  /// (~70 ms) yormamak için; liderlik sıraları dakikalar içinde anlamlı değişmez.
  static const Duration cacheTtl = Duration(minutes: 2);

  static LeaderboardSnapshot? _cached;
  static DateTime? _cachedAt;

  /// Önbellek KULLANICIYA özeldir: "Senin sıran", engeller ve gizleme kullanıcıya
  /// göre değişir. Hesap değişirse başkasının görüntüsü asla gösterilmez.
  static String? _cachedFor;

  static String? get _currentUserId => _client.auth.currentUser?.id;

  /// Önbelleği atar (ayar/gizleme değiştiğinde ve test için).
  static void invalidateCache() {
    _cached = null;
    _cachedAt = null;
    _cachedFor = null;
  }

  /// Ana sayfa: anahtarlar + tüm kartların verisi TEK çağrıda. Kartlar yandan
  /// kaydırıldığı için komşu kartın verisi önceden hazır olmalı.
  ///
  /// [cacheTtl] süresince aynı kullanıcı için önbellekten döner;
  /// [forceRefresh] önbelleği atlar. Hata fırlatır; ana sayfa "Yenile" gösterir.
  static Future<LeaderboardSnapshot> fetchSnapshot({
    bool forceRefresh = false,
  }) async {
    final userId = _currentUserId;
    final cached = _cached;
    final at = _cachedAt;
    if (!forceRefresh &&
        cached != null &&
        at != null &&
        _cachedFor == userId &&
        DateTime.now().difference(at) < cacheTtl) {
      return cached;
    }

    final raw = await _client.rpc('get_leaderboards');
    if (raw is! Map) {
      throw StateError('get_leaderboards beklenmeyen yanıt döndürdü');
    }
    final snapshot = LeaderboardSnapshot.fromJson(
      Map<String, dynamic>.from(raw),
    );
    _cached = snapshot;
    _cachedAt = DateTime.now();
    _cachedFor = userId;
    return snapshot;
  }

  /// Yayındaki bir hikayeyi (yazar bilgisiyle) getirir; süresi dolduysa ya da
  /// artık görünmüyorsa null.
  static Future<Story?> fetchLiveStory(String storyId) async {
    try {
      final row = await _client
          .from('stories')
          .select(
            '*, profiles!stories_user_id_fkey(username, full_name, avatar_url)',
          )
          .eq('id', storyId)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .maybeSingle();
      if (row == null) return null;
      final json = Map<String, dynamic>.from(row);
      final profile = json['profiles'];
      if (profile is Map) {
        json['username'] = profile['username'];
        json['full_name'] = profile['full_name'];
        json['avatar_url'] = profile['avatar_url'];
      }
      return Story.fromJson(json);
    } catch (e) {
      debugPrint('⚠️ Hikaye açılamadı: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Kullanıcının kendi gizliliği
  // ---------------------------------------------------------------------------

  static Future<LeaderboardVisibility> fetchMyVisibility() async {
    final raw = await _client.rpc('leaderboard_my_visibility');
    return LeaderboardVisibility.fromJson(
      raw is Map ? Map<String, dynamic>.from(raw) : const {},
    );
  }

  /// Kullanıcı kendini listelerden gizler/gösterir. Admin'in gizlemesine
  /// dokunmaz.
  static Future<LeaderboardVisibility> setSelfHidden(bool hidden) async {
    final raw = await _client.rpc(
      'leaderboard_set_self_hidden',
      params: {'p_hidden': hidden},
    );
    invalidateCache();
    return LeaderboardVisibility.fromJson(
      raw is Map ? Map<String, dynamic>.from(raw) : const {},
    );
  }

  // ---------------------------------------------------------------------------
  // Admin: gizleme
  // ---------------------------------------------------------------------------

  static Future<void> adminSetHidden(String userId, bool hidden) async {
    await _client.rpc(
      'admin_leaderboard_set_hidden',
      params: {'p_user': userId, 'p_hidden': hidden},
    );
    invalidateCache();
  }

  /// Gizli olan herkes (kendi isteğiyle ya da admin tarafından).
  static Future<Map<String, LeaderboardVisibility>> adminHiddenUsers() async {
    final raw = await _client.rpc('admin_leaderboard_hidden_users');
    final result = <String, LeaderboardVisibility>{};
    if (raw is List) {
      for (final row in raw) {
        if (row is! Map) continue;
        final id = row['h_user_id']?.toString();
        if (id == null) continue;
        result[id] = LeaderboardVisibility(
          selfHidden: row['h_self'] == true,
          adminHidden: row['h_admin'] == true,
        );
      }
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Admin: anahtarlar — `app_settings` INSERT/UPDATE politikaları
  // `auth_is_admin()` istiyor, yani admin olmayan çağrı veritabanı tarafında
  // reddedilir.
  // ---------------------------------------------------------------------------

  static Future<void> setEnabled(bool value) =>
      _write('leaderboard_enabled', value ? 'true' : 'false');

  static Future<void> setBoardEnabled(LeaderboardBoard board, bool value) =>
      _write(board.settingKey, value ? 'true' : 'false');

  static Future<void> setStatEnabled(LeaderboardStat stat, bool value) =>
      _write(stat.settingKey, value ? 'true' : 'false');

  static Future<void> setPeriod(LeaderboardPeriod period) =>
      _write('leaderboard_period', period.key);

  static Future<void> setLimit(int limit) =>
      _write('leaderboard_limit', '${limit.clamp(3, 10)}');

  /// Kart sırasını kaydeder (virgülle ayrılmış anahtarlar).
  static Future<void> setOrder(List<LeaderboardBoard> order) =>
      _write('leaderboard_order', order.map((b) => b.key).join(','));

  static Future<void> _write(String key, String value) async {
    await _client.from('app_settings').upsert({
      'key': key,
      // jsonb kolonuna JSON string yazılır. DÜZ metin gönderilir: PostgREST onu
      // zaten JSON string olarak kodlar. `'"true"'` göndermek jsonb'de
      // TIRNAKLI metin bırakır ve `::boolean` çevrimleri hata verir
      // (SocialAccessService de aynı biçimi kullanıyor).
      'value': value,
    }, onConflict: 'key');
    invalidateCache();
  }
}
