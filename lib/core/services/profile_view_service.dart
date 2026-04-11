import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/analytics_model.dart';

/// Profil ziyaret takip servisi
/// Her kullanıcının profilini kimlerin ziyaret ettiğini ve aylık istatistiklerini takip eder
class ProfileViewService {
  final _supabase = Supabase.instance.client;

  /// Profil ziyareti kaydet (günde 1 kez sayılır)
  /// [profileId] - Ziyaret edilen profil
  /// Viewer ID otomatik olarak auth.uid() ile alınır
  Future<void> trackProfileView({
    required String profileId,
  }) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      
      if (currentUserId == null) {
        debugPrint('⚠️ Kullanıcı giriş yapmamış - profil ziyareti kaydedilemedi');
        return;
      }

      // Kendi profilini ziyaret edenleri kaydetme
      if (currentUserId == profileId) {
        debugPrint('👤 Kendi profilini ziyaret - kaydedilmedi');
        return;
      }

      debugPrint('📊 Profil ziyareti kaydediliyor: $profileId <- $currentUserId');

      // RPC fonksiyonunu çağır (viewer_id otomatik auth.uid() ile alınır)
      await _supabase.rpc(
        'track_profile_view',
        params: {
          'p_profile_id': profileId,
        },
      );

      debugPrint('✅ Profil ziyareti kaydedildi');
    } catch (e) {
      debugPrint('❌ Profil ziyareti kaydedilemedi: $e');
    }
  }

  /// Mevcut ayın profil ziyaret istatistiklerini getir
  Future<CurrentMonthViewStats?> getCurrentMonthStats(String profileId) async {
    try {
      debugPrint('📊 Aylık profil istatistikleri getiriliyor: $profileId');

      final response = await _supabase.rpc(
        'get_profile_current_month_views',
        params: {'p_profile_id': profileId},
      ) as List;

      if (response.isEmpty) {
        return CurrentMonthViewStats(totalViews: 0, uniqueViewers: 0);
      }

      final data = response.first as Map<String, dynamic>;
      final stats = CurrentMonthViewStats.fromJson(data);
      
      debugPrint('✅ Aylık istatistikler: ${stats.totalViews} görüntüleme, ${stats.uniqueViewers} benzersiz');
      return stats;
    } catch (e) {
      debugPrint('❌ Aylık istatistikler alınamadı: $e');
      return null;
    }
  }

  /// Aylık profil ziyaret geçmişini getir
  /// [profileId] - İstatistikler alınacak profil
  /// [months] - Kaç aylık geçmiş (varsayılan: 6)
  Future<List<MonthlyViewStats>> getMonthlyHistory({
    required String profileId,
    int months = 6,
  }) async {
    try {
      debugPrint('📊 $months aylık profil geçmişi getiriliyor: $profileId');

      final response = await _supabase.rpc(
        'get_profile_monthly_stats',
        params: {
          'p_profile_id': profileId,
          'p_months': months,
        },
      ) as List;

      final history = response
          .map((item) => MonthlyViewStats.fromJson(item as Map<String, dynamic>))
          .toList();

      debugPrint('✅ ${history.length} aylık geçmiş alındı');
      return history;
    } catch (e) {
      debugPrint('❌ Aylık geçmiş alınamadı: $e');
      return [];
    }
  }

  /// Tam analytics özeti (şu an + geçmiş)
  Future<AnalyticsSummary?> getAnalyticsSummary({
    required String profileId,
    int months = 6,
  }) async {
    try {
      debugPrint('📊 Analytics özeti hazırlanıyor: $profileId');

      final currentMonth = await getCurrentMonthStats(profileId);
      final monthlyHistory = await getMonthlyHistory(
        profileId: profileId,
        months: months,
      );

      if (currentMonth == null) {
        return null;
      }

      // Toplam görüntüleme ve ortalama hesapla
      int totalViews = monthlyHistory.fold(0, (sum, stat) => sum + stat.viewCount);
      double averageViews = monthlyHistory.isEmpty ? 0 : totalViews / monthlyHistory.length;

      final summary = AnalyticsSummary(
        title: 'Profil Ziyaretleri',
        currentMonthViews: currentMonth.totalViews,
        currentMonthUniqueViewers: currentMonth.uniqueViewers,
        monthlyHistory: monthlyHistory,
        averageViewsPerMonth: averageViews,
        totalViews: totalViews,
      );

      debugPrint('✅ Analytics özeti hazırlandı: ${summary.totalViews} toplam görüntüleme');
      return summary;
    } catch (e) {
      debugPrint('❌ Analytics özeti hazırlanamadı: $e');
      return null;
    }
  }

  /// Profili kim ziyaret etti (son N kişi)
  Future<List<Map<String, dynamic>>> getRecentViewers({
    required String profileId,
    int limit = 10,
  }) async {
    try {
      debugPrint('👥 Son $limit ziyaretçi getiriliyor: $profileId');

      final response = await _supabase
          .from('profile_views')
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
          .eq('profile_id', profileId)
          .not('viewer_id', 'is', null)
          .order('viewed_at', ascending: false)
          .limit(limit);

      debugPrint('✅ ${response.length} ziyaretçi alındı');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Ziyaretçiler alınamadı: $e');
      return [];
    }
  }

  /// Belirli bir kullanıcının profil ziyaret geçmişi
  Future<List<Map<String, dynamic>>> getViewingHistory({
    required String viewerId,
    int limit = 20,
  }) async {
    try {
      debugPrint('👀 Kullanıcının ziyaret geçmişi getiriliyor: $viewerId');

      final response = await _supabase
          .from('profile_views')
          .select('''
            viewed_at,
            profile_id,
            profiles:profile_id (
              id,
              username,
              full_name,
              avatar_url
            )
          ''')
          .eq('viewer_id', viewerId)
          .order('viewed_at', ascending: false)
          .limit(limit);

      debugPrint('✅ ${response.length} ziyaret kaydı alındı');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Ziyaret geçmişi alınamadı: $e');
      return [];
    }
  }
}
