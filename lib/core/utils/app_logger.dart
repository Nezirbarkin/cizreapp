// ignore_for_file: deprecated_member_use

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Uygulama genelinde kullanılacak logger
class AppLogger {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      printTime: true,
    ),
    level: kDebugMode ? Level.debug : Level.warning,
  );

  /// Debug seviyesinde log
  static void debug(String message, {dynamic error, StackTrace? stackTrace}) {
    _logger.d(message, error: error, stackTrace: stackTrace);
  }

  /// Info seviyesinde log
  static void info(String message, {dynamic error, StackTrace? stackTrace}) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  /// Warning seviyesinde log
  static void warning(String message, {dynamic error, StackTrace? stackTrace}) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  /// Error seviyesinde log
  static void error(String message, {dynamic error, StackTrace? stackTrace}) {
    _logger.e(message, error: error, stackTrace: stackTrace);
    
    // Production'da crash reporting service'e gönder (Sentry, Firebase Crashlytics vs)
    if (!kDebugMode) {
      _reportToService(message, error, stackTrace);
    }
  }

  /// Fatal error log
  static void fatal(String message, {dynamic error, StackTrace? stackTrace}) {
    _logger.f(message, error: error, stackTrace: stackTrace);
    
    // Production'da crash reporting service'e gönder
    if (!kDebugMode) {
      _reportToService(message, error, stackTrace);
    }
  }

  /// Network request log
  static void network(String method, String url, {dynamic data, int? statusCode}) {
    _logger.d('🌐 $method $url ${statusCode != null ? "[$statusCode]" : ""}',
        error: data);
  }

  /// Crash reporting service'e gönder (opsiyonel)
  static void _reportToService(String message, dynamic error, StackTrace? stackTrace) {
    // TODO: Sentry, Firebase Crashlytics veya başka bir servise gönder
    // Örnek:
    // Sentry.captureException(error, stackTrace: stackTrace);
    debugPrint('📤 Error reported to service: $message');
  }
}
