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

  /// Hata kayitlarini merkezi analitige aktaran kanca.
  ///
  /// `main.dart` icinde `AnalyticsService.attachToLogger()` ile baglanir.
  /// Dogrudan import etmiyoruz cunku AnalyticsService zaten AppLogger'i
  /// kullaniyor; callback araya girmeseydi core/utils <-> core/services
  /// arasinda dairesel bir bagimlilik olusurdu.
  ///
  /// [stackTrace] ve [diagnostics] hatanin NEREDE olustugunu bulmak icindir:
  /// mesajin kendisi ("Null check operator used on a null value") tek basina
  /// hicbir dosyayi isaret etmiyordu ve admin panelindeki "Son Hatalar"
  /// listesi bu yuzden okunabilir ama takip edilemez kayitlar uretiyordu.
  static void Function(
    String type,
    String? details,
    StackTrace? stackTrace,
    String? diagnostics,
  )? errorSink;

  /// Error seviyesinde log
  ///
  /// [diagnostics] yalnizca `FlutterError.onError` gibi, istisnanin yaninda
  /// ek tani metni (hatali widget'in kaynak konumu vb.) tasiyan cagricilar
  /// icindir; merkezi kayitta hata kaynagini cikarmak icin taranir.
  static void error(
    String message, {
    dynamic error,
    StackTrace? stackTrace,
    String? diagnostics,
  }) {
    _logger.e(message, error: error, stackTrace: stackTrace);

    _sinkError(message, error, stackTrace, diagnostics);

    // Production'da crash reporting service'e gönder (Sentry, Firebase Crashlytics vs)
    if (!kDebugMode) {
      _reportToService(message, error, stackTrace);
    }
  }

  /// Fatal error log
  static void fatal(
    String message, {
    dynamic error,
    StackTrace? stackTrace,
    String? diagnostics,
  }) {
    _logger.f(message, error: error, stackTrace: stackTrace);

    _sinkError(message, error, stackTrace, diagnostics);

    // Production'da crash reporting service'e gönder
    if (!kDebugMode) {
      _reportToService(message, error, stackTrace);
    }
  }

  /// Kancayi cagirir; kanca patlarsa loglama zinciri kirilmasin diye yutulur.
  static void _sinkError(
    String message,
    dynamic error,
    StackTrace? stackTrace,
    String? diagnostics,
  ) {
    final sink = errorSink;
    if (sink == null) return;
    try {
      sink(message, error?.toString(), stackTrace, diagnostics);
    } catch (_) {
      // Analitik yazimi basarisiz olduysa uygulamanin akisi etkilenmemeli.
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
