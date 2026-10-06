import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth_shell.dart';

/// Çıkış sürerken tüm ekranı kaplayan opak perde
/// (bkz. `AppNavigator.signOutAndReset`).
///
/// Giriş ekranının üst bandıyla aynı marka renginde olduğu için perdeden
/// Giriş ekranına geçiş tek parça görünür. Geri tuşu bu sırada etkisizdir:
/// temizlik bitmeden yarı kapanmış bir oturuma geri dönülmesin.
class SigningOutView extends StatelessWidget {
  const SigningOutView({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AuthPalette.of(context);

    return PopScope(
      canPop: false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        child: Material(
          color: p.band,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AuthLogoMark(),
                const SizedBox(height: 28),
                SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: p.onBand,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Çıkış yapılıyor…',
                  style: TextStyle(
                    color: p.onBand,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
