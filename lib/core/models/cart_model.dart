class CartItem {
  final String id;
  final String userId;
  final String productId;
  final int quantity;
  final DateTime createdAt;
  final DateTime updatedAt;

  // İlişkili ürün bilgisi (join sonucu)
  final String? productName;
  final double? productPrice;
  final double? productOldPrice;

  /// İndirimli fiyat (DB `products.discount_price` kolonu). Sepet join'inde
  /// `effectivePrice` mantığıyla birlikte kullanılır — aksi halde kullanıcı
  /// detayda gördüğü indirimli fiyatı sepete eklediğinde indirimsiz fiyat
  /// üzerinden işlem görürdü.
  final double? productDiscountPrice;
  final String? productImageUrl;
  final String? shopId;
  final String? shopName;
  final bool? isAvailable;
  final int? stockQuantity;

  // Varyant bilgileri (renk, beden, numara)
  final Map<String, dynamic>? variantData;

  /// Flaş satıştan geldiyse ilgili referanslar (DB `cart.flash_sale_id`,
  /// `cart.flash_price`). null = ürün flaş satışta değildi.
  final String? flashSaleId;
  final double? flashPrice;

  /// Ürüne özel kargo alanları (DB `products.shipping_fee` / `free_shipping`).
  /// Sepetteki kargo ücretini sunucudaki kuralla aynı şekilde göstermek için
  /// join'de çekilir — aksi halde kullanıcı sepette bir ücret görüp ödemede
  /// başka bir ücretle karşılaşırdı.
  final double? productShippingFee;
  final bool productFreeShipping;

  /// Satıcının koyduğu sipariş adedi sınırları (DB `products.*_order_quantity`).
  final int? productMinOrderQuantity;
  final int? productMaxOrderQuantity;

  CartItem({
    required this.id,
    required this.userId,
    required this.productId,
    required this.quantity,
    required this.createdAt,
    required this.updatedAt,
    this.productName,
    this.productPrice,
    this.productOldPrice,
    this.productDiscountPrice,
    this.productImageUrl,
    this.shopId,
    this.shopName,
    this.isAvailable,
    this.stockQuantity,
    this.variantData,
    this.flashSaleId,
    this.flashPrice,
    this.productShippingFee,
    this.productFreeShipping = false,
    this.productMinOrderQuantity,
    this.productMaxOrderQuantity,
  });

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      productId: json['product_id'] as String,
      quantity: json['quantity'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      productName: json['product_name'] as String?,
      productPrice: json['product_price'] != null
          ? (json['product_price'] as num).toDouble()
          : null,
      productOldPrice: json['product_old_price'] != null
          ? (json['product_old_price'] as num).toDouble()
          : null,
      productDiscountPrice: json['product_discount_price'] != null
          ? (json['product_discount_price'] as num).toDouble()
          : null,
      productImageUrl: json['product_image_url'] as String?,
      shopId: json['shop_id'] as String?,
      shopName: json['shop_name'] as String?,
      isAvailable: json['is_available'] as bool?,
      stockQuantity: json['stock_quantity'] as int?,
      variantData: json['variant_data'] as Map<String, dynamic>?,
      flashSaleId: json['flash_sale_id'] as String?,
      flashPrice: (json['flash_price'] as num?)?.toDouble(),
      productShippingFee: (json['product_shipping_fee'] as num?)?.toDouble(),
      productFreeShipping: json['product_free_shipping'] as bool? ?? false,
      productMinOrderQuantity: (json['product_min_order_quantity'] as num?)
          ?.toInt(),
      productMaxOrderQuantity: (json['product_max_order_quantity'] as num?)
          ?.toInt(),
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
      'flash_sale_id': flashSaleId,
      'flash_price': flashPrice,
    };
  }

  // Getters
  /// Geçerli (indirimli) birim fiyat. Öncelik sırası:
  /// 1) `flashPrice` (flaş satıştan geldiyse, sepete eklenirken sabitlenen fiyat),
  /// 2) `productDiscountPrice` (ürünün kendi indirimli fiyatı),
  /// 3) `productPrice` (ürünün normal fiyatı).
  /// Bu sıralama kullanıcının her zaman en iyi fiyatı görmesini sağlar.
  double get effectivePrice {
    // 1) Flaş satış (varsa) her şeyi ezer — kullanıcı sepete flaş fiyattan eklediyse
    // satıcı sonradan sale'i değiştirse bile bu fiyat değişmez.
    if (flashPrice != null && flashPrice! > 0) {
      return flashPrice!;
    }
    // 2) Ürünün kendi discount_price'ı
    if (productDiscountPrice != null &&
        productDiscountPrice! > 0 &&
        productPrice != null &&
        productDiscountPrice! < productPrice!) {
      return productDiscountPrice!;
    }
    // 3) Normal fiyat
    return productPrice ?? 0;
  }

  /// Flaş satıştan mı geldi?
  bool get isFlashSaleItem =>
      flashSaleId != null && flashPrice != null && flashPrice! > 0;

  double get itemTotal {
    return effectivePrice * quantity;
  }

  /// Tasarruf tutarı (gösterim amaçlı): gerçek ödenen fiyat ile
  /// (flaş orijinal, old_price veya normal price) arasındaki fark × miktar.
  /// Öncelik sırası: flashPrice (original) > productOldPrice > productPrice.
  double get itemDiscount {
    final unit = effectivePrice;
    if (isFlashSaleItem && productPrice != null && productPrice! > unit) {
      // Flaş indirimde "eski fiyat" ürünün normal fiyatıdır.
      return (productPrice! - unit) * quantity;
    }
    if (productOldPrice != null && productOldPrice! > unit) {
      return (productOldPrice! - unit) * quantity;
    }
    if (productPrice != null && productPrice! > unit) {
      return (productPrice! - unit) * quantity;
    }
    return 0;
  }

  bool get hasDiscount {
    final unit = effectivePrice;
    if (isFlashSaleItem && productPrice != null && productPrice! > unit) {
      return true;
    }
    if (productOldPrice != null && productOldPrice! > unit) return true;
    if (productPrice != null && productPrice! > unit) return true;
    return false;
  }

  int get discountPercentage {
    final unit = effectivePrice;
    double? base;
    if (isFlashSaleItem && productPrice != null && productPrice! > unit) {
      base = productPrice;
    } else {
      base = productOldPrice ?? productPrice;
    }
    if (base != null && base > 0 && base > unit) {
      return (((base - unit) / base) * 100).round();
    }
    return 0;
  }

  /// Satıcının koyduğu en az sipariş adedi (yoksa 1).
  int get minOrderQuantity =>
      (productMinOrderQuantity != null && productMinOrderQuantity! > 0)
      ? productMinOrderQuantity!
      : 1;

  /// Stok ve satıcı limitinin küçüğü; ikisi de yoksa null.
  int? get maxOrderQuantity {
    final sellerMax =
        (productMaxOrderQuantity != null && productMaxOrderQuantity! > 0)
        ? productMaxOrderQuantity
        : null;
    final stock = stockQuantity;
    if (sellerMax == null) return stock;
    if (stock == null) return sellerMax;
    return sellerMax < stock ? sellerMax : stock;
  }

  bool get canAddMore {
    final max = maxOrderQuantity;
    return max == null || quantity < max;
  }

  /// Miktar satıcının koyduğu alt sınırın altına inebilir mi?
  bool get canRemoveOne => quantity > minOrderQuantity;

  /// Sepetteki adet satıcının kurallarına uyuyor mu? Uymuyorsa ödeme
  /// adımında sunucu reddeder, bu yüzden kullanıcıyı önceden uyarıyoruz.
  bool get violatesQuantityLimits {
    final max = productMaxOrderQuantity;
    if (quantity < minOrderQuantity) return true;
    if (max != null && max > 0 && quantity > max) return true;
    return false;
  }

  /// Uyarı metni (limit ihlali yoksa null).
  String? get quantityLimitWarning {
    if (!violatesQuantityLimits) return null;
    final max = productMaxOrderQuantity;
    if (quantity < minOrderQuantity) {
      return 'Bu üründen en az $minOrderQuantity adet alınmalı';
    }
    return 'Bu üründen en fazla $max adet alınabilir';
  }

  bool get isInStock {
    return (isAvailable ?? false) &&
        (stockQuantity == null || stockQuantity! > 0);
  }

  // Copy with
  CartItem copyWith({
    String? id,
    String? userId,
    String? productId,
    int? quantity,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? productName,
    double? productPrice,
    double? productOldPrice,
    double? productDiscountPrice,
    String? productImageUrl,
    String? shopId,
    String? shopName,
    bool? isAvailable,
    int? stockQuantity,
    Map<String, dynamic>? variantData,
    String? flashSaleId,
    double? flashPrice,
    double? productShippingFee,
    bool? productFreeShipping,
    int? productMinOrderQuantity,
    int? productMaxOrderQuantity,
  }) {
    return CartItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      productId: productId ?? this.productId,
      quantity: quantity ?? this.quantity,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      productName: productName ?? this.productName,
      productPrice: productPrice ?? this.productPrice,
      productOldPrice: productOldPrice ?? this.productOldPrice,
      productDiscountPrice: productDiscountPrice ?? this.productDiscountPrice,
      productImageUrl: productImageUrl ?? this.productImageUrl,
      shopId: shopId ?? this.shopId,
      shopName: shopName ?? this.shopName,
      isAvailable: isAvailable ?? this.isAvailable,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      variantData: variantData ?? this.variantData,
      flashSaleId: flashSaleId ?? this.flashSaleId,
      flashPrice: flashPrice ?? this.flashPrice,
      productShippingFee: productShippingFee ?? this.productShippingFee,
      productFreeShipping: productFreeShipping ?? this.productFreeShipping,
      productMinOrderQuantity:
          productMinOrderQuantity ?? this.productMinOrderQuantity,
      productMaxOrderQuantity:
          productMaxOrderQuantity ?? this.productMaxOrderQuantity,
    );
  }

  // Varyant bilgilerini okumak için helper metodlar
  String? get variantColor => variantData?['color'] as String?;
  String? get variantSize => variantData?['size'] as String?;
  String? get variantShoeSize => variantData?['shoeSize']?.toString();
  bool get hasVariant => variantData != null && variantData!.isNotEmpty;
}

class CartSummary {
  final List<CartItem> items;
  final double subtotal;
  final double discount;
  final double deliveryFee;
  final double total;
  final int totalItems;

  /// Toplam kupon indirimi (tüm dükkanlardaki kuponların toplamı).
  /// `total` hesaplamasında `subtotal`'dan düşülür.
  final double couponDiscount;

  CartSummary({
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.deliveryFee,
    required this.total,
    required this.totalItems,
    this.couponDiscount = 0,
  });

  factory CartSummary.fromItems(
    List<CartItem> items, {
    double deliveryFee = 0,
    double couponDiscount = 0,
  }) {
    final subtotal = items.fold<double>(0, (sum, item) => sum + item.itemTotal);

    final discount = items.fold<double>(
      0,
      (sum, item) => sum + item.itemDiscount,
    );

    final totalItems = items.fold<int>(0, (sum, item) => sum + item.quantity);

    // Not: `subtotal` zaten indirimli productPrice üzerinden hesaplanır
    // (CartItem.itemTotal = productPrice * quantity). `discount` alanı
    // tasarruf miktarıdır (oldPrice - price) * qty; UI'da bilgi amaçlı
    // gösterilir, toplamdan düşülmez (yapılırsa çift düşüm olur).
    //
    // Kupon indirimi (`couponDiscount`) ise product indiriminden bağımsız
    // olarak toplamdan düşülür.
    final clampedCoupon = couponDiscount.clamp(0.0, subtotal).toDouble();
    final total = subtotal - clampedCoupon + deliveryFee;

    return CartSummary(
      items: items,
      subtotal: subtotal,
      discount: discount,
      deliveryFee: deliveryFee,
      total: total,
      totalItems: totalItems,
      couponDiscount: clampedCoupon,
    );
  }

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;

  // Dükkan bazında gruplama
  Map<String, List<CartItem>> get groupedByShop {
    final Map<String, List<CartItem>> grouped = {};

    for (var item in items) {
      final shopId = item.shopId ?? 'unknown';
      if (!grouped.containsKey(shopId)) {
        grouped[shopId] = [];
      }
      grouped[shopId]!.add(item);
    }

    return grouped;
  }

  // Dükkan başına toplam hesaplama
  double getShopTotal(String shopId) {
    return items
        .where((item) => item.shopId == shopId)
        .fold<double>(0, (sum, item) => sum + item.itemTotal);
  }
}
