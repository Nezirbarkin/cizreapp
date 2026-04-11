import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Email Servisi
/// Supabase Edge Function üzerinden email gönderir
class EmailService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Teslim bildirim emaili gönder
  Future<bool> sendDeliveryNotificationEmail({
    required String userId,
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
          .select('email, full_name, username')
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
      
      debugPrint('  └─ email: $email');
      debugPrint('  └─ name: $name');
      
      // Supabase Edge Function'ı çağır
      final response = await _supabase.functions.invoke(
        'send-email',
        body: {
          'type': 'order_delivered',
          'to': email,
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
          .select('email, full_name, username')
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
          'to': email,
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
          .select('id, name, owner_id, profiles!inner(email, full_name)')
          .eq('id', shopId)
          .maybeSingle();
      
      if (shopResponse == null) {
        debugPrint('❌ EMAIL: Dükkan bulunamadı');
        return false;
      }
      
      final shopName = shopResponse['name'] as String? ?? 'Mağaza';
      final sellerEmail = shopResponse['profiles']?['email'] as String?;
      
      if (sellerEmail == null || sellerEmail.isEmpty) {
        debugPrint('❌ EMAIL: Satıcı email adresi bulunamadı');
        return false;
      }
      
      debugPrint('  └─ shopName: $shopName');
      debugPrint('  └─ sellerEmail: $sellerEmail');
      
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
          'to': sellerEmail,
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
      final adminProfiles = await _supabase
          .from('profiles')
          .select('email')
          .eq('role', 'admin');
      
      if (adminProfiles.isEmpty) {
        debugPrint('⚠️ EMAIL: Admin bulunamadı');
        return false;
      }
      
      // Ürün listesi formatla
      final itemsList = orderItems.map((item) {
        final name = item['product_name'] as String? ?? 'Ürün';
        final qty = item['quantity'] as int? ?? 1;
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
        return '$name x$qty - ₺${(price * qty).toStringAsFixed(2)}';
      }).toList();
      
      // Her admine email gönder
      int successCount = 0;
      for (final admin in adminProfiles) {
        final adminEmail = admin['email'] as String?;
        if (adminEmail != null && adminEmail.isNotEmpty) {
          final response = await _supabase.functions.invoke(
            'send-order-email',
            body: {
              'type': 'new_order_admin',
              'to': adminEmail,
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
            debugPrint('✅ EMAIL: Admin bildirimi gönderildi - $adminEmail');
          }
        }
      }
      
      return successCount > 0;
    } catch (e) {
      debugPrint('❌ EMAIL: Admin email gönderilirken hata: $e');
      return false;
    }
  }
}
