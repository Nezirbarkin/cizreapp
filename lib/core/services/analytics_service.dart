import 'package:hive/hive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
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

  factory AnalyticsEvent.fromJson(Map<String, dynamic> json) {
    // Hive'dan dönen metadata _Map<dynamic, dynamic> olabilir, güvenli çevir
    Map<String, dynamic>? meta;
    final rawMeta = json['metadata'];
    if (rawMeta is Map) {
      meta = rawMeta.map((k, v) => MapEntry(k.toString(), v));
    }
    return AnalyticsEvent(
      eventType: json['eventType'] as String,
      entityId: json['entityId'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      metadata: meta,
      duration: json['duration'] as int?,
    );
  }
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
    final event = AnalyticsEvent(
      eventType: eventType,
      entityId: entityId,
      timestamp: DateTime.now(),
      metadata: metadata,
      duration: duration,
    );

    // Merkezi kayıt gerçek admin verisinin kaynağıdır. Yerel Hive yalnızca
    // çevrimdışı/geriye dönük cihaz içi analitik için tutulur.
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId != null) {
        await client.from('app_analytics_events').insert({
          'user_id': userId,
          'event_type': eventType,
          'entity_id': entityId,
          'metadata': metadata ?? <String, dynamic>{},
          'duration_ms': duration,
        });
      }
    } catch (e) {
      AppLogger.error('Remote analytics event error: $e');
    }

    if (_box != null) {
      try {
        await _box!.add(event.toJson());
      } catch (e) {
        AppLogger.error('Local analytics event error: $e');
      }
    }
    AppLogger.debug('📊 Event tracked: $eventType');
  }

  /// Box'tan event'leri AnalyticsEvent'e dönüştür
  List<AnalyticsEvent> _getEvents() {
    if (_box == null) return [];
    final out = <AnalyticsEvent>[];
    for (final raw in _box!.values) {
      try {
        // Hive generic Box döndürdüğü için dış map dynamic key olabilir
        final m = Map<String, dynamic>.from(raw as Map);
        out.add(AnalyticsEvent.fromJson(m));
      } catch (e) {
        // Tek bir bozuk kayıt tüm listeyi yutmasın
        AppLogger.error('Skip malformed analytics event: $e');
      }
    }
    return out;
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
  Future<void> trackError(String errorType, {String? details}) => trackEvent(
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

      return Map<String, int>.fromEntries(sorted.take(limit));
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

      final totalDuration = viewEvents.fold<int>(
        0,
        (sum, e) => sum + (e.duration!),
      );
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
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      return events.where((e) => e.timestamp.isAfter(sevenDaysAgo)).toList()
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
      final errors = events.where((e) => e.eventType == 'error').toList()
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
      final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));
      final keysToDelete = <int>[];

      for (var i = 0; i < _box!.length; i++) {
        final event = _box!.getAt(i);
        if (event != null) {
          try {
            final analyticsEvent = AnalyticsEvent.fromJson(
              Map<String, dynamic>.from(event as Map),
            );
            if (analyticsEvent.timestamp.isBefore(cutoffDate)) {
              keysToDelete.add(i);
            }
          } catch (e) {
            // Geçersiz veri, sil
            AppLogger.error(
              'Skip malformed analytics event during cleanup: $e',
            );
            keysToDelete.add(i);
          }
        }
      }

      for (var key in keysToDelete.reversed) {
        await _box!.deleteAt(key);
      }

      AppLogger.debug('🧹 Cleared ${keysToDelete.length} old analytics events');
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
