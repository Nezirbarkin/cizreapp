import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Email Onay Kodu Servisi
/// Kapıda ödemelerde sipariş öncesi email ile doğrulama kodu gönderir
/// Kayıt sırasında email doğrulama için de kullanılır
class VerificationService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  // Rate limiting: Son istek zamanı ve cooldown süresi
  static DateTime? _lastRequestTime;
  static const _minRequestInterval = Duration(seconds: 2); // 5 saniyeden 2 saniyeye düşürüldü

  /// Kayıt öncesi email doğrulama kodu gönder (kullanıcı girmeden)
  ///
  /// Bu fonksiyon kayıt ekranında kullanılır - kullanıcı henüz giriş yapmamış
  /// Email adresine 6 haneli doğrulama kodu gönderir
  ///
  /// Returns: verification_id ve süre (saniye)
  Future<Map<String, dynamic>> sendRegistrationOtp({
    required String email,
    int maxRetries = 2,
  }) async {
    try {
      // Rate limiting kontrolü
      final now = DateTime.now();
      if (_lastRequestTime != null) {
        final elapsed = now.difference(_lastRequestTime!);
        if (elapsed < _minRequestInterval) {
          final remaining = _minRequestInterval - elapsed;
          debugPrint('⏳ VERIFICATION: Rate limit - $remaining saniye bekleniyor');
          throw Exception('Lütfen ${remaining.inSeconds + 1} saniye bekleyin');
        }
      }
      
      debugPrint('🔐 VERIFICATION: Kayıt OTP gönderiliyor...');
      debugPrint('  └─ email: $email');

      // Edge Function'ı çağır
      Map<String, dynamic>? data;
      int attempt = 0;
      
      while (attempt <= maxRetries) {
        try {
          final response = await _supabase.functions.invoke(
            'send-registration-otp',
            body: {
              'email': email.trim().toLowerCase(),
            },
          );

          if (response.status == 429) {
            attempt++;
            if (attempt <= maxRetries) {
              final waitTime = Duration(seconds: attempt * 2);
              debugPrint('⏳ VERIFICATION: 429 hatası - ${waitTime.inSeconds}sn sonra retry...');
              await Future.delayed(waitTime);
              continue;
            }
            throw Exception('Çok fazla istek. Lütfen 1 dakika bekleyin.');
          }

          if (response.status != 200) {
            final errorData = response.data;
            throw Exception(
              errorData['error'] ?? 'Doğrulama kodu gönderilemedi.',
            );
          }

          data = response.data as Map<String, dynamic>;
          break;
        } on Exception catch (e) {
          if (e.toString().contains('429') && attempt < maxRetries) {
            attempt++;
            final waitTime = Duration(seconds: attempt * 2);
            await Future.delayed(waitTime);
            continue;
          }
          rethrow;
        }
      }

      if (data == null) {
        throw Exception('Doğrulama kodu gönderilemedi.');
      }

      if (data['status'] != 'success') {
        throw Exception(data['error'] ?? 'Doğrulama kodu gönderilemedi');
      }

      // Başarılı - son istek zamanını güncelle
      _lastRequestTime = DateTime.now();

      debugPrint('✅ VERIFICATION: Kayıt OTP gönderildi');
      debugPrint('  └─ verification_id: ${data['verification_id']}');
      debugPrint('  └─ expires_in: ${data['expires_in_seconds']} saniye');

      return {
        'verification_id': data['verification_id'],
        'expires_in_seconds': data['expires_in_seconds'] ?? 300,
        'message': data['message'] ?? 'Doğrulama kodu e-posta adresinize gönderildi',
      };
    } catch (e) {
      debugPrint('❌ VERIFICATION: Kayıt OTP hatası - $e');
      
      if (e.toString().contains('429') || e.toString().contains('Çok fazla istek')) {
        throw Exception('Çok fazla istek gönderildi. Lütfen 45 saniye bekleyip tekrar deneyin.');
      }
      
      rethrow;
    }
  }

  /// Kayıt OTP'sini doğrula (kullanıcı girmeden)
  ///
  /// Returns: success (bool) ve message
  Future<Map<String, dynamic>> verifyRegistrationOtp({
    required String email,
    required String code,
  }) async {
    try {
      debugPrint('🔐 VERIFICATION: Kayıt OTP doğrulanıyor...');
      debugPrint('  └─ email: $email');
      debugPrint('  └─ code: $code');

      final response = await _supabase.rpc('verify_registration_otp', params: {
        'p_email': email.trim().toLowerCase(),
        'p_code': code,
      });

      if (response == null) {
        throw Exception('Doğrulama başarısız');
      }

      final result = response as Map<String, dynamic>;
      final success = result['success'] == true;

      debugPrint(success ? '✅ VERIFICATION: Kayıt OTP doğru' : '❌ VERIFICATION: Kayıt OTP yanlış');

      return {
        'success': success,
        'message': result['message'] ?? (success ? 'Kod doğrulandı' : 'Geçersiz kod'),
        'verified_email': result['verified_email'],
      };
    } catch (e) {
      debugPrint('❌ VERIFICATION: Kayıt OTP doğrulama hatası - $e');
      return {
        'success': false,
        'message': e.toString().replaceAll('Exception: ', ''),
      };
    }
  }

  /// Şifre sıfırlama OTP gönder
  ///
  /// Bu fonksiyon şifre sıfırlama ekranında kullanılır - kullanıcı henüz giriş yapmamış
  /// Email adresine 6 haneli doğrulama kodu gönderir
  ///
  /// Returns: verification_id ve süre (saniye)
  Future<Map<String, dynamic>> sendPasswordResetOtp({
    required String email,
    int maxRetries = 2,
  }) async {
    try {
      // Rate limiting kontrolü
      final now = DateTime.now();
      if (_lastRequestTime != null) {
        final elapsed = now.difference(_lastRequestTime!);
        if (elapsed < _minRequestInterval) {
          final remaining = _minRequestInterval - elapsed;
          debugPrint('⏳ VERIFICATION: Rate limit - $remaining saniye bekleniyor');
          throw Exception('Lütfen ${remaining.inSeconds + 1} saniye bekleyin');
        }
      }
      
      debugPrint('🔐 VERIFICATION: Şifre sıfırlama OTP gönderiliyor...');
      debugPrint('  └─ email: $email');

      // Edge Function'ı çağır
      Map<String, dynamic>? data;
      int attempt = 0;
      
      while (attempt <= maxRetries) {
        try {
          final response = await _supabase.functions.invoke(
            'send-password-reset-otp',
            body: {
              'email': email.trim().toLowerCase(),
            },
          );

          if (response.status == 429) {
            attempt++;
            if (attempt <= maxRetries) {
              final waitTime = Duration(seconds: attempt * 2);
              debugPrint('⏳ VERIFICATION: 429 hatası - ${waitTime.inSeconds}sn sonra retry...');
              await Future.delayed(waitTime);
              continue;
            }
            throw Exception('Çok fazla istek. Lütfen 1 dakika bekleyin.');
          }

          if (response.status != 200) {
            final errorData = response.data;
            throw Exception(
              errorData['error'] ?? 'Doğrulama kodu gönderilemedi.',
            );
          }

          data = response.data as Map<String, dynamic>;
          break;
        } on Exception catch (e) {
          if (e.toString().contains('429') && attempt < maxRetries) {
            attempt++;
            final waitTime = Duration(seconds: attempt * 2);
            await Future.delayed(waitTime);
            continue;
          }
          rethrow;
        }
      }

      if (data == null) {
        throw Exception('Doğrulama kodu gönderilemedi.');
      }

      if (data['status'] != 'success') {
        throw Exception(data['error'] ?? 'Doğrulama kodu gönderilemedi');
      }

      // Başarılı - son istek zamanını güncelle
      _lastRequestTime = DateTime.now();

      debugPrint('✅ VERIFICATION: Şifre sıfırlama OTP gönderildi');
      debugPrint('  └─ verification_id: ${data['verification_id']}');
      debugPrint('  └─ expires_in: ${data['expires_in_seconds']} saniye');

      return {
        'verification_id': data['verification_id'],
        'expires_in_seconds': data['expires_in_seconds'] ?? 300,
        'message': data['message'] ?? 'Doğrulama kodu e-posta adresinize gönderildi',
      };
    } catch (e) {
      debugPrint('❌ VERIFICATION: Şifre sıfırlama OTP hatası - $e');
      
      if (e.toString().contains('429') || e.toString().contains('Çok fazla istek')) {
        throw Exception('Çok fazla istek gönderildi. Lütfen 45 saniye bekleyip tekrar deneyin.');
      }
      
      rethrow;
    }
  }

  /// Şifre sıfırlama OTP'sini doğrula
  ///
  /// Returns: success (bool) ve message
  Future<Map<String, dynamic>> verifyPasswordResetOtp({
    required String email,
    required String code,
  }) async {
    try {
      debugPrint('🔐 VERIFICATION: Şifre sıfırlama OTP doğrulanıyor...');
      debugPrint('  └─ email: $email');
      debugPrint('  └─ code: $code');

      final response = await _supabase.rpc('verify_password_reset_otp', params: {
        'p_email': email.trim().toLowerCase(),
        'p_code': code,
      });

      if (response == null) {
        throw Exception('Doğrulama başarısız');
      }

      final result = response as Map<String, dynamic>;
      final success = result['success'] == true;

      debugPrint(success ? '✅ VERIFICATION: Şifre sıfırlama OTP doğru' : '❌ VERIFICATION: Şifre sıfırlama OTP yanlış');

      return {
        'success': success,
        'message': result['message'] ?? (success ? 'Kod doğrulandı' : 'Geçersiz kod'),
        'verified_email': result['verified_email'],
      };
    } catch (e) {
      debugPrint('❌ VERIFICATION: Şifre sıfırlama OTP doğrulama hatası - $e');
      return {
        'success': false,
        'message': e.toString().replaceAll('Exception: ', ''),
      };
    }
  }

  /// Onay kodu gönder (giriş yapmış kullanıcı için)
  ///
  /// Returns: verification_id ve süre (saniye)
  Future<Map<String, dynamic>> sendVerificationCode({
    required String codeType,
    int maxRetries = 2,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Kullanıcı oturumu bulunamadı');
      }
      
      // Rate limiting kontrolü
      final now = DateTime.now();
      if (_lastRequestTime != null) {
        final elapsed = now.difference(_lastRequestTime!);
        if (elapsed < _minRequestInterval) {
          final remaining = _minRequestInterval - elapsed;
          debugPrint('⏳ VERIFICATION: Rate limit - $remaining saniye bekleniyor');
          throw Exception('Lütfen ${remaining.inSeconds + 1} saniye bekleyin');
        }
      }
      
      debugPrint('🔐 VERIFICATION: Onay kodu gönderiliyor...');
      debugPrint('  └─ userId: $userId');
      debugPrint('  └─ codeType: $codeType');

      // Retry mekanizması ile gönder
      Map<String, dynamic>? data;
      int attempt = 0;
      
      while (attempt <= maxRetries) {
        try {
          final response = await _supabase.functions.invoke(
            'send-verification-code',
            body: {
              'code_type': codeType,
              'user_id': userId,
            },
          );

          if (response.status == 429) {
            // Rate limit hatası - retry
            attempt++;
            if (attempt <= maxRetries) {
              final waitTime = Duration(seconds: attempt * 2); // 2, 4, 6 saniye
              debugPrint('⏳ VERIFICATION: 429 hatası - ${waitTime.inSeconds}sn sonra retry...');
              await Future.delayed(waitTime);
              continue;
            }
            throw Exception('Çok fazla istek. Lütfen 1 dakika bekleyin.');
          }

          if (response.status != 200) {
            final errorData = response.data;
            throw Exception(
              errorData['error'] ?? 'Onay kodu gönderilemedi. Lütfen tekrar deneyin.',
            );
          }

          data = response.data as Map<String, dynamic>;
          break;
        } on Exception catch (e) {
          if (e.toString().contains('429') && attempt < maxRetries) {
            attempt++;
            final waitTime = Duration(seconds: attempt * 2);
            debugPrint('⏳ VERIFICATION: 429 hatası - ${waitTime.inSeconds}sn sonra retry...');
            await Future.delayed(waitTime);
            continue;
          }
          rethrow;
        }
      }

      if (data == null) {
        throw Exception('Onay kodu gönderilemedi. Lütfen tekrar deneyin.');
      }

      if (data['status'] != 'success') {
        throw Exception(data['error'] ?? 'Onay kodu gönderilemedi');
      }

      // Başarılı - son istek zamanını güncelle
      _lastRequestTime = DateTime.now();

      debugPrint('✅ VERIFICATION: Onay kodu gönderildi');
      debugPrint('  └─ verification_id: ${data['verification_id']}');
      debugPrint('  └─ expires_in: ${data['expires_in_seconds']} saniye');

      return {
        'verification_id': data['verification_id'],
        'expires_in_seconds': data['expires_in_seconds'] ?? 300,
        'message': data['message'] ?? 'Onay kodu bildirim olarak gönderildi',
      };
    } catch (e) {
      debugPrint('❌ VERIFICATION: Hata - $e');
      
      // Kullanıcı dostu hata mesajı
      if (e.toString().contains('429') || e.toString().contains('Çok fazla istek')) {
        throw Exception('Çok fazla istek gönderildi. Lütfen 45 saniye bekleyip tekrar deneyin.');
      }
      
      rethrow;
    }
  }

  /// Onay kodunu doğrula
  /// 
  /// Returns: success (bool) ve message
  Future<Map<String, dynamic>> verifyCode({
    required String code,
    required String codeType,
  }) async {
    try {
      debugPrint('🔐 VERIFICATION: Kod doğrulanıyor...');
      debugPrint('  └─ code: $code');
      debugPrint('  └─ codeType: $codeType');

      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Kullanıcı oturumu bulunamadı');
      }

      final response = await _supabase.rpc('verify_code', params: {
        'p_user_id': userId,
        'p_code': code,
        'p_code_type': codeType,
      });

      if (response == null) {
        throw Exception('Doğrulama başarısız');
      }

      final result = response as Map<String, dynamic>;
      final success = result['success'] == true;

      debugPrint(success ? '✅ VERIFICATION: Kod doğru' : '❌ VERIFICATION: Kod yanlış');

      return {
        'success': success,
        'message': result['message'] ?? (success ? 'Kod doğrulandı' : 'Geçersiz kod'),
        'verification_id': result['verification_id'],
      };
    } catch (e) {
      debugPrint('❌ VERIFICATION: Doğrulama hatası - $e');
      return {
        'success': false,
        'message': e.toString().replaceAll('Exception: ', ''),
      };
    }
  }

  /// Kalan süreyi hesapla (yeniden gönderme için)
  int getRemainingSeconds(DateTime? lastSentTime, int expiresInSeconds) {
    if (lastSentTime == null) return 0;
    
    final elapsed = DateTime.now().difference(lastSentTime).inSeconds;
    final remaining = expiresInSeconds - elapsed;
    return remaining > 0 ? remaining : 0;
  }

  /// Edge Function'ları ısıt (cold start'ı önle)
  /// Uygulama açılışında arka planda çağrılır
  static Future<void> warmUpEdgeFunctions() async {
    try {
      final supabase = Supabase.instance.client;
      
      // Kullanıcı giriş yapmamışsa warm-up yapma
      if (supabase.auth.currentUser == null) return;
      
      debugPrint('🔥 WARM-UP: Edge Function\'lar ısıtılıyor...');
      
      // send-verification-code fonksiyonuna hafif bir ping at
      // Gerçek kod göndermez, sadece fonksiyonu uyandırır
      final stopwatch = Stopwatch()..start();
      
      await supabase.functions.invoke(
        'send-verification-code',
        body: {'ping': true},
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('⚠️ WARM-UP: Timeout (10s) - ama fonksiyon ısınmış olabilir');
          return FunctionResponse(status: 408, data: {});
        },
      );
      
      stopwatch.stop();
      debugPrint('🔥 WARM-UP: Tamamlandı (${stopwatch.elapsedMilliseconds}ms)');
    } catch (e) {
      debugPrint('⚠️ WARM-UP: Hata (önemli değil) - $e');
      // Warm-up başarısız olsa bile uygulama çalışmaya devam eder
    }
  }
}
