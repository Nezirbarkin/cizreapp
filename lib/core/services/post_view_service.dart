import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/analytics_model.dart';

/// Post görüntüleme takip servisi
/// Her postun kimlerin görüntülediğini ve aylık istatistiklerini takip eder
class PostViewService {
  final _supabase = Supabase.instance.client;

  /// Post görüntülemesini kaydet (günde 1 kez sayılır)
  /// [postId] - Görüntülenen post
  /// Viewer ID otomatik olarak auth.uid() ile alınır
  Future<void> trackPostView({
    required String postId,
  }) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      
      if (currentUserId == null) {
        debugPrint('⚠️ Kullanıcı giriş yapmamış - post görüntülemesi kaydedilemedi');
        return;
      }

      // Post sahibinin ID'sini al (kendi postunu görüntülemeyi kaydetme)
      final postResponse = await _supabase
          .from('posts')
          .select('user_id')
          .eq('id', postId)
          .maybeSingle();

      if (postResponse == null) {
        debugPrint('⚠️ Post bulunamadı: $postId');
        return;
      }

      final postOwnerId = postResponse['user_id'];
      if (postOwnerId == currentUserId) {
        debugPrint('👤 Kendi postunu görüntüleme - kaydedilmedi');
        return;
      }

      debugPrint('📊 Post görüntülemesi kaydediliyor: $postId <- $currentUserId');

      // RPC fonksiyonunu çağır (viewer_id parametresini de gönder)
      await _supabase.rpc(
        'track_post_view',
        params: {
          'p_post_id': postId,
          'p_viewer_id': currentUserId,
        },
      );

      debugPrint('✅ Post görüntülemesi kaydedildi');
    } catch (e) {
      debugPrint('❌ Post görüntülemesi kaydedilemedi: $e');
    }
  }

  /// Kullanıcının mevcut ayda postlarının aldığı toplam görüntüleme
  Future<CurrentMonthViewStats?> getCurrentMonthStats(String userId) async {
    try {
      debugPrint('📊 Aylık post istatistikleri getiriliyor: $userId');

      final response = await _supabase.rpc(
        'get_user_current_month_post_views',
        params: {'p_user_id': userId},
      ) as List;

      if (response.isEmpty) {
        return CurrentMonthViewStats(totalViews: 0, uniqueViewers: 0);
      }

      final data = response.first as Map<String, dynamic>;
      final stats = CurrentMonthViewStats.fromJson(data);
      
      debugPrint('✅ Aylık post istatistikleri: ${stats.totalViews} görüntüleme, ${stats.uniqueViewers} benzersiz');
      return stats;
    } catch (e) {
      debugPrint('❌ Aylık post istatistikleri alınamadı: $e');
      return null;
    }
  }

  /// Kullanıcının postlarının aylık görüntüleme geçmişi
  /// [userId] - İstatistikler alınacak kullanıcı
  /// [months] - Kaç aylık geçmiş (varsayılan: 6)
  Future<List<MonthlyPostViewStats>> getMonthlyHistory({
    required String userId,
    int months = 6,
  }) async {
    try {
      debugPrint('📊 $months aylık post geçmişi getiriliyor: $userId');

      final response = await _supabase.rpc(
        'get_post_monthly_stats',
        params: {
          'p_user_id': userId,
          'p_months': months,
        },
      ) as List;

      final history = response
          .map((item) => MonthlyPostViewStats.fromJson(item as Map<String, dynamic>))
          .toList();

      debugPrint('✅ ${history.length} aylık post geçmişi alındı');
      return history;
    } catch (e) {
      debugPrint('❌ Aylık post geçmişi alınamadı: $e');
      return [];
    }
  }

  /// Tam analytics özeti (şu an + geçmiş)
  Future<AnalyticsSummary?> getAnalyticsSummary({
    required String userId,
    int months = 6,
  }) async {
    try {
      debugPrint('📊 Post analytics özeti hazırlanıyor: $userId');

      final currentMonth = await getCurrentMonthStats(userId);
      final monthlyHistory = await getMonthlyHistory(
        userId: userId,
        months: months,
      );

      if (currentMonth == null) {
        return null;
      }

      // Toplam görüntüleme ve ortalama hesapla
      int totalViews = monthlyHistory.fold(0, (sum, stat) => sum + stat.viewCount);
      double averageViews = monthlyHistory.isEmpty ? 0 : totalViews / monthlyHistory.length;

      final summary = AnalyticsSummary(
        title: 'Post Görüntülemeleri',
        currentMonthViews: currentMonth.totalViews,
        currentMonthUniqueViewers: currentMonth.uniqueViewers,
        monthlyHistory: monthlyHistory,
        averageViewsPerMonth: averageViews,
        totalViews: totalViews,
      );

      debugPrint('✅ Post analytics özeti hazırlandı: ${summary.totalViews} toplam görüntüleme');
      return summary;
    } catch (e) {
      debugPrint('❌ Post analytics özeti hazırlanamadı: $e');
      return null;
    }
  }

  /// Belirli bir postun son görüntüleyenleri
  Future<List<Map<String, dynamic>>> getRecentViewers({
    required String postId,
    int limit = 10,
  }) async {
    try {
      debugPrint('👥 Post\'un son $limit görüntüleyicisi getiriliyor: $postId');

      final response = await _supabase
          .from('post_views')
          .select('''
            viewed_at,
            viewer_id,
            profiles:viewer_id (
              id,
              username,
              full_name,
              avatar_url
            )
          ''')
          .eq('post_id', postId)
          .not('viewer_id', 'is', null)
          .order('viewed_at', ascending: false)
          .limit(limit);

      debugPrint('✅ ${response.length} görüntüleyici alındı');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Post görüntüleyicileri alınamadı: $e');
      return [];
    }
  }

  /// Belirli bir postun toplam görüntüleme sayısı
  Future<int> getPostViewCount(String postId) async {
    try {
      final response = await _supabase
          .from('post_views')
          .select('id')
          .eq('post_id', postId);

      final count = (response as List).length;
      debugPrint('📊 Post $postId toplam görüntüleme: $count');
      return count;
    } catch (e) {
      debugPrint('❌ Post görüntüleme sayısı alınamadı: $e');
      return 0;
    }
  }

  /// Belirli bir postun benzersiz görüntüleyici sayısı
  Future<int> getPostUniqueViewers(String postId) async {
    try {
      final response = await _supabase
          .from('post_views')
          .select('viewer_id')
          .eq('post_id', postId)
          .not('viewer_id', 'is', null);

      // Benzersiz viewer_id'leri say
      final uniqueViewers = (response as List)
          .map((item) => item['viewer_id'])
          .toSet()
          .length;

      debugPrint('📊 Post $postId benzersiz görüntüleyici: $uniqueViewers');
      return uniqueViewers;
    } catch (e) {
      debugPrint('❌ Post benzersiz görüntüleyici sayısı alınamadı: $e');
      return 0;
    }
  }

  /// Kullanıcının en çok görüntülenen postları
  Future<List<Map<String, dynamic>>> getUserTopPosts({
    required String userId,
    int limit = 10,
  }) async {
    try {
      debugPrint('🏆 Kullanıcının en çok görüntülenen $limit postu getiriliyor: $userId');

      final response = await _supabase.rpc(
        'get_user_top_posts_by_views',
        params: {
          'p_user_id': userId,
          'p_limit': limit,
        },
      );

      if (response is List) {
        debugPrint('✅ ${response.length} top post alındı');
        return List<Map<String, dynamic>>.from(response);
      }

      return [];
    } catch (e) {
      // Fonksiyon yoksa normal sorgu ile al
      debugPrint('⚠️ RPC fonksiyonu bulunamadı, normal sorgu kullanılıyor: $e');
      
      try {
        final posts = await _supabase
            .from('posts')
            .select('*')
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(limit);

        return List<Map<String, dynamic>>.from(posts);
      } catch (e2) {
        debugPrint('❌ Top postlar alınamadı: $e2');
        return [];
      }
    }
  }
}
