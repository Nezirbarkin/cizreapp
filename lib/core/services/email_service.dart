import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Email Servisi
/// Supabase Edge Function üzerinden email gönderir
class EmailService {
  /// Supabase client'ı güvenli şekilde al (lazy) - class-level initializer yerine
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      rethrow;
    }
  }

  /// Teslim bildirim emaili gönder
  Future<bool> sendDeliveryNotificationEmail({
    required String userId,
    /// Alicinin e-postasi sunucuda bu siparisten cozulur (to_order_customer).
    required String orderId,
    required String orderNumber,
    required String shopName,
    required double totalAmount,
    required DateTime deliveredAt,
  }) async {
    try {
      debugPrint('📧 EMAIL: Teslim bildirimi emaili gönderiliyor...');
      debugPrint('  └─ userId: $userId');
      debugPrint('  └─ orderNumber: $orderNumber');

      // Kullanıcı email adresini al
      final userProfile = await _supabase
          .from('profiles')
          .select('id, full_name, username')
          .eq('id', userId)
          .maybeSingle();

      if (userProfile == null) {
        debugPrint('❌ EMAIL: Kullanıcı profili bulunamadı');
        return false;
      }

      // E-posta adresi ISTEMCIDE OKUNMUYOR (20260907110001); adres
      // send-email icinde service_role ile cozuluyor.
      final name = userProfile['full_name'] as String? ??
                   userProfile['username'] as String? ??
                   'Değerli Müşterimiz';

      debugPrint('  └─ name: $name');

      // Supabase Edge Function'ı çağır
      final response = await _supabase.functions.invoke(
        'send-email',
        body: {
          'type': 'order_delivered',
          'to_order_customer': orderId,
          'data': {
            'customerName': name,
            'orderNumber': orderNumber,
            'shopName': shopName,
            'totalAmount': totalAmount.toStringAsFixed(2),
            'deliveredAt': deliveredAt.toIso8601String(),
          },
        },
      );

      if (response.status == 200) {
        debugPrint('✅ EMAIL: Teslim bildirimi emaili gönderildi');
        return true;
      } else {
        debugPrint('❌ EMAIL: Email gönderilemedi - Status: ${response.status}');
        debugPrint('❌ EMAIL: Response: ${response.data}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ EMAIL: Email gönderilirken hata: $e');
      // Email hatası uygulamayı engellemez
      return false;
    }
  }

  /// Sipariş onay emaili gönder
  Future<bool> sendOrderConfirmationEmail({
    required String userId,
    /// Alicinin e-postasi sunucuda bu siparisten cozulur (to_order_customer).
    required String orderId,
    required String orderNumber,
    required String shopName,
    required double totalAmount,
    required String deliveryAddress,
  }) async {
    try {
      debugPrint('📧 EMAIL: Sipariş onay emaili gönderiliyor...');

      // Kullanıcı email adresini al
      final userProfile = await _supabase
          .from('profiles')
          .select('id, full_name, username')
          .eq('id', userId)
          .maybeSingle();

      if (userProfile == null) {
        debugPrint('❌ EMAIL: Kullanıcı profili bulunamadı');
        return false;
      }

      final email = userProfile['email'] as String?;
      final name = userProfile['full_name'] as String? ??
                   userProfile['username'] as String? ??
                   'Değerli Müşterimiz';

      if (email == null || email.isEmpty) {
        debugPrint('❌ EMAIL: Kullanıcı email adresi bulunamadı');
        return false;
      }

      // Supabase Edge Function'ı çağır
      final response = await _supabase.functions.invoke(
        'send-email',
        body: {
          'type': 'order_confirmed',
          'to_order_customer': orderId,
          'data': {
            'customerName': name,
            'orderNumber': orderNumber,
            'shopName': shopName,
            'totalAmount': totalAmount.toStringAsFixed(2),
            'deliveryAddress': deliveryAddress,
          },
        },
      );

      if (response.status == 200) {
        debugPrint('✅ EMAIL: Sipariş onay emaili gönderildi');
        return true;
      } else {
        debugPrint('❌ EMAIL: Email gönderilemedi - Status: ${response.status}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ EMAIL: Email gönderilirken hata: $e');
      return false;
    }
  }

  /// Yeni sipariş bildirimi emaili gönder (Satıcıya)
  Future<bool> sendNewOrderEmailToSeller({
    required String shopId,
    required String orderId,
    required String orderNumber,
    required String customerName,
    required String deliveryAddress,
    required double totalAmount,
    required List<Map<String, dynamic>> orderItems,
  }) async {
    try {
      debugPrint('📧 EMAIL: Yeni sipariş bildirimi gönderiliyor (Satıcı)...');
      debugPrint('  └─ shopId: $shopId');
      debugPrint('  └─ orderId: $orderId');
      debugPrint('  └─ orderNumber: $orderNumber');

      // Dükkan bilgilerini ve satıcı email'ini al
      final shopResponse = await _supabase
          .from('shops')
          .select('id, name, owner_id, profiles!inner(id, full_name)')
          .eq('id', shopId)
          .maybeSingle();

      if (shopResponse == null) {
        debugPrint('❌ EMAIL: Dükkan bulunamadı');
        return false;
      }

      final shopName = shopResponse['name'] as String? ?? 'Mağaza';
      // Satici adresi sunucuda cozuluyor (to_shop_owner).

      debugPrint('  └─ shopName: $shopName');
      debugPrint('  └─ alici: dukkan sahibi (sunucuda cozulur)');

      // Ürün listesi formatla
      final itemsList = orderItems.map((item) {
        final name = item['product_name'] as String? ?? 'Ürün';
        final qty = item['quantity'] as int? ?? 1;
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
        return '$name x$qty - ₺${(price * qty).toStringAsFixed(2)}';
      }).toList();

      // Supabase Edge Function'ı çağır
      final response = await _supabase.functions.invoke(
        'send-order-email',
        body: {
          'type': 'new_order_seller',
          'to_shop_owner': shopId,
          'data': {
            'orderId': orderId,
            'orderNumber': orderNumber,
            'shopName': shopName,
            'customerName': customerName,
            'deliveryAddress': deliveryAddress,
            'totalAmount': totalAmount.toStringAsFixed(2),
            'orderItems': itemsList,
          },
        },
      );

      if (response.status == 200) {
        debugPrint('✅ EMAIL: Yeni sipariş bildirimi gönderildi (Satıcı)');
        return true;
      } else {
        debugPrint('❌ EMAIL: Email gönderilemedi - Status: ${response.status}');
        debugPrint('❌ EMAIL: Response: ${response.data}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ EMAIL: Email gönderilirken hata: $e');
      // Email hatası sipariş oluşturmayı engellemesin
      return false;
    }
  }

  /// Yeni sipariş bildirimi emaili gönder (Admin'e)
  Future<bool> sendNewOrderEmailToAdmin({
    required String shopId,
    required String orderId,
    required String orderNumber,
    required String shopName,
    required String customerName,
    required String deliveryAddress,
    required double totalAmount,
    required List<Map<String, dynamic>> orderItems,
  }) async {
    try {
      debugPrint('📧 EMAIL: Yeni sipariş bildirimi gönderiliyor (Admin)...');

      // Admin email listesi
      // Admin adresleri ISTEMCIDE COZULMUYOR: send-order-email
      // `to_role: 'admin'` ile alicilari service_role ile kendisi bulur.

      // Ürün listesi formatla
      final itemsList = orderItems.map((item) {
        final name = item['product_name'] as String? ?? 'Ürün';
        final qty = item['quantity'] as int? ?? 1;
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
        return '$name x$qty - ₺${(price * qty).toStringAsFixed(2)}';
      }).toList();

      // Tek cagri: alicilari edge function `to_role: admin` ile bulur.
      int successCount = 0;
      {
        {
          final response = await _supabase.functions.invoke(
            'send-order-email',
            body: {
              'type': 'new_order_admin',
              'to_role': 'admin',
              'data': {
                'orderId': orderId,
                'orderNumber': orderNumber,
                'shopName': shopName,
                'customerName': customerName,
                'deliveryAddress': deliveryAddress,
                'totalAmount': totalAmount.toStringAsFixed(2),
                'orderItems': itemsList,
              },
            },
          );

          if (response.status == 200) {
            successCount++;
            debugPrint('✅ EMAIL: Admin bildirimi gönderildi');
          }
        }
      }

      return successCount > 0;
    } catch (e) {
      debugPrint('❌ EMAIL: Admin email gönderilirken hata: $e');
      return false;
    }
  }

  /// Kuryeye yeni sipariş atandığında email bildirimi gönder
  Future<bool> sendCourierNewOrderEmail({
    required String courierEmail,
    required String courierName,
    required String shopName,
    required double totalAmount,
    required String deliveryAddress,
    required String orderNumber,
  }) async {
    try {
      if (courierEmail.isEmpty) {
        debugPrint('⚠️ EMAIL: Kurye emaili boş, email gönderilmedi');
        return false;
      }

      debugPrint('📧 EMAIL: Kuryeye yeni sipariş bildirimi gönderiliyor...');

      final response = await _supabase.functions.invoke(
        'send-order-email',
        body: {
          'type': 'new_order_courier',
          'to': courierEmail,
          'data': {
            'courierName': courierName,
            'shopName': shopName,
            'orderNumber': orderNumber,
            'totalAmount': totalAmount.toStringAsFixed(2),
            'deliveryAddress': deliveryAddress,
          },
        },
      );

      if (response.status == 200) {
        debugPrint('✅ EMAIL: Kurye yeni sipariş bildirimi gönderildi');
        return true;
      } else {
        debugPrint('❌ EMAIL: Kurye emaili gönderilemedi - Status: ${response.status}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ EMAIL: Kurye emaili gönderirken hata: $e');
      return false;
    }
  }

  /// Kurye ödeme isteği oluşturduğunda admine email bildirimi gönder
  Future<bool> sendCourierPayoutRequestEmailToAdmin({
    required String courierName,
    required double amount,
  }) async {
    try {
      debugPrint('📧 EMAIL: Kurye ödeme isteği bildirimi gönderiliyor (Admin)...');

      // Admin adresleri ISTEMCIDE COZULMUYOR: send-order-email
      // `to_role: 'admin'` ile alicilari service_role ile kendisi bulur.

      final response = await _supabase.functions.invoke(
        'send-order-email',
        body: {
          'type': 'courier_payout_request',
          'to_role': 'admin',
          'data': {
            'courierName': courierName,
            'totalAmount': amount.toStringAsFixed(2),
          },
        },
      );

      final ok = response.status == 200;
      debugPrint(ok
          ? '✅ EMAIL: Admin ödeme isteği bildirimi gönderildi'
          : '⚠️ EMAIL: Admin ödeme isteği bildirimi gönderilemedi');
      return ok;
    } catch (e) {
      debugPrint('❌ EMAIL: Admin ödeme isteği emaili gönderilirken hata: $e');
      return false;
    }
  }
}
