import 'dart:io';
import 'package:flutter/foundation.dart';
import 'app_logger.dart';

/// Custom Exception sınıfları
class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;
  final StackTrace? stackTrace;

  const AppException({
    required this.message,
    this.code,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() => 'AppException: $message (code: $code)';
}

class NetworkException extends AppException {
  const NetworkException({
    required super.message,
    super.code = 'NETWORK_ERROR',
    super.originalError,
    super.stackTrace,
  });
}

class AuthException extends AppException {
  const AuthException({
    required super.message,
    super.code = 'AUTH_ERROR',
    super.originalError,
    super.stackTrace,
  });
}

class StorageException extends AppException {
  const StorageException({
    required super.message,
    super.code = 'STORAGE_ERROR',
    super.originalError,
    super.stackTrace,
  });
}

class ValidationException extends AppException {
  const ValidationException({
    required super.message,
    super.code = 'VALIDATION_ERROR',
    super.originalError,
    super.stackTrace,
  });
}

class ServerException extends AppException {
  final int? statusCode;

  const ServerException({
    required super.message,
    this.statusCode,
    super.code = 'SERVER_ERROR',
    super.originalError,
    super.stackTrace,
  });
}

/// Error Handler - Tüm hataları merkezi olarak yönetir
class AppErrorHandler {
  static final AppErrorHandler _instance = AppErrorHandler._internal();
  factory AppErrorHandler() => _instance;
  const AppErrorHandler._internal();

  /// Hatayı logla ve kullanıcıya uygun mesaj döndür
  static String handleError(dynamic error, [StackTrace? stackTrace]) {
    return AppErrorHandler().processError(error, stackTrace);
  }

  /// Hatayı işle ve kullanıcı dostu mesaj döndür
  String processError(dynamic error, [StackTrace? stackTrace]) {
    final errorString = error.toString();
    
    // AppException tipinde hataları işle
    if (error is AppException) {
      _logError(error.message, error.stackTrace ?? stackTrace, error: error);
      return error.message;
    }

    // Nested exception kontrolü - "hata: $e" formatını parse et
    // Örnek: "Ürünler yüklenirken hata: ClientException with SocketException..."
    String actualError = errorString;
    if (errorString.contains(':')) {
      // İlk colon'dan sonraki kısmı al (gerçek hata)
      final parts = errorString.split(':');
      if (parts.length > 1) {
        // "..." formatındaki hata mesajını birleştir
        actualError = parts.sublist(1).join(':').trim();
      }
    }

    // Socket exception veya Network unreachable
    if (error is SocketException ||
        errorString.contains('SocketException') ||
        actualError.contains('SocketException') ||
        errorString.contains('Network is unreachable') ||
        actualError.contains('Network is unreachable') ||
        errorString.contains('Network error') ||
        actualError.contains('Network error') ||
        errorString.contains('errno = 101') ||
        actualError.contains('errno = 101')) {
      const message = 'İnternet bağlantınızı kontrol edin ve tekrar deneyin.';
      _logError(message, stackTrace, error: error);
      return message;
    }

    // Http exception
    if (errorString.contains('HttpException') ||
        actualError.contains('HttpException') ||
        errorString.contains('ClientException') ||
        actualError.contains('ClientException')) {
      const message = 'Bağlantı hatası. Lütfen tekrar deneyin.';
      _logError(message, stackTrace, error: error);
      return message;
    }

    // Timeout exception
    if (errorString.toLowerCase().contains('timeout') ||
        actualError.toLowerCase().contains('timeout')) {
      const message = 'İstek zaman aş��mına uğradı. Lütfen tekrar deneyin.';
      _logError(message, stackTrace, error: error);
      return message;
    }

    // Format exception (JSON parsing vs)
    if (error is FormatException || actualError.contains('FormatException')) {
      const message = 'Veri formatı hatası. Lütfen daha sonra tekrar deneyin.';
      _logError(message, stackTrace, error: error);
      return message;
    }

    // Bilinmeyen hata
    const message = 'Bir sorun oluştu. Lütfen daha sonra tekrar deneyin.';
    _logError(message, stackTrace, error: error);
    return message;
  }

  /// Hata loglama
  void _logError(String message, StackTrace? stackTrace, {dynamic error}) {
    AppLogger.error(
      message,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Exception'ı AppException'a çevir
  static AppException parseException(dynamic error, [StackTrace? stackTrace]) {
    // Network hataları
    if (error is SocketException) {
      return NetworkException(
        message: 'İnternet bağlantınız yok.',
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    // Timeout hataları
    if (error.toString().toLowerCase().contains('timeout')) {
      return const NetworkException(
        message: 'İstek zaman aşımına uğradı.',
        code: 'TIMEOUT',
      );
    }

    // Zaten AppException ise
    if (error is AppException) {
      return error;
    }

    // Diğer hatalar
    return AppException(
      message: error.toString(),
      originalError: error,
      stackTrace: stackTrace,
    );
  }
}

/// Extension - Exception'ları user-friendly mesaja çevir
extension ExceptionExtension on dynamic {
  String get userMessage {
    return AppErrorHandler.handleError(this);
  }
}
