// Kurye Bildirim ve Atama Servisi
// Sipariş confirmed/ready durumuna gectiginde kuryelere bildirim gonderir
// ve otomatik kurye ataması yapar.
//
// 2026-08-09: Tüm çapraz-kullanıcı bildirim/atanama yolları artık sunucu-
// otoriteli RPC'ler üzerinden:
//   * autoAssignCourierToOrder      -> assign_order_to_courier (auto-select)
//   * notifyCouriersForNewOrder     -> broadcast_order_to_couriers
//   * notifyCustomerOrderAssigned   -> add_notification
//   * notifyCustomerOrderDelivered  -> add_notification
// Eskiden doğrudan notifications.insert / courier_assignments.insert yapılıyordu;
// RLS (user_id=auth.uid()) ve INSERT policy eksikliği yüzünden hepsi sessizce
// bloklanıyordu. Ayrıca kurye seçimi için profiles'tan email/phone/delivered_count
// çekiliyordu (grant dışı PII kolonları → 42501).

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CourierNotificationService {
  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      return null;
    }
  }

  /// Sipariş confirmed/ready durumuna geçtiğinde otomatik kurye ataması yapar.
  /// Kuryesi olmayan satıcıların siparişleri için çalışır.
  ///
  /// Sunucu-otoriteli: assign_order_to_courier RPC (p_courier_id null + satıcı
  /// çağıranı) en uygun kuryeyi seçer, atomik atar, fee yazar ve kuryeye
  /// "atandı" bildirimi gönderir. Kurye seçimi istemcide yapılamaz (PII kolonları
  /// grant dışı); courier_assignments INSERT policy'si de yoktur.
  Future<void> autoAssignCourierToOrder({
    required String orderId,
    required String shopId,
    required double orderTotal,
    String orderStatus = 'ready',
  }) async {
    final client = _supabase;
    if (client == null) return;

    try {
      // Dükkanın kendi kuryesi varsa atama yapma.
      final shop = await client
          .from('shops')
          .select('has_own_courier')
          .eq('id', shopId)
          .maybeSingle();
      if (shop != null && shop['has_own_courier'] == true) {
        debugPrint('📦 Dükkanın kendi kuryesi var, otomatik atama yapılmadı');
        return;
      }

      await client.rpc(
        'assign_order_to_courier',
        params: {'p_order_id': orderId},
      );
      debugPrint('✅ Sipariş $orderId otomatik kuryeye atandı (RPC)');
    } catch (e) {
      debugPrint('❌ Otomatik kurye atama hatası: $e');
    }
  }

  /// Sipariş confirmed veya ready durumuna geçtiğinde tüm kuryelere bildirim
  /// g��nderir. Sunucu-otoriteli broadcast_order_to_couriers RPC, kuryesi
  /// olmayan dükkansa tüm uygun kuryelere bildirim yazar (kurye listesi
  /// istemciden çekilemediği için — profiles.role grant dışı). Aynı
  /// sipariş+tip için tekrar yayın yapmaz (dedup).
  Future<void> notifyCouriersForNewOrder({
    required String orderId,
    required String shopId,
    required String shopName,
    required double totalAmount,
    String orderStatus = 'ready',
  }) async {
    final client = _supabase;
    if (client == null) return;

    try {
      final String type;
      final String title;
      final String content;
      if (orderStatus == 'confirmed') {
        type = 'courier_new_order';
        title = '🛵 Yeni Sipariş Onaylandı!';
        content =
            '$shopName - ₺${totalAmount.toStringAsFixed(2)} tutarında yeni sipariş onaylandı. Yakında hazır olacak!';
      } else {
        type = 'courier_order_ready';
        title = '🛵 Yeni Sipariş Hazır!';
        content =
            '$shopName - ₺${totalAmount.toStringAsFixed(2)} tutarında yeni sipariş hazırlandı. Teslimata çıkabilirsiniz!';
      }

      final count = await client.rpc(
        'broadcast_order_to_couriers',
        params: {
          'p_order_id': orderId,
          'p_type': type,
          'p_title': title,
          'p_content': content,
        },
      );
      debugPrint('✅ $count kuryeye bildirim gönderildi ($orderStatus) — broadcast RPC');
    } catch (e) {
      debugPrint('❌ Kurye bildirimi gönderilirken hata: $e');
    }
  }

  /// Sipariş kurye tarafından alındığında müşteriye bildirim.
  ///
  /// add_notification RPC (SECURITY DEFINER) üzerinden — müşteri adına
  /// (user_id != auth.uid()) doğrudan notifications.insert RLS altında
  /// bloklanıyordu (42501).
  ///
  /// NOT: assign_order_to_courier RPC müşteriye "yolda" bildirimini atama
  /// anında TEK SEFER gönderir; bu metod kurye panelindeki picked_up yolu
  /// kaldırıldığı için artık çağrılmıyor, ancak doğru çalışır şekilde tutulur.
  Future<void> notifyCustomerOrderAssigned({
    required String customerId,
    required String orderId,
    required String courierName,
  }) async {
    final client = _supabase;
    if (client == null) return;

    try {
      await client.rpc('add_notification', params: {
        'p_user_id': customerId,
        'p_type': 'order_update',
        'p_title': '🚴 Siparişiniz Yolda!',
        'p_content': '$courierName siparişinizi teslim etmek için yola çıktı.',
        'p_entity_id': orderId,
      });
    } catch (e) {
      debugPrint('❌ Müşteri bildirimi hatası: $e');
    }
  }

  /// Sipariş teslim edildiğinde müşteriye TEK teslim bildirimi gönderir.
  /// Değerlendirme hatırlatması PendingReviewChecker tarafından ayrıca yapılır.
  ///
  /// add_notification RPC üzerinden (çapraz-kullanıcı insert RLS blokunu aşar).
  /// NOT: complete_order_delivery RPC müşteri+satıcı teslim bildirimini sunucu
  /// tarafında gönderdiği için bu metod artık kurye panelinden çağrılmıyor;
  /// ancak doğru çalışır şekilde tutulur.
  Future<void> notifyCustomerOrderDelivered({
    required String customerId,
    required String orderId,
  }) async {
    final client = _supabase;
    if (client == null) return;

    try {
      await client.rpc('add_notification', params: {
        'p_user_id': customerId,
        'p_type': 'order_delivered',
        'p_title': 'Sipariş Teslim Edildi',
        'p_content': 'Siparişiniz teslim edildi. Değerlendirme için tıklayın.',
        'p_entity_id': orderId,
      });
      debugPrint('✅ Teslim bildirimi gönderildi: orderId=$orderId');
    } catch (e) {
      debugPrint('❌ Teslim bildirimi hatası: $e');
    }
  }
}
