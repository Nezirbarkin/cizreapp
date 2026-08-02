import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/product_model.dart';

class ProductService {
  /// Supabase client'ı güvenli şekilde al (lazy) - class-level initializer yerine
  SupabaseClient get supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      rethrow;
    }
  }

  // Tüm ürünleri getir (sponsorlar en başta, sponsor olmayanlar rastgele)
  Future<List<Product>> getAllProducts() async {
    try {
      final response = await supabase
          .from('products')
          .select()
          .eq('is_available', true)
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false);

      // JSON'u tek geçişte parse et (önceden 3 kez parse ediliyordu)
      final products = (response as List<dynamic>)
          .map((item) => Product.fromJson(item as Map<String, dynamic>))
          .toList();

      // Sponsor ve sponsor olmayan ürünleri ayır
      final pinnedProducts = products.where((p) => p.isPinned).toList();
      final nonPinnedProducts = products.where((p) => !p.isPinned).toList();

      // Sponsor olmayanları karıştır (shuffle)
      nonPinnedProducts.shuffle();

      // Sponsorlar + karıştırılmış sponsor olmayanlar
      return [...pinnedProducts, ...nonPinnedProducts];
    } catch (e) {
      throw Exception('Ürünler yüklenirken hata: $e');
    }
  }

  // Belirli bir dükkanın ürünlerini getir (satıcının sabitlediği ürünler en üstte)
  Future<List<Product>> getShopProducts(String shopId) async {
    try {
      final response = await supabase
          .from('products')
          .select()
          .eq('shop_id', shopId)
          .eq('is_available', true)
          .order('seller_pinned', ascending: false)
          .order('created_at', ascending: false);

      return (response as List<dynamic>)
          .map((item) => Product.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Dükkan ürünleri yüklenirken hata: $e');
    }
  }

  // Kategoriye göre ürünleri getir
  Future<List<Product>> getProductsByCategory(String category) async {
    try {
      final response = await supabase
          .from('products')
          .select()
          .eq('category', category)
          .eq('is_available', true)
          .order('created_at', ascending: false);

      return (response as List<dynamic>)
          .map((item) => Product.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Kategori ürünleri yüklenirken hata: $e');
    }
  }

  // Ürün ara (isim veya açıklamada)
  Future<List<Product>> searchProducts(String query) async {
    try {
      final response = await supabase
          .from('products')
          .select()
          .eq('is_available', true)
          .or('name.ilike.%$query%,description.ilike.%$query%')
          .order('created_at', ascending: false)
          .limit(50);

      return (response as List<dynamic>)
          .map((item) => Product.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Ürün arama hatası: $e');
    }
  }

  // Tek bir ürünü getir
  Future<Product> getProductById(String productId) async {
    try {
      final response = await supabase
          .from('products')
          .select()
          .eq('id', productId)
          .single();

      return Product.fromJson(response);
    } catch (e) {
      throw Exception('Ürün yüklenirken hata: $e');
    }
  }

  // İndirimli ürünleri getir:
  // - `discount_price` veya `old_price` kolonu set edilmiş klasik indirim
  // - VEYA aktif (zaman penceresinde + is_active) `flash_sales` kaydı olan ürün
  // "İndirimdekiler" ekranı her iki türü de göstermeli; flaş sale'de ürünün
  // `discount_price` kolonu set edilmemiş olabilir, bu yüzden ayrıca flash_sales
  // tablosuna bakıp bu ürünleri de dahil ediyoruz.
  Future<List<Product>> getDiscountedProducts() async {
    try {
      // 1) Klasik indirimli ürünler
      final discountedResp = await supabase
          .from('products')
          .select()
          .eq('is_available', true)
          .or('old_price.not.is.null,discount_price.not.is.null')
          .order('created_at', ascending: false);

      final discounted = (discountedResp as List<dynamic>)
          .map((item) => Product.fromJson(item as Map<String, dynamic>))
          .where((product) => product.hasDiscount)
          .toList();

      // 2) Aktif flaş sale'lerdeki ürünler
      final now = DateTime.now().toUtc().toIso8601String();
      final flashResp = await supabase
          .from('flash_sales')
          .select('product_id, products!inner(*)')
          .eq('is_active', true)
          .lte('start_at', now)
          .gte('end_at', now)
          .order('end_at', ascending: true);

      final flashProducts = (flashResp as List<dynamic>)
          .map((item) {
            final prodJson = item['products'] as Map<String, dynamic>?;
            if (prodJson == null) return null;
            // Sadece is_available olanları al
            if (prodJson['is_available'] == false) return null;
            return Product.fromJson(prodJson);
          })
          .whereType<Product>()
          .toList();

      // 3) Birleştir ve aynı ürünü tekrarlama
      final seen = <String>{};
      final result = <Product>[];
      for (final p in [...discounted, ...flashProducts]) {
        if (seen.add(p.id)) result.add(p);
      }
      return result;
    } catch (e) {
      throw Exception('İndirimli ürünler yüklenirken hata: $e');
    }
  }

  // En popüler ürünleri getir (satış sayısına göre)
  Future<List<Product>> getPopularProducts({int limit = 10}) async {
    try {
      final response = await supabase
          .from('products')
          .select()
          .eq('is_available', true)
          .order('created_at', ascending: false)
          .limit(limit);

      return (response as List<dynamic>)
          .map((item) => Product.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Popüler ürünler yüklenirken hata: $e');
    }
  }

  // Fiyat aralığına göre ürünleri filtrele
  Future<List<Product>> filterByPriceRange(
    double minPrice,
    double maxPrice,
  ) async {
    try {
      final response = await supabase
          .from('products')
          .select()
          .eq('is_available', true)
          .gte('price', minPrice)
          .lte('price', maxPrice)
          .order('price', ascending: true);

      return (response as List<dynamic>)
          .map((item) => Product.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Fiyat filtresi uygulanırken hata: $e');
    }
  }

  // Stok bilgisini güncelle (admin/seller için)
  Future<void> updateStock(String productId, int quantity) async {
    try {
      await supabase
          .from('products')
          .update({'stock_quantity': quantity})
          .eq('id', productId);
    } catch (e) {
      throw Exception('Stok güncellenirken hata: $e');
    }
  }

  // Slug oluştur (URL için temiz string)
  String _generateSlug(String name) {
    // Türkçe karakterleri İngilizce karşılıklarına çevir
    final trMap = {
      'ç': 'c',
      'Ç': 'c',
      'ğ': 'g',
      'Ğ': 'g',
      'ı': 'i',
      'İ': 'i',
      'ö': 'o',
      'Ö': 'o',
      'ş': 's',
      'Ş': 's',
      'ü': 'u',
      'Ü': 'u',
    };

    String slug = name;
    trMap.forEach((tr, en) {
      slug = slug.replaceAll(tr, en);
    });

    // Küçük harfe çevir, boşlukları tire ile değiştir
    slug = slug.toLowerCase().replaceAll(RegExp(r'\s+'), '-');

    // Sadece harf, rakam ve tire bırak
    slug = slug.replaceAll(RegExp(r'[^a-z0-9-]'), '');

    // Birden fazla tireyi tek tireye çevir
    slug = slug.replaceAll(RegExp(r'-+'), '-');

    // Başında ve sonunda tire varsa kaldır
    slug = slug.replaceAll(RegExp(r'^-|-$'), '');

    // Boş ise varsayılan slug
    if (slug.isEmpty) {
      slug = 'urun-${DateTime.now().millisecondsSinceEpoch}';
    }

    return slug;
  }

  // Satıcının ürün sayısını kontrol et
  Future<int> getShopProductCount(String shopId) async {
    try {
      final response = await supabase
          .from('products')
          .select('id')
          .eq('shop_id', shopId);

      return (response as List).length;
    } catch (e) {
      return 0;
    }
  }

  // Ürün ekle (seller için)
  Future<Product> addProduct({
    required String shopId,
    required String name,
    required String description,
    required double price,
    required double? oldPrice,
    required int stockQuantity,
    required String? imageUrl,
    required String? category,
    List<String>? additionalImages,
    String productType = 'normal',
    List<String>? sizes,
    List<int>? shoeSizes,
    List<Map<String, dynamic>>? colors,
    String? smmProviderId,
    String? smmServiceId,
    double? pricePer1000,
    int? minQuantity,
    int? maxQuantity,
    int? maxOrdersPerUser,
    String? campaignType,
  }) async {
    try {
      // Ürün limitini kaldırdık - sınırsız ürün eklenebilir

      final slug = _generateSlug(name);

      final response = await supabase
          .from('products')
          .insert({
            'shop_id': shopId,
            'name': name,
            'slug': slug,
            'description': description,
            'price': price,
            'old_price': oldPrice,
            'stock_quantity': stockQuantity,
            'image_url': imageUrl,
            'additional_images': additionalImages ?? [],
            'category': category,
            'is_available': true,
            'product_type': productType,
            'sizes': sizes ?? [],
            'shoe_sizes': shoeSizes ?? [],
            'colors': colors ?? [],
            'smm_provider_id': smmProviderId,
            'smm_service_id': smmServiceId,
            'price_per_1000': pricePer1000,
            'min_quantity': minQuantity,
            'max_quantity': maxQuantity,
            'max_orders_per_user': maxOrdersPerUser,
            'campaign_type': campaignType,
          })
          .select()
          .single();

      return Product.fromJson(response);
    } catch (e) {
      throw Exception('Ürün eklenirken hata: $e');
    }
  }

  // Ürün güncelle (seller için)
  Future<Product> updateProduct({
    required String productId,
    required String name,
    required String description,
    required double price,
    required double? oldPrice,
    required int stockQuantity,
    required String? imageUrl,
    List<String>? additionalImages,
    required String? category,
    String? productType,
    List<String>? sizes,
    List<int>? shoeSizes,
    List<Map<String, dynamic>>? colors,
    String? smmProviderId,
    String? smmServiceId,
    double? pricePer1000,
    int? minQuantity,
    int? maxQuantity,
    int? maxOrdersPerUser,
    bool clearMaxOrdersPerUser = false,
    String? campaignType,
    bool clearCampaignType = false,
  }) async {
    try {
      final updateData = {
        'name': name,
        'description': description,
        'price': price,
        'old_price': oldPrice,
        'stock_quantity': stockQuantity,
        'image_url': imageUrl,
        'additional_images': additionalImages ?? [],
        'category': category,
      };

      if (campaignType != null) {
        updateData['campaign_type'] = campaignType;
      } else if (clearCampaignType) {
        updateData['campaign_type'] = null;
      }

      // Varyant alanlarını ekle
      if (productType != null) updateData['product_type'] = productType;
      if (sizes != null) updateData['sizes'] = sizes;
      if (shoeSizes != null) updateData['shoe_sizes'] = shoeSizes;
      if (colors != null) updateData['colors'] = colors;
      if (smmProviderId != null) updateData['smm_provider_id'] = smmProviderId;
      if (smmServiceId != null) updateData['smm_service_id'] = smmServiceId;
      if (pricePer1000 != null) updateData['price_per_1000'] = pricePer1000;
      if (minQuantity != null) updateData['min_quantity'] = minQuantity;
      if (maxQuantity != null) updateData['max_quantity'] = maxQuantity;
      if (maxOrdersPerUser != null) {
        updateData['max_orders_per_user'] = maxOrdersPerUser;
      } else if (clearMaxOrdersPerUser) {
        updateData['max_orders_per_user'] = null;
      }

      final response = await supabase
          .from('products')
          .update(updateData)
          .eq('id', productId)
          .select()
          .single();

      return Product.fromJson(response);
    } catch (e) {
      throw Exception('Ürün güncellenirken hata: $e');
    }
  }

  // Ürünü sil (seller için). Sipariş geçmişi olan ürünler silinemediğinden
  // bu durumda ürün otomatik olarak devre dışı bırakılır (soft delete).
  // Dönüş değeri true ise ürün silindi, false ise devre dışı bırakıldı.
  Future<bool> deleteProduct(String productId) async {
    try {
      await supabase.from('products').delete().eq('id', productId);
      return true;
    } catch (e) {
      if (e is PostgrestException && e.code == '23503') {
        await supabase
            .from('products')
            .update({'is_available': false})
            .eq('id', productId);
        return false;
      }
      throw Exception('Ürün silinirken hata: $e');
    }
  }

  // Ürünü devre dışı bırak/etkinleştir
  Future<void> toggleProductAvailability(
    String productId,
    bool isAvailable,
  ) async {
    try {
      await supabase
          .from('products')
          .update({'is_available': isAvailable})
          .eq('id', productId);
    } catch (e) {
      throw Exception('Ürün durumu güncellenirken hata: $e');
    }
  }

  // Ürünü sabitle/sabitlemeyi kaldır (seller için - kendi dükkanında)
  Future<void> toggleSellerPinned(String productId, bool sellerPinned) async {
    try {
      await supabase
          .from('products')
          .update({'seller_pinned': sellerPinned})
          .eq('id', productId);
    } catch (e) {
      throw Exception('Ürün sabitlenirken hata: $e');
    }
  }

  // Ürünü sponsor olarak sabitle/kaldır (admin için)
  Future<void> toggleProductPinned(String productId, bool isPinned) async {
    try {
      await supabase
          .from('products')
          .update({'is_pinned': isPinned})
          .eq('id', productId);
    } catch (e) {
      throw Exception('Ürün sponsor durumu güncellenirken hata: $e');
    }
  }
}
