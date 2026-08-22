import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/product_model.dart';

/// Toplu indirim uygulama biçimi. `dbValue` karşılıkları
/// `seller_bulk_set_discount` RPC'sinin kabul ettiği değerlerdir.
enum BulkDiscountMode {
  /// Fiyatın yüzdesi kadar indirim (örn. %20 -> fiyat * 0.80)
  percent('percent'),

  /// Fiyattan sabit tutar düşülür (örn. 25 ₺ -> fiyat - 25)
  amount('amount'),

  /// Seçili tüm ürünler bu fiyata düşer
  fixedPrice('fixed_price');

  const BulkDiscountMode(this.dbValue);
  final String dbValue;
}

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
      // ⚡ AÇILIŞ OPTİMİZASYONU (2026-08-14): İki sorgu birbirinden bağımsız —
      // sırayla değil paralel çekilir (2× RTT yerine ≈ 1× RTT).
      // Sorguların kendisi ve filtreleri DEĞİŞMEDİ.
      final now = DateTime.now().toUtc().toIso8601String();
      final results = await Future.wait([
        // 1) Klasik indirimli ürünler
        supabase
            .from('products')
            .select()
            .eq('is_available', true)
            .or('old_price.not.is.null,discount_price.not.is.null')
            .order('created_at', ascending: false),
        // 2) Aktif flaş sale'lerdeki ürünler
        supabase
            .from('flash_sales')
            .select('product_id, products!inner(*)')
            .eq('is_active', true)
            .lte('start_at', now)
            .gte('end_at', now)
            .order('end_at', ascending: true),
      ]);
      final discountedResp = results[0];
      final flashResp = results[1];

      final discounted = (discountedResp as List<dynamic>)
          .map((item) => Product.fromJson(item as Map<String, dynamic>))
          .where((product) => product.hasDiscount)
          .toList();

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
    List<String>? badges,
    int? prepTimeMinDays,
    int? prepTimeMaxDays,
    double? shippingFee,
    bool freeShipping = false,
    int? minOrderQuantity,
    int? maxOrderQuantity,
  }) async {
    try {
      // Ürün limitini kaldırdık - sınırsız ürün eklenebilir

      final slug = _generateSlug(name);

      // Session kontrolü
      final currentUser = supabase.auth.currentUser;
      final currentSession = supabase.auth.currentSession;
      // ignore: avoid_print
      print(
        'addProduct SESSION currentUser=${currentUser?.id} '
        'hasToken=${currentSession?.accessToken != null} '
        'expiresAt=${currentSession?.expiresAt} '
        'isExpired=${currentSession?.isExpired}',
      );

      // RPC ile ekle (RLS bypass + SECURITY DEFINER)
      // Önce RPC'yi dene, yoksa eski yönteme düş
      try {
        final rpcResult = await supabase.rpc(
          'add_product',
          params: {
            'p_shop_id': shopId,
            'p_name': name,
            'p_slug': slug,
            'p_description': description,
            'p_price': price,
            'p_old_price': oldPrice,
            'p_stock': stockQuantity,
            'p_image_url': imageUrl,
            'p_category': category,
            'p_additional_images': additionalImages ?? [],
            'p_product_type': productType,
            'p_sizes': sizes ?? [],
            'p_shoe_sizes': shoeSizes ?? [],
            'p_colors': colors ?? [],
            'p_badges': badges ?? <String>[],
            'p_prep_time_min_days': prepTimeMinDays,
            'p_prep_time_max_days': prepTimeMaxDays,
            'p_shipping_fee': shippingFee,
            'p_free_shipping': freeShipping,
            'p_min_order_quantity': minOrderQuantity,
            'p_max_order_quantity': maxOrderQuantity,
            'p_campaign_type': campaignType,
          },
        );

        // ignore: avoid_print
        print('RPC add_product BAŞARILI: $rpcResult');

        // RPC'den dönen product_id ile mevcut ürünü çek
        final productId = rpcResult as String;
        final response = await supabase
            .from('products')
            .select()
            .eq('id', productId)
            .single();

        return Product.fromJson(response);
      } catch (rpcError) {
        // ignore: avoid_print
        print('RPC add_product başarısız, fallback deneniyor: $rpcError');

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
              'badges': badges ?? <String>[],
              'prep_time_min_days': prepTimeMinDays,
              'prep_time_max_days': prepTimeMaxDays,
              'shipping_fee': shippingFee,
              'free_shipping': freeShipping,
              'min_order_quantity': minOrderQuantity,
              'max_order_quantity': maxOrderQuantity,
            })
            .select()
            .single();

        return Product.fromJson(response);
      }
    } catch (e, st) {
      // ignore: avoid_print
      print('addProduct FULL ERROR: $e');
      // ignore: avoid_print
      print('STACK: $st');
      rethrow;
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
    List<String>? badges,
    int? prepTimeMinDays,
    int? prepTimeMaxDays,
    double? shippingFee,
    bool? freeShipping,
    int? minOrderQuantity,
    int? maxOrderQuantity,

    /// Satıcı ürünü düzenlerken toplu indirimden kalan `discount_price`
    /// geçersizleşebilir (örn. fiyat indirimli fiyatın altına çekilirse). Bu
    /// bayrak set edildiğinde kolon temizlenir.
    bool clearDiscountPrice = false,
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

      // Ek özellikler: satıcı formu bu alanların tamamını her kayıtta gönderir,
      // bu yüzden null gelen değer "temizle" anlamına gelir.
      if (badges != null) updateData['badges'] = badges;
      updateData['prep_time_min_days'] = prepTimeMinDays;
      updateData['prep_time_max_days'] = prepTimeMaxDays;
      updateData['shipping_fee'] = shippingFee;
      if (freeShipping != null) updateData['free_shipping'] = freeShipping;
      updateData['min_order_quantity'] = minOrderQuantity;
      updateData['max_order_quantity'] = maxOrderQuantity;

      if (clearDiscountPrice) updateData['discount_price'] = null;

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

  /// Seçilen ürünlere tek işlemde indirim uygular (satıcı toplu indirim).
  ///
  /// İndirimli fiyat sunucuda hesaplanır — istemci yalnızca oran/tutar gönderir,
  /// böylece manipüle edilmiş bir fiyat veritabanına yazılamaz. Sunucu ayrıca
  /// ürünlerin gerçekten çağıran satıcıya ait olduğunu doğrular.
  ///
  /// [mode]: `percent` (oran), `amount` (tutar indir), `fixedPrice` (sabit fiyat).
  /// Dönüş: gerçekten güncellenen ürün sayısı. Sonucu geçersiz olan ürünler
  /// (fiyatı 0'a düşüren ya da fiyattan düşük olmayan indirimler) atlanır.
  Future<int> bulkSetDiscount({
    required List<String> productIds,
    required BulkDiscountMode mode,
    required double value,
  }) async {
    try {
      final result = await supabase.rpc(
        'seller_bulk_set_discount',
        params: {
          'p_product_ids': productIds,
          'p_mode': mode.dbValue,
          'p_value': value,
        },
      );
      return (result as num?)?.toInt() ?? 0;
    } catch (e) {
      throw Exception('Toplu indirim uygulanırken hata: $e');
    }
  }

  /// Seçilen ürünlerin indirimini kaldırır (`discount_price = null`).
  Future<int> bulkClearDiscount(List<String> productIds) async {
    try {
      final result = await supabase.rpc(
        'seller_bulk_set_discount',
        params: {
          'p_product_ids': productIds,
          'p_mode': 'clear',
          'p_value': null,
        },
      );
      return (result as num?)?.toInt() ?? 0;
    } catch (e) {
      throw Exception('İndirim kaldırılırken hata: $e');
    }
  }

  /// Seçilen ürünlerin rozetlerini tek işlemde ayarlar (mevcutların yerine geçer).
  /// Boş liste göndermek rozetleri temizler.
  Future<int> bulkSetBadges({
    required List<String> productIds,
    required List<String> badges,
  }) async {
    try {
      final result = await supabase.rpc(
        'seller_bulk_set_badges',
        params: {'p_product_ids': productIds, 'p_badges': badges},
      );
      return (result as num?)?.toInt() ?? 0;
    } catch (e) {
      throw Exception('Rozetler güncellenirken hata: $e');
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
