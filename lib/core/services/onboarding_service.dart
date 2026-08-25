import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Uygulamanın ilk açılışında tek seferlik gösterilen tanıtım (onboarding)
/// akışının görülüp görülmediğini takip eder.
///
/// Anahtar sürümlenir: tanıtım içeriği ileride köklü biçimde değişirse
/// [_version] artırılır ve tanıtım, daha önce görmüş kullanıcılara da bir
/// kez daha gösterilir.
class OnboardingService {
  OnboardingService._();

  static const _version = 1;
  static const _key = 'onboarding_seen_v$_version';

  static Future<bool> hasSeenOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? false;
    } catch (e) {
      // Okunamıyorsa tanıtımı göstermek zararsızdır; sonsuz döngüye
      // girmemesi için akış yine de "kapat" ile MainScreen'e devam eder.
      debugPrint('Onboarding durumu okunamadı: $e');
      return false;
    }
  }

  static Future<void> markOnboardingSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    } catch (e) {
      debugPrint('Onboarding durumu kaydedilemedi: $e');
    }
  }
}
