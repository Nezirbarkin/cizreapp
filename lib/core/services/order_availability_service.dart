import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sipariş alınabilirliği kontrol eden paylaşılan servis.
///
/// Tek sorumluluk: `app_about_settings.global_orders_enabled` bayrağını
/// güvenli şekilde okumak ve "geçici kapalı" durumlarına ait tutarlı mesajlar
/// üretmek. Hata durumunda varsayılan `true` döner; böylece arıza halinde
/// dükkanlar yanlışlıkla kapatılmaz (müşteri deneyimi için daha güvenli).
class OrderAvailabilityService {
  /// `app_about_settings` tablosundan global sipariş alma bayrağını okur.
  /// Tablo/sütun yoksa veya sorgu hata verirse `true` döner (güvenli varsayılan).
  static Future<bool> fetchGlobalOrdersEnabled() async {
    try {
      final response = await Supabase.instance.client
          .from('app_about_settings')
          .select('global_orders_enabled')
          .maybeSingle();

      if (response == null) return true;
      return response['global_orders_enabled'] as bool? ?? true;
    } catch (e) {
      debugPrint('⚠️ OrderAvailabilityService: global_orders_enabled okunamadı: $e');
      return true;
    }
  }

  /// Global sipariş alma kapalıysa gösterilecek snackbar mesajı.
  static const String globalClosedMessage = 'Sipariş alma şu anda kapalı';

  /// Dükkan geçici kapalıysa (is_accepting_orders=false) gösterilecek mesaj.
  static const String shopClosedMessage = 'Bu dükkan şu anda sipariş almıyor (Geçici Kapalı)';

  /// Verilen koşullara göre uygun uyarı mesajını döndürür.
  /// İkisi de kapalıysa global mesaj önceliklidir.
  static String? closedMessage({required bool globalEnabled, required bool shopAcceptingOrders}) {
    if (!globalEnabled) return globalClosedMessage;
    if (!shopAcceptingOrders) return shopClosedMessage;
    return null;
  }
}