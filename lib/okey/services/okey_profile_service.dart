import 'package:supabase_flutter/supabase_flutter.dart';

/// Masada ya da skor tablosunda bir oyuncuya dokununca açılan PROFİL KARTI.
///
/// Sunucudan yalnızca görünür/sayısal bilgi gelir: ad, avatar, okey puanı,
/// maç istatistikleri ve takip SAYILARI. Takipçi listeleri, e-posta gibi
/// kişisel veri hiç dönmez (bkz. okey_profile_card RPC).
class OkeyProfileCard {
  /// Gerçek kullanıcı ise kimliği; bot ise null.
  final String? userId;

  final String displayName;
  final String? avatarUrl;
  final int points;

  final int matchesPlayed;
  final int matchesWon;
  final int handsPlayed;
  final int handsWon;
  final int? bestMatchScore;

  final int followersCount;
  final int followingCount;
  final int friendsCount;

  /// Bu profili ben takip ediyor muyum.
  final bool isFollowing;

  /// GİZLİ bir hesaba takip İSTEĞİ gönderdim ve henüz onaylanmadı.
  ///
  /// [isFollowing] ile birlikte okunur: ikisi de false ise düğme "TAKİP ET",
  /// bu true ise "İSTEK GÖNDERİLDİ" der. Bu ayrım olmadan gizli bir hesaba
  /// istek gönderen oyuncu düğmeyi hâlâ "TAKİP ET" görüyor ve aynı isteği
  /// tekrar tekrar gönderiyordu.
  final bool isFollowRequested;

  /// Hedef hesap gizli mi (takip için onay gerekir mi).
  final bool isPrivate;

  /// Bu profil BENİM profilim mi.
  final bool isSelf;

  const OkeyProfileCard({
    required this.displayName,
    required this.points,
    required this.matchesPlayed,
    required this.matchesWon,
    required this.handsPlayed,
    required this.handsWon,
    required this.followersCount,
    required this.followingCount,
    required this.friendsCount,
    this.userId,
    this.avatarUrl,
    this.bestMatchScore,
    this.isFollowing = false,
    this.isFollowRequested = false,
    this.isPrivate = false,
    this.isSelf = false,
  });

  /// Takip durumu değişince kartın sayıları da değişir — sunucudan tüm kartı
  /// yeniden çekmeden güncellenebilsin diye.
  OkeyProfileCard copyWithFollow({
    required bool following,
    required bool requested,
    required int followers,
  }) => OkeyProfileCard(
    displayName: displayName,
    points: points,
    matchesPlayed: matchesPlayed,
    matchesWon: matchesWon,
    handsPlayed: handsPlayed,
    handsWon: handsWon,
    followersCount: followers,
    followingCount: followingCount,
    friendsCount: friendsCount,
    userId: userId,
    avatarUrl: avatarUrl,
    bestMatchScore: bestMatchScore,
    isFollowing: following,
    isFollowRequested: requested,
    isPrivate: isPrivate,
    isSelf: isSelf,
  );

  /// Kaybedilen maç — sunucudan ayrıca gelmez, TÜRETİLİR.
  ///
  /// Ayrı bir sütun olsaydı "oynanan = kazanılan + kaybedilen" değişmezini
  /// iki yerde korumak gerekirdi; tek bir çıkarma her zaman tutarlıdır.
  /// clamp: bozuk/eski bir istatistik satırı negatif sayı göstermesin.
  int get matchesLost =>
      (matchesPlayed - matchesWon) < 0 ? 0 : matchesPlayed - matchesWon;

  /// Kazanma oranı (0..1). Hiç maç yoksa 0.
  double get winRate => matchesPlayed == 0 ? 0 : matchesWon / matchesPlayed;

  /// "%46" biçiminde kazanma oranı.
  String get winRateLabel => '%${(winRate * 100).round()}';

  factory OkeyProfileCard.fromMap(Map<String, dynamic> m) => OkeyProfileCard(
    userId: m['user_id'] as String?,
    displayName: (m['display_name'] as String?) ?? 'Oyuncu',
    avatarUrl: m['avatar_url'] as String?,
    points: (m['points'] as num?)?.toInt() ?? 0,
    matchesPlayed: (m['matches_played'] as num?)?.toInt() ?? 0,
    matchesWon: (m['matches_won'] as num?)?.toInt() ?? 0,
    handsPlayed: (m['hands_played'] as num?)?.toInt() ?? 0,
    handsWon: (m['hands_won'] as num?)?.toInt() ?? 0,
    bestMatchScore: (m['best_match_score'] as num?)?.toInt(),
    followersCount: (m['followers_count'] as num?)?.toInt() ?? 0,
    followingCount: (m['following_count'] as num?)?.toInt() ?? 0,
    friendsCount: (m['friends_count'] as num?)?.toInt() ?? 0,
    isFollowing: m['is_following'] as bool? ?? false,
    isFollowRequested: m['is_follow_requested'] as bool? ?? false,
    isPrivate: m['is_private'] as bool? ?? false,
    isSelf: m['is_self'] as bool? ?? false,
  );
}

/// Profil kartını okuyan ince veri katmanı.
class OkeyProfileService {
  SupabaseClient get _client => Supabase.instance.client;

  /// Bir oyuncunun (ya da botun) profil kartı.
  ///
  /// [userId] ve [botProfileId]'den yalnız BİRİ verilir. Bot koltuğunun
  /// kullanıcı kimliği yoktur; kart bu yüzden iki farklı anahtarla
  /// sorgulanabilir olmalı.
  Future<OkeyProfileCard?> card({String? userId, String? botProfileId}) async {
    if (userId == null && botProfileId == null) return null;
    final rows = await _client.rpc(
      'okey_profile_card',
      params: {'p_user_id': userId, 'p_bot_profile_id': botProfileId},
    );
    final list = (rows as List?) ?? const [];
    if (list.isEmpty) return null;
    return OkeyProfileCard.fromMap(list.first as Map<String, dynamic>);
  }

  /// TAKİP ET / TAKİBİ BIRAK.
  ///
  /// Kararı sunucu verir: hedef hesap açıksa doğrudan takip başlar, gizliyse
  /// bir takip İSTEĞİ oluşur. İstemci hangisinin olduğunu tahmin etmez —
  /// dönen [OkeyFollowState] söyler.
  ///
  /// (Bu ayrım uygulamada dört ayrı ekranda ayrı ayrı yazılıydı; masadaki
  /// kart beşincisi olmasın diye tek bir RPC'ye alındı.)
  Future<OkeyFollowState> setFollow(String userId, bool follow) async {
    final rows = await _client.rpc(
      'okey_profile_follow',
      params: {'p_user_id': userId, 'p_follow': follow},
    );
    final list = (rows as List?) ?? const [];
    if (list.isEmpty) {
      return OkeyFollowState(
        isFollowing: follow,
        isRequested: false,
        followersCount: 0,
      );
    }
    final m = list.first as Map<String, dynamic>;
    return OkeyFollowState(
      isFollowing: m['is_following'] as bool? ?? false,
      isRequested: m['is_requested'] as bool? ?? false,
      followersCount: (m['followers_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// [OkeyProfileService.setFollow] sonrası GERÇEK durum.
class OkeyFollowState {
  final bool isFollowing;

  /// Gizli hesap: istek gönderildi, onay bekliyor.
  final bool isRequested;
  final int followersCount;

  const OkeyFollowState({
    required this.isFollowing,
    required this.isRequested,
    required this.followersCount,
  });
}
