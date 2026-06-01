import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/achievement_model.dart';

/// Başarımlar servisi - Kullanıcı başarımlarını, seviyelerini ve rozetlerini yönetir
class AchievementService {
  static const String _tableName = 'user_achievements';
  static const String _achievementsTableName = 'achievements';

  /// Supabase client'ı güvenli şekilde al
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      rethrow;
    }
  }

  /// Tüm mevcut başarımları getir
  Future<List<Achievement>> getAllAchievements() async {
    try {
      final response = await _supabase
          .from(_achievementsTableName)
          .select()
          .order('required_count', ascending: true);

      return (response as List)
          .map((json) => Achievement.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('❌ Başarımlar yüklenirken hata: $e');
      return _getDefaultAchievements();
    }
  }

  /// Kullanıcının başarımlarını getir
  Future<UserAchievements?> getUserAchievements(String userId) async {
    try {
      // Önce kullanıcının achievement kaydını getir
      final userAchievementResponse = await _supabase
          .from(_tableName)
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      // Tüm başarımları getir
      final allAchievements = await getAllAchievements();

      // Kullanıcının açtığı başarımları getir
      final unlockedResponse = await _supabase
          .from('user_unlocked_achievements')
          .select()
          .eq('user_id', userId);

      final unlockedIds = (unlockedResponse as List)
          .map((json) => json['achievement_id'] as String)
          .toSet();

      // Kullanıcının istatistiklerini getir
      final stats = await _getUserStats(userId);

      // Başarımları ilerleme durumlarıyla güncelle
      final achievementsWithProgress = allAchievements.map((achievement) {
        final isUnlocked = unlockedIds.contains(achievement.id);
        final currentCount = _getCurrentCount(achievement.type, stats);
        return achievement.copyWith(
          currentCount: currentCount,
          isUnlocked: isUnlocked,
        );
      }).toList();

      return UserAchievements(
        userId: userId,
        totalXp: userAchievementResponse?['total_xp'] as int? ?? 0,
        level: userAchievementResponse?['level'] as int? ?? 1,
        streakDays: userAchievementResponse?['streak_days'] as int? ?? 0,
        lastLoginDate: userAchievementResponse?['last_login_date'] != null
            ? DateTime.parse(userAchievementResponse!['last_login_date'])
            : null,
        achievements: achievementsWithProgress,
        stats: stats,
      );
    } catch (e) {
      debugPrint('❌ Kullanıcı başarımları yüklenirken hata: $e');
      return null;
    }
  }

  /// Kullanıcı istatistiklerini getir
  Future<Map<String, int>> _getUserStats(String userId) async {
    final stats = <String, int>{};

    try {
      // Sipariş sayısı
      final ordersCount = await _supabase
          .from('orders')
          .select('id')
          .eq('user_id', userId)
          .count();
      stats['orders'] = ordersCount.count;

      // Değerlendirme sayısı
      final reviewsCount = await _supabase
          .from('product_reviews')
          .select('id')
          .eq('user_id', userId)
          .count();
      stats['reviews'] = reviewsCount.count;

      // Takipçi sayısı
      final followersCount = await _supabase
          .from('follows')
          .select('id')
          .eq('following_id', userId)
          .count();
      stats['followers'] = followersCount.count;

      // Gönderi sayısı
      final postsCount = await _supabase
          .from('posts')
          .select('id')
          .eq('user_id', userId)
          .eq('is_active', true)
          .count();
      stats['posts'] = postsCount.count;

      // Farklı mağazalardan alışveriş sayısı
      final distinctShops = await _supabase
          .from('orders')
          .select('shop_id')
          .eq('user_id', userId);
      stats['distinct_shops'] = distinctShops.map((o) => o['shop_id']).toSet().length;

      // Toplam harcama
      final orders = await _supabase
          .from('orders')
          .select('total_amount')
          .eq('user_id', userId)
          .eq('status', 'delivered');
      double totalSpent = 0;
      for (var order in orders) {
        totalSpent += (order['total_amount'] as num?)?.toDouble() ?? 0;
      }
      stats['total_spent'] = totalSpent.round();

    } catch (e) {
      debugPrint('❌ Kullanıcı istatistikleri yüklenirken hata: $e');
    }

    return stats;
  }

  /// Başarım türüne göre mevcut sayıyı getir
  int _getCurrentCount(AchievementType type, Map<String, int> stats) {
    switch (type) {
      case AchievementType.firstOrder:
      case AchievementType.loyalCustomer:
      case AchievementType.superCustomer:
        return stats['orders'] ?? 0;
      case AchievementType.reviewer:
      case AchievementType.topReviewer:
        return stats['reviews'] ?? 0;
      case AchievementType.popular:
        return stats['followers'] ?? 0;
      case AchievementType.socializer:
        return stats['posts'] ?? 0;
      case AchievementType.bigSpender:
        return stats['total_spent'] ?? 0;
      case AchievementType.explorer:
        return stats['distinct_shops'] ?? 0;
      default:
        return 0;
    }
  }

  /// Başarım kontrolü ve açıldıysa XP verme
  Future<List<Achievement>> checkAndUnlockAchievements(String userId) async {
    final unlockedAchievements = <Achievement>[];

    try {
      final stats = await _getUserStats(userId);
      final allAchievements = await getAllAchievements();

      for (var achievement in allAchievements) {
        final currentCount = _getCurrentCount(achievement.type, stats);

        if (currentCount >= achievement.requiredCount && !achievement.isUnlocked) {
          // Başarımı aç
          await _unlockAchievement(userId, achievement.id, achievement.xpReward);
          unlockedAchievements.add(achievement.copyWith(
            currentCount: currentCount,
            isUnlocked: true,
          ));

          debugPrint('🏆 Başarım açıldı: ${achievement.title} (+${achievement.xpReward} XP)');
        }
      }

      // Günlük giriş streak kontrolü
      await _checkDailyStreak(userId);

    } catch (e) {
      debugPrint('❌ Başarım kontrolü hatası: $e');
    }

    return unlockedAchievements;
  }

  /// Başarımı aç ve XP ver
  Future<void> _unlockAchievement(String userId, String achievementId, int xpReward) async {
    try {
      // Başarımı aç
      await _supabase.from('user_unlocked_achievements').insert({
        'user_id': userId,
        'achievement_id': achievementId,
        'unlocked_at': DateTime.now().toIso8601String(),
      });

      // XP ekle
      await _supabase.rpc(
        'add_user_xp',
        params: {'p_user_id': userId, 'p_xp': xpReward},
      );
    } catch (e) {
      debugPrint('❌ Başarım açma hatası: $e');
    }
  }

  /// Günlük giriş streak kontrolü
  Future<void> _checkDailyStreak(String userId) async {
    try {
      final achievements = await getUserAchievements(userId);
      if (achievements == null) return;

      final now = DateTime.now();
      final lastLogin = achievements.lastLoginDate;

      int newStreak = achievements.streakDays;

      if (lastLogin != null) {
        final difference = now.difference(lastLogin).inDays;

        if (difference == 1) {
          // Ardışık gün
          newStreak++;
        } else if (difference > 1) {
          // Streak bozuldu
          newStreak = 1;
        }
        // Aynı gün - değişiklik yok
      } else {
        newStreak = 1;
      }

      // Veritabanını güncelle
      await _supabase.from(_tableName).upsert({
        'user_id': userId,
        'streak_days': newStreak,
        'last_login_date': now.toIso8601String(),
      });

      // Streak başarımlarını kontrol et
      if (newStreak >= 7) {
        // Haftalık streak başarımı
        await _checkAndUnlockWeeklyStreak(userId, newStreak);
      }
      if (newStreak >= 30) {
        // Aylık streak başarımı
        await _checkAndUnlockMonthlyStreak(userId, newStreak);
      }
    } catch (e) {
      debugPrint('❌ Streak kontrolü hatası: $e');
    }
  }

  /// Haftalık streak başarımı kontrolü
  Future<void> _checkAndUnlockWeeklyStreak(String userId, int streakDays) async {
    try {
      final achievement = await _supabase
          .from(_achievementsTableName)
          .select()
          .eq('type', 'weeklyStreak')
          .single();

      final alreadyUnlocked = await _supabase
          .from('user_unlocked_achievements')
          .select()
          .eq('user_id', userId)
          .eq('achievement_id', achievement['id'])
          .maybeSingle();

      if (alreadyUnlocked == null) {
        await _unlockAchievement(userId, achievement['id'], achievement['xp_reward'] ?? 50);
      }
    } catch (e) {
      debugPrint('❌ Haftalık streak başarımı kontrolü hatası: $e');
    }
  }

  /// Aylık streak başarımı kontrolü
  Future<void> _checkAndUnlockMonthlyStreak(String userId, int streakDays) async {
    try {
      final achievement = await _supabase
          .from(_achievementsTableName)
          .select()
          .eq('type', 'monthlyStreak')
          .single();

      final alreadyUnlocked = await _supabase
          .from('user_unlocked_achievements')
          .select()
          .eq('user_id', userId)
          .eq('achievement_id', achievement['id'])
          .maybeSingle();

      if (alreadyUnlocked == null) {
        await _unlockAchievement(userId, achievement['id'], achievement['xp_reward'] ?? 200);
      }
    } catch (e) {
      debugPrint('❌ Aylık streak başarımı kontrolü hatası: $e');
    }
  }

  /// Sipariş sonrası başarım kontrolü
  Future<void> onOrderCompleted(String userId) async {
    await checkAndUnlockAchievements(userId);
  }

  /// Değerlendirme sonrası başarım kontrolü
  Future<void> onReviewAdded(String userId) async {
    await checkAndUnlockAchievements(userId);
  }

  /// Gönderi paylaşımı sonrası başarım kontrolü
  Future<void> onPostShared(String userId) async {
    await checkAndUnlockAchievements(userId);
  }

  /// Yeni takipçi sonrası başarım kontrolü
  Future<void> onNewFollower(String userId) async {
    await checkAndUnlockAchievements(userId);
  }

  /// Varsayılan başarımlar (veritabanında yoksa)
  List<Achievement> _getDefaultAchievements() {
    return [
      Achievement(
        id: 'first_order',
        type: AchievementType.firstOrder,
        title: 'İlk Sipariş',
        description: 'İlk siparişinizi tamamlayın',
        iconName: 'shopping_bag',
        requiredCount: 1,
        xpReward: 10,
      ),
      Achievement(
        id: 'loyal_customer',
        type: AchievementType.loyalCustomer,
        title: 'Sadık Müşteri',
        description: '10 sipariş tamamlayın',
        iconName: 'star',
        requiredCount: 10,
        xpReward: 100,
      ),
      Achievement(
        id: 'super_customer',
        type: AchievementType.superCustomer,
        title: 'Süper Müşteri',
        description: '50 sipariş tamamlayın',
        iconName: 'workspace_premium',
        requiredCount: 50,
        xpReward: 500,
      ),
      Achievement(
        id: 'first_review',
        type: AchievementType.reviewer,
        title: 'İlk Değerlendirme',
        description: 'İlk ürün değerlendirmenizi yapın',
        iconName: 'star',
        requiredCount: 1,
        xpReward: 5,
      ),
      Achievement(
        id: 'top_reviewer',
        type: AchievementType.topReviewer,
        title: 'Üstün Değerlendiren',
        description: '10 ürün değerlendirin',
        iconName: 'military_tech',
        requiredCount: 10,
        xpReward: 50,
      ),
      Achievement(
        id: 'socializer',
        type: AchievementType.socializer,
        title: 'Sosyal İnsan',
        description: 'İlk gönderinizi paylaşın',
        iconName: 'celebration',
        requiredCount: 1,
        xpReward: 15,
      ),
      Achievement(
        id: 'popular',
        type: AchievementType.popular,
        title: 'Popüler',
        description: '100 takipçi kazanın',
        iconName: 'local_fire_department',
        requiredCount: 100,
        xpReward: 200,
      ),
      Achievement(
        id: 'weekly_streak',
        type: AchievementType.weeklyStreak,
        title: 'Haftalık Streak',
        description: '7 gün üst üste giriş yapın',
        iconName: 'bolt',
        requiredCount: 7,
        xpReward: 50,
      ),
      Achievement(
        id: 'monthly_streak',
        type: AchievementType.monthlyStreak,
        title: 'Aylık Streak',
        description: '30 gün üst üste giriş yapın',
        iconName: 'diamond',
        requiredCount: 30,
        xpReward: 200,
      ),
      Achievement(
        id: 'big_spender',
        type: AchievementType.bigSpender,
        title: 'Büyük Harcayıcı',
        description: '1000₺ harcama yapın',
        iconName: 'restaurant',
        requiredCount: 1000,
        xpReward: 100,
      ),
      Achievement(
        id: 'explorer',
        type: AchievementType.explorer,
        title: 'Kaşif',
        description: '10 farklı mağazadan alışveriş yapın',
        iconName: 'explore',
        requiredCount: 10,
        xpReward: 75,
      ),
    ];
  }
}