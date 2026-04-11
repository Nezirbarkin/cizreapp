import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mağaza analitik verileri servisi
class ShopAnalyticsService {
  final _supabase = Supabase.instance.client;

  /// shop_views tablosunun mevcut olup olmadığını kontrol et
  Future<bool> _tableExists(String tableName) async {
    try {
      await _supabase.from(tableName).select('id').limit(1);
      return true;
    } catch (e) {
      debugPrint('⚠️ $tableName tablosu mevcut değil veya erişilemiyor: $e');
      return false;
    }
  }

  /// Mağaza görüntüleme kaydet
  Future<void> recordShopView(String shopId, {String? sessionId}) async {
    debugPrint('🔵 SHOP VISIT DEBUG: recordShopView çağrıldı, shopId: $shopId');
    try {
      final userId = _supabase.auth.currentUser?.id;
      debugPrint('🔵 SHOP VISIT DEBUG: userId: $userId');
      
      await _supabase.from('shop_views').insert({
        'shop_id': shopId,
        'user_id': userId,
        'session_id': sessionId,
        'viewed_at': DateTime.now().toIso8601String(),
      });
      debugPrint('✅ Shop view kaydedildi: $shopId');
    } catch (e) {
      debugPrint('🔴 SHOP VISIT DEBUG: Shop view kayıt hatası: $e');
      debugPrint('🔴 HATA DETAYI: ${e.toString()}');
    }
  }

  /// Ürün görüntüleme kaydet
  Future<void> recordProductView(String productId, String shopId, {String? sessionId}) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      
      await _supabase.from('product_views').insert({
        'product_id': productId,
        'shop_id': shopId,
        'user_id': userId,
        'session_id': sessionId,
        'viewed_at': DateTime.now().toIso8601String(),
      });
      debugPrint('✅ Product view kaydedildi: $productId');
    } catch (e) {
      debugPrint('⚠️ Product view kayıt hatası (tablo yok olabilir): $e');
    }
  }

  /// Mağaza toplam görüntüleme sayısı
  Future<int> getShopTotalViews(String shopId) async {
    debugPrint('🔵 SHOP VISIT DEBUG: getShopTotalViews çağrıldı, shopId: $shopId');
    
    // Yöntem 1: RPC
    try {
      debugPrint('🔵 SHOP VISIT DEBUG: RPC get_shop_total_views deneniyor...');
      final response = await _supabase
          .rpc('get_shop_total_views', params: {'p_shop_id': shopId});
      debugPrint('📊 Shop total views (RPC): $response');
      if (response != null) return (response as num).toInt();
    } catch (e) {
      debugPrint('🔴 SHOP VISIT DEBUG: RPC get_shop_total_views hatası: $e');
    }

    // Yöntem 2: Doğrudan count sorgusu
    try {
      debugPrint('🔵 SHOP VISIT DEBUG: Direct count shop_views deneniyor...');
      final result = await _supabase
          .from('shop_views')
          .select()
          .eq('shop_id', shopId)
          .count(CountOption.exact);
      debugPrint('📊 Shop total views (direct count): ${result.count}');
      return result.count;
    } catch (e) {
      debugPrint('🔴 SHOP VISIT DEBUG: shop_views doğrudan sorgu hatası: $e');
    }

    // Yöntem 3: Tablo yoksa 0 döndür
    debugPrint('🟡 SHOP VISIT DEBUG: Tablo yok veya erişilemiyor, 0 döndürülüyor');
    return 0;
  }

  /// Bugünün görüntüleme sayısı
  Future<int> getShopTodayViews(String shopId) async {
    debugPrint('🔵 SHOP VISIT DEBUG: getShopTodayViews çağrıldı, shopId: $shopId');
    
    // Yöntem 1: RPC
    try {
      debugPrint('🔵 SHOP VISIT DEBUG: RPC get_shop_today_views deneniyor...');
      final response = await _supabase
          .rpc('get_shop_today_views', params: {'p_shop_id': shopId});
      debugPrint('📊 Shop today views (RPC): $response');
      if (response != null) return (response as num).toInt();
    } catch (e) {
      debugPrint('🔴 SHOP VISIT DEBUG: RPC get_shop_today_views hatası: $e');
    }

    // Yöntem 2: Doğrudan count sorgusu
    try {
      debugPrint('🔵 SHOP VISIT DEBUG: Direct count shop_views (today) deneniyor...');
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final result = await _supabase
          .from('shop_views')
          .select()
          .eq('shop_id', shopId)
          .gte('viewed_at', todayStart.toIso8601String())
          .count(CountOption.exact);
      debugPrint('📊 Shop today views (direct count): ${result.count}');
      return result.count;
    } catch (e) {
      debugPrint('🔴 SHOP VISIT DEBUG: shop_views bugün sorgusu hatası: $e');
    }

    debugPrint('🟡 SHOP VISIT DEBUG: 0 döndürülüyor');
    return 0;
  }

  /// En çok görüntülenen ürünler
  Future<List<Map<String, dynamic>>> getTopViewedProducts(String shopId, {int limit = 10}) async {
    // Yöntem 1: RPC
    try {
      final response = await _supabase
          .rpc('get_top_viewed_products', params: {
            'p_shop_id': shopId,
            'p_limit': limit,
          });
      final responseList = response as List;
      if (responseList.isNotEmpty) {
        debugPrint('📊 Top viewed products (RPC): ${responseList.length} ürün');
        return List<Map<String, dynamic>>.from(responseList);
      }
    } catch (e) {
      debugPrint('⚠️ RPC get_top_viewed_products hatası: $e');
    }

    // Yöntem 2: Doğrudan sorgu ile product_views + products join
    try {
      final response = await _supabase
          .from('product_views')
          .select('product_id, products!inner(name)')
          .eq('shop_id', shopId);
      
      if ((response as List).isNotEmpty) {
        // Manuel gruplama
        final Map<String, Map<String, dynamic>> grouped = {};
        for (var row in response) {
          final productId = row['product_id'] as String;
          final productName = row['products']?['name'] as String? ?? 'Ürün';
          
          if (!grouped.containsKey(productId)) {
            grouped[productId] = {
              'product_id': productId,
              'product_name': productName,
              'view_count': 0,
            };
          }
          grouped[productId]!['view_count'] = (grouped[productId]!['view_count'] as int) + 1;
        }
        
        final result = grouped.values.toList();
        result.sort((a, b) => (b['view_count'] as int).compareTo(a['view_count'] as int));
        
        debugPrint('📊 Top viewed products (direct): ${result.length} ürün');
        return result.take(limit).toList();
      }
    } catch (e) {
      debugPrint('⚠️ product_views doğrudan sorgu hatası: $e');
    }

    // Yöntem 3: product_views yoksa, order_items'dan en çok sipariş edilen ürünleri göster
    // order_items.shop_id null olabilir, bu yüzden orders tablosu üzerinden filtrele
    try {
      debugPrint('📊 product_views yok, order_items kullanılıyor...');
      
      // Önce order_items.shop_id ile dene
      List<dynamic> orderItemsResponse = [];
      
      try {
        orderItemsResponse = await _supabase
            .from('order_items')
            .select('product_id, product_name, quantity')
            .eq('shop_id', shopId);
        debugPrint('📊 order_items (shop_id filtre): ${orderItemsResponse.length} kayıt');
      } catch (e) {
        debugPrint('⚠️ order_items shop_id filtresi başarısız: $e');
      }
      
      // shop_id ile sonuç yoksa, orders tablosu üzerinden al
      if (orderItemsResponse.isEmpty) {
        debugPrint('📊 order_items orders join deneniyor...');
        // Bu mağazanın siparişlerindeki ürünleri al
        final ordersResponse = await _supabase
            .from('orders')
            .select('id')
            .eq('shop_id', shopId)
            .neq('status', 'cancelled');
        
        if ((ordersResponse as List).isNotEmpty) {
          final orderIds = ordersResponse.map((o) => o['id'] as String).toList();
          debugPrint('📊 Mağazanın ${orderIds.length} siparişi bulundu');
          
          // Her sipariş için order_items al (in_ filtresi)
          orderItemsResponse = await _supabase
              .from('order_items')
              .select('product_id, product_name, quantity')
              .inFilter('order_id', orderIds);
          debugPrint('📊 order_items (orders join): ${orderItemsResponse.length} kayıt');
        }
      }
      
      if (orderItemsResponse.isNotEmpty) {
        final Map<String, Map<String, dynamic>> grouped = {};
        for (var item in orderItemsResponse) {
          final productId = item['product_id'] as String? ?? '';
          final productName = item['product_name'] as String? ?? 'Ürün';
          final qty = (item['quantity'] as num?)?.toInt() ?? 1;
          
          if (productId.isEmpty) continue;
          
          if (!grouped.containsKey(productId)) {
            grouped[productId] = {
              'product_id': productId,
              'product_name': productName,
              'view_count': 0,
            };
          }
          grouped[productId]!['view_count'] = (grouped[productId]!['view_count'] as int) + qty;
        }
        
        final result = grouped.values.toList();
        result.sort((a, b) => (b['view_count'] as int).compareTo(a['view_count'] as int));
        
        debugPrint('📊 Top products from orders: ${result.length} ürün');
        return result.take(limit).toList();
      }
    } catch (e) {
      debugPrint('⚠️ order_items fallback hatası: $e');
    }

    return [];
  }

  /// En çok sipariş veren müşteriler
  Future<List<Map<String, dynamic>>> getTopCustomers(String shopId, {int limit = 10}) async {
    // Yöntem 1: RPC
    try {
      final response = await _supabase
          .rpc('get_top_customers', params: {
            'p_shop_id': shopId,
            'p_limit': limit,
          });
      final responseList = response as List;
      if (responseList.isNotEmpty) {
        debugPrint('📊 Top customers (RPC): ${responseList.length}');
        return List<Map<String, dynamic>>.from(responseList);
      }
    } catch (e) {
      debugPrint('⚠️ RPC get_top_customers hatası: $e');
    }

    // Yöntem 2: Doğrudan sorgu
    try {
      final ordersResponse = await _supabase
          .from('orders')
          .select('user_id, subtotal, profiles!inner(full_name)')
          .eq('shop_id', shopId)
          .neq('status', 'cancelled');

      final list = ordersResponse as List;
      if (list.isNotEmpty) {
        final Map<String, Map<String, dynamic>> grouped = {};
        for (var order in ordersResponse) {
          final userId = order['user_id'] as String? ?? '';
          final fullName = order['profiles']?['full_name'] as String? ?? 'Müşteri';
          final subtotal = (order['subtotal'] as num?)?.toDouble() ?? 0.0;
          
          if (userId.isEmpty) continue;
          
          if (!grouped.containsKey(userId)) {
            grouped[userId] = {
              'user_id': userId,
              'full_name': fullName,
              'order_count': 0,
              'total_spent': 0.0,
            };
          }
          grouped[userId]!['order_count'] = (grouped[userId]!['order_count'] as int) + 1;
          grouped[userId]!['total_spent'] = (grouped[userId]!['total_spent'] as double) + subtotal;
        }
        
        final result = grouped.values.toList();
        result.sort((a, b) => (b['order_count'] as int).compareTo(a['order_count'] as int));
        
        debugPrint('📊 Top customers (direct): ${result.length}');
        return result.take(limit).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Doğrudan müşteri sorgusu hatası: $e');
    }

    return [];
  }

  /// Satış istatistikleri
  Future<Map<String, dynamic>> getSalesStats(String shopId) async {
    try {
      // Toplam sipariş sayısı
      final ordersResult = await _supabase
          .from('orders')
          .select('id')
          .eq('shop_id', shopId)
          .neq('status', 'cancelled');
      final totalOrders = (ordersResult as List).length;

      // Toplam satış
      final salesResult = await _supabase
          .from('orders')
          .select('subtotal')
          .eq('shop_id', shopId)
          .eq('status', 'delivered');
      double totalSales = 0;
      for (var order in salesResult) {
        totalSales += (order['subtotal'] ?? 0).toDouble();
      }

      // Bu ay satış
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final monthSalesResult = await _supabase
          .from('orders')
          .select('subtotal')
          .eq('shop_id', shopId)
          .eq('status', 'delivered')
          .gte('created_at', startOfMonth.toIso8601String());
      double monthSales = 0;
      for (var order in monthSalesResult) {
        monthSales += (order['subtotal'] ?? 0).toDouble();
      }

      // Bugün satış
      final todaySalesResult = await _supabase
          .from('orders')
          .select('subtotal')
          .eq('shop_id', shopId)
          .eq('status', 'delivered')
          .gte('created_at', DateTime(now.year, now.month, now.day).toIso8601String());
      double todaySales = 0;
      for (var order in todaySalesResult) {
        todaySales += (order['subtotal'] ?? 0).toDouble();
      }

      // Benzersiz müşteri sayısı
      final customersResult = await _supabase
          .from('orders')
          .select('user_id')
          .eq('shop_id', shopId)
          .neq('status', 'cancelled');
      final uniqueCustomers = (customersResult as List).map((e) => e['user_id']).toSet().length;

      // Ortalama sipariş değeri
      final avgOrderValue = totalOrders > 0 ? totalSales / totalOrders : 0.0;

      return {
        'total_orders': totalOrders,
        'total_sales': totalSales,
        'month_sales': monthSales,
        'today_sales': todaySales,
        'unique_customers': uniqueCustomers,
        'avg_order_value': avgOrderValue,
      };
    } catch (e) {
      debugPrint('Sales stats hatası: $e');
      return {
        'total_orders': 0,
        'total_sales': 0.0,
        'month_sales': 0.0,
        'today_sales': 0.0,
        'unique_customers': 0,
        'avg_order_value': 0.0,
      };
    }
  }

  /// Son 7 gün satış grafiği verileri
  Future<List<Map<String, dynamic>>> getWeeklySalesData(String shopId) async {
    try {
      final now = DateTime.now();
      final weekAgo = now.subtract(const Duration(days: 7));
      
      final response = await _supabase
          .from('orders')
          .select('created_at, subtotal')
          .eq('shop_id', shopId)
          .eq('status', 'delivered')
          .gte('created_at', weekAgo.toIso8601String())
          .order('created_at');

      // Günlük bazda gruplama
      final Map<String, double> dailySales = {};
      for (int i = 0; i < 7; i++) {
        final date = now.subtract(Duration(days: 6 - i));
        final key = '${date.day}/${date.month}';
        dailySales[key] = 0;
      }

      for (var order in response) {
        final date = DateTime.parse(order['created_at']);
        final key = '${date.day}/${date.month}';
        dailySales[key] = (dailySales[key] ?? 0) + (order['subtotal'] ?? 0).toDouble();
      }

      return dailySales.entries.map((e) => {
        'date': e.key,
        'sales': e.value,
      }).toList();
    } catch (e) {
      debugPrint('Weekly sales hatası: $e');
      return [];
    }
  }

  /// Ürün performans verileri
  Future<List<Map<String, dynamic>>> getProductPerformance(String shopId) async {
    try {
      // Yöntem 1: order_items tablosundan doğrudan shop_id ile çek
      List<dynamic> orderItemsResponse = [];
      
      try {
        orderItemsResponse = await _supabase
            .from('order_items')
            .select('product_id, product_name, quantity, subtotal')
            .eq('shop_id', shopId);
        debugPrint('📊 Product performance (shop_id filtre): ${orderItemsResponse.length} kayıt');
      } catch (e) {
        debugPrint('⚠️ order_items shop_id filtresi başarısız: $e');
      }

      // Yöntem 2: shop_id ile sonuç yoksa, orders tablosu üzerinden al
      if (orderItemsResponse.isEmpty) {
        try {
          debugPrint('📊 order_items orders join deneniyor...');
          final ordersResponse = await _supabase
              .from('orders')
              .select('id')
              .eq('shop_id', shopId)
              .neq('status', 'cancelled');
          
          if ((ordersResponse as List).isNotEmpty) {
            final orderIds = ordersResponse.map((o) => o['id'] as String).toList();
            debugPrint('📊 Mağazanın ${orderIds.length} siparişi bulundu');
            
            orderItemsResponse = await _supabase
                .from('order_items')
                .select('product_id, product_name, quantity, subtotal')
                .inFilter('order_id', orderIds);
            debugPrint('📊 order_items (orders join): ${orderItemsResponse.length} kayıt');
          }
        } catch (e) {
          debugPrint('⚠️ order_items orders join hatası: $e');
        }
      }

      // Ürün bazında gruplama
      final Map<String, Map<String, dynamic>> productStats = {};
      
      for (var item in orderItemsResponse) {
        final productId = item['product_id'] as String? ?? '';
        final productName = item['product_name'] as String? ?? 'Ürün';
        
        if (productId.isEmpty) continue;
        
        if (!productStats.containsKey(productId)) {
          productStats[productId] = {
            'product_id': productId,
            'product_name': productName,
            'total_sold': 0,
            'total_revenue': 0.0,
          };
        }
        
        productStats[productId]!['total_sold'] =
            (productStats[productId]!['total_sold'] as int) + ((item['quantity'] as num?)?.toInt() ?? 0);
        productStats[productId]!['total_revenue'] =
            (productStats[productId]!['total_revenue'] as double) + ((item['subtotal'] as num?)?.toDouble() ?? 0);
      }

      final result = productStats.values.toList();
      result.sort((a, b) => (b['total_sold'] as int).compareTo(a['total_sold'] as int));
      
      return result.take(10).toList();
    } catch (e) {
      debugPrint('Product performance hatası: $e');
      return [];
    }
  }
}
