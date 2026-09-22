import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_presence.dart';

/// Başkalarının çevrimiçi / son görülme durumunu SUNUCUNUN KURALLARIYLA okur.
///
/// Ham `profiles.is_online` / `last_seen` sütunlarını burada OKUMAYIN: gizlilik
/// (hayalet modu, "son görülmeyi gizle", arkadaşlara özel, engel, gizli hesap) ve
/// admin'in ayarları (özellik anahtarları, 7 günlük sınır) yalnız
/// `presence_resolve` üzerinden uygulanır. Bu sınıf onun RPC yüzüdür.
///
/// Hata durumunda güvenli taraf: kimse için bir şey gösterilmez.
class UserPresenceService {
  UserPresenceService._();

  static final UserPresenceService instance = UserPresenceService._();

  /// Yönetici ayarlarının bellekte tutulma süresi. Admin bir anahtarı çevirince
  /// istemciler en geç bu kadar sonra (ya da uygulama öne gelince) fark eder;
  /// gizli bilgi zaten sunucudan gelmediği için gecikme bir sızıntı değildir.
  static const Duration settingsTtl = Duration(minutes: 5);

  /// Tek çağrıda sorgulanabilecek en çok kimlik (sunucu da 500'de keser).
  static const int maxBatch = 500;

  SupabaseClient get _client => Supabase.instance.client;

  ChatPresenceSettings _settings = const ChatPresenceSettings();
  DateTime? _settingsAt;
  Future<ChatPresenceSettings>? _settingsInFlight;

  /// Bellekteki son bilinen ayarlar; ekranlar ilk karede senkron karar verebilsin
  /// diye vardır. Henüz okunmadıysa varsayılanlar (özellikler açık, 7 gün).
  ChatPresenceSettings get cachedSettings => _settings;

  bool get hasLoadedSettings => _settingsAt != null;

  /// Yönetici ayarlarını okur ve önbelleğe alır. Eşzamanlı çağrılar TEK isteği
  /// paylaşır. Okunamazsa önceki (ya da varsayılan) ayarlar döner.
  Future<ChatPresenceSettings> loadSettings({bool force = false}) {
    final at = _settingsAt;
    if (!force && at != null && DateTime.now().difference(at) < settingsTtl) {
      return Future.value(_settings);
    }
    return _settingsInFlight ??= _fetchSettings().whenComplete(
      () => _settingsInFlight = null,
    );
  }

  Future<ChatPresenceSettings> _fetchSettings() async {
    try {
      final raw = await _client.rpc('get_chat_presence_settings');
      if (raw is Map) {
        _settings = ChatPresenceSettings.fromJson(
          Map<String, dynamic>.from(raw),
        );
        _settingsAt = DateTime.now();
      }
    } catch (e) {
      debugPrint('⚠️ Sohbet durumu ayarları okunamadı: $e');
    }
    return _settings;
  }

  /// Önbelleği atar (admin ayarı değiştirince ve çıkışta).
  void invalidate() {
    _settingsAt = null;
    _settingsInFlight = null;
  }

  /// Hesap değişince önceki hesabın önbelleği kalmasın.
  void reset() {
    invalidate();
    _settings = const ChatPresenceSettings();
  }

  /// Birden çok kullanıcının durumunu TEK çağrıyla çözer. Görüntüleyiciye göre
  /// gizli olanlar [UserPresence.canSeeOnline] = false ile döner; sunucunun
  /// döndürmediği (bilinmeyen) kimlikler haritada yoktur.
  Future<Map<String, UserPresence>> fetch(
    Iterable<String> userIds, {
    PresenceContext context = PresenceContext.chat,
  }) async {
    final ids = userIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const {};

    final result = <String, UserPresence>{};
    try {
      for (var start = 0; start < ids.length; start += maxBatch) {
        final chunk = ids.sublist(
          start,
          start + maxBatch > ids.length ? ids.length : start + maxBatch,
        );
        final raw = await _client.rpc(
          'get_user_presence',
          params: {'p_user_ids': chunk, 'p_context': context.name},
        );
        if (raw is! List) continue;
        for (final row in raw) {
          if (row is! Map) continue;
          final presence = UserPresence.fromJson(
            Map<String, dynamic>.from(row),
          );
          if (presence.userId.isNotEmpty) result[presence.userId] = presence;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Kullanıcı durumu okunamadı: $e');
    }
    return result;
  }

  Future<UserPresence?> fetchOne(
    String userId, {
    PresenceContext context = PresenceContext.chat,
  }) async {
    final map = await fetch([userId], context: context);
    return map[userId];
  }

  // ---------------------------------------------------------------------------
  // Kullanıcının kendi tercihleri
  // ---------------------------------------------------------------------------

  /// Kendi "son görülme" ve "yazıyor" tercihlerim. Okunamazsa varsayılanlar
  /// (herkese açık, yazıyor bilgisi gönderilir) döner ve hata yutulur.
  Future<ChatPrivacyPrefs> loadMyPrivacy() async {
    try {
      final raw = await _client.rpc<dynamic>('get_my_profile');
      if (raw is Map) {
        return ChatPrivacyPrefs.fromProfile(Map<String, dynamic>.from(raw));
      }
    } catch (e) {
      debugPrint('⚠️ Sohbet gizlilik tercihleri okunamadı: $e');
    }
    return const ChatPrivacyPrefs();
  }

  /// Tercihleri kaydeder. Yalnız verilen alanlar değişir. Başarısızlıkta
  /// istisna fırlatır: çağıran anahtarı eski konumuna döndürebilsin.
  Future<void> saveMyPrivacy({
    LastSeenAudience? lastSeenAudience,
    bool? showTypingIndicator,
  }) async {
    final friendsOnly = lastSeenAudience?.friendsOnly;
    await _client.rpc(
      'update_my_chat_privacy',
      params: {
        if (lastSeenAudience != null)
          'p_show_last_seen': lastSeenAudience.showLastSeen,
        if (friendsOnly != null) 'p_last_seen_friends_only': friendsOnly,
        if (showTypingIndicator != null)
          'p_show_typing_indicator': showTypingIndicator,
      },
    );
  }
}
