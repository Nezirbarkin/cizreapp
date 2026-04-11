import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../profile/services/profile_service.dart';

class AuthService {
  final _supabase = Supabase.instance.client;
  final _profileService = ProfileService();
  final _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  /// Şifre sıfırlama isteği gönder
  /// identifier: email veya username
  /// Returns: başarılı ise true
  Future<bool> requestPasswordReset(String identifier) async {
    String email;

    // Email mi username mi kontrol et
    if (identifier.contains('@')) {
      email = identifier.trim();
    } else {
      // Username ise email'i bul
      final userEmail = await _profileService.getEmailByIdentifier(identifier);
      if (userEmail == null) {
        throw Exception('Kullanıcı bulunamadı');
      }
      email = userEmail;
    }

    // Rate limiting için retry mekanizması
    int maxRetries = 3;
    Duration delay = const Duration(seconds: 2);
    
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        // Supabase'e şifre sıfırlama isteği gönder
        // auth-callback.html sayfasına yönlendirir, kullanıcı web'ten şifre değiştirebilir
        await _supabase.auth.resetPasswordForEmail(
          email,
          redirectTo: 'https://www.cizreapp.com/auth-callback.html',
        );

        debugPrint('✅ Şifre sıfırlama emaili gönderildi: $email');
        return true;
      } catch (e) {
        debugPrint('❌ Şifre sıfırlama hatası (deneme $attempt/$maxRetries): $e');
        
        // Rate limiting hatası ve son deneme değilse bekle ve tekrar dene
        final errorStr = e.toString().toLowerCase();
        final isRateLimitError = errorStr.contains('rate limit') ||
                                 errorStr.contains('too many') ||
                                 errorStr.contains('overload') ||
                                 errorStr.contains('429');
        
        if (isRateLimitError && attempt < maxRetries) {
          debugPrint('⏳ Rate limiting hatası, ${delay.inSeconds} saniye bekleniyor...');
          await Future.delayed(delay);
          // Her seferinde bekleme süresini artır
          delay = delay * 2;
          continue;
        }
        
        // Son deneme veya rate limiting hatası değilse hatayı fırlat
        rethrow;
      }
    }
    
    throw Exception('Şifre sıfırlama başarısız');
  }

  /// Yeni şifre belirle (reset token ile)
  Future<bool> updatePassword(String newPassword) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Oturum bulunamadı');
      }

      await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      debugPrint('✅ Şifre güncellendi');
      return true;
    } catch (e) {
      debugPrint('❌ Şifre güncelleme hatası: $e');
      rethrow;
    }
  }

  /// Email veya username ile giriş (identifier support)
  Future<AuthResponse> signInWithIdentifier({
    required String identifier,
    required String password,
  }) async {
    try {
      String email;

      // Email mi username mi kontrol et
      if (identifier.contains('@')) {
        email = identifier.trim();
      } else {
        // Username ise email'i bul
        final userEmail = await _profileService.getEmailByIdentifier(identifier);
        if (userEmail == null) {
          throw Exception('Kullanıcı bulunamadı');
        }
        email = userEmail;
      }

      // Giriş yap
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      debugPrint('✅ Giriş başarılı: ${response.user?.email}');
      return response;
    } catch (e) {
      debugPrint('❌ Giriş hatası: $e');
      rethrow;
    }
  }

  /// Yeni kullanıcı kaydı
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required String username,
  }) async {
    try {
      // Önce username kontrolü
      final isAvailable = await _profileService.isUsernameAvailable(username);
      if (!isAvailable) {
        throw Exception('Bu kullanıcı adı zaten kullanılıyor');
      }

      // Kullanıcı kaydı
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'username': username,
        },
      );

      if (response.user != null) {
        // Profil SQL trigger tarafından otomatik oluşturulur (handle_new_user fonksiyonu)
        // Manuel profil oluşturma kaldırıldı - RLS hatasını önlemek için
        // Username ve full_name zaten signUp data parametresi ile gönderiliyor
        debugPrint('✅ Kullanıcı kaydı başarılı: ${response.user?.email}');
      }

      return response;
    } catch (e) {
      debugPrint('❌ Kayıt hatası: $e');
      rethrow;
    }
  }

  /// Google ile native giriş/kayıt
  Future<AuthResponse> signInWithGoogle() async {
    try {
      // Google Sign In başlat
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw Exception('Google girişi iptal edildi');
      }

      // Google authentication
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) {
        throw Exception('Google ID token alınamadı');
      }

      // Supabase ile ID token kullanarak giriş yap
      final response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      // Eğer yeni kullanıcıysa profil oluştur
      if (response.user != null) {
        await _ensureProfileExists(
          userId: response.user!.id,
          email: response.user!.email ?? googleUser.email,
          fullName: googleUser.displayName ?? '',
          avatarUrl: googleUser.photoUrl,
        );
      }

      debugPrint('✅ Google girişi başarılı: ${response.user?.email}');
      return response;
    } catch (e) {
      debugPrint('❌ Google giriş hatası: $e');
      // Sign out on error
      await _googleSignIn.signOut();
      rethrow;
    }
  }

  /// Apple ile native giriş/kayıt
  Future<AuthResponse> signInWithApple() async {
    try {
      // Nonce oluştur (güvenlik için)
      final rawNonce = _generateNonce();
      final hashedNonce = _sha256ofString(rawNonce);

      // Apple Sign In başlat
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        throw Exception('Apple ID token alınamadı');
      }

      // Supabase ile ID token kullanarak giriş yap
      final response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );

      // Eğer yeni kullanıcıysa profil oluştur
      if (response.user != null) {
        String fullName = '';
        if (credential.givenName != null || credential.familyName != null) {
          fullName = '${credential.givenName ?? ''} ${credential.familyName ?? ''}'.trim();
        }

        await _ensureProfileExists(
          userId: response.user!.id,
          email: response.user!.email ?? credential.email ?? '',
          fullName: fullName,
        );
      }

      debugPrint('✅ Apple girişi başarılı: ${response.user?.email}');
      return response;
    } catch (e) {
      debugPrint('❌ Apple giriş hatası: $e');
      rethrow;
    }
  }

  /// Profil var mı kontrol et, yoksa oluştur
  Future<void> _ensureProfileExists({
    required String userId,
    required String email,
    required String fullName,
    String? avatarUrl,
  }) async {
    try {
      // Profil SQL trigger tarafından otomatik oluşturulur
      // Sadece profil var mı kontrol et, yoksa log yaz
      final existingProfile = await _supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (existingProfile == null) {
        debugPrint('⚠️ Profil henüz oluşturulmadı, trigger çalışıyor olmalı');
      } else {
        debugPrint('✅ Profil mevcut');
      }
    } catch (e) {
      debugPrint('⚠️ Profil kontrol hatası: $e');
      // Profil hatası giriş başarısını engellemez
    }
  }

  /// Random nonce üret (Apple Sign In için)
  String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  /// SHA256 hash (Apple Sign In nonce için)
  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Google Sign Out
  Future<void> signOutGoogle() async {
    try {
      await _googleSignIn.signOut();
      debugPrint('✅ Google çıkış yapıldı');
    } catch (e) {
      debugPrint('❌ Google çıkış hatası: $e');
    }
  }

  /// Auth error mesajlarını Türkçe'ye çevir
  String translateAuthError(String message) {
    // Giriş hataları
    if (message.contains('Invalid login credentials')) {
      return 'Email/kullanıcı adı veya şifre hatalı';
    }
    if (message.contains('Email not confirmed')) {
      return 'Lütfen email adresinizi doğrulayın';
    }
    if (message.contains('User not found')) {
      return 'Kullanıcı bulunamadı';
    }
    
    // Email hataları
    if (message.contains('Invalid email')) {
      return 'Geçersiz email adresi';
    }
    if (message.contains('User already registered') || message.contains('already been registered')) {
      return 'Bu email adresi zaten kayıtlı';
    }
    
    // Şifre hataları
    if (message.contains('Password should be at least 6 characters')) {
      return 'Şifre en az 6 karakter olmalıdır';
    }
    if (message.contains('Password is too weak')) {
      return 'Şifre çok zayıf, daha güçlü bir şifre seçin';
    }
    
    // Kullanıcı adı hataları
    if (message.contains('username') && message.contains('taken')) {
      return 'Bu kullanıcı adı zaten alınmış';
    }
    if (message.contains('user-friendly') || message.contains('Only letters')) {
      return 'Kullanıcı adı sadece harf, rakam, alt çizgi ve tire içerebilir';
    }
    
    // Ağ hataları
    if (message.contains('Network') || message.contains('network')) {
      return 'İnternet bağlantınızı kontrol edin';
    }
    
    // Genel hatalar
    if (message.contains('iptal edildi') || message.contains('cancelled')) {
      return 'İşlem iptal edildi';
    }
    if (message.contains('token')) {
      return 'Doğrulama hatası. Lütfen tekrar deneyin.';
    }
    if (message.contains('rate limit') || message.contains('Rate limit')) {
      return '⏱️ Çok fazla işlem yaptınız. Lütfen 30 saniye bekleyip tekrar deneyin.';
    }
    if (message.contains('exceeded') || message.contains('limit')) {
      return '⏱️ İşlem limiti aşıldı. Lütfen 1 dakika bekleyip tekrar deneyin.';
    }
    if (message.contains('overload') || message.contains('too many requests')) {
      return '⏱️ Sunucu yoğun. Lütfen 1 dakika bekleyip tekrar deneyin.';
    }
    
    return message;
  }

  /// OAuth hata mesajlarını Türkçe'ye çevir
  String translateOAuthError(String? message) {
    if (message == null) return 'Sosyal medya girişi başarısız';
    
    if (message.contains('popup closed') || message.contains('cancelled') || message.contains('iptal')) {
      return 'Giriş iptal edildi';
    }
    if (message.contains('access denied')) {
      return 'Erişim izni reddedildi';
    }
    if (message.contains('token')) {
      return 'Giriş doğrulama hatası';
    }
    if (message.contains('network') || message.contains('internet')) {
      return 'İnternet bağlantısı hatası';
    }
    return message;
  }
}
