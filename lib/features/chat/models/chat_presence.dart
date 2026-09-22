import 'package:flutter/foundation.dart';

/// Bir durum sorgusunun hangi ekran için yapıldığı. Sunucu, admin'in "sohbette
/// göster" ve "profilde göster" anahtarlarını bu bağlama göre uygular; `list`
/// sunucuda `chat` gibi davranır.
enum PresenceContext { chat, profile, list }

/// Yönetici kuralları (`get_chat_presence_settings`).
///
/// Alanlar SUNUCUDAKİ ham anahtarlardır: ana anahtar kapalıyken alt anahtarın
/// değeri korunur. Etkin değeri [showsLastSeen] gibi getter'lar hesaplar.
///
/// Bu sınıf bir güvenlik sınırı DEĞİL: gizli bilgi sunucudan zaten gelmez
/// (`presence_resolve`). Buradaki kurallar yalnızca gereksiz çağrıyı ve boş
/// arayüzü önler.
@immutable
class ChatPresenceSettings {
  const ChatPresenceSettings({
    this.lastSeen = true,
    this.lastSeenInChat = true,
    this.lastSeenInProfile = true,
    this.lastSeenMaxDays = 7,
    this.online = true,
    this.typing = true,
    this.typingInGroups = true,
  });

  /// Son görülme — ana anahtar.
  final bool lastSeen;
  final bool lastSeenInChat;
  final bool lastSeenInProfile;

  /// Son görülme bu günden eskiyse hiç gösterilmez.
  final int lastSeenMaxDays;

  /// Çevrimiçi durumu (yeşil nokta, "çevrimiçi" yazısı, aktif kullanıcılar).
  final bool online;

  /// "Yazıyor…" — ana anahtar.
  final bool typing;
  final bool typingInGroups;

  /// Eksik/bozuk alan varsayılana (açık, 7 gün) düşer; sunucu da aynısını yapar.
  factory ChatPresenceSettings.fromJson(Map<String, dynamic> json) {
    bool flag(String key) => json[key] is bool ? json[key] as bool : true;
    final days = json['last_seen_max_days'];
    return ChatPresenceSettings(
      lastSeen: flag('last_seen'),
      lastSeenInChat: flag('last_seen_in_chat'),
      lastSeenInProfile: flag('last_seen_in_profile'),
      lastSeenMaxDays: days is num && days >= 1 && days <= 365
          ? days.toInt()
          : 7,
      online: flag('online'),
      typing: flag('typing'),
      typingInGroups: flag('typing_in_groups'),
    );
  }

  /// Bu bağlamda son görülme gösterilebilir mi?
  bool showsLastSeen(PresenceContext context) =>
      lastSeen &&
      (context == PresenceContext.profile ? lastSeenInProfile : lastSeenInChat);

  /// Bu bağlamda çevrimiçi ya da son görülmeden en az biri gösterilebilir mi?
  bool showsAnyPresence(PresenceContext context) =>
      online || showsLastSeen(context);

  /// Birebir sohbette "yazıyor…" açık mı?
  bool get typingEnabled => typing;

  /// Grup sohbetinde "yazıyor…" açık mı?
  bool get groupTypingEnabled => typing && typingInGroups;

  ChatPresenceSettings copyWith({
    bool? lastSeen,
    bool? lastSeenInChat,
    bool? lastSeenInProfile,
    int? lastSeenMaxDays,
    bool? online,
    bool? typing,
    bool? typingInGroups,
  }) {
    return ChatPresenceSettings(
      lastSeen: lastSeen ?? this.lastSeen,
      lastSeenInChat: lastSeenInChat ?? this.lastSeenInChat,
      lastSeenInProfile: lastSeenInProfile ?? this.lastSeenInProfile,
      lastSeenMaxDays: lastSeenMaxDays ?? this.lastSeenMaxDays,
      online: online ?? this.online,
      typing: typing ?? this.typing,
      typingInGroups: typingInGroups ?? this.typingInGroups,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChatPresenceSettings &&
      other.lastSeen == lastSeen &&
      other.lastSeenInChat == lastSeenInChat &&
      other.lastSeenInProfile == lastSeenInProfile &&
      other.lastSeenMaxDays == lastSeenMaxDays &&
      other.online == online &&
      other.typing == typing &&
      other.typingInGroups == typingInGroups;

  @override
  int get hashCode => Object.hash(
    lastSeen,
    lastSeenInChat,
    lastSeenInProfile,
    lastSeenMaxDays,
    online,
    typing,
    typingInGroups,
  );
}

/// Bir kullanıcının, görüntüleyene göre ÇÖZÜMLENMİŞ durumu
/// (`get_user_presence` satırı).
@immutable
class UserPresence {
  const UserPresence({
    required this.userId,
    this.canSeeOnline = false,
    this.online = false,
    this.lastSeen,
  });

  /// Görüntüleyicinin göremediği kişi: hiçbir şey gösterilmez.
  const UserPresence.hidden(this.userId)
    : canSeeOnline = false,
      online = false,
      lastSeen = null;

  final String userId;

  /// Görüntüleyici bu kişinin "çevrimiçi" durumunu görebilir mi? Canlı presence
  /// akışıyla birleştirilirken bu bayrağa bakılır; yoksa engelli/hayalet biri
  /// akıştan "çevrimiçi" görünürdü.
  final bool canSeeOnline;

  /// Görebiliyorsa ve şu an gerçekten aktifse true.
  final bool online;

  /// İzin verilen ve süre sınırından yeni son görülme; yoksa null.
  final DateTime? lastSeen;

  factory UserPresence.fromJson(Map<String, dynamic> json) {
    final seen = json['last_seen'];
    return UserPresence(
      userId: (json['user_id'] ?? '').toString(),
      canSeeOnline: json['can_see_online'] == true,
      online: json['online'] == true,
      lastSeen: seen is String ? DateTime.tryParse(seen) : null,
    );
  }
}

/// Kullanıcının kendi "son görülme" tercihi. Sunucuda iki sütun
/// (`show_last_seen`, `last_seen_friends_only`) olarak tutulur; üçlü seçimin
/// iki sütuna eşlemesi burada tek yerde durur.
enum LastSeenAudience {
  /// Herkes görebilir.
  everyone,

  /// Yalnız karşılıklı takipleşilen arkadaşlar.
  friends,

  /// Hiç kimse.
  nobody;

  /// `show_last_seen` sütunu.
  bool get showLastSeen => this != LastSeenAudience.nobody;

  /// `last_seen_friends_only` sütunu. "Hiç kimse"de anlamsızdır; önceki seçim
  /// korunsun diye null döner (RPC null parametreyi değiştirmez).
  bool? get friendsOnly => switch (this) {
    LastSeenAudience.everyone => false,
    LastSeenAudience.friends => true,
    LastSeenAudience.nobody => null,
  };

  static LastSeenAudience fromColumns({
    required bool showLastSeen,
    required bool friendsOnly,
  }) {
    if (!showLastSeen) return LastSeenAudience.nobody;
    return friendsOnly ? LastSeenAudience.friends : LastSeenAudience.everyone;
  }
}

/// Kullanıcının kendi sohbet gizlilik tercihleri (`get_my_profile` alanları).
@immutable
class ChatPrivacyPrefs {
  const ChatPrivacyPrefs({
    this.lastSeenAudience = LastSeenAudience.everyone,
    this.showTypingIndicator = true,
  });

  final LastSeenAudience lastSeenAudience;

  /// Karşı tarafa "yazıyor…" bilgisini gönder.
  final bool showTypingIndicator;

  factory ChatPrivacyPrefs.fromProfile(Map<String, dynamic> profile) {
    return ChatPrivacyPrefs(
      lastSeenAudience: LastSeenAudience.fromColumns(
        showLastSeen: profile['show_last_seen'] as bool? ?? true,
        friendsOnly: profile['last_seen_friends_only'] as bool? ?? false,
      ),
      showTypingIndicator: profile['show_typing_indicator'] as bool? ?? true,
    );
  }

  ChatPrivacyPrefs copyWith({
    LastSeenAudience? lastSeenAudience,
    bool? showTypingIndicator,
  }) {
    return ChatPrivacyPrefs(
      lastSeenAudience: lastSeenAudience ?? this.lastSeenAudience,
      showTypingIndicator: showTypingIndicator ?? this.showTypingIndicator,
    );
  }
}

/// Durum metinleri. Saat dilimi sohbet ekranlarının geri kalanıyla aynı:
/// Türkiye sabit UTC+3 (yaz saati uygulaması yok).
class PresenceLabels {
  PresenceLabels._();

  static const String online = 'çevrimiçi';
  static const String typing = 'yazıyor';

  static const Duration turkeyOffset = Duration(hours: 3);

  static const List<String> _weekdays = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];

  /// "az önce", "12 dk önce", "bugün 14:32", "dün 21:10", "Salı 21:10",
  /// "12.09.2026". Öneksiz; başına "son görülme" [lastSeen] ekler.
  static String lastSeenAgo(DateTime lastSeen, {DateTime? now}) {
    final seen = lastSeen.toUtc().add(turkeyOffset);
    final current = (now ?? DateTime.now()).toUtc().add(turkeyOffset);

    var diff = current.difference(seen);
    // Saat farkı yüzünden geleceği gösteren zaman "az önce" sayılır.
    if (diff.isNegative) diff = Duration.zero;

    if (diff.inMinutes < 1) return 'az önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';

    final hm = '${_two(seen.hour)}:${_two(seen.minute)}';
    final dayGap = DateTime.utc(current.year, current.month, current.day)
        .difference(DateTime.utc(seen.year, seen.month, seen.day))
        .inDays;

    if (dayGap <= 0) return 'bugün $hm';
    if (dayGap == 1) return 'dün $hm';
    if (dayGap < 7) return '${_weekdays[seen.weekday - 1]} $hm';
    return '${_two(seen.day)}.${_two(seen.month)}.${seen.year}';
  }

  /// "son görülme bugün 14:32".
  static String lastSeen(DateTime lastSeen, {DateTime? now}) =>
      'son görülme ${lastSeenAgo(lastSeen, now: now)}';

  /// "Ali yazıyor", "Ali ve Ayşe yazıyor", "3 kişi yazıyor".
  static String typingNames(List<String> names) {
    final clean = names.where((n) => n.trim().isNotEmpty).toList();
    if (clean.isEmpty) return typing;
    if (clean.length == 1) return '${clean[0]} $typing';
    if (clean.length == 2) return '${clean[0]} ve ${clean[1]} $typing';
    return '${clean.length} kişi $typing';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
