import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/order_model.dart';
import '../../../core/models/invoice_info_model.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/email_service.dart';

class OrderService {
  final NotificationService _notificationService = NotificationService();
  final EmailService _emailService = EmailService();

  /// Kullanıcı başına izin verilen ücretsiz (0 TL) sipariş sayısı.
  static const int freeOrderLimitPerUser = 1;

  /// Supabase client'ı güvenli şekilde al (lazy) - class-level initializer yerine
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      rethrow;
    }
  }

  // Kullanıcının siparişlerini getir
  Future<List<Order>> getUserOrders(String userId) async {
    try {
      debugPrint('📋 ORDERS LIST: Kullanici siparisleri getiriliyor...');
      debugPrint('  └─ userId: $userId');
      
      final response = await _supabase
          .from('orders')
          .select('''
            *,
            order_items(*),
            shops(name)
          ''')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      debugPrint('📋 ORDERS LIST: Response alindi');
      debugPrint('  └─ Siparis sayisi: ${(response as List).length}');
      
      final orders = (response as List).map((json) => Order.fromJson(json)).toList();
      debugPrint('✅ ORDERS LIST: ${orders.length} siparis basariyla yuklendi');
      
      return orders;
    } catch (e) {
      debugPrint('❌ ORDERS LIST: Siparisler yuklenirken hata: $e');
      debugPrint('❌ ORDERS LIST: Hata tipi: ${e.runtimeType}');
      if (e is PostgrestException) {
        debugPrint('❌ ORDERS LIST: PostgrestException details:');
        debugPrint('  └─ message: ${e.message}');
        debugPrint('  └─ code: ${e.code}');
        debugPrint('  └─ details: ${e.details}');
        debugPrint('  └─ hint: ${e.hint}');
        
        // Eğer recursive policy hatası ise boş liste dön
        if (e.code == '42P17' || e.message.contains('infinite recursion')) {
          debugPrint('⚠️ ORDERS LIST: Recursive policy hatasi - bos liste donuluyor');
          debugPrint('⚠️ ORDERS LIST: FIX: FIX_ORDERS_POLICIES_CLEAN.sql calistir');
          return [];
        }
      }
      throw Exception('Siparişler yüklenirken hata: $e');
    }
  }

  // Dükkânın siparişlerini getir
  Future<List<Order>> getShopOrders(String shopId) async {
    try {
      debugPrint('🏪 SHOP ORDERS: Mağaza siparişleri getiriliyor...');
      debugPrint('  └─ shopId: $shopId');
      
      final response = await _supabase
          .from('orders')
          .select('*, order_items(*)')
          .eq('shop_id', shopId)
          .order('created_at', ascending: false);

      debugPrint('🏪 SHOP ORDERS: Response alındı');
      debugPrint('  └─ Sipariş sayısı: ${(response as List).length}');

      final orders = (response as List).map((json) {
        // delivery_address_text zaten orders tablosunda var
        final Map<String, dynamic> orderJson = Map<String, dynamic>.from(json);
        
        // Eğer delivery_address_text varsa address_display'e kopyala
        if (orderJson['delivery_address_text'] != null) {
          orderJson['address_display'] = orderJson['delivery_address_text'];
        }
        
        return Order.fromJson(orderJson);
      }).toList();

      debugPrint('✅ SHOP ORDERS: ${orders.length} sipariş başarıyla yüklendi');
      return orders;
    } catch (e) {
      debugPrint('❌ SHOP ORDERS: Siparişler yüklenirken hata: $e');
      debugPrint('❌ SHOP ORDERS: Hata tipi: ${e.runtimeType}');
      if (e is PostgrestException) {
        debugPrint('❌ SHOP ORDERS: PostgrestException details:');
        debugPrint('  └─ message: ${e.message}');
        debugPrint('  └─ code: ${e.code}');
        debugPrint('  └─ details: ${e.details}');
        debugPrint('  └─ hint: ${e.hint}');
      }
      throw Exception('Siparişler yüklenirken hata: $e');
    }
  }

  // ID'ye göre sipariş getir
  Future<Order?> getOrderById(String orderId) async {
    try {
      final response = await _supabase
          .from('orders')
          .select('*, order_items(*)')
          .eq('id', orderId)
          .single();

      return Order.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  // Sipariş numarasına göre sipariş getir
  Future<Order?> getOrderByNumber(String orderNumber) async {
    try {
      final response = await _supabase
          .from('orders')
          .select('*, order_items(*)')
          .eq('order_number', orderNumber)
          .single();

      return Order.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  // Sipariş durumunu güncelle (bildirim gönderir)
  Future<Order?> updateOrderStatus(
    String orderId,
    OrderStatus status,
  ) async {
    try {
      // Önce siparişi getir (kullanıcı ID'si için)
      final order = await getOrderById(orderId);
      if (order == null) {
        throw Exception('Sipariş bulunamadı');
      }

      // Teslim edildiyse payment_status'u da paid yap
      final updateData = <String, dynamic>{
        'status': status.dbValue,
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      // Sipariş teslim edildiyse ödeme durumunu da "paid" yap
      if (status == OrderStatus.delivered) {
        updateData['payment_status'] = 'paid';
      }

      final response = await _supabase
          .from('orders')
          .update(updateData)
          .eq('id', orderId)
          .select()
          .maybeSingle();

      if (response == null) {
        throw Exception('Sipariş güncellenemedi');
      }

      final updatedOrder = Order.fromJson(response);

      // Sipariş teslim edildiyse ödeme durumunu "paid" yap
      // Not: Stok düşürme artık DB trigger'ı tarafından yapılıyor
      // (decrease_product_stock, status='confirmed' olduğunda çalışır).
      // Dart tarafında çift düşümü önlemek için burada ek işlem yapılmıyor.
      if (status == OrderStatus.delivered) {
        debugPrint('✅ Sipariş teslim edildi - ödeme durumu "paid" yapıldı');
        
        // Email gönder (asenkron, hata uygulamayı engellemez)
        _emailService.sendDeliveryNotificationEmail(
          userId: updatedOrder.userId,
          orderId: updatedOrder.id,
          orderNumber: updatedOrder.orderNumberInt?.toString() ?? updatedOrder.id,
          shopName: updatedOrder.shopName ?? 'Dükkan',
          totalAmount: updatedOrder.totalAmount,
          deliveredAt: DateTime.now(),
        );
        
        // Değerlendirme bildirimi oluştur (SADECE BURADA - çift bildirimi önlemek için)
        try {
          // İlk ürün bilgisini al
          final productInfo = await _supabase
              .from('order_items')
              .select('product_id, products(name)')
              .eq('order_id', orderId)
              .limit(1)
              .maybeSingle();
          
          final productsData = productInfo?['products'] as Map<String, dynamic>?;
          final productName = productsData?['name'] as String?;
          
          // Tek teslim bildirimi - tipi order_delivered olmalı ki diğer modüllerle
          // (kurye akışı, bildirimler ekranı) aynı kanaldan işlensin.
          await _notificationService.createNotification(
            userId: updatedOrder.userId,
            type: 'order_delivered',
            title: 'Sipariş Teslim Edildi',
            content: productName != null
                ? '$productName için satıcıyı ve ürünü değerlendirin'
                : 'Satıcıyı ve ürünü değerlendirmek için tıklayın',
            entityId: orderId,
            entityImage: null,
          );

          debugPrint('✅ Teslim bildirimi gönderildi: orderId=$orderId');
        } catch (e) {
          debugPrint('⚠️ Değerlendirme bildirimi oluşturulamadı: $e');
        }
        
        return updatedOrder; // Teslim durumunda bildirim zaten gönderildi, metodu burada bitir
      }

      // Sipariş durumu bildirimi gönder (müşteriye) - delivered HARİÇ
      // Diğer durumlar: onaylandı, hazırlanıyor, yolda, iptal
      try {
        await _sendOrderStatusNotification(updatedOrder.userId, updatedOrder);
      } catch (notifError) {
        debugPrint('⚠️ Bildirim gönderilirken hata (sipariş güncellendi): $notifError');
      }
      
      return updatedOrder;
    } catch (e) {
      throw Exception('Sipariş durumu güncellenirken hata: $e');
    }
  }

  /// "Gel Al" siparişinde müşterinin teslim onayı (ready -> delivered).
  ///
  /// Doğrudan UPDATE yerine `confirm_pickup_order_received` SECURITY DEFINER
  /// RPC'si kullanılır: sahiplik, pickup olma, "hazır" durumu ve ödeme
  /// kontrolleri sunucuda yapılır; satıcı kazancı/bakiye trigger'ları da bu
  /// güncellemeyle normal akışında tetiklenir.
  Future<void> confirmPickupReceived(String orderId) async {
    try {
      await _supabase.rpc(
        'confirm_pickup_order_received',
        params: {'p_order_id': orderId},
      );
      debugPrint('✅ Gel Al siparişi teslim alındı olarak işaretlendi: $orderId');
    } catch (e) {
      debugPrint('❌ Gel Al teslim onayı hatası: $e');
      rethrow;
    }
  }

  // Ödeme durumunu güncelle
  Future<Order?> updatePaymentStatus(
    String orderId,
    String status,
  ) async {
    try {
      final response = await _supabase
          .from('orders')
          .update({
            'payment_status': status,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId)
          .select()
          .single();

      return Order.fromJson(response);
    } catch (e) {
      throw Exception('Ödeme durumu güncellenirken hata: $e');
    }
  }

  // Kurye ataması yap
  Future<Order?> assignCourier(
    String orderId,
    String courierName,
  ) async {
    try {
      final response = await _supabase
          .from('orders')
          .update({
            'courier_name': courierName,
            'status': 'on_the_way',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId)
          .select()
          .single();

      return Order.fromJson(response);
    } catch (e) {
      throw Exception('Kurye atanırken hata: $e');
    }
  }

  // Belirli bir durumdaki siparişleri getir
  Future<List<Order>> getOrdersByStatus(OrderStatus status) async {
    try {
      // ÖNEMLİ: status.dbValue kullanılmalı (onTheWay -> 'on_the_way').
      // status.name kullanılırsa 'onTheWay' gönderilir ama DB 'on_the_way'
      // sakladığından sorgu yolda siparişleri için sıfır satır dönerdi.
      final response = await _supabase
          .from('orders')
          .select('*, order_items(*)')
          .eq('status', status.dbValue)
          .order('created_at', ascending: false);

      return (response as List).map((json) => Order.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Siparişler yüklenirken hata: $e');
    }
  }

  // Siparişi iptal et
  Future<void> cancelOrder(String orderId, {String? reason}) async {
    try {
      await _supabase
          .from('orders')
          .update({
            'status': 'cancelled',
            'cancelled_at': DateTime.now().toUtc().toIso8601String(),
            'cancellation_reason': reason,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId);
    } catch (e) {
      throw Exception('Sipariş iptal edilirken hata: $e');
    }
  }

  // Sipariş istatistikleri (dükkânlar için)
  Future<Map<String, dynamic>> getShopStats(String shopId) async {
    try {
      final orders = await getShopOrders(shopId);

      int totalOrders = orders.length;
      double totalRevenue = 0;
      int completedOrders = 0;
      int pendingOrders = 0;

      for (var order in orders) {
        totalRevenue += order.totalAmount;
        if (order.status == OrderStatus.delivered) {
          completedOrders++;
        } else if (order.status == OrderStatus.pending ||
            order.status == OrderStatus.confirmed) {
          pendingOrders++;
        }
      }

      return {
        'totalOrders': totalOrders,
        'totalRevenue': totalRevenue,
        'completedOrders': completedOrders,
        'pendingOrders': pendingOrders,
        'averageRating': 0.0, // Veritabanından hesaplanabilir
      };
    } catch (e) {
      throw Exception('İstatistikler yüklenirken hata: $e');
    }
  }

  // Adres formatlama yardımcı metodu
  String _formatAddress(Map<String, dynamic> addr) {
    final parts = <String>[];
    if (addr['title'] != null && addr['title'].toString().isNotEmpty) {
      parts.add(addr['title']);
    }
    if (addr['address_line'] != null && addr['address_line'].toString().isNotEmpty) {
      parts.add(addr['address_line']);
    } else if (addr['full_address'] != null && addr['full_address'].toString().isNotEmpty) {
      parts.add(addr['full_address']);
    }
    if (addr['district'] != null && addr['district'].toString().isNotEmpty) {
      parts.add(addr['district']);
    }
    if (addr['city'] != null && addr['city'].toString().isNotEmpty) {
      parts.add(addr['city']);
    }
    return parts.join(', ');
  }

  // Not: Teslimat sonrası stok düşürme kaldırıldı.
  // Stok düşürme artık DB trigger'ı (decrease_product_stock) tarafından
  // sipariş statusu 'confirmed' olduğunda otomatik yapılıyor.
  // Dart tarafında çift düşümü önlemek için _decreaseStockOnDelivery metodu kullanılmıyor.

  // Sipariş durumu bildirimi gönder
  // NOT: delivered durumu updateOrderStatus'ta ayrıca ele alınıyor
  Future<void> _sendOrderStatusNotification(String userId, Order order) async {
    String type = 'order_update';
    String title = '';
    String content = '';

    switch (order.status) {
      case OrderStatus.confirmed:
        title = 'Sipariş Onaylandı';
        content = 'Siparişiniz onaylandı ve hazırlanıyor';
        type = 'order_update';
        break;
      case OrderStatus.preparing:
        // Bildirim gönderme (kullanıcı istemedi)
        return;
      case OrderStatus.ready:
        // Bildirim gönderme (kullanıcı istemedi)
        return;
      case OrderStatus.onTheWay:
        title = 'Sipariş Yolda';
        content = 'Siparişiniz size teslim edilmek üzere yola çıktı';
        type = 'order_update';
        break;
      case OrderStatus.delivered:
        // Teslim bildirimi updateOrderStatus içinde TEK SEFER oluşturuluyor.
        // Çift bildirimi önlemek için burada ekstra bildirim göndermiyoruz.
        return;
      case OrderStatus.cancelled:
        title = 'Siparişiniz İptal Edildi';
        content = 'Siparişiniz iptal edildi';
        type = 'order_update';
        break;
      default:
        return; // Diğer durumlarda bildirim gönderme
    }

    // Bildirim hatası email gönderimini engellemez (try-catch)
    try {
      await _notificationService.createNotification(
        userId: userId,
        type: type,
        title: title,
        content: content,
        entityId: order.id,
      );
    } catch (e) {
      debugPrint('❌ Bildirim gönderilirken hata (devam ediliyor): $e');
      // Hata olsa bile devam et, email gönderimini engelleme
    }
  }
}
