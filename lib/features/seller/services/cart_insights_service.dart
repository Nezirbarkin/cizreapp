import 'package:supabase_flutter/supabase_flutter.dart';

import '../../market/services/product_service.dart';
import '../models/cart_insights.dart';

/// Satıcı "Sepet Takibi" istemcisi (Görev 3.3).
///
/// İstatistik `get_shop_cart_stats` RPC'sinden gelir (yalnız mağaza sahibi,
/// yalnız sayılar). İndirim mevcut toplu indirim RPC'siyle uygulanır; fiyat
/// sunucuda hesaplanır ve ürünü sepetinde tutan müşterilere bildirimi
/// veritabanı tetikleyicisi gönderir.
class CartInsightsService {
  CartInsightsService({SupabaseClient? client, ProductService? productService})
    : _client = client,
      _productService = productService;

  final SupabaseClient? _client;
  final ProductService? _productService;

  SupabaseClient get _db => _client ?? Supabase.instance.client;

  Future<ShopCartStats> fetchStats(String shopId) async {
    final result = await _db.rpc('get_shop_cart_stats', params: {'p_shop_id': shopId});
    if (result is! Map) return ShopCartStats.empty;
    return ShopCartStats.fromJson(Map<String, dynamic>.from(result));
  }

  /// Ürüne %[percent] indirim uygular; güncellenen ürün sayısını döner (0 ise
  /// sunucu indirimi geçersiz saydı: fiyatı düşürmüyor ya da dijital ürün).
  Future<int> applyPercentDiscount(String productId, double percent) {
    return (_productService ?? ProductService()).bulkSetDiscount(
      productIds: [productId],
      mode: BulkDiscountMode.percent,
      value: percent,
    );
  }
}
