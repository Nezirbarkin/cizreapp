/// Ana sayfadaki "Önerilen Kişiler" kartı (Görev 3.5).
///
/// Sunucu biçimi `public.suggested_follows(limit)`; gerekçe ve sıralama
/// sunucuda hesaplanır (seni takip edenler > ortak takip > popülerlik > son 30
/// günde paylaşım …).
enum FollowSuggestionReason { followsYou, mutual, popular, newMember, suggested }

/// Takip ilişkisinin istemcideki hâli (sunucudaki `social_follow` dönüşü).
enum FollowStatus { none, following, requested }

FollowStatus followStatusFromCode(String? code) => switch (code) {
  'following' => FollowStatus.following,
  'requested' => FollowStatus.requested,
  _ => FollowStatus.none,
};

class FollowSuggestion {
  final String id;
  final String username;
  final String? fullName;
  final String? avatarUrl;
  final bool isVerified;
  final bool isPrivate;
  final int followersCount;
  final int mutualCount;
  final bool followsYou;
  final List<String> mutualNames;
  final FollowSuggestionReason reason;

  const FollowSuggestion({
    required this.id,
    required this.username,
    this.fullName,
    this.avatarUrl,
    this.isVerified = false,
    this.isPrivate = false,
    this.followersCount = 0,
    this.mutualCount = 0,
    this.followsYou = false,
    this.mutualNames = const [],
    this.reason = FollowSuggestionReason.suggested,
  });

  factory FollowSuggestion.fromJson(Map<String, dynamic> json) {
    int toInt(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
    String? text(Object? v) {
      final t = v?.toString().trim();
      return t == null || t.isEmpty ? null : t;
    }

    return FollowSuggestion(
      id: json['id'].toString(),
      username: text(json['username']) ?? '',
      fullName: text(json['full_name']),
      avatarUrl: text(json['avatar_url']),
      isVerified: json['is_verified'] == true,
      isPrivate: json['is_private'] == true,
      followersCount: toInt(json['followers_count']),
      mutualCount: toInt(json['mutual_count']),
      followsYou: json['follows_you'] == true,
      mutualNames: (json['mutual_names'] is List)
          ? (json['mutual_names'] as List).map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : const [],
      reason: switch (json['reason']) {
        'follows_you' => FollowSuggestionReason.followsYou,
        'mutual' => FollowSuggestionReason.mutual,
        'popular' => FollowSuggestionReason.popular,
        'new' => FollowSuggestionReason.newMember,
        _ => FollowSuggestionReason.suggested,
      },
    );
  }

  /// Kartta büyük yazan ad: tam ad, yoksa kullanıcı adı.
  String get displayName => fullName ?? (username.isEmpty ? 'Kullanıcı' : username);

  /// Neden önerildiği ("Seni takip ediyor", "ali ve 2 kişi daha takip ediyor" …).
  String get reasonText {
    switch (reason) {
      case FollowSuggestionReason.followsYou:
        return 'Seni takip ediyor';
      case FollowSuggestionReason.mutual:
        if (mutualNames.isEmpty) return '$mutualCount ortak takip';
        final first = mutualNames.first;
        final rest = mutualCount - 1;
        return rest > 0 ? '$first ve $rest kişi daha takip ediyor' : '$first takip ediyor';
      case FollowSuggestionReason.popular:
        return '$followersCount takipçi';
      case FollowSuggestionReason.newMember:
        return 'Yeni üye';
      case FollowSuggestionReason.suggested:
        return 'Senin için önerildi';
    }
  }

  /// Takip düğmesinin ilk etiketi (henüz takip edilmiyorken).
  String get followLabel {
    if (isPrivate) return 'İstek Gönder';
    return followsYou ? 'Geri Takip Et' : 'Takip Et';
  }
}
