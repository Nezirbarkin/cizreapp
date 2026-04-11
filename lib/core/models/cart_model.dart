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
  final String? productImageUrl;
  final String? shopId;
  final String? shopName;
  final bool? isAvailable;
  final int? stockQuantity;

  // Varyant bilgileri (renk, beden, numara)
  final Map<String, dynamic>? variantData;

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
    this.productImageUrl,
    this.shopId,
    this.shopName,
    this.isAvailable,
    this.stockQuantity,
    this.variantData,
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
      productImageUrl: json['product_image_url'] as String?,
      shopId: json['shop_id'] as String?,
      shopName: json['shop_name'] as String?,
      isAvailable: json['is_available'] as bool?,
      stockQuantity: json['stock_quantity'] as int?,
      variantData: json['variant_data'] as Map<String, dynamic>?,
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

  // Getters
  double get itemTotal {
    return (productPrice ?? 0) * quantity;
  }

  double get itemDiscount {
    if (productOldPrice != null && productPrice != null) {
      return (productOldPrice! - productPrice!) * quantity;
    }
    return 0;
  }

  bool get hasDiscount {
    return productOldPrice != null && productOldPrice! > (productPrice ?? 0);
  }

  int get discountPercentage {
    if (hasDiscount && productOldPrice != null && productPrice != null) {
      return (((productOldPrice! - productPrice!) / productOldPrice!) * 100).round();
    }
    return 0;
  }

  bool get canAddMore {
    return stockQuantity == null || quantity < stockQuantity!;
  }

  bool get isInStock {
    return (isAvailable ?? false) && (stockQuantity == null || stockQuantity! > 0);
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
    String? productImageUrl,
    String? shopId,
    String? shopName,
    bool? isAvailable,
    int? stockQuantity,
    Map<String, dynamic>? variantData,
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
      productImageUrl: productImageUrl ?? this.productImageUrl,
      shopId: shopId ?? this.shopId,
      shopName: shopName ?? this.shopName,
      isAvailable: isAvailable ?? this.isAvailable,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      variantData: variantData ?? this.variantData,
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

  CartSummary({
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.deliveryFee,
    required this.total,
    required this.totalItems,
  });

  factory CartSummary.fromItems(List<CartItem> items, {double deliveryFee = 0}) {
    final subtotal = items.fold<double>(
      0,
      (sum, item) => sum + item.itemTotal,
    );

    final discount = items.fold<double>(
      0,
      (sum, item) => sum + item.itemDiscount,
    );

    final totalItems = items.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );

    final total = subtotal + deliveryFee;

    return CartSummary(
      items: items,
      subtotal: subtotal,
      discount: discount,
      deliveryFee: deliveryFee,
      total: total,
      totalItems: totalItems,
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
