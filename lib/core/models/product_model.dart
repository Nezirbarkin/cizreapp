class ProductColor {
  final String name;
  final String hex;
  final int stock;

  ProductColor({
    required this.name,
    required this.hex,
    required this.stock,
  });

  factory ProductColor.fromJson(Map<String, dynamic> json) {
    return ProductColor(
      name: json['name'] as String,
      hex: json['hex'] as String,
      stock: json['stock'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'hex': hex,
      'stock': stock,
    };
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
  final bool sellerPinned; // Satıcı tarafından kendi dükkanında yapılan sabitleme
  final DateTime createdAt;
  final DateTime updatedAt;
  
  // Varyant alanları
  final String productType; // 'normal', 'clothing', 'shoes'
  final List<String> sizes; // Beden listesi (S, M, L, XL, etc.)
  final List<int> shoeSizes; // Ayakkabı numaraları
  final List<ProductColor> colors; // Renk listesi

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
    double rating = 0.0,
    int totalReviews = 0,
  })  : _rating = rating,
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
  bool get inStock => stockQuantity > 0 && isAvailable;

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
      if (discountPrice != null && discountPrice! > 0 && discountPrice! < price) {
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
  String get ratingDisplay => rating > 0 ? '${rating.toStringAsFixed(1)} ★' : 'Henüz puan yok';

  // Yorumlar var mı?
  bool get hasReviews => totalReviews > 0;

  // Varyant gerektiriyor mu?
  bool get hasVariants => productType != 'normal';
  
  // Giyim ürünü mü?
  bool get isClothing => productType == 'clothing';
  
  // Ayakkabı mı?
  bool get isShoes => productType == 'shoes';

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
        shoeSizesList = (json['shoe_sizes'] as List).map((e) => int.tryParse(e.toString()) ?? 0).toList();
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
        additionalImagesList = (json['additional_images'] as List).map((e) => e.toString()).toList();
      }
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
    double? rating,
    int? totalReviews,
  }) {
    return Product(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      oldPrice: oldPrice ?? this.oldPrice,
      discountPrice: discountPrice ?? this.discountPrice,
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
      rating: rating ?? this.rating,
      totalReviews: totalReviews ?? this.totalReviews,
    );
  }
}
