import 'dart:async';
import '../utils/app_logger.dart';

/// API çağrı metrikleri
class ApiMetric {
  final String endpoint;
  final int durationMs;
  final bool success;
  final DateTime timestamp;
  final String? errorMessage;

  ApiMetric({
    required this.endpoint,
    required this.durationMs,
    required this.success,
    required this.timestamp,
    this.errorMessage,
  });
}

/// Performance monitoring servisi
class PerformanceMonitoringService {
  static final PerformanceMonitoringService _instance =
      PerformanceMonitoringService._internal();
  factory PerformanceMonitoringService() => _instance;
  PerformanceMonitoringService._internal();

  // Metrikleri sakla (son 1000 çağrı)
  final List<ApiMetric> _apiMetrics = [];
  static const int _maxMetrics = 1000;

  /// API çağrısını ölç
  Future<T> measureApiCall<T>({
    required String endpoint,
    required Future<T> Function() apiCall,
  }) async {
    final stopwatch = Stopwatch()..start();
    bool success = true;
    String? errorMessage;

    try {
      final result = await apiCall();
      return result;
    } catch (e) {
      success = false;
      errorMessage = e.toString();
      rethrow;
    } finally {
      stopwatch.stop();
      _recordMetric(
        endpoint: endpoint,
        durationMs: stopwatch.elapsedMilliseconds,
        success: success,
        errorMessage: errorMessage,
      );
    }
  }

  /// Metriği kaydet
  void _recordMetric({
    required String endpoint,
    required int durationMs,
    required bool success,
    String? errorMessage,
  }) {
    final metric = ApiMetric(
      endpoint: endpoint,
      durationMs: durationMs,
      success: success,
      timestamp: DateTime.now(),
      errorMessage: errorMessage,
    );

    _apiMetrics.add(metric);

    // Maksimum sayıyı aşarsa en eskiyi sil
    if (_apiMetrics.length > _maxMetrics) {
      _apiMetrics.removeAt(0);
    }

    // Log
    if (success) {
      if (durationMs > 1000) {
        AppLogger.warning('⚡ Slow API: $endpoint took ${durationMs}ms');
      } else {
        AppLogger.debug('⚡ API: $endpoint took ${durationMs}ms');
      }
    } else {
      AppLogger.error('❌ API failed: $endpoint ($errorMessage)');
    }
  }

  /// Ortalama API response time (ms)
  int getAverageResponseTime() {
    if (_apiMetrics.isEmpty) return 0;

    final totalDuration =
        _apiMetrics.fold<int>(0, (sum, m) => sum + m.durationMs);
    return (totalDuration / _apiMetrics.length).toInt();
  }

  /// Endpoint başına ortalama süre
  Map<String, int> getAverageResponseTimeByEndpoint() {
    final endpointMetrics = <String, List<int>>{};

    for (var metric in _apiMetrics) {
      if (!endpointMetrics.containsKey(metric.endpoint)) {
        endpointMetrics[metric.endpoint] = [];
      }
      endpointMetrics[metric.endpoint]!.add(metric.durationMs);
    }

    final averages = <String, int>{};
    endpointMetrics.forEach((endpoint, durations) {
      final avg = durations.fold<int>(0, (sum, d) => sum + d) ~/
          durations.length;
      averages[endpoint] = avg;
    });

    return averages;
  }

  /// Başarı oranı (%)
  double getSuccessRate() {
    if (_apiMetrics.isEmpty) return 100.0;

    final successCount =
        _apiMetrics.where((m) => m.success).length;
    return (successCount / _apiMetrics.length) * 100;
  }

  /// Endpoint başına başarı oranı
  Map<String, double> getSuccessRateByEndpoint() {
    final endpointStats = <String, Map<String, int>>{};

    for (var metric in _apiMetrics) {
      if (!endpointStats.containsKey(metric.endpoint)) {
        endpointStats[metric.endpoint] = {'total': 0, 'success': 0};
      }
      endpointStats[metric.endpoint]!['total'] =
          endpointStats[metric.endpoint]!['total']! + 1;
      if (metric.success) {
        endpointStats[metric.endpoint]!['success'] =
            endpointStats[metric.endpoint]!['success']! + 1;
      }
    }

    final successRates = <String, double>{};
    endpointStats.forEach((endpoint, stats) {
      final rate = (stats['success']! / stats['total']!) * 100;
      successRates[endpoint] = rate;
    });

    return successRates;
  }

  /// En yavaş endpointler
  List<MapEntry<String, int>> getSlowestEndpoints({int limit = 5}) {
    final averages = getAverageResponseTimeByEndpoint();
    final sorted = averages.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).toList();
  }

  /// En çok başarısız olan endpointler
  List<MapEntry<String, int>> getMostFailedEndpoints({int limit = 5}) {
    final failureCounts = <String, int>{};

    for (var metric in _apiMetrics) {
      if (!metric.success) {
        failureCounts[metric.endpoint] =
            (failureCounts[metric.endpoint] ?? 0) + 1;
      }
    }

    final sorted = failureCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).toList();
  }

  /// Son hataları getir
  List<ApiMetric> getRecentErrors({int limit = 20}) {
    final errors =
        _apiMetrics.where((m) => !m.success).toList();
    errors.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return errors.take(limit).toList();
  }

  /// P95 latency (95. yüzdelik dilim)
  int getP95Latency() {
    if (_apiMetrics.isEmpty) return 0;

    final durations = _apiMetrics.map((m) => m.durationMs).toList()
      ..sort();
    final p95Index = (durations.length * 0.95).floor();
    return durations[p95Index];
  }

  /// P99 latency (99. yüzdelik dilim)
  int getP99Latency() {
    if (_apiMetrics.isEmpty) return 0;

    final durations = _apiMetrics.map((m) => m.durationMs).toList()
      ..sort();
    final p99Index = (durations.length * 0.99).floor();
    return durations[p99Index];
  }

  /// Son 5 dakikanın metrikleri
  List<ApiMetric> getRecentMetrics() {
    final fiveMinutesAgo =
        DateTime.now().subtract(const Duration(minutes: 5));
    return _apiMetrics
        .where((m) => m.timestamp.isAfter(fiveMinutesAgo))
        .toList();
  }

  /// Performans özeti
  Map<String, dynamic> getPerformanceSummary() {
    return {
      'total_calls': _apiMetrics.length,
      'average_response_time_ms': getAverageResponseTime(),
      'success_rate': getSuccessRate(),
      'p95_latency_ms': getP95Latency(),
      'p99_latency_ms': getP99Latency(),
      'slowest_endpoints': getSlowestEndpoints(limit: 3),
      'most_failed_endpoints': getMostFailedEndpoints(limit: 3),
      'recent_errors_count': getRecentErrors(limit: 10).length,
    };
  }

  /// Metrikleri temizle
  void clearMetrics() {
    _apiMetrics.clear();
    AppLogger.info('🧹 Performance metrics cleared');
  }

  /// Metrik sayısı
  int get metricCount => _apiMetrics.length;
}
