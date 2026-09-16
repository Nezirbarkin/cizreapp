import 'package:shared_preferences/shared_preferences.dart';

/// "Özelleştir" ekranındaki, HESABA DEĞİL CİHAZA bağlı arayüz tercihleri.
///
/// Sunucuya yazılmaz — [BalanceHeaderWidget] ile aynı desen (SharedPreferences
/// tabanlı basit bir bayrak): tercih okunamazsa/kaydedilemezse varsayılan
/// davranış (her şey görünür/açık) sürer, uygulamayı asla bozmaz.
class AppCustomizationPrefs {
  AppCustomizationPrefs._();

  static const String _hide101OkeyButtonKey = 'hide_101_okey_button';
  static const String _hideCourierIconKey = 'hide_courier_fab_icon';
  static const String _hideSehiriciCardKey = 'hide_sehirici_story_card';
  static const String _hideMusicPlayerKey = 'hide_sidebar_music_player';

  /// Yan menüdeki "101 Okey" butonu gizli mi?
  static Future<bool> getHide101OkeyButton() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_hide101OkeyButtonKey) ?? false; // Varsayılan: göster
    } catch (_) {
      return false;
    }
  }

  static Future<void> setHide101OkeyButton(bool hide) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hide101OkeyButtonKey, hide);
    } catch (_) {
      // Tercih kaydedilemezse buton görünür kalmaya devam eder.
    }
  }

  /// Sohbet ikonunun üzerindeki "Paket Gönder" (moto kurye) kısayolu gizli mi?
  ///
  /// Kurye servisi zaten admin tarafında kapalıysa ikon görünmez
  /// ([MarketScreen._courierServiceActive]) — bu tercih o servis AÇIKKEN de
  /// kullanıcının ikonu kendi isteğiyle gizlemesini sağlar.
  static Future<bool> getHideCourierIcon() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_hideCourierIconKey) ?? false; // Varsayılan: göster
    } catch (_) {
      return false;
    }
  }

  static Future<void> setHideCourierIcon(bool hide) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hideCourierIconKey, hide);
    } catch (_) {
      // Tercih kaydedilemezse ikon görünür kalmaya devam eder.
    }
  }

  /// Ana sayfadaki hikayeler satırının başındaki "Şehiriçi" kartı gizli mi?
  static Future<bool> getHideSehiriciCard() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_hideSehiriciCardKey) ?? false; // Varsayılan: göster
    } catch (_) {
      return false;
    }
  }

  static Future<void> setHideSehiriciCard(bool hide) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hideSehiriciCardKey, hide);
    } catch (_) {
      // Tercih kaydedilemezse kart görünür kalmaya devam eder.
    }
  }

  /// Yan menünün en üstündeki müzik çalar kartı ([NowPlayingPanel]) gizli mi?
  ///
  /// Müzik hâlâ arka planda çalmaya devam eder — bu tercih yalnızca sidebar
  /// header'ındaki kartın görünürlüğünü etkiler (bkz. "Arka Plan Müziği"
  /// anahtarı, o müziği tamamen kapatır).
  static Future<bool> getHideMusicPlayer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_hideMusicPlayerKey) ?? false; // Varsayılan: göster
    } catch (_) {
      return false;
    }
  }

  static Future<void> setHideMusicPlayer(bool hide) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hideMusicPlayerKey, hide);
    } catch (_) {
      // Tercih kaydedilemezse kart görünür kalmaya devam eder.
    }
  }
}
