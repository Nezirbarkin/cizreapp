// Kurye Bildirim ve Atama Servisi
// Sipariş confirmed/ready durumuna gectiginde kuryelere bildirim gonderir
// ve otomatik kurye ataması yapar

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

  /// Sipariş confirmed/ready durumuna geçtiğinde otomatik kurye ataması yapar
  /// Kuryesi olmayan satıcıların siparişleri için çalışır
  Future<void> autoAssignCourierToOrder({
    required String orderId,
    required String shopId,
    required double orderTotal,
    String orderStatus = 'ready',
  }) async {
    final client = _supabase;
    if (client == null) return;

    try {
      // 1. Dükkanın kendi kuryesi var mı kontrol et
      final shop = await client
          .from('shops')
          .select('has_own_courier, name')
          .eq('id', shopId)
          .maybeSingle();

      if (shop != null && shop['has_own_courier'] == true) {
        debugPrint('📦 Dükkanın kendi kuryesi var, otomatik atama yapılmadı');
        return;
      }

      // 2. Kurye ayarını al
      final settings = await client
          .from('courier_settings')
          .select('fee_per_delivery')
          .maybeSingle();

      final feeAmount = (settings?['fee_per_delivery'] as num?)?.toDouble() ?? 15.0;

      // 3. En az iş yapmış (veya teslimat yapmamış) online kuryeyi bul
      // Bu basit bir strateji - en az teslimat yapmış kuryeyi seç
      final couriers = await client
          .from('profiles')
          .select('id, delivered_count, is_online')
          .eq('role', 'courier')
          .order('delivered_count', ascending: true)
          .limit(10);

      if (couriers.isEmpty) {
        debugPrint('📦 Atanabilecek kurye bulunamadı');
        return;
      }

      // Online kuryeleri öncelikle al
      final onlineCouriers = couriers.where((c) => c['is_online'] == true).toList();
      final selectedCourierList = onlineCouriers.isNotEmpty ? onlineCouriers : couriers;

      if (selectedCourierList.isEmpty) {
        debugPrint('📦 Uygun kurye bulunamadı');
        return;
      }

      // İlk (en az iş yapmış) kuryeyi seç
      final selectedCourier = selectedCourierList.first;
      final courierId = selectedCourier['id'] as String;

      debugPrint('📦 Otomatik kurye atanıyor: $courierId, ücret: ₺$feeAmount');

      // 4. Atama oluştur
      await client.from('courier_assignments').insert({
        'order_id': orderId,
        'courier_id': courierId,
        'status': 'assigned',
        'fee_amount': feeAmount,
        'assigned_at': DateTime.now().toIso8601String(),
      });

      debugPrint('✅ Sipariş $orderId kurye $courierId\'e otomatik atandı');

      // 5. Siparişin orders.status alanını güncelleme (sadece courier_assignments'a ekledik)
      // orders.status = 'on_the_way' sadece kurye siparişi kabul ettiğinde yapılmalı
      // Aksi halde sipariş kurye panelinin "Atanabilir Siparişler" listesinden düşer
      // ve "Siparişlerim" listesinde de görünmez
      debugPrint('✅ Sipariş $orderId courier_assignments\'a eklendi (status değişmedi)');

      // 6. Kuryeye bildirim gönder
      await _notifyCourierOfAssignment(
        courierId: courierId,
        orderId: orderId,
        shopName: shop?['name'] ?? 'Dükkan',
        orderTotal: orderTotal,
      );
    } catch (e) {
      debugPrint('❌ Otomatik kurye atama hatası: $e');
    }
  }

  /// Belirli bir kuryeye sipariş atama bildirimi gönder
  Future<void> _notifyCourierOfAssignment({
    required String courierId,
    required String orderId,
    required String shopName,
    required double orderTotal,
  }) async {
    final client = _supabase;
    if (client == null) return;

    try {
      // Kuryenin FCM token'ını al
      final courierProfile = await client
          .from('profiles')
          .select('fcm_token')
          .eq('id', courierId)
          .maybeSingle();

      // Bildirim oluştur
      await client.from('notifications').insert({
        'user_id': courierId,
        'type': 'courier_order_assigned',
        'title': '🛵 Sipariş Sana Atandı!',
        'content': '$shopName - ₺${orderTotal.toStringAsFixed(2)} tutarında sipariş sana atandı. Hemen teslimata çık!',
        'data': {
          'order_id': orderId,
          'type': 'courier_order_assigned',
        },
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      });

      debugPrint('✅ Kurye $courierId\'e atama bildirimi gönderildi');

      // Push notification gönder (varsa FCM token)
      if (courierProfile?['fcm_token'] != null) {
        try {
          await client.functions.invoke('send-push-notification', body: {
            'userId': courierId,
            'title': '🛵 Sipariş Sana Atandı!',
            'body': '$shopName - ₺${orderTotal.toStringAsFixed(2)} sipariş sana atandı!',
            'data': {
              'order_id': orderId,
              'type': 'courier_order_assigned',
            },
          });
        } catch (e) {
          debugPrint('⚠️ Push notification gönderilemedi: $e');
        }
      }
    } catch (e) {
      debugPrint('❌ Kurye bildirimi hatası: $e');
    }
  }

  /// Sipariş confirmed veya ready durumuna gectiginde kuryelere bildirim gonder
  /// Hem veritabani bildirimi hem push notification gonderir
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
      // 1. Sipariş zaten bir kuryeye atanmış mı kontrol et
      final existingAssignment = await client
          .from('courier_assignments')
          .select('id, courier_id')
          .eq('order_id', orderId)
          .maybeSingle();

      if (existingAssignment != null) {
        debugPrint('📦 Sipariş zaten bir kuryeye atanmış, bildirim gonderilmedi');
        return; // Kurye atanmış, tekrar bildirim gonderme
      }

      // 1b. Bu sipariş için kuryelere zaten bildirim gönderilmiş mi?
      // Satıcı siparişi confirmed -> preparing -> ready durumlarına geçirdiğinde
      // her geçişte bu metod çağrılıyor; tekrar bildirim eklenirse kuryede aynı
      // sipariş için birden fazla bildirim birikiyor. Bu yüzden bir kez gönderildiyse
      // tekrar gönderilmez (çift/çoklu bildirim engeli).
      final existingNotification = await client
          .from('notifications')
          .select('id')
          .inFilter('type', ['courier_new_order', 'courier_order_ready', 'courier_order_assigned'])
          .eq('data->>order_id', orderId)
          .limit(1)
          .maybeSingle();

      if (existingNotification != null) {
        debugPrint('📦 Bu sipariş için kuryelere zaten bildirim gönderilmiş, tekrar gönderilmedi');
        return;
      }

      // 2. Dukkanin kendi kuryesi var mi kontrol et
      final shop = await client
          .from('shops')
          .select('has_own_courier, name')
          .eq('id', shopId)
          .maybeSingle();

      if (shop != null && shop['has_own_courier'] == true) {
        debugPrint('📦 Dukkanin kendi kuryesi var, bildirim gonderilmedi');
        return; // Dukkanin kendi kuryesi var, bildirim gonderme
      }

      // 3. Tum kuryeleri bul (online/offline fark etmez, hepsine bildirim gitsin)
      final couriers = await client
          .from('profiles')
          .select('id, fcm_token')
          .eq('role', 'courier');

      if (couriers.isEmpty) {
        debugPrint('📦 Kurye bulunamadı');
        return;
      }

      debugPrint('📦 ${couriers.length} kuryeye bildirim gonderiliyor...');
      final shopNameFinal = shop?['name'] ?? shopName;

      // 4. Son kontrol: Hala atanmamış mı? (Yarış koşulu için)
      final recheck = await client
          .from('courier_assignments')
          .select('id')
          .eq('order_id', orderId)
          .maybeSingle();
      if (recheck != null) {
        debugPrint('⚠️ Sipariş bu arada atandı, bildirim iptal');
        return;
      }

      // Duruma göre bildirim mesajı
      final String notificationTitle;
      final String notificationContent;
      final String notificationType;
      
      if (orderStatus == 'confirmed') {
        notificationTitle = '🛵 Yeni Sipariş Onaylandı!';
        notificationContent = '$shopNameFinal - ₺${totalAmount.toStringAsFixed(2)} tutarında yeni sipariş onaylandı. Yakında hazır olacak!';
        notificationType = 'courier_new_order';
      } else {
        notificationTitle = '🛵 Yeni Sipariş Hazır!';
        notificationContent = '$shopNameFinal - ₺${totalAmount.toStringAsFixed(2)} tutarında yeni sipariş hazırlandı. Teslimata çıkabilirsiniz!';
        notificationType = 'courier_order_ready';
      }

      // 3. Her kuryeye bildirim gönder
      final notifications = [];
      for (final courier in couriers) {
        notifications.add({
          'user_id': courier['id'],
          'type': notificationType,
          'title': notificationTitle,
          'content': notificationContent,
          'data': {
            'order_id': orderId,
            'shop_id': shopId,
            'shop_name': shopNameFinal,
            'total_amount': totalAmount,
            'order_status': orderStatus,
            'type': 'courier_order',
          },
          'is_read': false,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      // 4. Bildirimleri toplu olarak ekle
      if (notifications.isNotEmpty) {
        await client.from('notifications').insert(notifications);
        debugPrint('✅ ${notifications.length} kuryeye DB bildirimi gönderildi ($orderStatus)');
      }

      // 5. Push notification gönder (FCM)
      await _sendPushNotificationToCouriers(
        couriers: couriers,
        title: notificationTitle,
        body: notificationContent,
        data: {
          'order_id': orderId,
          'shop_id': shopId,
          'order_status': orderStatus,
          'type': notificationType,
        },
      );
    } catch (e) {
      debugPrint('❌ Kurye bildirimi gönderilirken hata: $e');
    }
  }

  /// Push notification gönder (Supabase Edge Function üzerinden)
  Future<void> _sendPushNotificationToCouriers({
    required List<Map<String, dynamic>> couriers,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    final client = _supabase;
    if (client == null) return;

    try {
      // FCM token'ı olan kuryeleri filtrele
      final couriersWithToken = couriers
          .where((c) => c['fcm_token'] != null && (c['fcm_token'] as String).isNotEmpty)
          .toList();

      if (couriersWithToken.isEmpty) {
        debugPrint('⚠️ FCM tokeni olan kurye yok, push notification gonderilemedi');
        return;
      }

      // Edge Function üzerinden toplu push notification gönder
      // Not: Supabase Edge Function 'send-push-notification' tanımlı olmalı
      final tokens = couriersWithToken.map((c) => c['fcm_token']).toList();
      
      debugPrint('📤 ${tokens.length} FCM token\'a push notification gönderiliyor...');

      // Her kurye için ayrı ayrı gönder (toplu gönderim desteği için edge function gerekiyor)
      for (final courier in couriersWithToken) {
        try {
          await client.functions.invoke('send-push-notification', body: {
            'userId': courier['id'],
            'title': title,
            'body': body,
            'data': data,
          });
        } catch (e) {
          // Tekil hata genel bildirimi durdurmasın
          debugPrint('⚠️ Push notification hatası (${courier['id']}): $e');
        }
      }

      debugPrint('✅ Push notification gönderimi tamamlandı');
    } catch (e) {
      debugPrint('❌ Push notification gönderme hatası: $e');
      // Push notification hatası kritik değil, DB bildirimi zaten gönderildi
    }
  }

  /// Push notification gönder (FCM üzerinden)
  Future<void> sendPushNotificationToCouriers({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    final client = _supabase;
    if (client == null) return;

    try {
      // Online kuryeleri bul
      final onlineCouriers = await client
          .from('profiles')
          .select('id')
          .eq('role', 'courier')
          .eq('is_online', true);

      if (onlineCouriers.isEmpty) return;

      // Edge function üzerinden push notification gönder
      // Not: Bu Supabase Edge Function olarak çalışmalı
      for (final courier in onlineCouriers) {
        try {
          await client.functions.invoke('send-push-notification', body: {
            'userId': courier['id'],
            'title': title,
            'body': body,
            'data': data,
          });
        } catch (e) {
          debugPrint('⚠️ Push notification gönderilemedi: $e');
          // Devam et, diğer kuryelere göndermeye çalış
        }
      }
    } catch (e) {
      debugPrint('❌ Push notification hatası: $e');
    }
  }

  /// Sipariş kurye tarafından alındığında müşteriye bildirim
  Future<void> notifyCustomerOrderAssigned({
    required String customerId,
    required String orderId,
    required String courierName,
  }) async {
    final client = _supabase;
    if (client == null) return;

    try {
      await client.from('notifications').insert({
        'user_id': customerId,
        'type': 'order_update',
        'title': '🚴 Siparişiniz Yolda!',
        'content': '$courierName siparişinizi teslim etmek için yola çıktı.',
        'data': {
          'order_id': orderId,
        },
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('❌ Müşteri bildirimi hatası: $e');
    }
  }

  /// Sipariş teslim edildiğinde müşteriye TEK teslim bildirimi gönderir.
  /// Değerlendirme hatırlatması PendingReviewChecker tarafından ayrıca yapılır,
  /// bu yüzden burada ikinci bir bildirim oluşturulmaz (çift bildirim engeli).
  Future<void> notifyCustomerOrderDelivered({
    required String customerId,
    required String orderId,
  }) async {
    final client = _supabase;
    if (client == null) return;

    try {
      await client.from('notifications').insert({
        'user_id': customerId,
        'type': 'order_delivered',
        'title': 'Sipariş Teslim Edildi',
        'content': 'Satıcıyı ve ürünü değerlendirmek için tıklayın.',
        'data': {
          'order_id': orderId,
          'type': 'order_delivered',
        },
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
      debugPrint('✅ Teslim bildirimi gönderildi: orderId=$orderId');
    } catch (e) {
      debugPrint('❌ Teslim bildirimi hatası: $e');
    }
  }
}