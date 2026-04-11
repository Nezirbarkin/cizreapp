import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/product_model.dart';

class ProductService {
  final supabase = Supabase.instance.client;

  // Tüm ürünleri getir (sponsorlar en başta, sponsor olmayanlar rastgele)
  Future<List<Product>> getAllProducts() async {
    try {
      final response = await supabase
          .from('products')
          .select()
          .eq('is_available', true)
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false);

      List<dynamic> productsList = response as List<dynamic>;
      
      // Sponsor ve sponsor olmayan ürünleri ayır
      final pinnedProducts = productsList.where((p) {
        final product = Product.fromJson(p as Map<String, dynamic>);
        return product.isPinned;
      }).toList();
      
      final nonPinnedProducts = productsList.where((p) {
        final product = Product.fromJson(p as Map<String, dynamic>);
        return !product.isPinned;
      }).toList();
      
      // Sponsor olmayanları karıştır (shuffle)
      nonPinnedProducts.shuffle();
      
      // Sponsorlar + karıştırılmış sponsor olmayanlar
      final shuffledList = [...pinnedProducts, ...nonPinnedProducts];

      return shuffledList.map((item) => Product.fromJson(item as Map<String, dynamic>)).toList();
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
          .order('created_at', ascending: false);

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

  // İndirimli ürünleri getir (old_price veya discount_price olan ürünler)
  Future<List<Product>> getDiscountedProducts() async {
    try {
      final response = await supabase
          .from('products')
          .select()
          .eq('is_available', true)
          .or('old_price.not.is.null,discount_price.not.is.null')
          .order('created_at', ascending: false);

      // Gerçekten indirimli olan ürünleri filtrele
      return (response as List<dynamic>)
          .map((item) => Product.fromJson(item as Map<String, dynamic>))
          .where((product) => product.hasDiscount)
          .toList();
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
      await supabase.from('products').update({
        'stock_quantity': quantity,
      }).eq('id', productId);
    } catch (e) {
      throw Exception('Stok güncellenirken hata: $e');
    }
  }

  // Slug oluştur (URL için temiz string)
  String _generateSlug(String name) {
    // Türkçe karakterleri İngilizce karşılıklarına çevir
    final trMap = {
      'ç': 'c', 'Ç': 'c',
      'ğ': 'g', 'Ğ': 'g',
      'ı': 'i', 'İ': 'i',
      'ö': 'o', 'Ö': 'o',
      'ş': 's', 'Ş': 's',
      'ü': 'u', 'Ü': 'u',
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
  }) async {
    try {
      // Ürün limitini kaldırdık - sınırsız ürün eklenebilir
      
      final slug = _generateSlug(name);
      
      final response = await supabase.from('products').insert({
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
      }).select().single();

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
      
      // Varyant alanlarını ekle
      if (productType != null) updateData['product_type'] = productType;
      if (sizes != null) updateData['sizes'] = sizes;
      if (shoeSizes != null) updateData['shoe_sizes'] = shoeSizes;
      if (colors != null) updateData['colors'] = colors;

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

  // Ürünü sil (seller için)
  Future<void> deleteProduct(String productId) async {
    try {
      await supabase.from('products').delete().eq('id', productId);
    } catch (e) {
      throw Exception('Ürün silinirken hata: $e');
    }
  }

  // Ürünü devre dışı bırak/etkinleştir
  Future<void> toggleProductAvailability(
    String productId,
    bool isAvailable,
  ) async {
    try {
      await supabase.from('products').update({
        'is_available': isAvailable,
      }).eq('id', productId);
    } catch (e) {
      throw Exception('Ürün durumu güncellenirken hata: $e');
    }
  }

  // Ürünü sabitle/sabitlemeyi kaldır (seller için - kendi dükkanında)
  Future<void> toggleSellerPinned(
    String productId,
    bool sellerPinned,
  ) async {
    try {
      await supabase.from('products').update({
        'seller_pinned': sellerPinned,
      }).eq('id', productId);
    } catch (e) {
      throw Exception('Ürün sabitlenirken hata: $e');
    }
  }

  // Ürünü sponsor olarak sabitle/kaldır (admin için)
  Future<void> toggleProductPinned(
    String productId,
    bool isPinned,
  ) async {
    try {
      await supabase.from('products').update({
        'is_pinned': isPinned,
      }).eq('id', productId);
    } catch (e) {
      throw Exception('Ürün sponsor durumu güncellenirken hata: $e');
    }
  }
}
