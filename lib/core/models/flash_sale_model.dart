// Flash Satış modeli - sınırlı süre + sınırlı stok kampanyaları
class FlashSale {
  final String id;
  final String productId;
  final String shopId;
  final double originalPrice;
  final double flashPrice;
  final int stockLimit;
  final int soldCount;
  final DateTime startAt;
  final DateTime endAt;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Join ile gelen opsiyonel alanlar
  final String? productName;
  final String? productImageUrl;
  final String? shopName;

  FlashSale({
    required this.id,
    required this.productId,
    required this.shopId,
    required this.originalPrice,
    required this.flashPrice,
    required this.stockLimit,
    required this.soldCount,
    required this.startAt,
    required this.endAt,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.productName,
    this.productImageUrl,
    this.shopName,
  });

  factory FlashSale.fromJson(Map<String, dynamic> json) {
    final productJson = json['products'] as Map<String, dynamic>?;
    final shopJson = json['shops'] as Map<String, dynamic>?;
    return FlashSale(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      shopId: json['shop_id'] as String,
      originalPrice: (json['original_price'] as num).toDouble(),
      flashPrice: (json['flash_price'] as num).toDouble(),
      stockLimit: (json['stock_limit'] as num).toInt(),
      soldCount: (json['sold_count'] as num? ?? 0).toInt(),
      startAt: DateTime.parse(json['start_at'] as String),
      endAt: DateTime.parse(json['end_at'] as String),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      productName: productJson?['name'] as String?,
      productImageUrl: productJson?['image_url'] as String?,
      shopName: shopJson?['name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'shop_id': shopId,
      'original_price': originalPrice,
      'flash_price': flashPrice,
      'stock_limit': stockLimit,
      'sold_count': soldCount,
      'start_at': startAt.toIso8601String(),
      'end_at': endAt.toIso8601String(),
      'is_active': isActive,
    };
  }

  // --- Türev property'ler ---

  double get discountPercent =>
      originalPrice > 0
          ? ((originalPrice - flashPrice) / originalPrice) * 100
          : 0;

  int get remainingStock => (stockLimit - soldCount).clamp(0, stockLimit);

  double get soldPercent =>
      stockLimit > 0 ? (soldCount / stockLimit) * 100 : 0;

  bool get hasStarted => DateTime.now().isAfter(startAt);
  bool get hasEnded => DateTime.now().isAfter(endAt);
  bool get isOngoing => hasStarted && !hasEnded;
  bool get isSoldOut => remainingStock <= 0;

  Duration get remainingDuration {
    final now = DateTime.now();
    if (now.isAfter(endAt)) return Duration.zero;
    return endAt.difference(now);
  }

  FlashSale copyWith({
    String? id,
    String? productId,
    String? shopId,
    double? originalPrice,
    double? flashPrice,
    int? stockLimit,
    int? soldCount,
    DateTime? startAt,
    DateTime? endAt,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? productName,
    String? productImageUrl,
    String? shopName,
  }) {
    return FlashSale(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      shopId: shopId ?? this.shopId,
      originalPrice: originalPrice ?? this.originalPrice,
      flashPrice: flashPrice ?? this.flashPrice,
      stockLimit: stockLimit ?? this.stockLimit,
      soldCount: soldCount ?? this.soldCount,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      productName: productName ?? this.productName,
      productImageUrl: productImageUrl ?? this.productImageUrl,
      shopName: shopName ?? this.shopName,
    );
  }
}