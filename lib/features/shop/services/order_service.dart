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

  // Sipariş oluştur
  Future<Order?> createOrder({
    required String userId,
    required String shopId,
    required List<OrderItem> items,
    required String deliveryAddressText,
    String? addressId,
    required double subtotal,
    required double deliveryFee,
    required double discount,
    required double total,
    required double commissionAmount,
    PaymentMethod paymentMethod = PaymentMethod.cash,
    String? notes,
    String? customerPhone, // Müşteri telefonu eklendi
    InvoiceInfo? invoiceInfo, // Fatura bilgileri eklendi
    String? couponId, // Uygulanan kupon (orders.coupon_id)
    double couponDiscount = 0, // Kupon indirimi (orders.coupon_discount)
  }) async {
    try {
      debugPrint('🛒 ORDER: Sipariş oluşturuluyor...');
      debugPrint('  └─ userId: $userId');
      debugPrint('  └─ shopId: $shopId');
      debugPrint('  └─ total: $total');

      // 0 TL siparişler için kullanıcı başı limit kontrolü
      if (total <= 0) {
        // İptal edilen siparişleri sayma: kullanıcı iptal ettiyse hakkı geri döner.
        final freeOrderResponse = await _supabase
            .from('orders')
            .select('id')
            .eq('user_id', userId)
            .eq('total', 0)
            .neq('status', 'cancelled')
            .count(CountOption.exact);
        final freeOrderCount = freeOrderResponse.count;
        if (freeOrderCount >= freeOrderLimitPerUser) {
          debugPrint('🛒 ORDER: Ücretsiz sipariş limiti aşıldı ($freeOrderCount/$freeOrderLimitPerUser)');
          throw Exception('Ücretsiz sipariş hakkınızı kullandınız. Bu üründen sadece $freeOrderLimitPerUser kez ücretsiz sipariş verebilirsiniz.');
        }
      }

      // Sipariş numarası oluştur
      final orderNumber = 'ORD${DateTime.now().millisecondsSinceEpoch}';
      debugPrint('  └─ orderNumber: $orderNumber');

      // Fatura bilgilerini hazırla
      final invoiceData = invoiceInfo?.toOrderSnapshot() ?? {};

      debugPrint('🛒 ORDER: INSERT işlemi başlatılıyor...');

      // Siparişi oluştur ve gerçek satırı (UUID dahil) tek gidişte al.
      // orders SELECT RLS artık düzeltildi (20260209000001 + 20260209000002),
      // bu yüzden insert().select() güvenli çalışır. Eski kod INSERT'i
      // SELECT'ten ayırıp SELECT başarısız olursa SAHTE bir Order
      // (id: 'ORDER_<ts>') döndürüyordu — bu durumda order_items HİÇ
      // eklenmiyor, bakiye sahte ID ile düşülmeye çalışılıyor ve DB'de
      // ürünsüz asılı bir sipariş kalıyordu. Artık tek gidişte gerçek satır
      // alınıyor; başarısızlıkta sipariş temiz şekilde başarısız olur
      // (asılı boş sipariş oluşmaz). insert().select() Postgres RETURNING
      // kullandığı için order_number çakışması da yanlış satır döndürmez.
      // Komisyon alanları SQL trigger tarafından otomatik doldurulur
      // (admin_commission, admin_delivery_fee, seller_net_amount, commission_status).
      final orderResponse = await _supabase.from('orders').insert({
        'order_number': orderNumber,
        'user_id': userId,
        'shop_id': shopId,
        'delivery_address_text': deliveryAddressText,
        'address_id': addressId,
        'customer_phone': customerPhone,
        'payment_method': paymentMethod.name,
        'payment_status': 'pending',
        'subtotal': subtotal,
        'delivery_fee': deliveryFee,
        'discount': discount,
        'total': total,
        // Kupon kaydı: coupon_id/coupon_discount eskiden hiç yazılmıyordu
        // (model okuyordu ama insert atlıyordu). Artık yazılıyor; kullanım
        // sayacı ayrıca use_coupon RPC ile artırılır.
        if (couponId != null) 'coupon_id': couponId,
        'coupon_discount': couponDiscount,
        // Komisyon alanları trigger tarafından otomatik doldurulacak.
        'status': 'pending',
        'notes': notes,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        // Fatura bilgileri
        if (invoiceData['invoice_type'] != null) 'invoice_type': invoiceData['invoice_type'],
        if (invoiceData['invoice_full_name'] != null) 'invoice_full_name': invoiceData['invoice_full_name'],
        if (invoiceData['invoice_tax_number'] != null) 'invoice_tax_number': invoiceData['invoice_tax_number'],
        if (invoiceData['invoice_tc_no'] != null) 'invoice_tc_no': invoiceData['invoice_tc_no'],
        if (invoiceData['invoice_tax_office'] != null) 'invoice_tax_office': invoiceData['invoice_tax_office'],
        if (invoiceData['invoice_address'] != null) 'invoice_address': invoiceData['invoice_address'],
        if (invoiceData['invoice_email'] != null) 'invoice_email': invoiceData['invoice_email'],
      }).select().single();
      final order = Order.fromJson(orderResponse);
      debugPrint('✅ ORDER: INSERT başarılı - ID: ${order.id}');

      // Sipariş öğelerini kaydet.
      debugPrint('🛒 ORDER: Sipariş öğeleri ekleniyor (${items.length} adet)...');
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        debugPrint('  └─ Item ${i + 1}: ${item.productName} x${item.quantity}'
            '${item.isFlashSaleItem ? " [FLASH SALE]" : ""}');
        final insertMap = <String, dynamic>{
          'order_id': order.id,
          'product_id': item.productId,
          'product_name': item.productName,
          'price': item.price, // Hem price hem product_price ekle
          'product_price': item.price, // Schema'da product_price olarak adlandırılmış
          'quantity': item.quantity,
          'subtotal': item.subtotal, // ZORUNLU ALAN - price * quantity
          'product_image_url': item.productImageUrl,
          'shop_id': item.shopId,
          'shop_name': item.shopName,
          'created_at': DateTime.now().toIso8601String(),
        };
        // Flaş satış bilgisi varsa ekle (faturalama/raporlama için).
        if (item.flashSaleId != null) {
          insertMap['flash_sale_id'] = item.flashSaleId;
        }
        if (item.flashPrice != null) {
          insertMap['flash_price'] = item.flashPrice;
        }
        await _supabase.from('order_items').insert(insertMap);
      }
      debugPrint('✅ ORDER: Tüm sipariş öğeleri eklendi');

      // Not: Stok düşürme artık DB trigger'ı (decrease_product_stock) tarafından
      // sipariş statusu 'confirmed' olduğunda otomatik yapılıyor.
      // Dart tarafında çift düşümü önlemek için burada ek işlem yapılmıyor.
      debugPrint('📦 STOCK: Stok düşürme DB trigger\'ına bırakıldı (confirmed durumunda)');

      // Satıcıya bildirimler:
      // - EMAIL → DB trigger'ı `notify_new_order_email` (migration 20260204000000)
      //   Edge Function `send-order-email` ile zaten gönderiyor. Dart'tan
      //   tekrar göndermek ÇİFT email yaratıyordu. Bu nedenle email adımı
      //   kaldırıldı (2026-07-29 FIX).
      // - PUSH → Dart tarafından gönderiliyor (DB'de push kanalı yok).

      // Müşteri adını al (push bildirim içeriği için)
      String customerName = 'Müşteri';
      try {
        final customerProfile = await _supabase
            .from('profiles')
            .select('full_name, username')
            .eq('id', userId)
            .maybeSingle();

        customerName = customerProfile?['full_name'] as String? ??
                       customerProfile?['username'] as String? ?? 'Müşteri';
      } catch (e) {
        debugPrint('⚠️ ORDER: Müşteri profili alınamadı (push etkilenmez): $e');
      }

      // 🔔 SATICIYA PUSH BİLDİRİMİ GÖNDER
      try {
        final shopOwnerResp = await _supabase
            .from('shops')
            .select('owner_id')
            .eq('id', shopId)
            .maybeSingle();

        final shopOwnerId = shopOwnerResp?['owner_id'] as String?;

        if (shopOwnerId != null) {
          await _notificationService.createNotification(
            userId: shopOwnerId,
            type: 'new_order',
            title: 'Yeni Sipariş!',
            content: '$customerName - ₺${total.toStringAsFixed(2)} tutarında yeni sipariş geldi!',
            actorId: userId,
            actorName: customerName,
            entityId: order.id,
          );

          debugPrint('🔔 ORDER: Satıcıya push bildirimi gönderildi (ownerId: $shopOwnerId)');
        } else {
          debugPrint('⚠️ ORDER: Mağaza sahibi bulunamadı, push gönderilemedi');
        }
      } catch (notifError) {
        debugPrint('⚠️ ORDER: Push bildirim gönderilirken hata (sipariş etkilenmez): $notifError');
      }

      return order;
    } catch (e) {
      debugPrint('❌ ORDER: Sipariş oluşturulurken hata: $e');
      debugPrint('❌ ORDER: Hata tipi: ${e.runtimeType}');
      if (e is PostgrestException) {
        debugPrint('❌ ORDER: PostgrestException details:');
        debugPrint('  └─ message: ${e.message}');
        debugPrint('  └─ code: ${e.code}');
        debugPrint('  └─ details: ${e.details}');
        debugPrint('  └─ hint: ${e.hint}');
      }
      throw Exception('Sipariş oluşturulurken hata: $e');
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
            'cancelled_at': DateTime.now().toIso8601String(),
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

  /// Çok dükkanlı sipariş oluştur
  /// Sepetteki her dükkan için ayrı sipariş oluşturur
  Future<MultiShopOrderResult> createMultiShopOrder({
    required String userId,
    required Map<String, List<OrderItem>> itemsByShop, // shopId -> items
    required String deliveryAddressText,
    String? addressId,
    required PaymentMethod paymentMethod,
    String? notes,
    String? customerPhone, // Müşteri telefonu eklendi
    InvoiceInfo? invoiceInfo, // Fatura bilgileri eklendi
    Map<String, double>? discountByShop, // shopId -> indirim tutarı (kupon vb.)
    Map<String, String?>? couponIdByShop, // shopId -> kupon id (orders.coupon_id)
    Map<String, double>? couponDiscountByShop, // shopId -> kupon indirimi (orders.coupon_discount)
  }) async {
    try {
      debugPrint('🛒 MULTI-SHOP ORDER: Çok dükkanlı sipariş oluşturuluyor...');
      debugPrint('  └─ Dükkan sayısı: ${itemsByShop.length}');
      
      // Grup sipariş ID ve numara oluştur (sadece timestamp, UUID değil)
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final orderGroupId = 'GRP_$timestamp';
      final groupOrderNumber = 'GRP$timestamp';
      
      debugPrint('  └─ orderGroupId: $orderGroupId');
      debugPrint('  └─ groupOrderNumber: $groupOrderNumber');
      
      final List<Order> createdOrders = [];
      final List<String> errors = [];
      
      // Her dükkan için ayrı sipariş oluştur
      for (final entry in itemsByShop.entries) {
        final shopId = entry.key;
        final items = entry.value;
        
        try {
          debugPrint('📦 Dükkan $shopId için sipariş oluşturuluyor...');
          
          // Ara toplam hesapla
          double subtotal = 0;
          for (final item in items) {
            subtotal += item.price * item.quantity;
          }
          
          // Dükkan teslimat ücretini al
          final shopResponse = await _supabase
              .from('shops')
              .select('delivery_fee, has_own_courier, commission_rate')
              .eq('id', shopId)
              .single();
          
          final deliveryFee = (shopResponse['delivery_fee'] as num?)?.toDouble() ?? 15.0;
          final commissionRate = (shopResponse['commission_rate'] as num?)?.toDouble() ?? 10.0;
          final commissionAmount = subtotal * (commissionRate / 100);
          // İndirim (kupon vb.) discountByShop'tan; eski kod 'discount': 0
          // hardcoded ediyordu ve checkout'taki kuponu sessizce atıyordu.
          final discount = discountByShop?[shopId] ?? 0.0;
          final couponId = couponIdByShop?[shopId];
          final couponDiscount = couponDiscountByShop?[shopId] ?? 0.0;
          final total = subtotal + deliveryFee - discount;
          
          debugPrint('  ├─ subtotal: $subtotal');
          debugPrint('  ├─ deliveryFee: $deliveryFee');
          debugPrint('  ├─ commissionAmount: $commissionAmount');
          debugPrint('  └─ total: $total');
          
          // Sipariş numarası oluştur. shopId 6 karakterden kısaysa
          // .substring(0,6) RangeError fırlatıyordu; güvenli ön ek al.
          final prefix = shopId.length >= 6 ? shopId.substring(0, 6) : shopId;
          final orderNumber = 'ORD${DateTime.now().millisecondsSinceEpoch}_$prefix';

          // 0 TL siparişler için kullanıcı başı limit kontrolü (tekli createOrder
          // ile tutarlı). İptal edilenler sayılmaz.
          if (total <= 0) {
            final freeOrderResponse = await _supabase
                .from('orders')
                .select('id')
                .eq('user_id', userId)
                .eq('total', 0)
                .neq('status', 'cancelled')
                .count(CountOption.exact);
            if (freeOrderResponse.count >= freeOrderLimitPerUser) {
              throw Exception(
                  'Ücretsiz sipariş hakkınızı kullandınız. '
                  'Bu üründen sadece $freeOrderLimitPerUser kez ücretsiz sipariş verebilirsiniz.');
            }
          }
          
          // Fatura bilgilerini hazırla
          final invoiceData = invoiceInfo?.toOrderSnapshot() ?? {};
          
          // Siparişi oluştur ve gerçek satırı tek gidişte al (insert().select()).
          // Eski ayrı SELECT + maybeSingle(), order_number çakışmasında user_id
          // filtresiz yanlış siparişi çekebilirdi; insert().select() Postgres
          // RETURNING ile gerçek eklenen satırı döndürür (çakışma-güvenli).
          final orderResponse = await _supabase.from('orders').insert({
            'order_number': orderNumber,
            'user_id': userId,
            'shop_id': shopId,
            'delivery_address_text': deliveryAddressText,
            'address_id': addressId,
            'customer_phone': customerPhone, // Müşteri telefonu eklendi
            'payment_method': paymentMethod.name,
            'payment_status': 'pending',
            'subtotal': subtotal,
            'delivery_fee': deliveryFee,
            'discount': discount,
            'total': total,
            // Kupon kaydı (multi-shop): eskiden yazılmıyordu.
            if (couponId != null) 'coupon_id': couponId,
            'coupon_discount': couponDiscount,
            'status': 'pending',
            'notes': notes,
            'order_group_id': orderGroupId,
            'group_order_number': groupOrderNumber,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
            // Fatura bilgileri
            if (invoiceData['invoice_type'] != null) 'invoice_type': invoiceData['invoice_type'],
            if (invoiceData['invoice_full_name'] != null) 'invoice_full_name': invoiceData['invoice_full_name'],
            if (invoiceData['invoice_tax_number'] != null) 'invoice_tax_number': invoiceData['invoice_tax_number'],
            if (invoiceData['invoice_tc_no'] != null) 'invoice_tc_no': invoiceData['invoice_tc_no'],
            if (invoiceData['invoice_tax_office'] != null) 'invoice_tax_office': invoiceData['invoice_tax_office'],
            if (invoiceData['invoice_address'] != null) 'invoice_address': invoiceData['invoice_address'],
            if (invoiceData['invoice_email'] != null) 'invoice_email': invoiceData['invoice_email'],
          }).select().single();
          final order = Order.fromJson(orderResponse);
          debugPrint('✅ Dükkan $shopId siparişi oluşturuldu - ID: ${order.id}');

          // Sipariş öğelerini ekle
          for (final item in items) {
              final insertMap = <String, dynamic>{
                'order_id': order.id,
                'product_id': item.productId,
                'product_name': item.productName,
                'price': item.price,
                'product_price': item.price,
                'quantity': item.quantity,
                'subtotal': item.subtotal,
                'product_image_url': item.productImageUrl,
                'shop_id': item.shopId,
                'shop_name': item.shopName,
                'created_at': DateTime.now().toIso8601String(),
              };
              if (item.flashSaleId != null) {
                insertMap['flash_sale_id'] = item.flashSaleId;
              }
              if (item.flashPrice != null) {
                insertMap['flash_price'] = item.flashPrice;
              }
              await _supabase.from('order_items').insert(insertMap);
              
              // Not: Stok düşürme DB trigger'ı (decrease_product_stock) tarafından
              // sipariş statusu 'confirmed' olduğunda otomatik yapılıyor.
              // Dart tarafında çift düşümü önlemek için burada ek işlem yapılmıyor.
              debugPrint('  └─ Stok düşürme DB trigger\'ına bırakıldı (confirmed durumunda)');
            }
            
            createdOrders.add(order);
            debugPrint('✅ Dükkan $shopId siparişi oluşturuldu');

            // EMAIL → DB trigger'ı (notify_new_order_email) Edge Function
            // `send-order-email` ile zaten gönderiyor. Dart'tan tekrar göndermek
            // ÇİFT email yaratıyordu → kaldırıldı (2026-07-29 FIX).
            // PUSH → sadece Dart tarafından.

            // Müşteri adını al (push içeriği için)
            String customerName = 'Müşteri';
            try {
              final customerProfile = await _supabase
                  .from('profiles')
                  .select('full_name, username')
                  .eq('id', userId)
                  .maybeSingle();

              customerName = customerProfile?['full_name'] as String? ??
                             customerProfile?['username'] as String? ?? 'Müşteri';
            } catch (e) {
              debugPrint('⚠️ Multi-shop: Müşteri profili alınamadı: $e');
            }

            // 🔔 SATICIYA PUSH BİLDİRİMİ GÖNDER
            try {
              final shopOwnerResp = await _supabase
                  .from('shops')
                  .select('owner_id')
                  .eq('id', shopId)
                  .maybeSingle();

              final shopOwnerId = shopOwnerResp?['owner_id'] as String?;

              if (shopOwnerId != null) {
                await _notificationService.createNotification(
                  userId: shopOwnerId,
                  type: 'new_order',
                  title: 'Yeni Sipariş!',
                  content: '$customerName - ₺${total.toStringAsFixed(2)} tutarında yeni sipariş geldi!',
                  actorId: userId,
                  actorName: customerName,
                  entityId: order.id,
                );

                debugPrint('🔔 Multi-shop: Satıcıya push bildirimi gönderildi (ownerId: $shopOwnerId)');
              } else {
                debugPrint('⚠️ Multi-shop: Mağaza sahibi bulunamadı, push gönderilemedi');
              }
            } catch (notifError) {
              debugPrint('⚠️ Multi-shop: Push bildirim gönderilirken hata (sipariş etkilenmez): $notifError');
            }
        } catch (shopError) {
          debugPrint('❌ Dükkan $shopId için sipariş oluşturulamadı: $shopError');
          errors.add('Dükkan $shopId: $shopError');
        }
      }
      
      if (createdOrders.isEmpty) {
        throw Exception('Hiçbir sipariş oluşturulamadı. Hatalar: ${errors.join(", ")}');
      }
      
      debugPrint('🎉 Toplam ${createdOrders.length} sipariş oluşturuldu');
      
      return MultiShopOrderResult(
        orderGroupId: orderGroupId,
        groupOrderNumber: groupOrderNumber,
        orders: createdOrders,
        errors: errors,
      );
    } catch (e) {
      debugPrint('❌ Çok dükkanlı sipariş oluşturulurken hata: $e');
      rethrow;
    }
  }
}

/// Çok dükkanlı sipariş sonucu
class MultiShopOrderResult {
  final String orderGroupId;
  final String groupOrderNumber;
  final List<Order> orders;
  final List<String> errors;

  MultiShopOrderResult({
    required this.orderGroupId,
    required this.groupOrderNumber,
    required this.orders,
    required this.errors,
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get isSuccess => orders.isNotEmpty;
  int get orderCount => orders.length;
}
