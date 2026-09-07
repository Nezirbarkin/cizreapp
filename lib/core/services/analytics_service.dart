import 'dart:async';

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

  // --- Hata akisi korumalari ---------------------------------------------
  // AppLogger.error uygulamanin her yerinden cagriliyor. Kancayi filtresiz
  // baglarsak (a) tek bir dongusel hata tabloyu doldurur, (b) merkezi yazimin
  // kendi hatasi tekrar AppLogger.error'a dusup sonsuz dongu yapar.
  static const Duration _errorDedupeWindow = Duration(minutes: 5);
  static const int _maxErrorEventsPerRun = 50;
  final Map<String, DateTime> _recentErrorKeys = {};
  int _errorEventsThisRun = 0;
  bool _errorSinkBusy = false;

  /// AppLogger.error/fatal cagrilarini merkezi analitige baglar.
  /// `main.dart` icinde, Supabase hazir olduktan sonra bir kez cagrilir.
  static void attachToLogger() {
    final instance = AnalyticsService();
    AppLogger.errorSink = instance._onLoggedError;
  }

  void _onLoggedError(
    String message,
    String? details,
    StackTrace? stackTrace,
    String? diagnostics,
  ) {
    // Merkezi yazim sirasinda olusan hatanin kendisini tekrar yazmaya
    // calismamak icin re-entrancy kilidi.
    if (_errorSinkBusy) return;
    if (_errorEventsThisRun >= _maxErrorEventsPerRun) return;

    final type = _normalizeErrorType(message);
    final origin = _extractOrigin(stackTrace, diagnostics);
    // Ayni mesajin farkli ekranlardan gelen kopyalari ayri kayitlar olmali;
    // aksi halde ilk ekran 5 dakika boyunca digerlerini bastirirdi.
    final key = '$type|${_truncate(details ?? '', 120)}|${origin ?? ''}';
    final now = DateTime.now();
    final lastSeen = _recentErrorKeys[key];
    if (lastSeen != null && now.difference(lastSeen) < _errorDedupeWindow) {
      return;
    }
    _recentErrorKeys[key] = now;
    if (_recentErrorKeys.length > 200) {
      _recentErrorKeys.removeWhere(
        (_, seenAt) => now.difference(seenAt) >= _errorDedupeWindow,
      );
    }
    _errorEventsThisRun++;

    _errorSinkBusy = true;
    // Loglama cagrisini bloklamamak icin bekletmiyoruz.
    unawaited(
      trackError(type, details: details, origin: origin).whenComplete(() {
        _errorSinkBusy = false;
      }),
    );
  }

  /// Hatanin kaynagini `dosya.dart:satir` olarak cikarir.
  ///
  /// Iki kaynak taranir: (1) yigin izi — uygulama kareleri
  /// `package:cizreapp/...dart:12:34` bicimindedir; (2) `FlutterErrorDetails`
  /// metni — layout hatalarinda ("RenderFlex overflowed", "Incorrect use of
  /// ParentDataWidget") yigin izi tamamen framework icindedir, ama tani metni
  /// hatayi ureten widget'in kaynak konumunu `file:///.../lib/...dart:12:34`
  /// olarak tasir. Uygulama koduna ait ILK kare kazanir.
  static String? _extractOrigin(StackTrace? stackTrace, String? diagnostics) {
    for (final source in <String?>[stackTrace?.toString(), diagnostics]) {
      if (source == null || source.isEmpty) continue;
      for (final match in _appFramePattern.allMatches(source)) {
        final path = match.group(1)!;
        // Gomulu SDK yollari (.../flutter/packages/flutter/lib/src/...) da
        // '/lib/' iceriyor; bunlar hatanin kaynagi degil.
        if (path.startsWith('src/')) continue;
        return _truncate('$path:${match.group(2)}', 120);
      }
    }
    return null;
  }

  static final RegExp _appFramePattern = RegExp(
    r'(?:package:cizreapp/|/lib/)([\w/]+\.dart):(\d+)',
  );

  /// Log mesajindan gruplanabilir bir hata tipi uretir.
  ///
  /// Ham mesaj ("❌ Feed loading error: SocketException(...)") tipe cevrilmezse
  /// `errorTypeCounts` her satiri ayri bir tip sayar ve dagilim kartı
  /// okunamaz hale gelir.
  static String _normalizeErrorType(String message) {
    var text = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Bastaki emoji/isaretleri at.
    text = text.replaceFirst(RegExp(r'^[^\p{L}\p{N}]+', unicode: true), '');
    final colon = text.indexOf(':');
    if (colon >= 8) {
      text = text.substring(0, colon);
    }
    text = text.trim();
    if (text.isEmpty) text = 'Bilinmeyen';
    return _truncate(text, 80);
  }

  static String _truncate(String value, int maxLength) =>
      value.length <= maxLength ? value : value.substring(0, maxLength);

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
      // Bilerek AppLogger.error DEGIL: errorSink bu cagriyi tekrar merkezi
      // yazima sokar ve baglanti kopukken sonsuz dongu olusur.
      AppLogger.warning('Remote analytics event error: $e');
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
  ///
  /// [origin] hatayi ureten uygulama dosyasi/satiri (varsa); admin
  /// panelindeki "Son Hatalar" listesinde gosterilir.
  Future<void> trackError(
    String errorType, {
    String? details,
    String? origin,
  }) => trackEvent(
    eventType: 'error',
    metadata: {'type': errorType, 'details': details, 'origin': origin},
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

  /// Sadece bu cihazdaki yerel Hive kayitlarini temizler.
  /// Merkezi (admin panelinde gorunen) veri icin [purgeRemoteEvents] kullanin.
  Future<void> clearAllEvents() async {
    if (_box == null) return;
    try {
      await _box!.clear();
      AppLogger.info('🧹 All local analytics events cleared');
    } catch (e) {
      AppLogger.error('Clear all events error: $e');
    }
  }

  /// Merkezi analitik kayitlarini siler (yalnizca admin; RPC tarafinda
  /// `private.current_user_is_admin()` ile dogrulanir). Silinen satir sayisini
  /// dondurur. [olderThanDays] null ise tum tablo temizlenir.
  Future<int> purgeRemoteEvents({int? olderThanDays}) async {
    final raw = await Supabase.instance.client.rpc<dynamic>(
      'admin_purge_analytics_events',
      params: {'p_older_than_days': olderThanDays},
    );
    return raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  /// Yalnizca bu cihazdaki yerel event sayisi. Admin panelinde toplam etkinlik
  /// gostermek icin kullanmayin - merkezi sayim `admin_logs_data` RPC'sinden
  /// `totalEvents` alanindan gelir.
  int get localEventCount => _box?.length ?? 0;
}
