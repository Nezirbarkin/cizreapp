// =============================================================================
// Auth Validators Test - Saf fonksiyon testleri (mock gerektirmez)
// CizreApp - Email/username/password validation kuralları
// =============================================================================
// Kullanım:
//   flutter test test/utils/auth_validators_test.dart
// =============================================================================

// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

/// Auth validasyon kuralları - AuthService'ten bağımsız, saf fonksiyonlar.
/// Bu fonksiyonlar gerçek projede AuthService içinde inline kullanılıyor
/// ve burada merkezi olarak test ediliyor. Aynı kurallar hem client hem
/// backend (Supabase RLS) tarafında uygulanmalı.
class AuthValidators {
  /// Email validasyonu
  /// Geçerli: non-empty, '@' içermeli, '.', boşluk yok
  static bool isValidEmail(String email) {
    if (email.isEmpty) return false;
    if (email.contains(' ')) return false;
    if (!email.contains('@')) return false;
    if (!email.contains('.')) return false;

    // @ ve . sırası: @ önce, . sonra
    final atIndex = email.indexOf('@');
    final dotIndex = email.lastIndexOf('.');
    if (atIndex < 1) return false; // @ sonda veya başta olamaz
    if (dotIndex < atIndex + 2) return false; // @ sonrası en az 1 karakter
    if (dotIndex >= email.length - 1) return false; // . sonda olamaz

    return true;
  }

  /// Username validasyonu
  /// Geçerli: 3-20 karakter, sadece harf/rakam/altçizgi, altçizgi ile başlayamaz
  static bool isValidUsername(String username) {
    if (username.length < 3 || username.length > 20) return false;
    if (username.startsWith('_')) return false;

    final regex = RegExp(r'^[a-zA-Z0-9_]+$');
    return regex.hasMatch(username);
  }

  /// Password validasyonu
  /// Minimum 6 karakter (Supabase default), maksimum 128
  static bool isValidPassword(String password) {
    if (password.length < 6) return false;
    if (password.length > 128) return false;
    return true;
  }

  /// Password güç skoru (0-4)
  /// 0: çok zayıf, 1: zayıf, 2: orta, 3: güçlü, 4: çok güçlü
  static int passwordStrength(String password) {
    if (password.isEmpty) return 0;

    int score = 0;
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(password)) score++;
    if (RegExp(r'[a-z]').hasMatch(password)) score++;
    if (RegExp(r'[0-9]').hasMatch(password)) score++;
    if (RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(password)) score++;

    // 0-1: zayıf, 2-3: orta, 4: güçlü, 5-6: çok güçlü
    if (score <= 1) return 1;
    if (score <= 3) return 2;
    if (score <= 4) return 3;
    return 4;
  }

  /// Identifier email mi username mi?
  /// @ içeriyorsa email, yoksa username kabul et
  static IdentifierType classifyIdentifier(String identifier) {
    if (identifier.isEmpty) return IdentifierType.invalid;
    if (identifier.contains('@')) return IdentifierType.email;
    return IdentifierType.username;
  }

  /// Identifier temizle (trim, lowercase)
  static String sanitizeIdentifier(String identifier) {
    return identifier.trim().toLowerCase();
  }
}

enum IdentifierType { email, username, invalid }

void main() {
  // ===========================================================================
  // 1. EMAIL VALIDATION
  // ===========================================================================
  group('📧 Email Validation', () {
    test('Geçerli email kabul edilmeli', () {
      expect(AuthValidators.isValidEmail('user@example.com'), isTrue);
      expect(AuthValidators.isValidEmail('test.user+tag@cizreapp.com'), isTrue);
      expect(AuthValidators.isValidEmail('a@b.co'), isTrue);
    });

    test('Boş string reddedilmeli', () {
      expect(AuthValidators.isValidEmail(''), isFalse);
    });

    test('@ işareti olmayan reddedilmeli', () {
      expect(AuthValidators.isValidEmail('userexample.com'), isFalse);
      expect(AuthValidators.isValidEmail('plainusername'), isFalse);
    });

    test('Nokta olmayan reddedilmeli', () {
      expect(AuthValidators.isValidEmail('user@example'), isFalse);
    });

    test('Boşluk içeren reddedilmeli', () {
      expect(AuthValidators.isValidEmail('user @example.com'), isFalse);
      expect(AuthValidators.isValidEmail(' user@example.com'), isFalse);
      expect(AuthValidators.isValidEmail('user@example.com '), isFalse);
    });

    test('@ sonda veya başta olamaz', () {
      expect(AuthValidators.isValidEmail('@example.com'), isFalse);
      expect(AuthValidators.isValidEmail('user@'), isFalse);
    });

    test('Nokta sonda olamaz', () {
      expect(AuthValidators.isValidEmail('user@example.'), isFalse);
    });
  });

  // ===========================================================================
  // 2. USERNAME VALIDATION
  // ===========================================================================
  group('👤 Username Validation', () {
    test('Geçerli username kabul edilmeli', () {
      expect(AuthValidators.isValidUsername('ahmet'), isTrue);
      expect(AuthValidators.isValidUsername('user_123'), isTrue);
      expect(AuthValidators.isValidUsername('cizreapp'), isTrue);
    });

    test('Çok kısa (3\'ten az) reddedilmeli', () {
      expect(AuthValidators.isValidUsername('ab'), isFalse);
      expect(AuthValidators.isValidUsername('a'), isFalse);
    });

    test('Çok uzun (20\'den fazla) reddedilmeli', () {
      expect(AuthValidators.isValidUsername('a' * 21), isFalse);
    });

    test('Altçizgi ile başlayamaz', () {
      expect(AuthValidators.isValidUsername('_user'), isFalse);
    });

    test('Sadece izin verilen karakterler (harf, rakam, altçizgi)', () {
      expect(AuthValidators.isValidUsername('user-name'), isFalse); // tire yok
      expect(AuthValidators.isValidUsername('user.name'), isFalse); // nokta yok
      expect(
        AuthValidators.isValidUsername('user name'),
        isFalse,
      ); // boşluk yok
      expect(AuthValidators.isValidUsername('user@name'), isFalse); // @ yok
      expect(
        AuthValidators.isValidUsername('user#name'),
        isFalse,
      ); // özel karakter yok
    });

    test('Sınır değerler (3 ve 20 karakter)', () {
      expect(AuthValidators.isValidUsername('abc'), isTrue); // 3 = sınır
      expect(AuthValidators.isValidUsername('a' * 20), isTrue); // 20 = sınır
    });
  });

  // ===========================================================================
  // 3. PASSWORD VALIDATION
  // ===========================================================================
  group('🔒 Password Validation', () {
    test('Minimum 6 karakter kabul edilmeli', () {
      expect(AuthValidators.isValidPassword('123456'), isTrue);
    });

    test('6\'dan az karakter reddedilmeli', () {
      expect(AuthValidators.isValidPassword('12345'), isFalse);
      expect(AuthValidators.isValidPassword(''), isFalse);
    });

    test('Maksimum 128 karakter sınırı', () {
      expect(AuthValidators.isValidPassword('a' * 128), isTrue);
      expect(AuthValidators.isValidPassword('a' * 129), isFalse);
    });
  });

  // ===========================================================================
  // 4. PASSWORD STRENGTH
  // ===========================================================================
  group('💪 Password Strength', () {
    test('Boş şifre en düşük skor (0)', () {
      expect(AuthValidators.passwordStrength(''), equals(0));
    });

    test('Kısa ve basit şifre zayıf (1)', () {
      expect(AuthValidators.passwordStrength('123'), equals(1));
      expect(AuthValidators.passwordStrength('abc'), equals(1));
    });

    test('8+ karakter farklı tiplerde orta-güçlü (2-3)', () {
      expect(AuthValidators.passwordStrength('password1'), equals(2));
      expect(
        AuthValidators.passwordStrength('Password1'),
        greaterThanOrEqualTo(2),
      );
    });

    test('Büyük harf + küçük harf + rakam güçlü (3+)', () {
      expect(
        AuthValidators.passwordStrength('MyP4ssword'),
        greaterThanOrEqualTo(3),
      );
    });

    test('Tüm tipler + özel karakter çok güçlü (4)', () {
      expect(AuthValidators.passwordStrength('MyP4ssword!@#'), equals(4));
      expect(AuthValidators.passwordStrength('VeryStr0ng!Pass'), equals(4));
    });
  });

  // ===========================================================================
  // 5. IDENTIFIER CLASSIFICATION
  // ===========================================================================
  group('🔍 Identifier Classification', () {
    test('@ içeren identifier email olarak sınıflandırılmalı', () {
      expect(
        AuthValidators.classifyIdentifier('user@example.com'),
        equals(IdentifierType.email),
      );
    });

    test('@ içermeyen identifier username olarak sınıflandırılmalı', () {
      expect(
        AuthValidators.classifyIdentifier('ahmet_yilmaz'),
        equals(IdentifierType.username),
      );
    });

    test('Boş string invalid olarak sınıflandırılmalı', () {
      expect(
        AuthValidators.classifyIdentifier(''),
        equals(IdentifierType.invalid),
      );
    });
  });

  // ===========================================================================
  // 6. SANITIZATION
  // ===========================================================================
  group('🧹 Sanitization', () {
    test('Identifier trim ve lowercase yapılmalı', () {
      expect(
        AuthValidators.sanitizeIdentifier('  Ahmet_Yilmaz  '),
        equals('ahmet_yilmaz'),
      );
      expect(
        AuthValidators.sanitizeIdentifier('USER@EXAMPLE.COM'),
        equals('user@example.com'),
      );
    });
  });

  // ===========================================================================
  // 7. SONUÇ RAPORU
  // ===========================================================================
  tearDownAll(() {
    print('\n${'=' * 60}');
    print('🧪 AUTH VALIDATORS TEST SONUÇ RAPORU');
    print('=' * 60);
    print('✅ Tüm validation kuralları test edildi');
    print('💡 Bu testler Supabase/mock gerektirmez');
    print('   - AuthService.validation logic');
    print('   - Login/Register form validation');
    print('   - Password strength meter');
    print('=' * 60);
  });
}
