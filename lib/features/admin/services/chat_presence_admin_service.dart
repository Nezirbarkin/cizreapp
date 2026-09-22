import 'package:supabase_flutter/supabase_flutter.dart';

import '../../chat/models/chat_presence.dart';
import '../../chat/services/user_presence_service.dart';

/// Admin > Sohbet Durumu: kullanıcıların bu özellikleri nasıl kullandığının özeti
/// (`admin_chat_presence_stats`). Bot vitrin hesapları sayılmaz.
class ChatPresenceStats {
  const ChatPresenceStats({
    this.total = 0,
    this.onlineNow = 0,
    this.lastSeenHidden = 0,
    this.lastSeenFriends = 0,
    this.typingOff = 0,
    this.ghost = 0,
    this.onlineOff = 0,
  });

  final int total;
  final int onlineNow;

  /// "Son görülmemi hiç kimse görmesin" diyenler.
  final int lastSeenHidden;

  /// Son görülmeyi yalnız arkadaşlarına açanlar.
  final int lastSeenFriends;

  /// "Yazıyor…" bilgisini paylaşmayanlar.
  final int typingOff;

  /// Hayalet modundakiler.
  final int ghost;

  /// "Çevrimiçi görünme"yi kapatanlar.
  final int onlineOff;

  factory ChatPresenceStats.fromJson(Map<String, dynamic> json) {
    int n(String key) => (json[key] as num?)?.toInt() ?? 0;
    return ChatPresenceStats(
      total: n('total'),
      onlineNow: n('online_now'),
      lastSeenHidden: n('last_seen_hidden'),
      lastSeenFriends: n('last_seen_friends'),
      typingOff: n('typing_off'),
      ghost: n('ghost'),
      onlineOff: n('online_off'),
    );
  }
}

/// Sohbet durumu (son görülme / çevrimiçi / yazıyor) için yönetici ayarları.
///
/// Anahtarlar sunucuda da uygulanır: kapalı bir özelliğin bilgisi sunucudan hiç
/// dönmez. Yazımlar `admin_set_chat_presence_setting` RPC'sinden geçer; o anahtar
/// beyaz listesini ve değer aralığını doğrular, admin olmayanı reddeder.
class ChatPresenceAdminService {
  ChatPresenceAdminService._();

  static const String keyLastSeen = 'chat_presence_last_seen_enabled';
  static const String keyLastSeenInChat = 'chat_presence_last_seen_in_chat';
  static const String keyLastSeenInProfile =
      'chat_presence_last_seen_in_profile';
  static const String keyLastSeenMaxDays = 'chat_presence_last_seen_max_days';
  static const String keyOnline = 'chat_presence_online_enabled';
  static const String keyTyping = 'chat_presence_typing_enabled';
  static const String keyTypingInGroups = 'chat_presence_typing_in_groups';

  /// Son görülme süre sınırı için sunucunun kabul ettiği aralık.
  static const int minDays = 1;
  static const int maxDays = 365;

  static SupabaseClient get _client => Supabase.instance.client;

  /// Okunamazsa hata fırlatır: "okunamadı" ile "kapalı" birbirine karışmasın.
  static Future<ChatPresenceSettings> loadSettings() async {
    final raw = await _client.rpc('get_chat_presence_settings');
    if (raw is! Map) {
      throw StateError('get_chat_presence_settings beklenmeyen yanıt döndürdü');
    }
    return ChatPresenceSettings.fromJson(Map<String, dynamic>.from(raw));
  }

  static Future<ChatPresenceStats> loadStats() async {
    final raw = await _client.rpc('admin_chat_presence_stats');
    if (raw is! Map) return const ChatPresenceStats();
    return ChatPresenceStats.fromJson(Map<String, dynamic>.from(raw));
  }

  /// Bir açma/kapama anahtarını yazar; güncel ayarları döner.
  static Future<ChatPresenceSettings> setFlag(String key, bool value) =>
      _write(key, value ? 'true' : 'false');

  /// Son görülme süre sınırını (gün) yazar.
  static Future<ChatPresenceSettings> setMaxDays(int days) =>
      _write(keyLastSeenMaxDays, days.clamp(minDays, maxDays).toString());

  static Future<ChatPresenceSettings> _write(String key, String value) async {
    final raw = await _client.rpc(
      'admin_set_chat_presence_setting',
      params: {'p_key': key, 'p_value': value},
    );
    // Bu cihazın önbelleği hemen tazelensin (diğer cihazlar en geç birkaç dk sonra).
    UserPresenceService.instance.invalidate();
    if (raw is! Map) return loadSettings();
    return ChatPresenceSettings.fromJson(Map<String, dynamic>.from(raw));
  }
}
