import 'package:supabase_flutter/supabase_flutter.dart';

/// Son 7 günün bir günü.
class DailyViews {
  const DailyViews(this.day, this.views);

  final DateTime day;
  final int views;
}

/// Sahibe özel gönderi istatistikleri (`get_post_insights`).
class PostInsights {
  const PostInsights({
    required this.views,
    required this.uniqueViewers,
    required this.detailOpens,
    required this.likes,
    required this.comments,
    required this.shares,
    required this.saves,
    required this.followerViewers,
    required this.daily,
    this.engagementRate,
    this.nonFollowerRate,
  });

  final int views;
  final int uniqueViewers;
  final int detailOpens;
  final int likes;
  final int comments;
  final int shares;
  final int saves;
  final int followerViewers;

  /// (beğeni + yorum + paylaşım + kaydetme) / benzersiz kişi, yüzde.
  final double? engagementRate;

  /// Takip etmeyenlerden gelen erişim, yüzde.
  final double? nonFollowerRate;
  final List<DailyViews> daily;

  int get interactions => likes + comments + shares + saves;

  factory PostInsights.fromJson(Map<String, dynamic> j) {
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    double? d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    final raw = j['daily'];
    return PostInsights(
      views: i(j['views']),
      uniqueViewers: i(j['unique_viewers']),
      detailOpens: i(j['detail_opens']),
      likes: i(j['likes']),
      comments: i(j['comments']),
      shares: i(j['shares']),
      saves: i(j['saves']),
      followerViewers: i(j['follower_viewers']),
      engagementRate: d(j['engagement_rate']),
      nonFollowerRate: d(j['non_follower_rate']),
      daily: raw is List
          ? [
              for (final e in raw.whereType<Map>())
                if (DateTime.tryParse('${e['day']}') case final day?)
                  DailyViews(day, i(e['views'])),
            ]
          : const [],
    );
  }
}

class PostInsightsService {
  PostInsightsService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _db => _client ?? Supabase.instance.client;

  Future<PostInsights> fetch(String postId) async {
    final res = await _db.rpc('get_post_insights', params: {'p_post_id': postId});
    return PostInsights.fromJson(Map<String, dynamic>.from(res as Map));
  }
}
