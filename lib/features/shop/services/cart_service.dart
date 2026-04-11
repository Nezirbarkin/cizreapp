import 'package:supabase_flutter/supabase_flutter.dart';

class CartService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Sepetteki öğeleri getir
  Future<List<CartItem>> getCartItems(String userId) async {
    try {
      final response = await _supabase
          .from('cart_items')
          .select('*, products(*)')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => CartItem.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Sepet yüklenirken hata: $e');
    }
  }

  // Ürün sepete ekle
  Future<CartItem?> addToCart({
    required String userId,
    required String productId,
    required int quantity,
  }) async {
    try {
      final response = await _supabase.from('cart_items').upsert({
        'user_id': userId,
        'product_id': productId,
        'quantity': quantity,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).select().single();

      return CartItem.fromJson(response);
    } catch (e) {
      throw Exception('Ürün sepete eklenirken hata: $e');
    }
  }

  // Sepetteki ürün miktarını güncelle
  Future<CartItem?> updateCartItemQuantity(
    String cartItemId,
    int quantity,
  ) async {
    try {
      if (quantity <= 0) {
        await removeFromCart(cartItemId);
        return null;
      }

      final response = await _supabase
          .from('cart_items')
          .update({'quantity': quantity})
          .eq('id', cartItemId)
          .select()
          .single();

      return CartItem.fromJson(response);
    } catch (e) {
      throw Exception('Miktar güncellenirken hata: $e');
    }
  }

  // Ürünü sepetten çıkar
  Future<void> removeFromCart(String cartItemId) async {
    try {
      await _supabase.from('cart_items').delete().eq('id', cartItemId);
    } catch (e) {
      throw Exception('Ürün sepetten çıkarılırken hata: $e');
    }
  }

  // Tüm sepeti temizle
  Future<void> clearCart(String userId) async {
    try {
      await _supabase.from('cart_items').delete().eq('user_id', userId);
    } catch (e) {
      throw Exception('Sepet temizlenirken hata: $e');
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

  // Sepet toplam tutarını hesapla
  Future<double> getCartTotal(String userId) async {
    try {
      final items = await getCartItems(userId);
      double total = 0;

      for (var item in items) {
        // Ürün bilgisini database'den al ve fiyatını hesapla
        total += item.quantity * 100.0; // Örnek fiyat
      }

      return total;
    } catch (e) {
      throw Exception('Toplam hesaplanırken hata: $e');
    }
  }

  // Sepet öğe sayısını getir
  Future<int> getCartItemCount(String userId) async {
    try {
      final response = await _supabase
          .from('cart_items')
          .select('id')
          .eq('user_id', userId);

      return response.length;
    } catch (e) {
      return 0;
    }
  }
}

// CartItem model
class CartItem {
  final String id;
  final String userId;
  final String productId;
  final int quantity;
  final DateTime createdAt;
  final DateTime updatedAt;

  CartItem({
    required this.id,
    required this.userId,
    required this.productId,
    required this.quantity,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      productId: json['product_id'] as String,
      quantity: json['quantity'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'product_id': productId,
      'quantity': quantity,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
