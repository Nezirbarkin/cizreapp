import 'dart:async';
import '../utils/app_logger.dart';

/// API çağrılarında debounce ve throttle uygulamak için yardımcı sınıf
class ThrottleManager {
  final Duration duration;
  Timer? _timer;
  bool _isThrottled = false;

  ThrottleManager({required this.duration});

  /// Fonksiyonu throttle ile çalıştır
  void throttle(Function() callback) {
    if (_isThrottled) {
      AppLogger.debug('🚦 Call throttled');
      return;
    }

    _isThrottled = true;
    callback();

    _timer = Timer(duration, () {
      _isThrottled = false;
      AppLogger.debug('🚦 Throttle reset');
    });
  }

  /// Throttle'ı sıfırla
  void reset() {
    _timer?.cancel();
    _isThrottled = false;
    AppLogger.debug('🚦 Throttle reset manually');
  }

  /// Temizle
  void dispose() {
    _timer?.cancel();
  }
}

/// Debounce uygulamak için yardımcı sınıf
class DebounceManager {
  final Duration duration;
  Timer? _timer;

  DebounceManager({required this.duration});

  /// Fonksiyonu debounce ile çalıştır
  void debounce(Function() callback) {
    _timer?.cancel();
    AppLogger.debug('⏱️ Debounce: waiting...');

    _timer = Timer(duration, () {
      AppLogger.debug('⏱️ Debounce: executing callback');
      callback();
    });
  }

  /// Debounce'ı iptal et
  void cancel() {
    _timer?.cancel();
    AppLogger.debug('⏱️ Debounce cancelled');
  }

  /// Temizle
  void dispose() {
    _timer?.cancel();
  }
}

/// API çağrıları için rate limiting
class RateLimiter {
  final int maxRequests;
  final Duration timeWindow;
  final List<DateTime> _requestTimes = [];

  RateLimiter({
    required this.maxRequests,
    required this.timeWindow,
  });

  /// Rate limit kontrol et
  bool canMakeRequest() {
    final now = DateTime.now();

    // Eski istekleri temizle
    _requestTimes.removeWhere(
      (time) => now.difference(time) > timeWindow,
    );

    if (_requestTimes.length < maxRequests) {
      _requestTimes.add(now);
      AppLogger.debug('✅ Request allowed (${_requestTimes.length}/$maxRequests)');
      return true;
    }

    AppLogger.warning('⛔ Rate limit exceeded');
    return false;
  }

  /// Beklenecek süreyi al (milisaniye)
  int getWaitTimeMs() {
    if (_requestTimes.isEmpty) return 0;

    final oldestRequest = _requestTimes.first;
    final resetTime = oldestRequest.add(timeWindow);
    final now = DateTime.now();

    if (now.isBefore(resetTime)) {
      return resetTime.difference(now).inMilliseconds;
    }

    return 0;
  }

  /// Rate limiter'ı sıfırla
  void reset() {
    _requestTimes.clear();
    AppLogger.debug('🔄 Rate limiter reset');
  }
}

/// Kombinasyonlu rate limiting (Throttle + Debounce)
class SmartRateLimiter {
  final ThrottleManager throttleManager;
  final DebounceManager debounceManager;
  final RateLimiter rateLimiter;
  bool _isProcessing = false;

  SmartRateLimiter({
    required Duration throttleDuration,
    required Duration debounceDuration,
    required int maxRequests,
    required Duration timeWindow,
  })  : throttleManager = ThrottleManager(duration: throttleDuration),
        debounceManager = DebounceManager(duration: debounceDuration),
        rateLimiter = RateLimiter(
          maxRequests: maxRequests,
          timeWindow: timeWindow,
        );

  /// Akıllı rate limiting ile fonksiyonu çalıştır
  void execute(Function() callback) {
    if (_isProcessing) {
      AppLogger.debug('⏳ Already processing');
      return;
    }

    if (!rateLimiter.canMakeRequest()) {
      final waitTime = rateLimiter.getWaitTimeMs();
      AppLogger.warning('⏳ Rate limit: wait ${waitTime}ms');
      return;
    }

    _isProcessing = true;

    throttleManager.throttle(() {
      debounceManager.debounce(() {
        try {
          callback();
        } finally {
          _isProcessing = false;
          AppLogger.debug('✅ Execution completed');
        }
      });
    });
  }

  /// Beklenecek süreyi al
  int getWaitTimeMs() => rateLimiter.getWaitTimeMs();

  /// Temizle
  void dispose() {
    throttleManager.dispose();
    debounceManager.dispose();
    rateLimiter.reset();
  }
}
