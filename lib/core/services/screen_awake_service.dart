import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ekranın kendiliğinden kararmasını engeller (canlı yayın sırasında).
///
/// Satıcı ürünü kameraya gösterirken ekrana dokunmaz; ekran zaman aşımıyla
/// kararırsa Android etkinliği duraklar, iOS uygulamayı arka plana alır ve
/// kamera akışı kesilir. Yerel taraf: Android `MainActivity`
/// (FLAG_KEEP_SCREEN_ON), iOS `AppDelegate` (isIdleTimerDisabled). Eklenti
/// yoksa (web, test) sessizce hiçbir şey yapmaz.
class ScreenAwakeService {
  ScreenAwakeService._();

  static const MethodChannel _channel = MethodChannel('cizreapp/screen_awake');

  static Future<void> setKeepOn(bool on) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('setKeepOn', on);
    } on MissingPluginException {
      // Test ortamı ya da eski yerel kabuk: yapılacak bir şey yok.
    } catch (e) {
      debugPrint('ScreenAwakeService: $e');
    }
  }
}
