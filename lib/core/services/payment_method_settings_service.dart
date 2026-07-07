import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/order_model.dart';

/// Admin panelden kontrol edilen sipariş ödeme yöntemi ayarları.
///
/// Tek SELECT sorgusu ile 4 toggle değerini okur; checkout ekranları
/// bunu kullanarak kullanıcıya hangi `PaymentMethod` seçeneklerinin
/// gösterileceğini filtreler.
///
/// GERİYE DÖNÜK UYUMLULUK:
/// - Yeni kolonlar DB'de yoksa (eski DB) `?? true` ile tümü aktif kabul edilir
///   → mevcut kullanıcılar etkilenmez.
/// - `load()` hata fırlatırsa `allEnabled()` static fallback ile tümü aktif
///   döner → ekranlar eski davranışı korur (regresyon yok).
///
/// RLS: `app_about_settings` SELECT authenticated + anon için açık
/// (PUBLIC SELECT policy zaten var), yeni kolonlar otomatik dahil olur.
/// UPDATE sadece admin policy'sinde; bu sınıf yalnızca okuma yapar.
class PaymentMethodSettings {
  /// Kapıda Nakit (PaymentMethod.cash)
  final bool codEnabled;

  /// Kapıda Kart (PaymentMethod.cardOnDelivery)
  final bool cardOnDeliveryEnabled;

  /// Online Ödeme (PaymentMethod.online) — app_about_settings.online_payment_enabled
  final bool onlineEnabled;

  /// Bakiye ile Ödeme (PaymentMethod.balance)
  final bool balanceEnabled;

  const PaymentMethodSettings({
    required this.codEnabled,
    required this.cardOnDeliveryEnabled,
    required this.onlineEnabled,
    required this.balanceEnabled,
  });

  /// Güvenli fallback: tüm yöntemler aktif (mevcut davranış).
  /// Ayar yüklenemediğinde veya yeni kolonlar henüz deploy edilmediğinde
  /// checkout ekranları eski gibi tüm seçenekleri gösterir.
  const PaymentMethodSettings.allEnabled()
      : codEnabled = true,
        cardOnDeliveryEnabled = true,
        onlineEnabled = true,
        balanceEnabled = true;

  /// DB'den okuma başarısız olursa hata fırlatmak YERİNE fallback döneriz;
  /// böylece checkout ekranı hata mesajıyla boğulmaz, kullanıcı sipariş
  /// verebilir (mevcut davranışı korur).
  static const PaymentMethodSettings fallback = PaymentMethodSettings.allEnabled();

  /// Ayar yükleme. Tek sorgu (SELECT 4 kolon + apps_about_settings.id).
  /// Sorgu başarısız olursa veya response null ise fallback döner.
  static Future<PaymentMethodSettings> load() async {
    try {
      final response = await Supabase.instance.client
          .from('app_about_settings')
          .select(
            'order_cod_enabled, order_card_on_delivery_enabled, '
            'online_payment_enabled, order_balance_enabled',
          )
          .maybeSingle();

      if (response == null) {
        return fallback;
      }

      return PaymentMethodSettings(
        codEnabled: response['order_cod_enabled'] as bool? ?? true,
        cardOnDeliveryEnabled: response['order_card_on_delivery_enabled'] as bool? ?? true,
        onlineEnabled: response['online_payment_enabled'] as bool? ?? true,
        balanceEnabled: response['order_balance_enabled'] as bool? ?? true,
      );
    } catch (e, st) {
      debugPrint('⚠️ PaymentMethodSettings.load başarısız, fallback kullanılıyor: $e');
      debugPrintStack(stackTrace: st, maxFrames: 3);
      return fallback;
    }
  }

  /// Verilen `PaymentMethod` admin tarafından aktif mi?
  bool isAvailable(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return codEnabled;
      case PaymentMethod.cardOnDelivery:
        return cardOnDeliveryEnabled;
      case PaymentMethod.online:
        return onlineEnabled;
      case PaymentMethod.balance:
        return balanceEnabled;
    }
  }

  /// Aktif yöntemlerin listesini enum sırasıyla döner.
  /// Default seçim hesaplamak için kullanılır (ör. cash pasifse ilk
  /// aktif yönteme geç).
  List<PaymentMethod> get availableMethods => PaymentMethod.values
      .where(isAvailable)
      .toList(growable: false);

  /// Mevcut seçili yöntem artık aktif değilse, listedeki ilk aktif yöntemi döner.
  /// Tüm yöntemler kapalıysa cash döner (mevcut davranış; null-safe).
  PaymentMethod pickDefault({PaymentMethod? preferred}) {
    final available = availableMethods;
    if (available.isEmpty) {
      // Hiçbir yöntem açık değil → en azından cash'e düş (boş UI önleme)
      return PaymentMethod.cash;
    }
    if (preferred != null && available.contains(preferred)) {
      return preferred;
    }
    return available.first;
  }
}
