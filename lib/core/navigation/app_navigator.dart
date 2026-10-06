import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/services/auth_service.dart';
import '../../features/auth/widgets/signing_out_view.dart';
import '../services/push_notification_service.dart';
import '../services/user_activity_service.dart';

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

  /// Bir çıkış akışı sürüyor mu? Çift dokunuşta ikinci akış başlamaz.
  static bool _signingOut = false;

  /// Oturumu kapatır, bu cihazdaki kullanıcıya ait durumu temizler ve
  /// [destination] rotasına gider (varsayılan: Giriş ekranı).
  ///
  /// KALICI SİYAH EKRAN HATASI (2026-09): Çıkış eskiden temizlik adımlarını
  /// ekranda hiçbir şey değiştirmeden SIRAYLA bekliyor, sonra hedefe
  /// `pushNamedAndRemoveUntil` ile gidiyordu. Flutter eski sayfaları yeni
  /// sayfanın geçişi bitene kadar ağaçta tutar; bu arada kapanış animasyonunu
  /// bekleyen bir `Navigator.of(context).pop()` (ör. kullanıcının "donmuş"
  /// sandığı yan menüyü kapatması) kendi sayfasını değil en üstteki YENİ
  /// sayfayı kapatıyordu. Eski sayfalar zaten silinmek üzere olduğundan
  /// Navigator tamamen boşalıyor, ekran uygulama yeniden açılana kadar siyah
  /// kalıyordu (bkz. test/core/navigation/app_navigator_sign_out_test.dart).
  ///
  /// Şimdiki sıra:
  ///  1. Hemen opak bir "Çıkış yapılıyor…" perdesi açılır; altındaki her şey
  ///     (yan menü, çekmece, diyaloglar, eski ana sayfa) perde tamamen
  ///     görününce kaldırılır — oturum hâlâ açıkken ve görünmeden. Gecikmeli
  ///     bir pop artık hiçbir sayfaya ulaşamaz; perdenin kendisi de pop ile
  ///     kapanmaz.
  ///  2. Oturum gerektiren temizlik (eylem günlüğü, FCM token) PARALEL ve kısa
  ///     zaman aşımıyla; ardından Supabase ve Google oturumu kapatılır.
  ///  3. Hedef sayfa perdenin üstüne açılır, perde geçiş bitince kalkar.
  static Future<void> signOutAndReset([String destination = '/login']) async {
    if (_signingOut) return;
    _signingOut = true;
    try {
      _showSigningOutCurtain();

      // Oturum gerektiren adımlar signOut'tan ÖNCE. Ağ/Firebase yanıt
      // vermezse bile hiçbiri çıkışı asılı bırakmasın.
      await Future.wait([
        _quietly(
          () => UserActivityService.instance.log(
            'logout',
            category: 'auth',
            summary: 'Çıkış yaptı',
          ),
          const Duration(seconds: 3),
        ),
        _quietly(
          PushNotificationService.clearTokenOnLogout,
          const Duration(seconds: 6),
        ),
      ]);

      // Supabase yerel oturumu ağ çağrısından ÖNCE siler; zaman aşımı olsa da
      // oturum bu cihazda kapanmış olur. Google oturumu da bırakılır, yoksa
      // bir sonraki "Google ile devam et" hesap seçtirmeden aynı hesaba girer.
      await Future.wait([
        _quietly(
          () => Supabase.instance.client.auth.signOut(),
          const Duration(seconds: 6),
        ),
        _quietly(
          () => AuthService().signOutGoogle(),
          const Duration(seconds: 3),
        ),
      ]);
    } finally {
      _signingOut = false;
    }

    _resetTo(destination);
  }

  /// [context]'in sayfası Navigator'da EN ÜSTTEYSE onu kapatır ve true döner;
  /// değilse hiçbir şey yapmaz.
  ///
  /// `Navigator.of(context).pop()` kendi sayfasını değil en üstteki sayfayı
  /// kapatır. Bir kapanış animasyonu gibi bir `await`'ten sonra çağrılırsa o
  /// arada açılmış başka bir sayfayı — hatta yığındaki son sayfayı — kapatıp
  /// ekranı boş bırakabilir.
  static bool popIfCurrent<T extends Object?>(
    BuildContext context, [
    T? result,
  ]) {
    if (!context.mounted) return false;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return false;
    Navigator.of(context).pop<T>(result);
    return true;
  }

  /// Geri gidilecek bir sayfa varsa üstteki sayfayı kapatır; yığında tek
  /// sayfa kaldıysa [fallback] rotasına gider. Tek kalan sayfayı `pop()`
  /// etmek Navigator'ı boşaltır ve ekranı kalıcı siyah bırakır.
  static void popOrGo(BuildContext context, String fallback) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushNamedAndRemoveUntil(fallback, (_) => false);
    }
  }

  /// Perdeyi açar ve altındaki tüm sayfaları kaldırılmak üzere işaretler.
  /// Navigator işaretli sayfaları perdenin açılış geçişi bitene kadar
  /// ekranda tutar, sonra atar; arada boş (siyah) bir kare oluşmaz.
  ///
  /// Perde yalnızca görsel bir güvencedir: açılamazsa çıkış yine de
  /// tamamlanır ve hedef sayfaya gidilir.
  static void _showSigningOutCurtain() {
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;

    try {
      final curtain = _SigningOutRoute();
      navigator.push(curtain);
      while (curtain.isActive && !curtain.isFirst) {
        navigator.removeRouteBelow(curtain);
      }
    } catch (e) {
      debugPrint('⚠️ AppNavigator: çıkış perdesi açılamadı ($e)');
    }
  }

  /// Yığını temizleyip [routeName]'e gider. Rota açılamazsa kullanıcı
  /// perdede asılı kalmasın diye ana sayfaya döner.
  static void _resetTo(String routeName) {
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;
    try {
      navigator.pushNamedAndRemoveUntil(routeName, (_) => false);
    } catch (e) {
      debugPrint(
        '⚠️ AppNavigator: "$routeName" açılamadı ($e), ana sayfaya dönülüyor',
      );
      navigator.pushNamedAndRemoveUntil('/', (_) => false);
    }
  }

  /// [action]'ı en fazla [limit] kadar bekler; hata ya da zaman aşımı çıkışı
  /// durdurmaz.
  static Future<void> _quietly(
    Future<void> Function() action,
    Duration limit,
  ) async {
    try {
      await action().timeout(limit);
    } catch (_) {}
  }
}

/// Çıkış sürerken tüm ekranı kaplayan opak perde (bkz. [SigningOutView]).
///
/// [didPop] false döner: eski sayfalardan gelen gecikmeli bir
/// `Navigator.pop()` perdeyi kapatıp kullanıcıyı boş bir ekrana düşüremez.
/// Perde yalnızca hedef sayfa açılırken yığın temizlenince kalkar.
class _SigningOutRoute extends PageRouteBuilder<void> {
  _SigningOutRoute()
    : super(
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => const SigningOutView(),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      );

  // super çağrılmaz: çağrılırsa perde kapanır. Flutter'ın kendi
  // LocalHistoryRoute.didPop'u da pop'u içeride karşıladığında aynı şekilde
  // super çağırmadan false döner.
  @override
  // ignore: must_call_super
  bool didPop(void result) => false;
}
