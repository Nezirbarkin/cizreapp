import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/push_notification_service.dart';

/// Root navigator'a global erişim.
///
/// Build context yerine bu key kullanılarak yapılan yönlendirmeler, çağıran
/// widget async bir bekleme sonrası dispose edilse bile çalışır. Oturum
/// kapatma gibi yönlendirmelerin "deactivated widget" hatasıyla sessizce
/// atlanıp ekranda siyah bir kalıntı bırakmasını önler.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Uygulama genelindeki kimlik/yönlendirme akışlarını merkezileştirir.
class AppNavigator {
  AppNavigator._();

  /// Oturumu güvenli şekilde kapatır ve [destination] rotasına gider.
  ///
  /// Çıkış butonları genellikle `Navigator.of(context)` kullanır; ancak
  /// `await signOut()` gibi async işlemlerden sonra context dispose olmuşsa
  /// bu çağrı "Looking up a deactivated widget's ancestor" hatası fırlatıp
  /// yönlendirmeyi atlar ve kullanıcıyı boş/siyah ekranda bırakır. Burada
  /// root navigator key kullanıldığı için yönlendirme her zaman çalışır.
  ///
  /// [destination] varsayılan olarak misafir ana ekrandır ('/'). Admin/kurye
  /// panelleri için '/login' kullanılabilir.
  static Future<void> signOutAndReset([String destination = '/']) async {
    // FCM token mutlaka signOut'tan ÖNCE temizlenmeli (session hâlâ gerekli).
    // Zaman aşımı: ağ/Firebase çağrısı yanıt vermezse bile çıkış akışı
    // asılı kalmadan devam etsin (kullanıcı "çıkış yap"a basınca hiçbir
    // şey olmuyor hissine kapılmasın).
    try {
      await PushNotificationService.clearTokenOnLogout()
          .timeout(const Duration(seconds: 6));
    } catch (_) {}

    try {
      await Supabase.instance.client.auth
          .signOut()
          .timeout(const Duration(seconds: 6));
    } catch (_) {}

    final nav = appNavigatorKey.currentState;
    if (nav != null) {
      nav.pushNamedAndRemoveUntil(destination, (route) => false);
    }
  }
}
