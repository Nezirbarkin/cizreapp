// ignore_for_file: avoid_relative_lib_imports

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Kimlik doğrulama akışı sözleşmesi', () {
    test('aktif giriş ekranı kullanıcı adı için AuthService kullanır', () {
      final source = File(
        'lib/features/auth/screens/login_screen_v2.dart',
      ).readAsStringSync();

      expect(source, contains('_authService.signInWithIdentifier('));
      expect(
        source,
        isNot(contains(".from('profiles')\n              .select('email')")),
        reason: 'Anon giriş ekranı profiles.email alanını doğrudan okuyamaz.',
      );
    });

    test('yerel Auth e-posta OTP uzunluğu 6 olarak sabittir', () {
      final config = File('supabase/config.toml').readAsStringSync();

      expect(
        RegExp(r'\[auth\.email\][\s\S]*?otp_length\s*=\s*6').hasMatch(config),
        isTrue,
      );
    });

    test('şifre kurtarma ekranı tam 6 OTP kutusu kullanır', () {
      final source = File(
        'lib/features/auth/screens/reset_password_screen.dart',
      ).readAsStringSync();

      expect(source, contains('List.generate(\n    6,'));
      expect(source, contains('if (code.length != 6)'));
      expect(source, contains('type: OtpType.recovery'));
    });
  });
}
