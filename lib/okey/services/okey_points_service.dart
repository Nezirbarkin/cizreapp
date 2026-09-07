import 'package:supabase_flutter/supabase_flutter.dart';

/// Okey cüzdanının durumu.
class OkeyWallet {
  final int points;
  final DateTime? lastHourlyClaimAt;
  final bool canClaimHourly;
  final int secondsUntilNextGift;
  final int hourlyGiftPoints;
  final int adRewardPoints;

  const OkeyWallet({
    required this.points,
    required this.canClaimHourly,
    required this.secondsUntilNextGift,
    required this.hourlyGiftPoints,
    required this.adRewardPoints,
    this.lastHourlyClaimAt,
  });

  factory OkeyWallet.fromMap(Map<String, dynamic> m) => OkeyWallet(
    points: (m['points'] as num).toInt(),
    lastHourlyClaimAt: m['last_hourly_claim_at'] == null
        ? null
        : DateTime.parse(m['last_hourly_claim_at'] as String),
    canClaimHourly: m['can_claim_hourly'] as bool? ?? false,
    secondsUntilNextGift: (m['seconds_until_next_gift'] as num?)?.toInt() ?? 0,
    hourlyGiftPoints: (m['hourly_gift_points'] as num?)?.toInt() ?? 100,
    adRewardPoints: (m['ad_reward_points'] as num?)?.toInt() ?? 250,
  );

  static const empty = OkeyWallet(
    points: 0,
    canClaimHourly: false,
    secondsUntilNextGift: 0,
    hourlyGiftPoints: 100,
    adRewardPoints: 250,
  );
}

/// Skor tablosundaki bir satır.
class OkeyLeaderboardEntry {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final int points;
  final int matchesPlayed;
  final int matchesWon;
  final int handsWon;
  final int? bestMatchScore;

  const OkeyLeaderboardEntry({
    required this.userId,
    required this.displayName,
    required this.points,
    required this.matchesPlayed,
    required this.matchesWon,
    required this.handsWon,
    this.avatarUrl,
    this.bestMatchScore,
  });

  factory OkeyLeaderboardEntry.fromMap(Map<String, dynamic> m) =>
      OkeyLeaderboardEntry(
        userId: m['user_id'] as String,
        displayName: m['display_name'] as String? ?? 'Oyuncu',
        avatarUrl: m['avatar_url'] as String?,
        points: (m['points'] as num?)?.toInt() ?? 0,
        matchesPlayed: (m['matches_played'] as num?)?.toInt() ?? 0,
        matchesWon: (m['matches_won'] as num?)?.toInt() ?? 0,
        handsWon: (m['hands_won'] as num?)?.toInt() ?? 0,
        bestMatchScore: (m['best_match_score'] as num?)?.toInt(),
      );
}

/// Okey'e ÖZEL puan sistemi. Bu puanlar uygulamanın diğer bakiye/ödül
/// sistemlerinden tamamen ayrıdır ve yalnızca Okey masalarında kullanılır.
class OkeyPointsService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<OkeyWallet> getWallet() async {
    final rows = await _client.rpc('okey_get_wallet');
    final list = rows as List;
    if (list.isEmpty) return OkeyWallet.empty;
    return OkeyWallet.fromMap(list.first as Map<String, dynamic>);
  }

  /// Saatlik hediye. Süre dolmadıysa sunucu `APP:gift_not_ready` döndürür —
  /// zaman kontrolü SUNUCUDA yapılır, istemcinin saatine güvenilmez.
  Future<int> claimHourlyGift() async {
    final r = await _client.rpc('okey_claim_hourly_gift');
    return (r as num).toInt();
  }

  /// Reklam ödülü. [sessionId] mevcut SSV-doğrulamalı reklam altyapısından
  /// gelen oturum kimliğidir; sunucu oturumun gerçekten doğrulandığını
  /// bağımsız olarak kontrol eder ve aynı oturum iki kez puan veremez.
  Future<int> claimAdReward(String sessionId) async {
    final r = await _client.rpc(
      'okey_claim_ad_reward',
      params: {'p_session_id': sessionId},
    );
    return (r as num).toInt();
  }

  Future<List<OkeyLeaderboardEntry>> leaderboard({int limit = 50}) async {
    final rows = await _client.rpc(
      'okey_leaderboard',
      params: {'p_limit': limit},
    );
    return (rows as List)
        .map((r) => OkeyLeaderboardEntry.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Puan hareketleri geçmişi (kendi kayıtlarım).
  Future<List<Map<String, dynamic>>> history({int limit = 50}) async {
    final rows = await _client
        .from('okey_point_transactions')
        .select('amount, reason, balance_after, created_at')
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List).cast<Map<String, dynamic>>();
  }
}
