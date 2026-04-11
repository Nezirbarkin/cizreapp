import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/order_model.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/email_service.dart';

class OrderService {
  final NotificationService _notificationService = NotificationService();
  final EmailService _emailService = EmailService();
  final SupabaseClient _supabase = Supabase.instance.client;

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
  }) async {
    try {
      debugPrint('🛒 ORDER: Sipariş oluşturuluyor...');
      debugPrint('  └─ userId: $userId');
      debugPrint('  └─ shopId: $shopId');
      debugPrint('  └─ total: $total');
      
      // Sipariş numarası oluştur
      final orderNumber = 'ORD${DateTime.now().millisecondsSinceEpoch}';
      debugPrint('  └─ orderNumber: $orderNumber');

      debugPrint('🛒 ORDER: INSERT işlemi başlatılıyor...');
      
      // INSERT işlemini yap (SELECT tetiklemeden) - GERÇEK HATAYI GÖR
      // Not: Komisyon alanları SQL trigger tarafından otomatik doldurulur
      // (admin_commission, admin_delivery_fee, seller_net_amount, commission_status)
      try {
        await _supabase.from('orders').insert({
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
          // Komisyon alanları trigger tarafından otomatik doldurulacak
          // (admin_commission, admin_delivery_fee, seller_net_amount, commission_status)
          'status': 'pending',
          'notes': notes,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
        debugPrint('✅ ORDER: INSERT basarili');
      } catch (insertError) {
        debugPrint('❌ ORDER: INSERT HATA YAKALANDI!');
        debugPrint('❌ ORDER: Hata tipi: ${insertError.runtimeType}');
        if (insertError is PostgrestException) {
          debugPrint('❌ ORDER: PostgrestException - INSERT Failed:');
          debugPrint('  ├─ message: ${insertError.message}');
          debugPrint('  ├─ code: ${insertError.code}');
          debugPrint('  ├─ details: ${insertError.details}');
          debugPrint('  └─ hint: ${insertError.hint}');
        } else {
          debugPrint('❌ ORDER: $insertError');
        }
        rethrow; // Hatayı yukarıya fırlat
      }
      
      debugPrint('🛒 ORDER: Order nesnesi getiriliyor...');
      
      late Order order;
      bool selectSuccess = false;
      
      // SELECT policy'si recursive loop yapabilir, try-catch ile yakala
      try {
        final response = await _supabase
            .from('orders')
            .select()
            .eq('order_number', orderNumber)
            .eq('user_id', userId)
            .maybeSingle();
        
        if (response != null) {
          debugPrint('✅ ORDER: Order nesnesi olusturuluyor...');
          order = Order.fromJson(response);
          debugPrint('✅ ORDER: Order olusturuldu - ID: ${order.id}');
          selectSuccess = true;
        } else {
          throw Exception('SELECT returned null');
        }
      } catch (selectError) {
        // SELECT policy'sine takildi ama veri database'de var
        debugPrint('WARN: SELECT hata yakalandi: $selectError');
        debugPrint('WARN: Order localden olusturuluyor...');
        order = Order(
          id: 'ORDER_${DateTime.now().millisecondsSinceEpoch}',
          userId: userId,
          shopId: shopId,
          subtotal: subtotal,
          discountAmount: discount,
          deliveryFee: deliveryFee,
          totalAmount: total,
          status: OrderStatus.pending,
          paymentMethod: paymentMethod,
          paymentStatus: 'pending',
          items: [],
          deliveryNotes: notes,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        debugPrint('WARN: Local Order olusturuldu');
        debugPrint('WARN: Supabase RLS policy recursive loop yapiyor!');
        debugPrint('WARN: FIX: FIX_ORDERS_POLICIES_CLEAN.sql SQL Editorda calistir');
        selectSuccess = false;
      }

      // Sipariş öğelerini kaydet - SADECE SELECT başarılı olduysa
      if (selectSuccess) {
        debugPrint('🛒 ORDER: Sipariş öğeleri ekleniyor (${items.length} adet)...');
        for (var i = 0; i < items.length; i++) {
          final item = items[i];
          debugPrint('  └─ Item ${i + 1}: ${item.productName} x${item.quantity}');
          await _supabase.from('order_items').insert({
            'order_id': order.id,
            'product_id': item.productId,
            'product_name': item.productName,
            'price': item.price,  // Hem price hem product_price ekle
            'product_price': item.price,  // Schema'da product_price olarak adlandirilmis
            'quantity': item.quantity,
            'subtotal': item.subtotal,  // ZORUNLU ALAN - price * quantity
            'product_image_url': item.productImageUrl,
            'shop_id': item.shopId,
            'shop_name': item.shopName,
            'created_at': DateTime.now().toIso8601String(),
          });
        }
        debugPrint('✅ ORDER: Tüm sipariş öğeleri eklendi');
        
        // Stok düşürme - Sipariş oluşturulduğunda stokları güncelle
        debugPrint('📦 STOCK: Stoklar düşürülüyor...');
        for (var i = 0; i < items.length; i++) {
          final item = items[i];
          try {
            // Mevcut stok miktarını al
            final productResponse = await _supabase
                .from('products')
                .select('stock')
                .eq('id', item.productId)
                .maybeSingle();
            
            if (productResponse != null) {
              final currentStock = productResponse['stock'] as int? ?? 0;
              final newStock = currentStock - item.quantity;
              
              // Stoku güncelle (negatif olamaz)
              await _supabase
                  .from('products')
                  .update({
                    'stock': newStock < 0 ? 0 : newStock,
                    'updated_at': DateTime.now().toIso8601String(),
                  })
                  .eq('id', item.productId);
              
              debugPrint('  └─ ${item.productName}: $currentStock -> ${newStock < 0 ? 0 : newStock} (sipariş: ${item.quantity})');
            }
          } catch (stockError) {
            debugPrint('⚠️ STOCK: Stok güncellenirken hata (${item.productName}): $stockError');
            // Stok hatası sipariş işlemini durdurmaz
          }
        }
        debugPrint('✅ STOCK: Stok düşürme işlemi tamamlandı');
      } else {
        debugPrint('WARN: Fallback Order kullanildi, order_items eklenmedi');
        debugPrint('WARN: Siparis database\'de mevcut ama SELECT hatasi nedeniyle alinamadi');
      }
      
      // NOT: Satıcıya bildirim artık SQL trigger tarafından gönderiliyor
      // FIX_ORDER_NOTIFICATIONS_TURKISH.sql ile duplike önleme
      
      // Satıcıya "yeni sipariş" e-postası gönder (Dart tarafından doğrudan)
      try {
        // Müşteri bilgilerini al
        final customerProfile = await _supabase
            .from('profiles')
            .select('full_name, username')
            .eq('id', userId)
            .maybeSingle();
        
        final customerName = customerProfile?['full_name'] as String? ??
                            customerProfile?['username'] as String? ?? 'Müşteri';
        
        // Ürün bilgilerini hazırla
        final orderItemsList = items.map((item) => {
          'product_name': item.productName,
          'quantity': item.quantity,
          'price': item.price,
        }).toList();
        
        // Satıcıya email gönder
        _emailService.sendNewOrderEmailToSeller(
          shopId: shopId,
          orderId: order.id,
          orderNumber: order.orderNumberInt?.toString() ?? order.id.substring(0, 8),
          customerName: customerName,
          deliveryAddress: deliveryAddressText,
          totalAmount: total,
          orderItems: orderItemsList,
        );
        
        // Admin'e email gönder
        final shopNameResp = await _supabase
            .from('shops')
            .select('name')
            .eq('id', shopId)
            .maybeSingle();
        final shopNameStr = shopNameResp?['name'] as String? ?? 'Mağaza';
        
        _emailService.sendNewOrderEmailToAdmin(
          shopId: shopId,
          orderId: order.id,
          orderNumber: order.orderNumberInt?.toString() ?? order.id.substring(0, 8),
          shopName: shopNameStr,
          customerName: customerName,
          deliveryAddress: deliveryAddressText,
          totalAmount: total,
          orderItems: orderItemsList,
        );
        
        debugPrint('📧 ORDER: E-posta bildirimi Dart tarafından gönderildi');
      } catch (emailError) {
        debugPrint('⚠️ ORDER: E-posta gönderilirken hata (sipariş etkilenmez): $emailError');
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

      // Sipariş teslim edildiyse stokları düşür
      if (status == OrderStatus.delivered) {
        await _decreaseStockOnDelivery(orderId);
        debugPrint('✅ Sipariş teslim edildi - ödeme durumu "paid" yapıldı');
        
        // Email gönder (asenkron, hata uygulamayı engellemez)
        _emailService.sendDeliveryNotificationEmail(
          userId: updatedOrder.userId,
          orderNumber: updatedOrder.orderNumberInt?.toString() ?? updatedOrder.id,
          shopName: updatedOrder.shopName ?? 'Dükkan',
          totalAmount: updatedOrder.totalAmount,
          deliveredAt: DateTime.now(),
        );
        
        // Değerlendirme bildirimi oluştur
        try {
          final notificationService = NotificationService();
          final shopName = updatedOrder.shopName ?? 'Dükkan';
          
          // İlk ürün bilgisini al
          final productInfo = await _supabase
              .from('order_items')
              .select('product_id, products(name)')
              .eq('order_id', orderId)
              .limit(1)
              .maybeSingle();
          
          final productId = productInfo?['product_id'] as String?;
          final productsData = productInfo?['products'] as Map<String, dynamic>?;
          final productName = productsData?['name'] as String?;
          
          await notificationService.createReviewNotification(
            userId: updatedOrder.userId,
            orderId: orderId,
            shopName: shopName,
            productId: productId,
            productName: productName,
          );
        } catch (e) {
          debugPrint('⚠️ Değerlendirme bildirimi oluşturulamadı: $e');
        }
      }

      // Sipariş durumu bildirimi gönder (müşteriye)
      // Dart tarafından gönderiyoruz (SQL trigger varsa da devre dışı bırakılmalı)
      // NOT: delivered durumu için yukarıda zaten createReviewNotification çağrıldı
      if (status != OrderStatus.delivered) {
        try {
          await _sendOrderStatusNotification(updatedOrder.userId, updatedOrder);
        } catch (notifError) {
          debugPrint('⚠️ Bildirim gönderilirken hata (sipariş güncellendi): $notifError');
        }
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
      final response = await _supabase
          .from('orders')
          .select('*, order_items(*)')
          .eq('status', status.name)
          .order('created_at', ascending: false);

      return (response as List).map((json) => Order.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Siparişler yüklenirken hata: $e');
    }
  }

  // Siparişi iptal et
  Future<void> cancelOrder(String orderId) async {
    try {
      await _supabase
          .from('orders')
          .update({
            'status': 'cancelled',
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

  // Teslimat sonrası stok düşürme
  Future<void> _decreaseStockOnDelivery(String orderId) async {
    try {
      debugPrint('📦 Stok düşürme başlatılıyor: $orderId');
      
      // Sipariş kalemlerini getir
      final orderItemsResponse = await _supabase
          .from('order_items')
          .select('product_id, quantity')
          .eq('order_id', orderId);
      
      if (orderItemsResponse.isEmpty) {
        debugPrint('⚠️ Sipariş kalemleri bulunamadı, stok düşürülemedi');
        return;
      }
      
      // Her ürün için stoğu düşür
      for (var item in orderItemsResponse) {
        final productId = item['product_id'];
        final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
        
        if (productId == null || quantity <= 0) continue;
        
        // Mevcut stok bilgisini al
        final productResponse = await _supabase
            .from('products')
            .select('stock')
            .eq('id', productId)
            .maybeSingle();
        
        if (productResponse == null) {
          debugPrint('⚠️ Ürün bulunamadı: $productId');
          continue;
        }
        
        final currentStock = (productResponse['stock'] as num?)?.toInt() ?? 0;
        final newStock = currentStock - quantity;
        
        // Stoğu güncelle (negatife düşmesini engelle)
        await _supabase
            .from('products')
            .update({
              'stock': newStock < 0 ? 0 : newStock,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', productId);
        
        debugPrint('✅ Stok güncellendi: Ürün=$productId, Eski=$currentStock, Yeni=$newStock');
      }
      
      debugPrint('🎉 Tüm stoklar başarıyla düşürüldü');
    } catch (e) {
      debugPrint('❌ Stok düşürme hatası: $e');
      // Stok hatası siparişi engellemeziz
    }
  }

  // Sipariş durumu bildirimi gönder
  Future<void> _sendOrderStatusNotification(String userId, Order order) async {
    String type = 'order_update';
    String title = '';
    String content = '';

    switch (order.status) {
      case OrderStatus.confirmed:
        title = 'Siparişiniz Onaylandı';
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
        title = 'Siparişiniz Yolda';
        content = 'Siparişiniz size teslim edilmek üzere yola çıktı';
        type = 'order_update';
        break;
      case OrderStatus.delivered:
        // Değerlendirme bildirimi gönder
        await _sendReviewRequestNotification(userId, order);
        return; // Bildirim _sendReviewRequestNotification'da gönderiliyor
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

  /// Değerlendirme istek bildirimi gönder (teslimat sonrası)
  Future<void> _sendReviewRequestNotification(String userId, Order order) async {
    try {
      // Siparişteki ilk ürünü ve dükkan bilgisini al
      final productInfo = order.items.isNotEmpty ? order.items.first : null;
      
      String content;
      if (productInfo != null) {
        content = 'Ürünü ve satıcıyı değerlendirmek için tıklayın';
      } else {
        content = 'Siparişinizi değerlendirmek için tıklayın';
      }

      // Değerlendirme bildirimi gönder
      await _notificationService.createNotification(
        userId: userId,
        type: 'review_request', // Yeni bildirim tipi
        title: 'Siparişiniz Teslim Edildi! 🎉',
        content: content,
        entityId: order.id,
        entityImage: productInfo?.productImageUrl,
      );
      
      debugPrint('✅ Değerlendirme bildirimi gönderildi: orderId=${order.id}');
    } catch (e) {
      debugPrint('❌ Değerlendirme bildirimi gönderilirken hata: $e');
      // Hata olsa bile işlemi engelleme
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
          final total = subtotal + deliveryFee;
          
          debugPrint('  ├─ subtotal: $subtotal');
          debugPrint('  ├─ deliveryFee: $deliveryFee');
          debugPrint('  ├─ commissionAmount: $commissionAmount');
          debugPrint('  └─ total: $total');
          
          // Sipariş numarası oluştur
          final orderNumber = 'ORD${DateTime.now().millisecondsSinceEpoch}_${shopId.substring(0, 6)}';
          
          // Siparişi oluştur
          await _supabase.from('orders').insert({
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
            'discount': 0,
            'total': total,
            'status': 'pending',
            'notes': notes,
            'order_group_id': orderGroupId,
            'group_order_number': groupOrderNumber,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });
          
          // Siparişi getir
          final orderResponse = await _supabase
              .from('orders')
              .select()
              .eq('order_number', orderNumber)
              .maybeSingle();
          
          if (orderResponse != null) {
            final order = Order.fromJson(orderResponse);
            
            // Sipariş öğelerini ekle
            for (final item in items) {
              await _supabase.from('order_items').insert({
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
              });
              
              // Stok düşür
              try {
                final productResponse = await _supabase
                    .from('products')
                    .select('stock')
                    .eq('id', item.productId)
                    .maybeSingle();
                
                if (productResponse != null) {
                  final currentStock = productResponse['stock'] as int? ?? 0;
                  final newStock = currentStock - item.quantity;
                  
                  await _supabase
                      .from('products')
                      .update({
                        'stock': newStock < 0 ? 0 : newStock,
                        'updated_at': DateTime.now().toIso8601String(),
                      })
                      .eq('id', item.productId);
                  
                  debugPrint('  └─ Stok güncellendi: ${item.productName} ($currentStock -> $newStock)');
                }
              } catch (stockError) {
                debugPrint('⚠️ Stok güncellenirken hata: $stockError');
              }
            }
            
            createdOrders.add(order);
            debugPrint('✅ Dükkan $shopId siparişi oluşturuldu');
            
            // Satıcıya ve Admin'e email gönder
            try {
              final customerProfile = await _supabase
                  .from('profiles')
                  .select('full_name, username')
                  .eq('id', userId)
                  .maybeSingle();
              
              final customerName = customerProfile?['full_name'] as String? ??
                                  customerProfile?['username'] as String? ?? 'Müşteri';
              
              final orderItemsList = items.map((item) => {
                'product_name': item.productName,
                'quantity': item.quantity,
                'price': item.price,
              }).toList();
              
              final shopNameResp = await _supabase
                  .from('shops')
                  .select('name')
                  .eq('id', shopId)
                  .maybeSingle();
              final shopNameStr = shopNameResp?['name'] as String? ?? 'Mağaza';
              
              // Satıcıya email
              _emailService.sendNewOrderEmailToSeller(
                shopId: shopId,
                orderId: order.id,
                orderNumber: order.orderNumberInt?.toString() ?? order.id.substring(0, 8),
                customerName: customerName,
                deliveryAddress: deliveryAddressText,
                totalAmount: total,
                orderItems: orderItemsList,
              );
              
              // Admin'e email
              _emailService.sendNewOrderEmailToAdmin(
                shopId: shopId,
                orderId: order.id,
                orderNumber: order.orderNumberInt?.toString() ?? order.id.substring(0, 8),
                shopName: shopNameStr,
                customerName: customerName,
                deliveryAddress: deliveryAddressText,
                totalAmount: total,
                orderItems: orderItemsList,
              );
              
              debugPrint('📧 Multi-shop: Email gönderildi (Dükkan: $shopNameStr)');
            } catch (emailError) {
              debugPrint('⚠️ Email gönderilirken hata (sipariş etkilenmez): $emailError');
            }
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
