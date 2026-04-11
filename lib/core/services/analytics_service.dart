import 'package:hive/hive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/app_logger.dart';

/// Analytics veri modeli - Basit sınıf (Hive annotation olmadan)
class AnalyticsEvent {
  final String eventType; // 'post_view', 'like', 'comment', 'share', 'error'
  final String? entityId; // post_id, user_id vb
  final DateTime timestamp;
  final Map<String, dynamic>? metadata; // Ekstra bilgiler
  final int? duration; // ms cinsinden (post view süresi vb)

  AnalyticsEvent({
    required this.eventType,
    this.entityId,
    required this.timestamp,
    this.metadata,
    this.duration,
  });

  // JSON serialization
  Map<String, dynamic> toJson() => {
    'eventType': eventType,
    'entityId': entityId,
    'timestamp': timestamp.toIso8601String(),
    'metadata': metadata,
    'duration': duration,
  };

  factory AnalyticsEvent.fromJson(Map<String, dynamic> json) => AnalyticsEvent(
    eventType: json['eventType'] as String,
    entityId: json['entityId'] as String?,
    timestamp: DateTime.parse(json['timestamp'] as String),
    metadata: json['metadata'] as Map<String, dynamic>?,
    duration: json['duration'] as int?,
  );
}

/// Analytics servis - Kullanıcı davranışlarını takip eder
class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  static const String _boxName = 'analytics_events';
  static Box? _box; // Generic Box (AnalyticsEvent olmadan) - nullable

  /// Analytics servisini başlat
  static Future<void> initialize() async {
    // Web'de Hive kullanmıyoruz - IndexedDB problemi
    if (kIsWeb) {
      AppLogger.info('ℹ️ Analytics service skipped on web platform');
      return;
    }

    try {
      _box = await Hive.openBox(_boxName);
      AppLogger.info('📊 Analytics service initialized');
    } catch (e) {
      AppLogger.error('Analytics initialization error: $e');
      _box = null;
    }
  }

  /// Event kaydet
  Future<void> trackEvent({
    required String eventType,
    String? entityId,
    Map<String, dynamic>? metadata,
    int? duration,
  }) async {
    if (_box == null) return;
    try {
      final event = AnalyticsEvent(
        eventType: eventType,
        entityId: entityId,
        timestamp: DateTime.now(),
        metadata: metadata,
        duration: duration,
      );
      await _box!.add(event.toJson()); // JSON olarak kaydet
      AppLogger.debug('📊 Event tracked: $eventType');
    } catch (e) {
      AppLogger.error('Track event error: $e');
    }
  }

  /// Box'tan event'leri AnalyticsEvent'e dönüştür
  List<AnalyticsEvent> _getEvents() {
    if (_box == null) return [];
    try {
      return _box!.values
          .map((e) => AnalyticsEvent.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      AppLogger.error('Get events error: $e');
      return [];
    }
  }

  /// Post görüntülenme
  Future<void> trackPostView(String postId, {int? duration}) =>
      trackEvent(eventType: 'post_view', entityId: postId, duration: duration);

  /// Post beğeni
  Future<void> trackPostLike(String postId) =>
      trackEvent(eventType: 'like', entityId: postId);

  /// Yorum
  Future<void> trackComment(String postId) =>
      trackEvent(eventType: 'comment', entityId: postId);

  /// Paylaş
  Future<void> trackShare(String postId) =>
      trackEvent(eventType: 'share', entityId: postId);

  /// Hata kaydet
  Future<void> trackError(String errorType, {String? details}) =>
      trackEvent(
        eventType: 'error',
        metadata: {'type': errorType, 'details': details},
      );

  /// En çok görüntülenen postlar
  Map<String, int> getMostViewedPosts({int limit = 10}) {
    try {
      final events = _getEvents();
      final viewEvents = events
          .where((e) => e.eventType == 'post_view' && e.entityId != null)
          .toList();

      final counts = <String, int>{};
      for (var event in viewEvents) {
        counts[event.entityId!] = (counts[event.entityId!] ?? 0) + 1;
      }

      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return Map<String, int>.fromEntries(
        sorted.take(limit),
      );
    } catch (e) {
      AppLogger.error('Get most viewed posts error: $e');
      return {};
    }
  }

  /// Engagement metrikleri
  Map<String, int> getEngagementMetrics() {
    try {
      final events = _getEvents();
      final metrics = <String, int>{
        'views': 0,
        'likes': 0,
        'comments': 0,
        'shares': 0,
        'errors': 0,
      };

      for (var event in events) {
        switch (event.eventType) {
          case 'post_view':
            metrics['views'] = metrics['views']! + 1;
            break;
          case 'like':
            metrics['likes'] = metrics['likes']! + 1;
            break;
          case 'comment':
            metrics['comments'] = metrics['comments']! + 1;
            break;
          case 'share':
            metrics['shares'] = metrics['shares']! + 1;
            break;
          case 'error':
            metrics['errors'] = metrics['errors']! + 1;
            break;
        }
      }

      return metrics;
    } catch (e) {
      AppLogger.error('Get engagement metrics error: $e');
      return {};
    }
  }

  /// Saatlik etkinlik dağılımı
  Map<int, int> getHourlyDistribution() {
    try {
      final events = _getEvents();
      final distribution = <int, int>{};

      for (var event in events) {
        final hour = event.timestamp.hour;
        distribution[hour] = (distribution[hour] ?? 0) + 1;
      }

      return distribution;
    } catch (e) {
      AppLogger.error('Get hourly distribution error: $e');
      return {};
    }
  }

  /// Ortalama post görüntüleme süresi (ms)
  int getAveragePostViewDuration() {
    try {
      final events = _getEvents();
      final viewEvents = events
          .where((e) => e.eventType == 'post_view' && e.duration != null)
          .toList();

      if (viewEvents.isEmpty) return 0;

      final totalDuration =
          viewEvents.fold<int>(0, (sum, e) => sum + (e.duration!));
      return (totalDuration / viewEvents.length).round();
    } catch (e) {
      AppLogger.error('Get average post view duration error: $e');
      return 0;
    }
  }

  /// Son 7 günün etkinlikleri
  List<AnalyticsEvent> getLastSevenDaysEvents() {
    try {
      final events = _getEvents();
      final sevenDaysAgo =
          DateTime.now().subtract(const Duration(days: 7));
      return events
          .where((e) => e.timestamp.isAfter(sevenDaysAgo))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (e) {
      AppLogger.error('Get last 7 days events error: $e');
      return [];
    }
  }

  /// Hataları getir
  List<AnalyticsEvent> getErrors({int limit = 50}) {
    try {
      final events = _getEvents();
      final errors = events
          .where((e) => e.eventType == 'error')
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      return errors.take(limit).toList();
    } catch (e) {
      AppLogger.error('Get errors error: $e');
      return [];
    }
  }

  /// Eski veriler temizle (30 günden eski)
  Future<void> clearOldEvents({int daysToKeep = 30}) async {
    if (_box == null) return;
    try {
      final cutoffDate =
          DateTime.now().subtract(Duration(days: daysToKeep));
      final keysToDelete = <int>[];

      for (var i = 0; i < _box!.length; i++) {
        final event = _box!.getAt(i);
        if (event != null) {
          try {
            final analyticsEvent = AnalyticsEvent.fromJson(
              Map<String, dynamic>.from(event as Map)
            );
            if (analyticsEvent.timestamp.isBefore(cutoffDate)) {
              keysToDelete.add(i);
            }
          } catch (e) {
            // Geçersiz veri, sil
            keysToDelete.add(i);
          }
        }
      }

      for (var key in keysToDelete.reversed) {
        await _box!.deleteAt(key);
      }

      AppLogger.debug(
          '🧹 Cleared ${keysToDelete.length} old analytics events');
    } catch (e) {
      AppLogger.error('Clear old events error: $e');
    }
  }

  /// Tüm veriler temizle
  Future<void> clearAllEvents() async {
    if (_box == null) return;
    try {
      await _box!.clear();
      AppLogger.info('🧹 All analytics events cleared');
    } catch (e) {
      AppLogger.error('Clear all events error: $e');
    }
  }

  /// Toplam event sayısı
  int get eventCount => _box?.length ?? 0;
}
