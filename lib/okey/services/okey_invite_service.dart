import 'package:supabase_flutter/supabase_flutter.dart';

/// Bekleme odasına davet edilebilecek bir kişi.
///
/// Liste, oyuncunun TAKİP ETTİĞİ kişilerden oluşur (sunucu da aynı kuralı
/// uygular). [isFriend] karşılıklı takibi — yani bu kod tabanındaki gerçek
/// "arkadaş" tanımını — gösterir ve liste onları başa alır.
class OkeyInviteCandidate {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final int points;

  /// Karşılıklı takip (arkadaş).
  final bool isFriend;

  /// Bu masada zaten oturuyor.
  final bool inRoom;

  /// Bu masa için bekleyen daveti var.
  final bool invited;

  const OkeyInviteCandidate({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.points = 0,
    this.isFriend = false,
    this.inRoom = false,
    this.invited = false,
  });

  /// Davet düğmesi basılabilir mi.
  bool get canInvite => !inRoom && !invited;

  OkeyInviteCandidate copyWith({bool? invited}) => OkeyInviteCandidate(
    userId: userId,
    displayName: displayName,
    avatarUrl: avatarUrl,
    points: points,
    isFriend: isFriend,
    inRoom: inRoom,
    invited: invited ?? this.invited,
  );

  factory OkeyInviteCandidate.fromMap(Map<String, dynamic> m) =>
      OkeyInviteCandidate(
        userId: m['user_id'] as String,
        displayName: (m['display_name'] as String?) ?? 'Oyuncu',
        avatarUrl: m['avatar_url'] as String?,
        points: (m['points'] as num?)?.toInt() ?? 0,
        isFriend: m['is_friend'] as bool? ?? false,
        inRoom: m['in_room'] as bool? ?? false,
        invited: m['invited'] as bool? ?? false,
      );
}

/// BANA gelen, hâlâ geçerli bir masa daveti.
///
/// Sunucu yalnızca oturulabilir davetleri döndürür (masa hâlâ bekliyor, boş
/// koltuk var, davet 2 saatten yeni) — istemcinin ayrıca elemesi gerekmez.
class OkeyRoomInvite {
  final String inviteId;
  final String roomId;
  final String inviterId;
  final String inviterName;
  final String? inviterAvatar;

  /// Masaya oturmanın bedeli (giriş puanı × el sayısı).
  final int tableStake;
  final int totalHands;
  final String gameMode;
  final String teamMode;
  final String assistMode;
  final int seatedCount;
  final DateTime createdAt;

  const OkeyRoomInvite({
    required this.inviteId,
    required this.roomId,
    required this.inviterId,
    required this.inviterName,
    required this.tableStake,
    required this.totalHands,
    required this.gameMode,
    required this.teamMode,
    required this.assistMode,
    required this.seatedCount,
    required this.createdAt,
    this.inviterAvatar,
  });

  factory OkeyRoomInvite.fromMap(Map<String, dynamic> m) => OkeyRoomInvite(
    inviteId: m['invite_id'] as String,
    roomId: m['room_id'] as String,
    inviterId: m['inviter_id'] as String,
    inviterName: (m['inviter_name'] as String?) ?? 'Bir oyuncu',
    inviterAvatar: m['inviter_avatar'] as String?,
    tableStake: (m['table_stake'] as num?)?.toInt() ?? 0,
    totalHands: (m['total_hands'] as num?)?.toInt() ?? 3,
    gameMode: (m['game_mode'] as String?) ?? 'katlamasiz',
    teamMode: (m['team_mode'] as String?) ?? 'essiz',
    assistMode: (m['assist_mode'] as String?) ?? 'yardimli',
    seatedCount: (m['seated_count'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.parse(m['created_at'] as String),
  );
}

/// Arkadaş daveti RPC'leri için ince istemci katmanı.
///
/// Doğrulamanın TAMAMI sunucudadır (takip ilişkisi, masa durumu, boş koltuk,
/// hız sınırı — bkz. 20260905000002 göçü). Buradaki tek ek iş, `APP:` hata
/// kodlarını kullanıcıya gösterilebilir Türkçe cümlelere çevirmektir.
class OkeyInviteService {
  SupabaseClient get _client => Supabase.instance.client;

  /// Masaya davet edilebilecek kişiler (takip edilenler; arkadaşlar başta).
  Future<List<OkeyInviteCandidate>> invitableFriends(
    String roomId, {
    String? search,
  }) async {
    final rows = await _client.rpc(
      'okey_invitable_friends',
      params: {'p_room_id': roomId, 'p_search': search, 'p_limit': 50},
    );
    return ((rows as List?) ?? const [])
        .map((r) => OkeyInviteCandidate.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Daveti gönderir. Davet edilene bildirim + push gider.
  Future<void> invite({
    required String roomId,
    required String inviteeId,
  }) async {
    await _client.rpc(
      'okey_invite_to_room',
      params: {'p_room_id': roomId, 'p_invitee_id': inviteeId},
    );
  }

  /// Bana gelen açık davetler.
  Future<List<OkeyRoomInvite>> myInvites() async {
    final rows = await _client.rpc('okey_my_room_invites');
    return ((rows as List?) ?? const [])
        .map((r) => OkeyRoomInvite.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Daveti kabul eder ve MASAYA OTURUR; girilen odanın kimliğini döner.
  ///
  /// Oturma sunucuda aynı işlemde yapılır: masa dolmuşsa ya da puan
  /// yetmiyorsa buradan hata gelir ve davet açık kalır — davet eden
  /// yanlışlıkla "kabul edildi" bildirimi almaz.
  Future<String> accept(String inviteId) async {
    final rows = await _client.rpc(
      'okey_accept_room_invite',
      params: {'p_invite_id': inviteId},
    );
    final list = (rows as List?) ?? const [];
    if (list.isEmpty) throw StateError('APP:invite_not_found');
    return (list.first as Map<String, dynamic>)['r_room_id'] as String;
  }

  Future<void> decline(String inviteId) async {
    await _client.rpc(
      'okey_decline_room_invite',
      params: {'p_invite_id': inviteId},
    );
  }

  /// Sunucunun `APP:<kod>` işaretlerini kullanıcıya gösterilebilir cümleye
  /// çevirir. Eşleşme yoksa genel bir mesaj döner — ham Postgres metni
  /// hiçbir zaman ekrana basılmaz.
  static String friendlyError(Object error) {
    final raw = error.toString();
    const map = <String, String>{
      'APP:auth_required': 'Bu işlem için giriş yapmalısın.',
      'APP:okey_banned': 'Okey erişimin kapalı.',
      'APP:not_in_room': 'Davet edebilmek için masada oturuyor olmalısın.',
      'APP:not_found': 'Masa bulunamadı.',
      'APP:room_not_joinable': 'Masa artık davet kabul etmiyor, oyun başladı.',
      'APP:room_full': 'Masada boş koltuk kalmadı.',
      'APP:not_following':
          'Yalnızca takip ettiğin kişileri davet edebilirsin. '
          'Önce onu takip et.',
      'APP:invitee_not_invitable': 'Bu hesap davet edilemiyor.',
      'APP:already_seated': 'Bu oyuncu zaten masada.',
      'APP:invite_already_sent': 'Davetin gitti, biraz bekle.',
      'APP:invite_rate_limited':
          'Bu saatte çok fazla davet gönderdin, biraz sonra dene.',
      'APP:invite_not_found': 'Davet bulunamadı ya da geçerliliğini yitirdi.',
      'APP:invite_already_answered': 'Bu davet zaten yanıtlanmış.',
      'APP:invalid_invitee': 'Bu kişi davet edilemez.',
      'APP:insufficient_points': 'Bu masa için yeterli puanın yok.',
    };
    for (final entry in map.entries) {
      if (raw.contains(entry.key)) return entry.value;
    }
    return 'İşlem tamamlanamadı, tekrar dene.';
  }
}
