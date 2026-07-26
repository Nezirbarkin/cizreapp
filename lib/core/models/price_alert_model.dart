// Fiyat Düşüş Alarmı modeli - favori üründe hedef fiyata düşünce bildirim
class PriceAlert {
  final String id;
  final String userId;
  final String productId;
  final double targetPrice;
  final double currentPriceAtCreation;
  final bool isActive;
  final DateTime? triggeredAt;
  final DateTime createdAt;

  // Join ile gelen opsiyonel alanlar
  final String? productName;
  final String? productImageUrl;
  final double? productCurrentPrice;

  PriceAlert({
    required this.id,
    required this.userId,
    required this.productId,
    required this.targetPrice,
    required this.currentPriceAtCreation,
    required this.isActive,
    this.triggeredAt,
    required this.createdAt,
    this.productName,
    this.productImageUrl,
    this.productCurrentPrice,
  });

  factory PriceAlert.fromJson(Map<String, dynamic> json) {
    final productJson = json['products'] as Map<String, dynamic>?;
    double? currentPrice;
    if (productJson != null) {
      final discount = productJson['discount_price'] as num?;
      final price = productJson['price'] as num?;
      currentPrice = (discount ?? price)?.toDouble();
    }
    return PriceAlert(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      productId: json['product_id'] as String,
      targetPrice: (json['target_price'] as num).toDouble(),
      currentPriceAtCreation: (json['current_price_at_creation'] as num).toDouble(),
      isActive: json['is_active'] as bool? ?? true,
      triggeredAt: json['triggered_at'] != null
          ? DateTime.parse(json['triggered_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      productName: productJson?['name'] as String?,
      productImageUrl: productJson?['image_url'] as String?,
      productCurrentPrice: currentPrice,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'product_id': productId,
      'target_price': targetPrice,
      'current_price_at_creation': currentPriceAtCreation,
      'is_active': isActive,
      'triggered_at': triggeredAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  bool get isTriggered => triggeredAt != null;

  PriceAlert copyWith({
    String? id,
    String? userId,
    String? productId,
    double? targetPrice,
    double? currentPriceAtCreation,
    bool? isActive,
    DateTime? triggeredAt,
    DateTime? createdAt,
    String? productName,
    String? productImageUrl,
    double? productCurrentPrice,
  }) {
    return PriceAlert(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      productId: productId ?? this.productId,
      targetPrice: targetPrice ?? this.targetPrice,
      currentPriceAtCreation: currentPriceAtCreation ?? this.currentPriceAtCreation,
      isActive: isActive ?? this.isActive,
      triggeredAt: triggeredAt ?? this.triggeredAt,
      createdAt: createdAt ?? this.createdAt,
      productName: productName ?? this.productName,
      productImageUrl: productImageUrl ?? this.productImageUrl,
      productCurrentPrice: productCurrentPrice ?? this.productCurrentPrice,
    );
  }
}