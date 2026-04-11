import '../utils/app_logger.dart';
import 'cache_service.dart';
import 'analytics_service.dart';

/// Otomatik temizleme servisi
/// Uygulama başlangıcında eski cache ve analytics verilerini temizler
class CleanupService {
  static final CleanupService _instance = CleanupService._internal();
  factory CleanupService() => _instance;
  CleanupService._internal();

  final CacheService _cacheService = CacheService();
  final AnalyticsService _analyticsService = AnalyticsService();

  /// Uygulama başlangıcında otomatik temizleme
  Future<void> performStartupCleanup() async {
    try {
      AppLogger.info('🧹 Starting auto-cleanup...');

      // Paralel olarak çalıştır
      await Future.wait([
        _cleanupExpiredCache(),
        _cleanupOldAnalytics(),
      ]);

      AppLogger.info('✅ Auto-cleanup completed');
    } catch (e) {
      AppLogger.error('❌ Auto-cleanup error: $e');
    }
  }

  /// Süresi dolan cache'leri temizle
  Future<void> _cleanupExpiredCache() async {
    try {
      final sizeBefore = _cacheService.cacheSize;
      await _cacheService.clearExpiredPosts();
      final sizeAfter = _cacheService.cacheSize;
      final cleaned = sizeBefore - sizeAfter;

      if (cleaned > 0) {
        AppLogger.info('🗑️ Cleaned $cleaned expired cache entries');
      }
    } catch (e) {
      AppLogger.error('Cache cleanup error: $e');
    }
  }

  /// 30 günden eski analytics verilerini temizle
  Future<void> _cleanupOldAnalytics() async {
    try {
      final sizeBefore = _analyticsService.eventCount;
      await _analyticsService.clearOldEvents(daysToKeep: 30);
      final sizeAfter = _analyticsService.eventCount;
      final cleaned = sizeBefore - sizeAfter;

      if (cleaned > 0) {
        AppLogger.info('🗑️ Cleaned $cleaned old analytics events');
      }
    } catch (e) {
      AppLogger.error('Analytics cleanup error: $e');
    }
  }

  /// Manuel temizleme - Tümünü sil
  Future<void> clearAllData() async {
    try {
      AppLogger.info('🧹 Clearing all cached data...');

      await Future.wait([
        _cacheService.clearCache(),
        _analyticsService.clearAllEvents(),
      ]);

      AppLogger.info('✅ All data cleared');
    } catch (e) {
      AppLogger.error('Clear all data error: $e');
      rethrow;
    }
  }

  /// Cache temizle
  Future<void> clearCache() async {
    try {
      await _cacheService.clearCache();
      AppLogger.info('✅ Cache cleared');
    } catch (e) {
      AppLogger.error('Clear cache error: $e');
      rethrow;
    }
  }

  /// Analytics temizle
  Future<void> clearAnalytics() async {
    try {
      await _analyticsService.clearAllEvents();
      AppLogger.info('✅ Analytics cleared');
    } catch (e) {
      AppLogger.error('Clear analytics error: $e');
      rethrow;
    }
  }

  /// Storage durumu
  Map<String, int> getStorageStats() {
    return {
      'cache_size': _cacheService.cacheSize,
      'analytics_count': _analyticsService.eventCount,
    };
  }
}
