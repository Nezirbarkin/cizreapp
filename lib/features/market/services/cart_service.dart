import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/cart_model.dart';

class CartService {
  /// Supabase client'ı güvenli şekilde al (lazy) - class-level initializer yerine
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      rethrow;
    }
  }

  // Sepeti getir (ürün detaylarıyla birlikte)
  Future<List<CartItem>> getCart(String userId) async {
    try {
      final response = await _supabase
          .from('cart')
          .select('''
            id,
            user_id,
            product_id,
            quantity,
            created_at,
            updated_at,
            variant_data,
            products (
              name,
              price,
              old_price,
              image_url,
              shop_id,
              is_available,
              stock_quantity,
              shops (
                name
              )
            )
          ''')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return (response as List).map((item) {
        final product = item['products'] as Map<String, dynamic>?;
        final shop = product?['shops'] as Map<String, dynamic>?;

        return CartItem(
            id: item['id']?.toString() ?? '',
            userId: item['user_id']?.toString() ?? '',
            productId: item['product_id']?.toString() ?? '',
            quantity: (item['quantity'] as num?)?.toInt() ?? 1,
            createdAt: item['created_at'] != null
                ? DateTime.parse(item['created_at'].toString())
                : DateTime.now(),
            updatedAt: item['updated_at'] != null
                ? DateTime.parse(item['updated_at'].toString())
                : DateTime.now(),
          productName: product?['name']?.toString(),
          productPrice: product?['price'] != null
              ? (product!['price'] as num?)?.toDouble()
              : null,
          productOldPrice: product?['old_price'] != null
              ? (product!['old_price'] as num?)?.toDouble()
              : null,
          productImageUrl: product?['image_url']?.toString(),
          shopId: product?['shop_id']?.toString(),
          shopName: shop?['name']?.toString(),
          isAvailable: product?['is_available'] as bool?,
          stockQuantity: (product?['stock_quantity'] as num?)?.toInt(),
          variantData: item['variant_data'] as Map<String, dynamic>?,
        );
      }).toList();
    } catch (e) {
      throw Exception('Sepet yüklenirken hata: $e');
    }
  }

  // Sepete ürün ekle veya güncelle
  Future<CartItem> addToCart({
    required String userId,
    required String productId,
    int quantity = 1,
    Map<String, dynamic>? variantData,
  }) async {
    // Validasyon - userId ve productId null/boş olmamalı
    if (userId.isEmpty) {
      throw Exception('Kullanıcı ID boş olamaz');
    }
    if (productId.isEmpty) {
      throw Exception('Ürün ID boş olamaz');
    }
    
    try {
      // Stok kontrolü - üründeki mevcut stok miktarını al
      final productResponse = await _supabase
          .from('products')
          .select('stock_quantity, is_available')
          .eq('id', productId)
          .single();

      final isAvailable = productResponse['is_available'] as bool? ?? true;
      final stockQuantity = (productResponse['stock_quantity'] as num?)?.toInt();

      if (!isAvailable) {
        throw Exception('Bu ürün şu anda satışta değil');
      }

      // Varyantlı ürünler için varyant bazlı kontrol yap
      final response = await _supabase
          .from('cart')
          .select('id, quantity, variant_data')
          .eq('user_id', userId)
          .eq('product_id', productId);

      CartItem? existingItem;
      if (variantData != null && variantData.isNotEmpty) {
        // Aynı varyant kombinasyonunu ara
        for (final item in (response as List)) {
          final itemVariant = item['variant_data'] as Map<String, dynamic>?;
          if (itemVariant != null && _variantDataEquals(itemVariant, variantData)) {
            existingItem = _mapToCartItem(item);
            break;
          }
        }
      } else {
        // Varyantsız ürün için ilk eşleşen öğeyi al
        if (response.isNotEmpty) {
          existingItem = _mapToCartItem(response.first);
        }
      }

      if (existingItem != null) {
        // Varsa miktarı artır
        final newQuantity = existingItem.quantity + quantity;
        if (stockQuantity != null && newQuantity > stockQuantity) {
          throw Exception('Stokta yeterli ürün yok (kalan: $stockQuantity)');
        }
        await _supabase
            .from('cart')
            .update({'quantity': newQuantity})
            .eq('id', existingItem.id);

        // Güncellenmiş sepet öğesini getir
        final updated = await _supabase
            .from('cart')
            .select('''
              id,
              user_id,
              product_id,
              quantity,
              created_at,
              updated_at,
              variant_data,
              products (
                name,
                price,
                old_price,
                image_url,
                shop_id,
                is_available,
                stock_quantity,
                shops (name)
              )
            ''')
            .eq('id', existingItem.id)
            .single();

        return _mapToCartItem(updated);
      }

      if (stockQuantity != null && quantity > stockQuantity) {
        throw Exception('Stokta yeterli ürün yok (kalan: $stockQuantity)');
      }

      // Yeni ekle
      final insertData = {
        'user_id': userId,
        'product_id': productId,
        'quantity': quantity,
      };
      if (variantData != null && variantData.isNotEmpty) {
        insertData['variant_data'] = variantData;
      }

      final insertResponse = await _supabase
          .from('cart')
          .insert(insertData)
          .select('''
            id,
            user_id,
            product_id,
            quantity,
            created_at,
            updated_at,
            variant_data,
            products (
              name,
              price,
              old_price,
              image_url,
              shop_id,
              is_available,
              stock_quantity,
              shops (name)
            )
          ''')
          .single();

      return _mapToCartItem(insertResponse);
    } catch (e) {
      throw Exception('Sepete eklenirken hata: $e');
    }
  }

  // Sepet öğesi miktarını güncelle
  Future<void> updateQuantity({
    required String cartItemId,
    required int quantity,
  }) async {
    try {
      if (quantity <= 0) {
        // Miktar 0 veya negatifse sil
        await removeFromCart(cartItemId);
        return;
      }

      await _supabase
          .from('cart')
          .update({'quantity': quantity})
          .eq('id', cartItemId);
    } catch (e) {
      throw Exception('Miktar güncellenirken hata: $e');
    }
  }

  // Sepetten ürün sil
  Future<void> removeFromCart(String cartItemId) async {
    try {
      await _supabase.from('cart').delete().eq('id', cartItemId);
    } catch (e) {
      throw Exception('Sepetten silinirken hata: $e');
    }
  }

  // Sepeti temizle
  Future<void> clearCart(String userId) async {
    try {
      await _supabase.from('cart').delete().eq('user_id', userId);
    } catch (e) {
      throw Exception('Sepet temizlenirken hata: $e');
    }
  }

  // Sepet özeti getir
  Future<CartSummary> getCartSummary(String userId, {double? deliveryFee}) async {
    try {
      final items = await getCart(userId);

      // Teslimat ücreti: cart_provider.getDeliveryFee() ile TUTARLI olmalı.
      // ÖNEMLI (2026-07-03 fix): Eskiden yalnızca items.first.shopId'nin HAM
      // delivery_fee'si alınıyor, ücretsiz teslimat eşiği (free_delivery_min_amount)
      // UYGULANMIYOR ve çok-dükkanlı sepette diğer dükkanlar sayılmıyordu. Bu
      // yüzden sepet ekranı (ücretsiz gösterir) ile sipariş onayı (ücret ekler)
      // farklı tutar gösteriyordu. Artık dükkan bazında eşik uygulanıp toplanıyor.
      double fee;
      if (deliveryFee != null) {
        fee = deliveryFee;
      } else {
        fee = 0;
        final grouped = <String, List<CartItem>>{};
        for (final item in items) {
          final sid = item.shopId;
          if (sid == null) continue;
          grouped.putIfAbsent(sid, () => []).add(item);
        }
        for (final entry in grouped.entries) {
          final info = await getShopDeliveryInfo(entry.key);
          final shopTotal =
              entry.value.fold<double>(0, (s, it) => s + it.itemTotal);
          fee += calculateDeliveryFee(
            shopTotal,
            info['delivery_fee'] ?? 15.0,
            info['free_delivery_min_amount'] ?? 0.0,
          );
        }
      }

      return CartSummary.fromItems(items, deliveryFee: fee);
    } catch (e) {
      throw Exception('Sepet özeti alınırken hata: $e');
    }
  }

  // Dükkan teslimat bilgilerini getir (delivery_fee ve free_delivery_min_amount)
  Future<Map<String, double>> getShopDeliveryInfo(String shopId) async {
    try {
      final response = await _supabase
          .from('shops')
          .select('delivery_fee, free_delivery_min_amount')
          .eq('id', shopId)
          .single();
      
      final deliveryFee = (response['delivery_fee'] as num?)?.toDouble() ?? 15.0;
      final freeDeliveryMinAmount = (response['free_delivery_min_amount'] as num?)?.toDouble() ?? 0.0;
      
      return {
        'delivery_fee': deliveryFee,
        'free_delivery_min_amount': freeDeliveryMinAmount,
      };
    } catch (e) {
      // ignore: avoid_print
      print('⚠️ Teslimat bilgileri alınırken hata: $e');
      return {
        'delivery_fee': 15.0,
        'free_delivery_min_amount': 0.0,
      };
    }
  }

  // Dükkan teslimat ücretini getir (geriye uyumluluk için)
  Future<double> getShopDeliveryFee(String shopId) async {
    final info = await getShopDeliveryInfo(shopId);
    return info['delivery_fee'] ?? 15.0;
  }

  // Ücretsiz teslimat hesapla - sepet toplamına göre teslimat ücreti döndürür
  double calculateDeliveryFee(double cartTotal, double deliveryFee, double freeDeliveryMinAmount) {
    if (freeDeliveryMinAmount > 0 && cartTotal >= freeDeliveryMinAmount) {
      return 0.0; // Ücretsiz teslimat
    }
    return deliveryFee;
  }

  // Sepetteki ürün sayısını getir
  Future<int> getCartItemCount(String userId) async {
    try {
      final items = await getCart(userId);
      return items.fold<int>(0, (sum, item) => sum + item.quantity);
    } catch (e) {
      return 0;
    }
  }

  // Ürünün sepette olup olmadığını kontrol et
  Future<bool> isInCart(String userId, String productId) async {
    try {
      final response = await _supabase
          .from('cart')
          .select('id')
          .eq('user_id', userId)
          .eq('product_id', productId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      return false;
    }
  }

  // Sepetteki ürün miktarını getir
  Future<int> getProductQuantityInCart(String userId, String productId) async {
    try {
      final response = await _supabase
          .from('cart')
          .select('quantity')
          .eq('user_id', userId)
          .eq('product_id', productId)
          .maybeSingle();

      if (response != null) {
        // Supabase JSON sayıları bazen double dönebilir; num üzerinden .toInt() güvenli cast yapar.
        return (response['quantity'] as num?)?.toInt() ?? 0;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  // İki varyant verisinin eşit olup olmadığını kontrol et
  bool _variantDataEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      final aVal = a[key]?.toString();
      final bVal = b[key]?.toString();
      if (bVal == null || aVal != bVal) return false;
    }
    return true;
  }

  // Helper: Response'u CartItem'a dönüştür
  CartItem _mapToCartItem(Map<String, dynamic> item) {
    final product = item['products'] as Map<String, dynamic>?;
    final shop = product?['shops'] as Map<String, dynamic>?;

    return CartItem(
      id: item['id']?.toString() ?? '',
      userId: item['user_id']?.toString() ?? '',
      productId: item['product_id']?.toString() ?? '',
      quantity: (item['quantity'] as num?)?.toInt() ?? 1,
      createdAt: item['created_at'] != null
          ? DateTime.parse(item['created_at'].toString())
          : DateTime.now(),
      updatedAt: item['updated_at'] != null
          ? DateTime.parse(item['updated_at'].toString())
          : DateTime.now(),
      productName: product?['name']?.toString(),
      productPrice: product?['price'] != null
          ? (product!['price'] as num?)?.toDouble()
          : null,
      productOldPrice: product?['old_price'] != null
          ? (product!['old_price'] as num?)?.toDouble()
          : null,
      productImageUrl: product?['image_url']?.toString(),
      shopId: product?['shop_id']?.toString(),
      shopName: shop?['name']?.toString(),
      isAvailable: product?['is_available'] as bool?,
      stockQuantity: (product?['stock_quantity'] as num?)?.toInt(),
      variantData: item['variant_data'] as Map<String, dynamic>?,
    );
  }

  /// Sepeti dükkanlara göre grupla (çok dükkanlı sipariş için)
  /// Her dükkan için ayrı CartSummary döndürür
  Future<Map<String, ShopCartSummary>> groupCartByShop(String userId) async {
    try {
      final items = await getCart(userId);
      
      // Dükkanlara göre grupla
      final Map<String, List<CartItem>> groupedItems = {};
      for (final item in items) {
        final shopId = item.shopId;
        if (shopId == null) continue;
        
        if (!groupedItems.containsKey(shopId)) {
          groupedItems[shopId] = [];
        }
        groupedItems[shopId]!.add(item);
      }
      
      // Her dükkan için özet oluştur
      final Map<String, ShopCartSummary> summaries = {};
      for (final entry in groupedItems.entries) {
        final shopId = entry.key;
        final shopItems = entry.value;
        
        // Dükkan bilgilerini al (teslimat ücreti ve ücretsiz teslimat limiti için)
        final deliveryInfo = await getShopDeliveryInfo(shopId);
        final baseDeliveryFee = deliveryInfo['delivery_fee'] ?? 15.0;
        final freeDeliveryMinAmount = deliveryInfo['free_delivery_min_amount'] ?? 0.0;
        final shopName = shopItems.first.shopName ?? 'Dükkan';
        
        // Ara toplam hesapla
        double subtotal = 0;
        for (final item in shopItems) {
          subtotal += (item.productPrice ?? 0) * item.quantity;
        }
        
        // Ücretsiz teslimat kontrolü
        final deliveryFee = calculateDeliveryFee(subtotal, baseDeliveryFee, freeDeliveryMinAmount);
        
        summaries[shopId] = ShopCartSummary(
          shopId: shopId,
          shopName: shopName,
          items: shopItems,
          subtotal: subtotal,
          deliveryFee: deliveryFee,
          total: subtotal + deliveryFee,
          freeDeliveryMinAmount: freeDeliveryMinAmount,
          isFreeDelivery: deliveryFee == 0 && freeDeliveryMinAmount > 0,
        );
      }
      
      return summaries;
    } catch (e) {
      throw Exception('Sepet gruplandırılırken hata: $e');
    }
  }
}

/// Dükkan bazında sepet özeti
class ShopCartSummary {
  final String shopId;
  final String shopName;
  final List<CartItem> items;
  final double subtotal;
  final double deliveryFee;
  final double total;
  final double freeDeliveryMinAmount;
  final bool isFreeDelivery;

  ShopCartSummary({
    required this.shopId,
    required this.shopName,
    required this.items,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    this.freeDeliveryMinAmount = 0,
    this.isFreeDelivery = false,
  });

  int get itemCount => items.fold<int>(0, (sum, item) => sum + item.quantity);

  // Ücretsiz teslimat için kalan tutarı hesapla
  double get remainingForFreeDelivery {
    if (freeDeliveryMinAmount <= 0 || isFreeDelivery) return 0;
    final remaining = freeDeliveryMinAmount - subtotal;
    return remaining > 0 ? remaining : 0;
  }
}
