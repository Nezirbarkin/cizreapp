import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/follow_suggestion.dart';

class FollowResult {
  final FollowStatus status;
  final int followersCount;

  const FollowResult(this.status, this.followersCount);
}

class FollowException implements Exception {
  final String message;
  final String? code;

  const FollowException(this.message, [this.code]);

  @override
  String toString() => 'FollowException($code: $message)';
}

/// Takip ve takip önerileri (Görev 3.5).
///
/// Takip tek RPC'den (`social_follow`): herkese açık hesabı takip eder, gizli
/// hesaba istek gönderir (onaylanınca takip olur), engelli hesabı reddeder,
/// takibi bırakınca bekleyen isteği de geri alır. Tabloya doğrudan yazılmaz —
/// veritabanı gizli hesaba doğrudan takibi zaten reddeder.
class FollowService {
  FollowService({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  String? get currentUserId => _client.auth.currentUser?.id;

  Future<FollowResult> follow(String userId) => _setFollow(userId, true);

  Future<FollowResult> unfollow(String userId) => _setFollow(userId, false);

  Future<FollowResult> _setFollow(String userId, bool follow) async {
    try {
      final data = await _client.rpc('social_follow', params: {'p_user_id': userId, 'p_follow': follow});
      final json = Map<String, dynamic>.from(data as Map);
      final count = json['followers_count'];
      return FollowResult(
        followStatusFromCode(json['status']?.toString()),
        count is num ? count.toInt() : int.tryParse('$count') ?? 0,
      );
    } catch (e) {
      throw toException(e);
    }
  }

  /// Ana sayfa önerileri. Misafirde boş (sunucuya gidilmez).
  Future<List<FollowSuggestion>> suggestions({int limit = 10}) async {
    if (currentUserId == null) return const [];
    try {
      final data = await _client.rpc('suggested_follows', params: {'p_limit': limit});
      if (data is! List) return const [];
      return data.whereType<Map>().map((e) => FollowSuggestion.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (e) {
      throw toException(e);
    }
  }

  /// Kartı kapat: bu kişi 60 gün önerilmez.
  Future<void> dismissSuggestion(String userId) async {
    try {
      await _client.rpc('dismiss_follow_suggestion', params: {'p_user_id': userId});
    } catch (e) {
      throw toException(e);
    }
  }

  /// Bekleyen (onay bekleyen) takip isteklerinin hedefleri.
  Future<Set<String>> pendingRequestIds() async {
    final me = currentUserId;
    if (me == null) return const {};
    final rows = await _client
        .from('follow_requests')
        .select('following_id')
        .eq('follower_id', me)
        .eq('status', 'pending');
    return {for (final row in rows as List) (row as Map)['following_id'].toString()};
  }

  static FollowException toException(Object error) {
    if (error is FollowException) return error;
    if (error is PostgrestException) {
      switch (error.hint) {
        case 'AUTH_REQUIRED':
          return const FollowException('Takip için giriş yapmalısın.', 'AUTH_REQUIRED');
        case 'FOLLOW_SELF':
          return const FollowException('Kendini takip edemezsin.', 'FOLLOW_SELF');
        case 'FOLLOW_NOT_FOUND':
          return const FollowException('Kullanıcı bulunamadı.', 'FOLLOW_NOT_FOUND');
        case 'FOLLOW_BLOCKED':
          return const FollowException('Bu kullanıcıyı takip edemezsin.', 'FOLLOW_BLOCKED');
      }
    }
    return FollowException('İşlem tamamlanamadı; tekrar dene.', error.runtimeType.toString());
  }
}
