import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Android ve iOS'da uygulama ikonu üzerinde bildirim sayısı (badge) gösteren servis.
/// Android'de ShortcutBadger kullanır, iOS'da UIApplication badge API'si kullanır.
/// Harici paket gerektirmeden MethodChannel ile çalışır.
class AppBadgeService {
  static const _channel = MethodChannel('com.cizreapp/badge');

  /// Badge sayısını günceller
  static Future<void> updateBadgeCount(int count) async {
    if (kIsWeb) return;
    
    try {
      await _channel.invokeMethod('updateBadge', {'count': count});
    } catch (e) {
      debugPrint('App badge güncelleme hatası: $e');
    }
  }

  /// Badge'i kaldırır
  static Future<void> removeBadge() async {
    if (kIsWeb) return;
    
    try {
      await _channel.invokeMethod('removeBadge');
    } catch (e) {
      debugPrint('App badge kaldırma hatası: $e');
    }
  }
}
