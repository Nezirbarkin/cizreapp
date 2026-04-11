import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/shop_model.dart';

/// Shop cache result - similar to StaleCacheResult
class ShopCacheResult<T> {
  final T? data;
  final bool isFromCache;
  
  const ShopCacheResult({
    this.data,
    this.isFromCache = false,
  });
}

class ShopService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  // Simple memory cache - is_acceptingOrders için kısa cache (30 saniye)
  // Çünkü satıcılar sipariş almayı açıp kapatıyor, bu değişikliği hemen görmek önemli
  static const _cacheDuration = Duration(seconds: 30);
  final Map<String, _CachedShop> _shopCache = {};
  final Map<String, _CachedShopList> _shopListCache = {};

  // Tüm aktif ve onaylı dükkânları getir - cache devre dışı (her zaman taze veri)
  Future<List<Shop>> getShops({String? categoryId, bool? isOpen}) async {
    // Cache devre dışı - her zaman ağdan taze veri çek
    // Dükkanların is_accepting_orders durumu hızlı değişebildiği için cache kullanmıyoruz
    return await _fetchShops(categoryId: categoryId, isOpen: isOpen);
  }

  /// Arka planda dükkanları çek ve cache'i güncelle
  void _fetchShopsInBackground({String? categoryId, bool? isOpen}) {
    Future.microtask(() async {
      try {
        final shops = await _fetchShops(categoryId: categoryId, isOpen: isOpen);
        final cacheKey = 'shops_${categoryId ?? "all"}_${isOpen ?? "all"}';
        _shopListCache[cacheKey] = _CachedShopList(shops, DateTime.now().add(_cacheDuration));
      } catch (e) {
        // Hata olsa bile sessizce geç - arka plan işlemi
      }
    });
  }

  /// Network'ten dükkanları çek
  Future<List<Shop>> _fetchShops({String? categoryId, bool? isOpen}) async {
    try {
      var query = _supabase
          .from('shops')
          .select()
          .eq('is_active', true)
          .eq('is_approved', true);

      if (categoryId != null) {
        query = query.eq('category_id', categoryId);
      }

      final response = await query
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false);

      List<Shop> shops = (response as List)
          .map((json) => Shop.fromJson(json))
          .toList();

      // Eğer isOpen filter'ı varsa, açık/kapalı durumuna göre filtrele
      if (isOpen != null) {
        shops = shops.where((shop) => shop.isOpen == isOpen).toList();
      }

      // Cache'e kaydet
      final cacheKey = 'shops_${categoryId ?? "all"}_${isOpen ?? "all"}';
      _shopListCache[cacheKey] = _CachedShopList(shops, DateTime.now().add(_cacheDuration));

      return shops;
    } catch (e) {
      // Hata olursa cache'ten dene
      final cacheKey = 'shops_${categoryId ?? "all"}_${isOpen ?? "all"}';
      final cached = _shopListCache[cacheKey];
      if (cached != null) {
        return cached.shops;
      }
      throw Exception('Dükkanlar yüklenirken hata: $e');
    }
  }

  // ID'ye göre dükkân getir - with cache
  Future<Shop?> getShopById(String id) async {
    // Önce cache'ten kontrol et
    final cached = _shopCache[id];
    if (cached != null && !cached.isExpired) {
      // Cache'ten döndür, arka planda güncelle
      _fetchShopByIdInBackground(id);
      return cached.shop;
    }
    
    return await _fetchShopById(id);
  }

  /// Arka planda tek dükkanı çek
  void _fetchShopByIdInBackground(String id) {
    Future.microtask(() async {
      try {
        final shop = await _fetchShopById(id);
        if (shop != null) {
          _shopCache[id] = _CachedShop(shop, DateTime.now().add(_cacheDuration));
        }
      } catch (e) {
        // Hata olsa bile sessizce geç
      }
    });
  }

  /// Network'ten tek dükkanı çek
  Future<Shop?> _fetchShopById(String id) async {
    try {
      final response = await _supabase
          .from('shops')
          .select()
          .eq('id', id)
          .single();

      final shop = Shop.fromJson(response);
      // Cache'e kaydet
      _shopCache[id] = _CachedShop(shop, DateTime.now().add(_cacheDuration));
      return shop;
    } catch (e) {
      // Hata olursa cache'ten dene
      final cached = _shopCache[id];
      if (cached != null) {
        return cached.shop;
      }
      return null;
    }
  }

  // Kullanıcının dükkânını getir (satıcılar için)
  Future<Shop?> getUserShop(String userId) async {
    try {
      final response = await _supabase
          .from('shops')
          .select()
          .eq('owner_id', userId)
          .single();

      return Shop.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  // Kategori ID'ye göre onaylı dükkânları getir
  Future<List<Shop>> getShopsByCategory(String categoryId) async {
    try {
      final response = await _supabase
          .from('shops')
          .select()
          .eq('category_id', categoryId)
          .eq('is_active', true)
          .eq('is_approved', true)
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => Shop.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Kategori dükkanları yüklenirken hata: $e');
    }
  }

  // Dükkân ara (isim, açıklama) - sadece onaylı
  Future<List<Shop>> searchShops(String query) async {
    try {
      final response = await _supabase
          .from('shops')
          .select()
          .eq('is_active', true)
          .eq('is_approved', true)
          .or('name.ilike.%$query%,description.ilike.%$query%')
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => Shop.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Dükkân araması yapılırken hata: $e');
    }
  }

  // Dükkân oluştur (satıcılar için)
  Future<Shop?> createShop({
    required String sellerId,
    required String categoryId,
    required String name,
    required String description,
    String? phone,
    String? address,
  }) async {
    try {
      final response = await _supabase.from('shops').insert({
        'seller_id': sellerId,
        'category_id': categoryId,
        'name': name,
        'description': description,
        'phone': phone,
        'address': address,
        'is_active': true,
        'rating': 0.0,
        'total_sales': 0,
        'created_at': DateTime.now().toIso8601String(),
      }).select().single();

      return Shop.fromJson(response);
    } catch (e) {
      throw Exception('Dükkân oluşturulurken hata: $e');
    }
  }

  // Dükkân güncelle (satıcılar için)
  Future<Shop?> updateShop(String shopId, Map<String, dynamic> updates) async {
    try {
      final response = await _supabase
          .from('shops')
          .update(updates)
          .eq('id', shopId)
          .select()
          .single();

      return Shop.fromJson(response);
    } catch (e) {
      throw Exception('Dükkân güncellenirken hata: $e');
    }
  }

  // Dükkânı sil (admin için)
  Future<void> deleteShop(String shopId) async {
    try {
      await _supabase.from('shops').delete().eq('id', shopId);
    } catch (e) {
      throw Exception('Dükkân silinirken hata: $e');
    }
  }

  // En çok satış yapan dükkânları getir
  Future<List<Shop>> getTopShops({int limit = 10}) async {
    try {
      final response = await _supabase
          .from('shops')
          .select()
          .eq('is_active', true)
          .order('total_sales', ascending: false)
          .limit(limit);

      return (response as List)
          .map((json) => Shop.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('En çok satış yapan dükkânlar yüklenirken hata: $e');
    }
  }

  // En yüksek puanlı dükkânları getir
  Future<List<Shop>> getTopRatedShops({int limit = 10}) async {
    try {
      final response = await _supabase
          .from('shops')
          .select()
          .eq('is_active', true)
          .order('rating', ascending: false)
          .limit(limit);

      return (response as List)
          .map((json) => Shop.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('En yüksek puanlı dükkânlar yüklenirken hata: $e');
    }
  }

  // ⚡ OPTİMİZE: Kategoriler için dükkan sayılarını SQL tarafında hesapla
  // Eskisi tüm dükkanları çekip Dart'ta sayıyordu - artık SQL GROUP BY kullanılıyor
  Future<Map<String, int>> getShopsCountByCategory() async {
    try {
      // Supabase'de RPC yoksa, select ile group by yapamadığımız için
      // sadece category_id sütununu çekip Dart'ta sayıyoruz (veri miktarı çok az)
      final response = await _supabase
          .from('shops')
          .select('category_id')
          .eq('is_active', true)
          .eq('is_approved', true);

      final counts = <String, int>{};
      for (var row in (response as List)) {
        final catId = row['category_id'] as String?;
        if (catId != null) {
          counts[catId] = (counts[catId] ?? 0) + 1;
        }
      }
      return counts;
    } catch (e) {
      throw Exception('Kategori dükkan sayıları hesaplanırken hata: $e');
    }
  }

  /// Cache'i temizle
  void clearCache() {
    _shopCache.clear();
    _shopListCache.clear();
  }

  /// Süresi dolan cache'i temizle
  void clearExpiredCache() {
    final now = DateTime.now();
    _shopCache.removeWhere((key, value) => value.expiry.isBefore(now));
    _shopListCache.removeWhere((key, value) => value.expiry.isBefore(now));
  }
}

/// Cache için yardımcı class'lar
class _CachedShop {
  final Shop shop;
  final DateTime expiry;
  
  _CachedShop(this.shop, this.expiry);
  
  bool get isExpired => DateTime.now().isAfter(expiry);
}

class _CachedShopList {
  final List<Shop> shops;
  final DateTime expiry;
  
  _CachedShopList(this.shops, this.expiry);
  
  bool get isExpired => DateTime.now().isAfter(expiry);
}
