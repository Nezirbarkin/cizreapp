import 'package:flutter/material.dart';

/// Satıcının ürüne ekleyebileceği rozetler.
///
/// Buradaki `key` değerleri veritabanındaki `products.badges` dizisinde saklanır
/// ve `products_badges_allowed` CHECK constraint'i ile birebir aynı olmalıdır —
/// listeye yeni bir rozet eklenecekse önce migration ile constraint güncellenir.
class ProductBadge {
  final String key;
  final String label;
  final IconData icon;
  final Color color;

  const ProductBadge({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
  });

  /// Bir üründe aynı anda gösterilebilecek en fazla rozet sayısı (DB ile aynı).
  static const int maxPerProduct = 3;

  static const List<ProductBadge> all = [
    ProductBadge(
      key: 'yeni',
      label: 'Yeni',
      icon: Icons.fiber_new,
      color: Color(0xFF2E7D32),
    ),
    ProductBadge(
      key: 'cok_satan',
      label: 'Çok Satan',
      icon: Icons.local_fire_department,
      color: Color(0xFFE64A19),
    ),
    ProductBadge(
      key: 'sinirli_stok',
      label: 'Sınırlı Stok',
      icon: Icons.hourglass_bottom,
      color: Color(0xFFC62828),
    ),
    ProductBadge(
      key: 'el_yapimi',
      label: 'El Yapımı',
      icon: Icons.back_hand_outlined,
      color: Color(0xFF6D4C41),
    ),
    ProductBadge(
      key: 'organik',
      label: 'Organik',
      icon: Icons.eco_outlined,
      color: Color(0xFF388E3C),
    ),
    ProductBadge(
      key: 'yerli_uretim',
      label: 'Yerli Üretim',
      icon: Icons.flag_outlined,
      color: Color(0xFFD32F2F),
    ),
    ProductBadge(
      key: 'ithal',
      label: 'İthal',
      icon: Icons.public,
      color: Color(0xFF1565C0),
    ),
    ProductBadge(
      key: 'garantili',
      label: 'Garantili',
      icon: Icons.verified_user_outlined,
      color: Color(0xFF00838F),
    ),
    ProductBadge(
      key: 'son_firsat',
      label: 'Son Fırsat',
      icon: Icons.bolt,
      color: Color(0xFFF9A825),
    ),
  ];

  /// Bilinmeyen key'ler için null döner; DB'de eski/kaldırılmış bir rozet
  /// kalmışsa UI patlamak yerine o rozeti sessizce atlar.
  static ProductBadge? fromKey(String key) {
    for (final b in all) {
      if (b.key == key) return b;
    }
    return null;
  }
}

class ProductColor {
  final String name;
  final String hex;
  final int stock;

  ProductColor({required this.name, required this.hex, required this.stock});

  factory ProductColor.fromJson(Map<String, dynamic> json) {
    return ProductColor(
      name: json['name'] as String,
      hex: json['hex'] as String,
      stock: json['stock'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'hex': hex, 'stock': stock};
  }
}

class Product {
  final String id;
  final String shopId;
  final String name;
  final String? description;
  final double price;
  final double? oldPrice;
  final double? discountPrice; // İndirimli fiyat (discount_price kolonu için)
  final int stockQuantity;
  final String? imageUrl;
  final List<String> additionalImages; // Ek görseller
  final String? category;
  final bool isAvailable;
  final bool isPinned; // Admin tarafından yapılan global sponsorlama
  final bool
  sellerPinned; // Satıcı tarafından kendi dükkanında yapılan sabitleme
  final DateTime createdAt;
  final DateTime updatedAt;

  // Varyant alanları
  final String productType; // 'normal', 'clothing', 'shoes'
  final List<String> sizes; // Beden listesi (S, M, L, XL, etc.)
  final List<int> shoeSizes; // Ayakkabı numaraları
  final List<ProductColor> colors; // Renk listesi

  // Dijital ürün (SMM panel) alanları - productType == 'digital' iken kullanılır
  final String? smmProviderId;
  final String? smmServiceId;
  final double? pricePer1000;
  final int? minQuantity;
  final int? maxQuantity;
  final int?
  maxOrdersPerUser; // Satıcının belirlediği kullanıcı başına sipariş limiti (null = limitsiz)
  final bool isPointsEligible;
  final int maxPointsCoveragePercent;

  // Kampanya: şu an sadece 'buy2_get1_balance' ("2 al biri bakiye") destekleniyor
  final String? campaignType;

  // ── Satıcının ekleyebildiği ek özellikler ──────────────────────────────────
  /// Ürün rozetleri (`ProductBadge.all` içindeki key'ler).
  final List<String> badges;

  /// Hazırlık (kargoya veriliş) süresi, gün. İkisi de null = süre belirtilmemiş.
  final int? prepTimeMinDays;
  final int? prepTimeMaxDays;

  /// Ürüne özel kargo ücreti. null = mağazanın `delivery_fee` değeri geçerli.
  final double? shippingFee;

  /// Ürüne özel ücretsiz kargo. Bir mağazanın sepetteki tüm ürünleri
  /// `freeShipping` ise o mağazanın kargo ücreti 0 olur.
  final bool freeShipping;

  /// Fiziksel ürünlerde sipariş adedi sınırı (dijital ürünlerde
  /// `minQuantity`/`maxQuantity` kullanılır, bu alanlar uygulanmaz).
  final int? minOrderQuantity;
  final int? maxOrderQuantity;

  // Puanlama alanları (veritabanından çekilir)
  final double _rating;
  final int _totalReviews;

  Product({
    required this.id,
    required this.shopId,
    required this.name,
    this.description,
    required this.price,
    this.oldPrice,
    this.discountPrice,
    required this.stockQuantity,
    this.imageUrl,
    this.additionalImages = const [],
    this.category,
    required this.isAvailable,
    this.isPinned = false,
    this.sellerPinned = false,
    required this.createdAt,
    required this.updatedAt,
    this.productType = 'normal',
    this.sizes = const [],
    this.shoeSizes = const [],
    this.colors = const [],
    this.smmProviderId,
    this.smmServiceId,
    this.pricePer1000,
    this.minQuantity,
    this.maxQuantity,
    this.maxOrdersPerUser,
    this.isPointsEligible = false,
    this.maxPointsCoveragePercent = 100,
    this.campaignType,
    this.badges = const [],
    this.prepTimeMinDays,
    this.prepTimeMaxDays,
    this.shippingFee,
    this.freeShipping = false,
    this.minOrderQuantity,
    this.maxOrderQuantity,
    double rating = 0.0,
    int totalReviews = 0,
  }) : _rating = rating,
       _totalReviews = totalReviews;

  // İndirim yüzdesi hesapla
  int? get discountPercentage {
    // Önce discount_price kolonuna bak
    if (discountPrice != null && discountPrice! > 0 && discountPrice! < price) {
      return (((price - discountPrice!) / price) * 100).round();
    }
    // Yoksa old_price kolonuna bak
    if (oldPrice != null && oldPrice! > price) {
      return (((oldPrice! - price) / oldPrice!) * 100).round();
    }
    return null;
  }

  // İndirimli mi?
  bool get hasDiscount {
    // discount_price kolonu varsa ve 0'dan büyük ve normal fiyattan küçükse
    if (discountPrice != null && discountPrice! > 0 && discountPrice! < price) {
      return true;
    }
    // Yoksa old_price kolonuna bak
    return oldPrice != null && oldPrice! > price;
  }

  // Stokta var mı?
  bool get inStock => (isDigital || stockQuantity > 0) && isAvailable;

  // Geçerli fiyat (indirim varsa indirimli fiyat, yoksa normal fiyat)
  double get effectivePrice {
    // Önce discount_price kolonuna bak
    if (discountPrice != null && discountPrice! > 0 && discountPrice! < price) {
      return discountPrice!;
    }
    // Yoksa normal fiyatı kullan
    return price;
  }

  // Eski fiyat (görüntüleme için)
  double? get displayOldPrice {
    // İndirim varsa eski fiyatı döndür
    if (hasDiscount) {
      // discount_price kullanılmışsa price'ı eski fiyat olarak göster
      if (discountPrice != null &&
          discountPrice! > 0 &&
          discountPrice! < price) {
        return price;
      }
      // old_price kullanılmışsa onu göster
      return oldPrice;
    }
    return null;
  }

  // Tüm resimler listesi (ana resim + ek resimler)
  List<String> get images {
    final allImages = <String>[];
    if (imageUrl != null) allImages.add(imageUrl!);
    allImages.addAll(additionalImages);
    return allImages;
  }

  // Rating (veritabanından çekilen gerçek değer)
  double get rating => _rating;

  // Toplam review sayısı (veritabanından çekilen gerçek değer)
  int get totalReviews => _totalReviews;

  // Yıldızlı puan gösterimi (örn: "4.5 ★")
  String get ratingDisplay =>
      rating > 0 ? '${rating.toStringAsFixed(1)} ★' : 'Henüz puan yok';

  // Yorumlar var mı?
  bool get hasReviews => totalReviews > 0;

  // Varyant gerektiriyor mu? (dijital ürünler varyant/stok mantığına girmez)
  bool get hasVariants => productType != 'normal' && productType != 'digital';

  // Giyim ürünü mü?
  bool get isClothing => productType == 'clothing';

  // Ayakkabı mı?
  bool get isShoes => productType == 'shoes';

  // Dijital (SMM panel) ürünü mü?
  bool get isDigital => productType == 'digital';

  // "2 al biri bakiye" kampanyası aktif mi?
  bool get isBuy2Get1BalanceCampaign => campaignType == 'buy2_get1_balance';

  // ── Ek özellik yardımcıları ────────────────────────────────────────────────

  /// Gösterilebilir rozetler. DB'de tanınmayan bir key kalmışsa atlanır.
  List<ProductBadge> get badgeDetails =>
      badges.map(ProductBadge.fromKey).whereType<ProductBadge>().toList();

  /// Hazırlık süresi metni. Süre girilmemişse null döner (UI hiç göstermez).
  String? get prepTimeLabel {
    final min = prepTimeMinDays;
    final max = prepTimeMaxDays;
    if (min == null && max == null) return null;

    // Tek değer girilmişse onu kullan.
    if (min == null) return _prepDayText(max!);
    if (max == null || max == min) return _prepDayText(min);
    return '$min-$max iş günü içinde kargoda';
  }

  String _prepDayText(int days) =>
      days == 0 ? 'Aynı gün kargoda' : '$days iş günü içinde kargoda';

  /// Bu ürünün kendi kargo kuralı var mı? (bilgi rozetleri için)
  bool get hasCustomShipping => freeShipping || (shippingFee != null);

  /// Sepete eklenebilecek en az adet. Belirtilmemişse 1.
  /// Dijital ürünlerde bu alan kullanılmaz.
  int get minOrderQty =>
      (!isDigital && minOrderQuantity != null && minOrderQuantity! > 0)
      ? minOrderQuantity!
      : 1;

  /// Sepete eklenebilecek en fazla adet — satıcı limiti ile stok limitinin
  /// küçüğü. Hiçbiri yoksa null (yalnızca stok/adet üst sınırı geçerli).
  int? get maxOrderQty {
    if (isDigital) return null;
    final limit = maxOrderQuantity;
    if (limit == null || limit <= 0) return null;
    return limit;
  }

  /// Satıcının koyduğu adet sınırı için açıklama metni.
  String? get orderQuantityLabel {
    if (isDigital) return null;
    final min = minOrderQty;
    final max = maxOrderQty;
    if (min <= 1 && max == null) return null;
    if (min > 1 && max != null) {
      return 'En az $min, en fazla $max adet alınabilir';
    }
    if (min > 1) return 'En az $min adet alınabilir';
    return 'En fazla $max adet alınabilir';
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    // sizes parsing
    List<String> sizesList = [];
    if (json['sizes'] != null) {
      if (json['sizes'] is List) {
        sizesList = (json['sizes'] as List).map((e) => e.toString()).toList();
      }
    }

    // shoe_sizes parsing
    List<int> shoeSizesList = [];
    if (json['shoe_sizes'] != null) {
      if (json['shoe_sizes'] is List) {
        shoeSizesList = (json['shoe_sizes'] as List)
            .map((e) => int.tryParse(e.toString()) ?? 0)
            .toList();
      }
    }

    // colors parsing
    List<ProductColor> colorsList = [];
    if (json['colors'] != null) {
      if (json['colors'] is List) {
        colorsList = (json['colors'] as List)
            .map((e) => ProductColor.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    }

    // additional_images parsing
    List<String> additionalImagesList = [];
    if (json['additional_images'] != null) {
      if (json['additional_images'] is List) {
        additionalImagesList = (json['additional_images'] as List)
            .map((e) => e.toString())
            .toList();
      }
    }

    // badges parsing
    List<String> badgesList = [];
    if (json['badges'] is List) {
      badgesList = (json['badges'] as List).map((e) => e.toString()).toList();
    }

    // discount_price'ı da al
    final discountPriceValue = json['discount_price'] != null
        ? (json['discount_price'] is int)
              ? (json['discount_price'] as int).toDouble()
              : (json['discount_price'] as num?)?.toDouble()
        : null;

    return Product(
      id: json['id'] as String,
      shopId: json['shop_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      price: (json['price'] is int)
          ? (json['price'] as int).toDouble()
          : (json['price'] as num).toDouble(),
      oldPrice: json['old_price'] != null
          ? (json['old_price'] is int)
                ? (json['old_price'] as int).toDouble()
                : (json['old_price'] as num).toDouble()
          : null,
      discountPrice: discountPriceValue,
      stockQuantity: json['stock_quantity'] as int? ?? 0,
      imageUrl: json['image_url'] as String?,
      additionalImages: additionalImagesList,
      category: json['category'] as String?,
      isAvailable: json['is_available'] as bool? ?? true,
      isPinned: json['is_pinned'] as bool? ?? false,
      sellerPinned: json['seller_pinned'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      productType: json['product_type'] as String? ?? 'normal',
      sizes: sizesList,
      shoeSizes: shoeSizesList,
      colors: colorsList,
      smmProviderId: json['smm_provider_id'] as String?,
      smmServiceId: json['smm_service_id'] as String?,
      pricePer1000: (json['price_per_1000'] as num?)?.toDouble(),
      minQuantity: json['min_quantity'] as int?,
      maxQuantity: json['max_quantity'] as int?,
      maxOrdersPerUser: json['max_orders_per_user'] as int?,
      isPointsEligible: json['is_points_eligible'] as bool? ?? false,
      maxPointsCoveragePercent:
          (json['max_points_coverage_percent'] as num?)?.toInt() ?? 100,
      campaignType: json['campaign_type'] as String?,
      badges: badgesList,
      prepTimeMinDays: (json['prep_time_min_days'] as num?)?.toInt(),
      prepTimeMaxDays: (json['prep_time_max_days'] as num?)?.toInt(),
      shippingFee: (json['shipping_fee'] as num?)?.toDouble(),
      freeShipping: json['free_shipping'] as bool? ?? false,
      minOrderQuantity: (json['min_order_quantity'] as num?)?.toInt(),
      maxOrderQuantity: (json['max_order_quantity'] as num?)?.toInt(),
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      totalReviews: json['total_reviews'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shop_id': shopId,
      'name': name,
      'description': description,
      'price': price,
      'old_price': oldPrice,
      'discount_price': discountPrice,
      'stock_quantity': stockQuantity,
      'image_url': imageUrl,
      'additional_images': additionalImages,
      'category': category,
      'is_available': isAvailable,
      'is_pinned': isPinned,
      'seller_pinned': sellerPinned,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'product_type': productType,
      'sizes': sizes,
      'shoe_sizes': shoeSizes,
      'colors': colors.map((c) => c.toJson()).toList(),
      'smm_provider_id': smmProviderId,
      'smm_service_id': smmServiceId,
      'price_per_1000': pricePer1000,
      'min_quantity': minQuantity,
      'max_quantity': maxQuantity,
      'max_orders_per_user': maxOrdersPerUser,
      'is_points_eligible': isDigital ? isPointsEligible : false,
      'max_points_coverage_percent': maxPointsCoveragePercent,
      'campaign_type': campaignType,
      'badges': badges,
      'prep_time_min_days': prepTimeMinDays,
      'prep_time_max_days': prepTimeMaxDays,
      'shipping_fee': shippingFee,
      'free_shipping': freeShipping,
      'min_order_quantity': minOrderQuantity,
      'max_order_quantity': maxOrderQuantity,
      'rating': rating,
      'total_reviews': totalReviews,
    };
  }

  Product copyWith({
    String? id,
    String? shopId,
    String? name,
    String? description,
    double? price,
    double? oldPrice,
    double? discountPrice,
    int? stockQuantity,
    String? imageUrl,
    List<String>? additionalImages,
    String? category,
    bool? isAvailable,
    bool? isPinned,
    bool? sellerPinned,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? productType,
    List<String>? sizes,
    List<int>? shoeSizes,
    List<ProductColor>? colors,
    String? smmProviderId,
    String? smmServiceId,
    double? pricePer1000,
    int? minQuantity,
    int? maxQuantity,
    int? maxOrdersPerUser,
    bool? isPointsEligible,
    int? maxPointsCoveragePercent,
    String? campaignType,
    List<String>? badges,
    int? prepTimeMinDays,
    int? prepTimeMaxDays,
    double? shippingFee,
    bool? freeShipping,
    int? minOrderQuantity,
    int? maxOrderQuantity,
    double? rating,
    int? totalReviews,

    /// `discountPrice`'ı gerçekten null yapmak için. `discountPrice: null`
    /// geçmek `??` zinciri yüzünden mevcut değeri korur; toplu "indirimi
    /// kaldır" işleminden sonra listeyi güncellemek için bu bayrak gerekir.
    bool clearDiscountPrice = false,
  }) {
    return Product(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      oldPrice: oldPrice ?? this.oldPrice,
      discountPrice: clearDiscountPrice
          ? null
          : (discountPrice ?? this.discountPrice),
      stockQuantity: stockQuantity ?? this.stockQuantity,
      imageUrl: imageUrl ?? this.imageUrl,
      additionalImages: additionalImages ?? this.additionalImages,
      category: category ?? this.category,
      isAvailable: isAvailable ?? this.isAvailable,
      isPinned: isPinned ?? this.isPinned,
      sellerPinned: sellerPinned ?? this.sellerPinned,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      productType: productType ?? this.productType,
      sizes: sizes ?? this.sizes,
      shoeSizes: shoeSizes ?? this.shoeSizes,
      colors: colors ?? this.colors,
      smmProviderId: smmProviderId ?? this.smmProviderId,
      smmServiceId: smmServiceId ?? this.smmServiceId,
      pricePer1000: pricePer1000 ?? this.pricePer1000,
      minQuantity: minQuantity ?? this.minQuantity,
      maxQuantity: maxQuantity ?? this.maxQuantity,
      maxOrdersPerUser: maxOrdersPerUser ?? this.maxOrdersPerUser,
      isPointsEligible: productType != null && productType != 'digital'
          ? false
          : isPointsEligible ?? this.isPointsEligible,
      maxPointsCoveragePercent:
          maxPointsCoveragePercent ?? this.maxPointsCoveragePercent,
      campaignType: campaignType ?? this.campaignType,
      badges: badges ?? this.badges,
      prepTimeMinDays: prepTimeMinDays ?? this.prepTimeMinDays,
      prepTimeMaxDays: prepTimeMaxDays ?? this.prepTimeMaxDays,
      shippingFee: shippingFee ?? this.shippingFee,
      freeShipping: freeShipping ?? this.freeShipping,
      minOrderQuantity: minOrderQuantity ?? this.minOrderQuantity,
      maxOrderQuantity: maxOrderQuantity ?? this.maxOrderQuantity,
      rating: rating ?? this.rating,
      totalReviews: totalReviews ?? this.totalReviews,
    );
  }
}
