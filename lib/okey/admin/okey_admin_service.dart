import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/okey_room_backdrop.dart' show OkeyRoomBackdrop;
import 'okey_admin_bots_tab.dart' show OkeyBotProfile;

/// Admin panelindeki bir Okey masasının özeti (TAŞLAR ASLA DÖNMEZ).
class OkeyAdminRoom {
  final String roomId;
  final String status;
  final String gameMode;
  final String teamMode;
  final String assistMode;
  final bool isPrivate;
  final int handNo;
  final int turnSeat;
  final int seatedCount;
  final int botCount;

  /// Masayı ŞU AN izleyen kişi sayısı.
  final int spectatorCount;

  /// Masadaki SON ETKİNLİK: kurulma / "buradayım" damgası / son hamle
  /// içinde en yenisi (bkz. okey_room_last_activity).
  final DateTime lastActivity;

  final DateTime createdAt;

  const OkeyAdminRoom({
    required this.roomId,
    required this.status,
    required this.gameMode,
    required this.teamMode,
    required this.assistMode,
    required this.isPrivate,
    required this.handNo,
    required this.turnSeat,
    required this.seatedCount,
    required this.botCount,
    required this.createdAt,
    required this.lastActivity,
    this.spectatorCount = 0,
  });

  /// Masa TERK EDİLMİŞ mi? (sunucudaki eşikle aynı: 30 dakika)
  ///
  /// Sunucu bu masaları zaten listelemez; alan, adminin "ölü masaları da
  /// göster" anahtarını açtığında hangilerinin ölü olduğunu görebilmesi için
  /// var.
  bool get isIdle =>
      DateTime.now().difference(lastActivity) > const Duration(minutes: 30);

  factory OkeyAdminRoom.fromMap(Map<String, dynamic> m) => OkeyAdminRoom(
    roomId: m['room_id'] as String,
    status: m['status'] as String,
    gameMode: m['game_mode'] as String? ?? 'katlamasiz',
    teamMode: m['team_mode'] as String? ?? 'essiz',
    assistMode: m['assist_mode'] as String? ?? 'yardimli',
    isPrivate: m['is_private'] as bool? ?? false,
    handNo: m['hand_no'] as int? ?? 0,
    turnSeat: m['turn_seat'] as int? ?? 0,
    seatedCount: m['seated_count'] as int? ?? 0,
    botCount: m['bot_count'] as int? ?? 0,
    spectatorCount: (m['spectator_count'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.parse(m['created_at'] as String),
    lastActivity: m['last_activity'] == null
        ? DateTime.parse(m['created_at'] as String)
        : DateTime.parse(m['last_activity'] as String),
  );
}

/// Bir masadaki oyuncu satırı (yalnız sayaç; taşlar dönmez).
class OkeyAdminSeat {
  final int seatNo;
  final String? userId;
  final String displayName;
  final bool isBot;
  final bool isReady;
  final DateTime? lastSeenAt;
  final int tileCount;

  const OkeyAdminSeat({
    required this.seatNo,
    required this.displayName,
    required this.isBot,
    required this.isReady,
    required this.tileCount,
    this.userId,
    this.lastSeenAt,
  });

  factory OkeyAdminSeat.fromMap(Map<String, dynamic> m) => OkeyAdminSeat(
    seatNo: m['seat_no'] as int,
    userId: m['user_id'] as String?,
    displayName: m['display_name'] as String? ?? '—',
    isBot: m['is_bot'] as bool? ?? false,
    isReady: m['is_ready'] as bool? ?? false,
    lastSeenAt: m['last_seen_at'] == null
        ? null
        : DateTime.parse(m['last_seen_at'] as String),
    tileCount: m['tile_count'] as int? ?? 0,
  );

  /// 30 saniyeden uzun süredir görünmüyorsa bağlantısı kopmuş sayılır.
  bool get isDisconnected {
    if (isBot || userId == null) return false;
    final t = lastSeenAt;
    if (t == null) return true;
    return DateTime.now().difference(t).inSeconds > 30;
  }
}

/// Okey genel ayarları (admin panelinden düzenlenir).
class OkeySettingsData {
  final int maxScore;
  final int turnSeconds;
  final int roomCreationFee;
  final int commissionPercent;
  final int hourlyGiftPoints;
  final int adRewardPoints;
  final int startingPoints;

  /// RULES.md §7/§8 ceza ayarları. 0 verilirse o ceza kapanır.
  final int okeyDiscardPenalty;
  final int okeyInHandPenalty;
  final int mistakeDiscardPenalty;
  final int sideDrawPenalty;

  const OkeySettingsData({
    required this.maxScore,
    required this.turnSeconds,
    required this.roomCreationFee,
    required this.commissionPercent,
    required this.hourlyGiftPoints,
    required this.adRewardPoints,
    required this.startingPoints,
    required this.okeyDiscardPenalty,
    required this.okeyInHandPenalty,
    required this.mistakeDiscardPenalty,
    required this.sideDrawPenalty,
  });

  factory OkeySettingsData.fromMap(Map<String, dynamic> m) => OkeySettingsData(
    maxScore: (m['default_max_score'] as num?)?.toInt() ?? 101,
    turnSeconds: (m['default_turn_seconds'] as num?)?.toInt() ?? 20,
    roomCreationFee: (m['room_creation_fee'] as num?)?.toInt() ?? 0,
    commissionPercent: (m['commission_percent'] as num?)?.toInt() ?? 0,
    hourlyGiftPoints: (m['hourly_gift_points'] as num?)?.toInt() ?? 100,
    adRewardPoints: (m['ad_reward_points'] as num?)?.toInt() ?? 250,
    startingPoints: (m['starting_points'] as num?)?.toInt() ?? 1000,
    okeyDiscardPenalty: (m['okey_discard_penalty'] as num?)?.toInt() ?? 101,
    okeyInHandPenalty: (m['okey_in_hand_penalty'] as num?)?.toInt() ?? 101,
    mistakeDiscardPenalty:
        (m['mistake_discard_penalty'] as num?)?.toInt() ?? 101,
    sideDrawPenalty: (m['side_draw_penalty'] as num?)?.toInt() ?? 101,
  );
}

/// Sistem kazancı özeti.
class OkeyRevenueSummary {
  final int total;
  final int roomFees;
  final int commissions;
  final int today;
  final int pointsInCirculation;

  const OkeyRevenueSummary({
    required this.total,
    required this.roomFees,
    required this.commissions,
    required this.today,
    required this.pointsInCirculation,
  });

  static const empty = OkeyRevenueSummary(
    total: 0,
    roomFees: 0,
    commissions: 0,
    today: 0,
    pointsInCirculation: 0,
  );

  factory OkeyRevenueSummary.fromMap(Map<String, dynamic> m) =>
      OkeyRevenueSummary(
        total: (m['total_revenue'] as num?)?.toInt() ?? 0,
        roomFees: (m['room_fee_total'] as num?)?.toInt() ?? 0,
        commissions: (m['commission_total'] as num?)?.toInt() ?? 0,
        today: (m['today_revenue'] as num?)?.toInt() ?? 0,
        pointsInCirculation:
            (m['total_points_in_circulation'] as num?)?.toInt() ?? 0,
      );
}

/// Admin panelindeki hediye satırı — masadaki menünün kaynağı.
///
/// Oyuncunun gördüğü [OkeyGift]'ten farkı: PASİF hediyeler ve sıralama
/// alanı da gelir. Panelden kapatılan bir hediye listeden kaybolsaydı geri
/// açılamazdı.
class OkeyAdminGift {
  final String id;
  final String code;
  final String name;
  final String icon;
  final int price;
  final int sortOrder;
  final bool isActive;

  /// İkonun masada nasıl oynayacağı (bkz. OkeyGiftAnim).
  final String anim;

  const OkeyAdminGift({
    required this.id,
    required this.code,
    required this.name,
    required this.icon,
    required this.price,
    required this.sortOrder,
    required this.isActive,
    this.anim = 'bounce',
  });

  factory OkeyAdminGift.fromMap(Map<String, dynamic> m) => OkeyAdminGift(
    id: (m['id'] ?? '').toString(),
    code: m['code'] as String? ?? '',
    name: m['name'] as String? ?? '',
    icon: m['icon'] as String? ?? '🎁',
    price: (m['price'] as num?)?.toInt() ?? 0,
    sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
    isActive: m['is_active'] as bool? ?? true,
    anim: m['anim'] as String? ?? 'bounce',
  );
}

/// Admin panelindeki Okey yönetimi için veri katmanı.
///
/// GİZLİLİK: Buradaki hiçbir çağrı oyuncuların ELİNDEKİ TAŞLARI getirmez —
/// yalnızca taş SAYISI döner. Moderasyon için bile olsa hile-önleme sınırı
/// admin için de geçerlidir.
class OkeyAdminService {
  static const String soundsBucket = 'okey-sounds';

  SupabaseClient get _client => Supabase.instance.client;

  /// Masa listesi — VARSAYILAN OLARAK yalnızca aktif masalar.
  ///
  /// [includeIdle] true ise terk edilmiş masalar da gelir; admin onları
  /// görüp temizleyebilsin diye. Filtre sunucudadır: "aktif"in tanımı
  /// temizlik ve izleme listesiyle aynı yerden gelir
  /// (bkz. okey_room_last_activity).
  Future<List<OkeyAdminRoom>> listActiveRooms({
    bool includeIdle = false,
  }) async {
    final rows = await _client.rpc(
      'admin_okey_overview',
      params: {'p_include_idle': includeIdle},
    );
    return (rows as List)
        .map((r) => OkeyAdminRoom.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Terk edilmiş / bitmiş masaları kapatır; kapatılan masa sayısını döner.
  Future<int> cleanupStaleRooms() async {
    final r = await _client.rpc('okey_cleanup_stale_rooms');
    return (r as num?)?.toInt() ?? 0;
  }

  Future<List<OkeyAdminSeat>> listRoomPlayers(String roomId) async {
    final rows = await _client.rpc(
      'admin_okey_room_players',
      params: {'p_room_id': roomId},
    );
    return (rows as List)
        .map((r) => OkeyAdminSeat.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Oyuncuyu masadan çıkarır; koltuk bota devredilir ki masa kilitlenmesin.
  Future<void> kickPlayer(String roomId, int seatNo) async {
    await _client.rpc(
      'admin_okey_kick_player',
      params: {'p_room_id': roomId, 'p_seat': seatNo},
    );
  }

  Future<void> banUser(String userId, {String? reason, DateTime? until}) async {
    await _client.rpc(
      'admin_okey_set_ban',
      params: {
        'p_user_id': userId,
        'p_reason': reason,
        'p_expires_at': until?.toIso8601String(),
      },
    );
  }

  Future<void> removeBan(String userId) async {
    await _client.rpc('admin_okey_remove_ban', params: {'p_user_id': userId});
  }

  Future<OkeySettingsData> getSettings() async {
    final row = await _client
        .from('okey_settings')
        .select(
          'default_max_score, default_turn_seconds, room_creation_fee, '
          'commission_percent, hourly_gift_points, ad_reward_points, '
          'starting_points, okey_discard_penalty, okey_in_hand_penalty, '
          'mistake_discard_penalty, side_draw_penalty',
        )
        .eq('id', true)
        .single();
    return OkeySettingsData.fromMap(row);
  }

  /// null geçilen alan DEĞİŞMEZ (sunucuda COALESCE ile mevcut değer korunur).
  /// Ceza alanlarına 0 verilirse o ceza kapanır.
  Future<void> updateSettings({
    required int maxScore,
    required int turnSeconds,
    int? roomCreationFee,
    int? commissionPercent,
    int? hourlyGiftPoints,
    int? adRewardPoints,
    int? startingPoints,
    int? okeyDiscardPenalty,
    int? okeyInHandPenalty,
    int? mistakeDiscardPenalty,
    int? sideDrawPenalty,
  }) async {
    await _client.rpc(
      'admin_okey_update_settings',
      params: {
        'p_max_score': maxScore,
        'p_turn_seconds': turnSeconds,
        'p_room_creation_fee': roomCreationFee,
        'p_commission_percent': commissionPercent,
        'p_hourly_gift_points': hourlyGiftPoints,
        'p_ad_reward_points': adRewardPoints,
        'p_starting_points': startingPoints,
        'p_okey_discard_penalty': okeyDiscardPenalty,
        'p_okey_in_hand_penalty': okeyInHandPenalty,
        'p_mistake_discard_penalty': mistakeDiscardPenalty,
        'p_side_draw_penalty': sideDrawPenalty,
      },
    );
  }

  /// Sistem kazancı özeti (oda ücretleri + komisyonlar).
  Future<OkeyRevenueSummary> revenueSummary() async {
    final rows = await _client.rpc('admin_okey_revenue_summary');
    final list = rows as List;
    if (list.isEmpty) return OkeyRevenueSummary.empty;
    return OkeyRevenueSummary.fromMap(list.first as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------------
  // SES DOSYALARI
  // ---------------------------------------------------------------------

  /// sound_key -> public_url
  Future<Map<String, String>> listSounds() async {
    final rows = await _client
        .from('okey_sound_assets')
        .select('sound_key, public_url');
    final map = <String, String>{};
    for (final r in (rows as List)) {
      final m = r as Map<String, dynamic>;
      map[m['sound_key'] as String] = m['public_url'] as String;
    }
    return map;
  }

  /// Yüklenen dosyanın uzantısına göre MIME türü.
  ///
  /// NEDEN AÇIKÇA VERİLİYOR: bucket'ın `allowed_mime_types` kontrolü sunucuda
  /// yapılır. İçerik türü gönderilmezse Supabase yolun uzantısından tahmin
  /// eder ve .m4a için çoğu zaman `application/octet-stream`e düşer — bu da
  /// izinli listede olmadığı için yükleme sessizce reddedilirdi.
  static String _contentTypeFor(String ext) {
    switch (ext.toLowerCase()) {
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
        return 'audio/ogg';
      case 'aac':
        return 'audio/aac';
      case 'm4a':
      case 'mp4':
        // .m4a aslında bir MP4 kabıdır; sunucu tarafında audio/mp4 ve
        // audio/x-m4a'nın ikisi de kabul edilir.
        return 'audio/mp4';
      case 'webm':
        return 'audio/webm';
      default:
        return 'audio/mpeg';
    }
  }

  /// Desteklenen ses uzantıları.
  static const List<String> supportedAudioExtensions = [
    'mp3',
    'm4a',
    'wav',
    'ogg',
    'aac',
  ];

  /// Dosya adından uzantıyı çıkarır (küçük harf, noktasız). Uzantı yoksa ''.
  static String extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase().trim();
  }

  /// Dosyanın İÇERİĞİNDEN türünü okur (sihirli baytlar / file signature).
  ///
  /// NEDEN GEREKLİ: Android'de galeriden ya da bir bulut sağlayıcısından
  /// seçilen dosya çoğu zaman uzantısız bir adla gelir (`image:1000000034`,
  /// `document`, `IMG_20260904` gibi). Yalnızca ada bakan doğrulama bu
  /// dosyaları "Desteklenmeyen dosya" diye reddediyordu — oysa içerik
  /// gayet geçerli bir JPEG'di. Ad yetmediğinde içeriğe bakılır.
  ///
  /// Tanınmazsa null döner (yani gerçekten desteklenmeyen bir dosya).
  static String? sniffImageExtension(Uint8List b) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'jpg';
    }
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47 &&
        b[4] == 0x0D &&
        b[5] == 0x0A &&
        b[6] == 0x1A &&
        b[7] == 0x0A) {
      return 'png';
    }
    // WEBP: "RIFF" .... "WEBP"
    if (b.length >= 12 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return 'webp';
    }
    return null;
  }

  /// Ses dosyasının içeriğinden türü. Bkz. [sniffImageExtension].
  static String? sniffAudioExtension(Uint8List b) {
    if (b.length < 12) return null;
    // ID3 etiketli MP3
    if (b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33) return 'mp3';
    // Etiketsiz MP3 çerçevesi (0xFF 0xEx/0xFx)
    if (b[0] == 0xFF && (b[1] & 0xE0) == 0xE0) return 'mp3';
    // "RIFF" .... "WAVE"
    if (b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x41 &&
        b[10] == 0x56 &&
        b[11] == 0x45) {
      return 'wav';
    }
    // "OggS"
    if (b[0] == 0x4F && b[1] == 0x67 && b[2] == 0x67 && b[3] == 0x53) {
      return 'ogg';
    }
    // MP4/M4A kabı: 4 bayt uzunluk + "ftyp"
    if (b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) {
      return 'm4a';
    }
    // ADTS AAC
    if (b[0] == 0xFF && (b[1] & 0xF6) == 0xF0) return 'aac';
    return null;
  }

  /// Görsel için kullanılacak uzantı: önce dosya adı, olmazsa içerik.
  /// Hiçbiri tutmuyorsa null (dosya gerçekten desteklenmiyor).
  static String? resolveImageExtension(String fileName, Uint8List bytes) {
    final byName = extensionOf(fileName);
    if (supportedImageExtensions.contains(byName)) {
      return byName == 'jpeg' ? 'jpg' : byName;
    }
    return sniffImageExtension(bytes);
  }

  /// Ses için kullanılacak uzantı. Bkz. [resolveImageExtension].
  static String? resolveAudioExtension(String fileName, Uint8List bytes) {
    final byName = extensionOf(fileName);
    if (supportedAudioExtensions.contains(byName)) return byName;
    return sniffAudioExtension(bytes);
  }

  /// Bir hatayı ADMİNE ANLAM İFADE EDEN Türkçe bir cümleye çevirir.
  ///
  /// NEDEN: panelde her yakalanan hata `Hata: $e` diye basılıyordu; ekranda
  /// `PostgrestException(message: APP:forbidden, code: 42501, details: ...)`
  /// gibi bir metin çıkıyor, admin ne yapacağını anlamıyordu. Sunucu zaten
  /// `APP:<kod>` biçiminde niyet belirtiyor — burada karşılığı yazılır.
  static String describeError(Object error) {
    final raw = error.toString();
    final lower = raw.toLowerCase();

    const appMessages = <String, String>{
      'APP:forbidden': 'Bu işlem için admin yetkisi gerekiyor.',
      'APP:name_required': 'Ad boş olamaz.',
      'APP:name_taken': 'Bu ad zaten kullanılıyor — farklı bir ad girin.',
      'APP:not_found': 'Kayıt bulunamadı; başka biri silmiş olabilir.',
      'APP:path_required': 'Dosya yolu boş geldi, yükleme tamamlanamadı.',
      'APP:invalid_amount': 'Geçersiz çip miktarı.',
    };
    for (final entry in appMessages.entries) {
      if (raw.contains(entry.key)) return entry.value;
    }

    if (lower.contains('duplicate key') || lower.contains('23505')) {
      return 'Bu kayıt zaten var (ad benzersiz olmalı).';
    }
    if (lower.contains('row-level security') ||
        lower.contains('violates row-level')) {
      return 'Yetki reddedildi — hesabınız admin görünmüyor.';
    }
    if (lower.contains('mime type') && lower.contains('not supported')) {
      return 'Dosya biçimi sunucu tarafından kabul edilmiyor.';
    }
    if (lower.contains('maximum allowed size') ||
        lower.contains('payload too large') ||
        lower.contains('entity too large')) {
      return 'Dosya boyut sınırını aşıyor.';
    }
    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('clientexception') ||
        lower.contains('timeoutexception')) {
      return 'Bağlantı kurulamadı — internet bağlantınızı kontrol edin.';
    }

    // PostgrestException(message: X, ...) → yalnız X
    final m = RegExp(r'message:\s*([^,)]+)').firstMatch(raw);
    if (m != null) return m.group(1)!.trim();
    return raw;
  }

  /// Bu dosya adı desteklenen bir ses dosyası mı?
  ///
  /// NEDEN BURADA: Dosya seçiciye uzantı filtresi verildiğinde Android,
  /// uzantıyı MIME türüne çevirip filtreliyor. `.m4a` dosyaları cihaza göre
  /// `audio/mp4`, `audio/x-m4a` ya da başka bir tür raporladığı için
  /// seçicide SOLUK kalıp seçilemiyordu. Bu yüzden seçici artık TÜM
  /// dosyaları gösteriyor ve doğrulamayı biz yapıyoruz.
  static bool isSupportedAudio(String fileName) =>
      supportedAudioExtensions.contains(extensionOf(fileName));

  /// Kullanıcıya gösterilecek desteklenen format listesi.
  static String get supportedAudioLabel => supportedAudioExtensions.join(', ');

  // ---------------------------------------------------------------------
  // MASA ARKA PLANI (oda fotoğrafı)
  // ---------------------------------------------------------------------

  static const String backgroundsBucket = 'okey-backgrounds';

  /// Sunucudaki bucket'ın allowed_mime_types listesiyle AYNI olmalı
  /// (20260903000008): arayüzde kabul edip sunucunun reddetmesi, kullanıcıya
  /// sebebi anlaşılmayan bir hata olarak yansırdı.
  static const supportedImageExtensions = ['jpg', 'jpeg', 'png', 'webp'];

  static bool isSupportedImage(String fileName) =>
      supportedImageExtensions.contains(extensionOf(fileName));

  static String get supportedImageLabel => supportedImageExtensions.join(', ');

  /// Sunucudaki file_size_limit ile AYNI (5 MB).
  static const int backdropMaxBytes = 5 * 1024 * 1024;

  /// Yüklü masa arka planının URL'i (yoksa null).
  Future<String?> getTableBackdropUrl() async {
    final row = await _client
        .from('okey_table_assets')
        .select('public_url')
        .eq('asset_key', OkeyRoomBackdrop.assetKey)
        .maybeSingle();
    return row?['public_url'] as String?;
  }

  /// Masa arka planı görselini yükler ve kaydı günceller.
  ///
  /// ESKİ DOSYA SİLİNİR — ses akışıyla AYNI sıra: önce eski yol okunur, yeni
  /// dosya yazılır, kayıt güncellenir, EN SON eski dosya silinir. Silme
  /// başarısız olsa bile yeni görsel geçerli kalır.
  Future<String> uploadTableBackdrop({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final ext = extensionOf(fileName).isEmpty ? 'jpg' : extensionOf(fileName);

    String? previousPath;
    try {
      final r = await _client.rpc(
        'admin_okey_previous_table_asset_path',
        params: {'p_asset_key': OkeyRoomBackdrop.assetKey},
      );
      previousPath = r as String?;
    } catch (_) {
      // Eski yol okunamazsa yükleme yine de yapılır; sadece eski dosya kalır.
    }

    final path =
        '${OkeyRoomBackdrop.assetKey}/'
        '${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _client.storage
        .from(backgroundsBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );

    final url = _client.storage.from(backgroundsBucket).getPublicUrl(path);

    await _client.rpc(
      'admin_okey_set_table_asset',
      params: {
        'p_asset_key': OkeyRoomBackdrop.assetKey,
        'p_storage_path': path,
        'p_public_url': url,
      },
    );

    if (previousPath != null && previousPath != path) {
      try {
        await _client.storage.from(backgroundsBucket).remove([previousPath]);
      } catch (_) {
        // Artık dosya kalması oyunu etkilemez; sessizce geç.
      }
    }

    OkeyRoomBackdrop.invalidateCache();
    return url;
  }

  // ---------------------------------------------------------------------
  // BOT AVATARLARI
  // ---------------------------------------------------------------------

  static const String botAvatarsBucket = 'okey-bot-avatars';

  /// Sunucudaki bucket'ın file_size_limit değeriyle AYNI (2 MB).
  ///
  /// Avatar masada en fazla ~90px çizilir; daha büyüğü hem boşuna trafik hem
  /// de sunucuda reddedilir. Sınırı burada da bilmek, kullanıcıya yükleme
  /// başarısız olmadan ÖNCE anlaşılır bir mesaj verebilmek için gerekli.
  static const int botAvatarMaxBytes = 2 * 1024 * 1024;

  /// Bot profiline fotoğraf yükler ve profili günceller.
  ///
  /// Sıra masa arka planıyla AYNI: yeni dosya yazılır → kayıt güncellenir →
  /// EN SON eski dosya silinir. Tersi olsaydı, arada oluşan bir hata profili
  /// artık var olmayan bir dosyaya bağlı bırakırdı.
  Future<String> uploadBotAvatar({
    required String botProfileId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final ext = extensionOf(fileName).isEmpty ? 'jpg' : extensionOf(fileName);
    final path = '$botProfileId/${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _client.storage
        .from(botAvatarsBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );

    final url = _client.storage.from(botAvatarsBucket).getPublicUrl(path);

    final previous = await _client.rpc(
      'admin_okey_set_bot_avatar',
      params: {
        'p_id': botProfileId,
        'p_storage_path': path,
        'p_public_url': url,
      },
    );

    final previousPath = previous as String?;
    if (previousPath != null &&
        previousPath.isNotEmpty &&
        previousPath != path) {
      try {
        await _client.storage.from(botAvatarsBucket).remove([previousPath]);
      } catch (_) {
        // Artık dosya kalması oyunu etkilemez; sessizce geç.
      }
    }
    return url;
  }

  /// Bot profilinin fotoğrafını kaldırır (dosya da silinir).
  Future<void> clearBotAvatar(String botProfileId) async {
    final removed = await _client.rpc(
      'admin_okey_clear_bot_avatar',
      params: {'p_id': botProfileId},
    );
    final path = removed as String?;
    if (path != null && path.isNotEmpty) {
      try {
        await _client.storage.from(botAvatarsBucket).remove([path]);
      } catch (_) {
        // Kayıt zaten temizlendi; artık dosya oyunu etkilemez.
      }
    }
  }

  /// Arka planı kaldırır — oyun vektörel odaya geri döner.
  Future<void> clearTableBackdrop() async {
    final removed = await _client.rpc(
      'admin_okey_clear_table_asset',
      params: {'p_asset_key': OkeyRoomBackdrop.assetKey},
    );
    final path = removed as String?;
    if (path != null && path.isNotEmpty) {
      try {
        await _client.storage.from(backgroundsBucket).remove([path]);
      } catch (_) {
        // Kayıt zaten silindi; artık dosya oyunu etkilemez.
      }
    }
    OkeyRoomBackdrop.invalidateCache();
  }

  /// Bir ses olayı için dosya yükler ve kaydı günceller.
  /// [soundKey] = OkeySound enum'unun `.name` değeri (ör. `laugh`) veya
  /// arka plan şarkısı için `OkeySoundService.musicKey`.
  ///
  /// ESKİ DOSYA SİLİNİR: her yükleme zaman damgalı yeni bir yol yazar; eski
  /// dosya temizlenmezse depoda sonsuza kadar birikirdi.
  Future<String> uploadSound({
    required String soundKey,
    required String fileName,
    required Uint8List bytes,
  }) async {
    // extensionOf: küçük harfe indirir. `split('.').last` büyük harfli
    // uzantıyı (SES.MP3) olduğu gibi bırakıp depoda `.MP3` yollar üretiyordu.
    final ext = extensionOf(fileName).isEmpty ? 'mp3' : extensionOf(fileName);

    // Yeni dosyayı yazmadan ÖNCE eskisinin yolunu öğren
    String? previousPath;
    try {
      final r = await _client.rpc(
        'admin_okey_previous_sound_path',
        params: {'p_sound_key': soundKey},
      );
      previousPath = r as String?;
    } catch (_) {
      // Eski yol alınamazsa yükleme yine de sürer; sadece temizlik atlanır.
    }

    // Zaman damgası: istemcilerdeki önbellek eski dosyada takılı kalmasın
    final path = '$soundKey/${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _client.storage
        .from(soundsBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _contentTypeFor(ext),
          ),
        );

    final url = _client.storage.from(soundsBucket).getPublicUrl(path);

    await _client.rpc(
      'admin_okey_set_sound',
      params: {
        'p_sound_key': soundKey,
        'p_storage_path': path,
        'p_public_url': url,
      },
    );

    // Kayıt güncellendikten SONRA eskisini sil — sıra bu şekilde olmalı ki
    // silme başarısız olsa bile yeni dosya zaten geçerli kalsın.
    if (previousPath != null &&
        previousPath.isNotEmpty &&
        previousPath != path) {
      try {
        await _client.storage.from(soundsBucket).remove([previousPath]);
      } catch (_) {
        // Artık dosya kalması oyunu etkilemez; sessizce geç.
      }
    }

    return url;
  }

  // ---------------------------------------------------------------------
  // ÇALMA LİSTESİ (çoklu şarkı)
  //
  // Şarkılar efektlerle aynı depoda ama `music:<uuid>` anahtarlarıyla
  // tutulur; böylece mevcut yükleme/silme altyapısı aynen kullanılır.
  // ---------------------------------------------------------------------

  /// Yüklü şarkılar: (anahtar, ad, url).
  Future<List<({String key, String name, String url})>> listMusic() async {
    final rows = await _client.rpc('okey_list_music');
    return ((rows as List?) ?? const [])
        .map((r) {
          final m = r as Map<String, dynamic>;
          final key = m['sound_key'] as String? ?? '';
          return (
            key: key,
            name: (m['display_name'] as String?)?.trim().isNotEmpty == true
                ? m['display_name'] as String
                : 'Şarkı',
            url: m['public_url'] as String? ?? '',
          );
        })
        .where((e) => e.key.isNotEmpty && e.url.isNotEmpty)
        .toList();
  }

  /// Çalma listesine YENİ bir şarkı ekler (üzerine yazmaz).
  Future<void> addMusic({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final ext = extensionOf(fileName);
    final path =
        'music/${DateTime.now().millisecondsSinceEpoch}.'
        '${ext.isEmpty ? 'mp3' : ext}';

    await _client.storage
        .from(soundsBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _contentTypeFor(ext),
          ),
        );

    final url = _client.storage.from(soundsBucket).getPublicUrl(path);

    await _client.rpc(
      'admin_okey_add_music',
      params: {
        'p_storage_path': path,
        'p_public_url': url,
        'p_display_name': fileName,
      },
    );
  }

  // ---------------------------------------------------------------------
  // BOT PROFİLLERİ
  //
  // Botların masada görüneceği ad ve avatar. Havuz boşsa botlar eski
  // davranışla "Bot N" olarak görünür — yani bu özellik opsiyoneldir.
  // ---------------------------------------------------------------------

  Future<List<OkeyBotProfile>> listBotProfiles() async {
    final rows = await _client
        .from('okey_bot_profiles')
        .select()
        .order('display_name');
    return (rows as List)
        .map((r) => OkeyBotProfile.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// [id] null ise yeni profil oluşturur, doluysa günceller.
  /// Bot profilini oluşturur/günceller ve KAYDIN ID'SİNİ döndürür.
  ///
  /// ID'nin dönmesi şart: yeni bir profile fotoğraf yüklemek için önce o
  /// profilin var olması ve id'sinin bilinmesi gerekir (dosya yolu
  /// `<id>/<zaman>.jpg`). Eskiden `void` dönüyordu, bu yüzden "bot eklerken
  /// fotoğraf yükleme" mümkün değildi — önce kaydet, sonra listeden ayrıca
  /// yükle demek gerekiyordu.
  Future<String> upsertBotProfile({
    String? id,
    required String displayName,
    String? avatarUrl,
    bool isActive = true,
  }) async {
    final row = await _client.rpc(
      'admin_okey_upsert_bot_profile',
      params: {
        'p_id': id,
        'p_display_name': displayName,
        'p_avatar_url': avatarUrl,
        'p_is_active': isActive,
      },
    );
    return parseUpsertedId(row);
  }

  /// `admin_okey_upsert_bot_profile` cevabından profil id'sini çıkarır.
  ///
  /// RPC tek bir satır döndürür (`RETURNS okey_bot_profiles`) ama PostgREST
  /// bunu duruma göre map YA DA tek elemanlı liste olarak sarabiliyor. İki
  /// biçim de kabul edilir; id gelmezse sessizce devam etmek yerine hata
  /// verilir, çünkü id olmadan fotoğraf yüklenemez ve kullanıcı "kaydettim
  /// ama fotoğraf gitmedi" ile baş başa kalır.
  @visibleForTesting
  static String parseUpsertedId(dynamic row) {
    final map = row is List
        ? (row.isEmpty ? null : row.first as Map<String, dynamic>?)
        : row as Map<String, dynamic>?;
    final id = map?['id'] as String?;
    if (id == null) {
      throw StateError('Bot profili kaydedildi ama id dönmedi');
    }
    return id;
  }

  Future<void> deleteBotProfile(String id) async {
    await _client.rpc('admin_okey_delete_bot_profile', params: {'p_id': id});
  }

  // ---------------------------------------------------------------------
  // PUAN YÖNETİMİ
  // ---------------------------------------------------------------------

  /// Kullanıcıya Okey puanı ekler (negatif değer düşer).
  Future<int> grantPoints(String userId, int amount, {String? note}) async {
    final r = await _client.rpc(
      'admin_okey_grant_points',
      params: {'p_user_id': userId, 'p_amount': amount, 'p_note': note},
    );
    return (r as num).toInt();
  }

  /// Ada göre kullanıcı arar (puan eklemek için).
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    // PostgREST filtre dizgesinde virgül koşulları, parantez gruplama
    // yapar. Ham arama metni doğrudan yapıştırıldığı için "Ali, Veli" ya
    // da "Ahmet (baba)" yazan admin 400 hatası alıyordu. Değer tırnak
    // içine alınır; tırnak ve ters bölü kaçırılır.
    final safe = q.replaceAll('\\', r'\\').replaceAll('"', r'\"');
    final rows = await _client
        .from('profiles')
        .select('id, username, full_name, avatar_url')
        .or('username.ilike."%$safe%",full_name.ilike."%$safe%"')
        .limit(20);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// Bir kullanıcının Okey puanı.
  Future<int> getUserPoints(String userId) async {
    final row = await _client
        .from('okey_wallets')
        .select('points')
        .eq('user_id', userId)
        .maybeSingle();
    return ((row?['points'] as num?) ?? 0).toInt();
  }

  /// Sesi kaldırır: hem veritabanı kaydını hem DEPODAKİ DOSYAYI siler.
  ///
  /// Önceden yalnızca kayıt siliniyordu; dosya depoda sonsuza kadar kalıyor
  /// ve kota tüketiyordu.
  // ---------------------------------------------------------------------
  // HEDİYELER
  // ---------------------------------------------------------------------

  /// Tüm hediyeler — pasifler dahil (bkz. [OkeyAdminGift]).
  Future<List<OkeyAdminGift>> listGifts() async {
    final rows = await _client.rpc('okey_admin_list_gifts');
    return [
      for (final r in (rows as List? ?? const []))
        OkeyAdminGift.fromMap(r as Map<String, dynamic>),
    ];
  }

  /// Yeni hediye ekler ya da var olanı günceller.
  ///
  /// [id] null ise KOD üzerinden çakışma çözülür: aynı kodla ikinci bir
  /// hediye eklenmez, var olan güncellenir. Böylece admin "kahve"yi iki kez
  /// eklediğinde masada iki kahve belirmez.
  Future<String?> upsertGift({
    String? id,
    required String code,
    required String name,
    required String icon,
    required int price,
    int sortOrder = 0,
    bool isActive = true,
    String anim = 'bounce',
  }) async {
    final result = await _client.rpc(
      'okey_admin_upsert_gift',
      params: {
        'p_id': id,
        'p_code': code,
        'p_name': name,
        'p_icon': icon,
        'p_price': price,
        'p_sort_order': sortOrder,
        'p_is_active': isActive,
        'p_anim': anim,
      },
    );
    return result?.toString();
  }

  Future<void> deleteGift(String id) async {
    await _client.rpc('okey_admin_delete_gift', params: {'p_id': id});
  }

  /// Hediye bedelinin ALICIYA geçen yüzdesi (kalanı sistem kazancı).
  Future<int> giftRecipientPercent() async {
    final v = await _client.rpc('okey_admin_get_gift_percent');
    return (v as num?)?.toInt() ?? 50;
  }

  Future<int> setGiftRecipientPercent(int percent) async {
    final v = await _client.rpc(
      'okey_admin_set_gift_percent',
      params: {'p_percent': percent},
    );
    return (v as num?)?.toInt() ?? percent;
  }

  Future<void> clearSound(String soundKey) async {
    final removedPath =
        await _client.rpc(
              'admin_okey_clear_sound',
              params: {'p_sound_key': soundKey},
            )
            as String?;

    if (removedPath != null && removedPath.isNotEmpty) {
      try {
        await _client.storage.from(soundsBucket).remove([removedPath]);
      } catch (_) {
        // Kayıt zaten silindi; artık dosya kalması oyunu etkilemez.
      }
    }
  }
}
