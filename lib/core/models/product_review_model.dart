class ProductReview {
  final String id;
  final String productId;
  final String userId;
  final int rating;
  final String? comment;
  final DateTime createdAt;
  final DateTime updatedAt;

  // User bilgisi (join için)
  final String? userName;
  final String? userAvatar;

  // Satıcı cevabı alanları
  final String? sellerReply;
  final DateTime? sellerRepliedAt;

  // Sipariş ilişkisi
  final String? orderId;

  // Onay durumu (admin/mod onayı)
  final bool isApproved;

  // Faydalı oy sayısı
  final int helpfulCount;
  final bool? isHelpful; // Mevcut kullanıcı oyu verdi mi?

  ProductReview({
    required this.id,
    required this.productId,
    required this.userId,
    required this.rating,
    this.comment,
    required this.createdAt,
    required this.updatedAt,
    this.userName,
    this.userAvatar,
    this.sellerReply,
    this.sellerRepliedAt,
    this.orderId,
    this.isApproved = true,
    this.helpfulCount = 0,
    this.isHelpful,
  });

  factory ProductReview.fromJson(Map<String, dynamic> json) {
    return ProductReview(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      userId: json['user_id'] as String,
      rating: json['rating'] as int,
      comment: json['comment'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      userName: json['user_name'] as String?,
      userAvatar: json['user_avatar'] as String?,
      sellerReply: json['seller_reply'] as String?,
      sellerRepliedAt: json['seller_replied_at'] != null
          ? DateTime.parse(json['seller_replied_at'] as String)
          : null,
      orderId: json['order_id'] as String?,
      isApproved: json['is_approved'] as bool? ?? true,
      helpfulCount: json['helpful_count'] as int? ?? 0,
      isHelpful: json['is_helpful'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'user_id': userId,
      'rating': rating,
      'comment': comment,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'seller_reply': sellerReply,
      'seller_replied_at': sellerRepliedAt?.toIso8601String(),
      'order_id': orderId,
      'is_approved': isApproved,
      'helpful_count': helpfulCount,
    };
  }

  // Satıcı cevabı var mı?
  bool get hasSellerReply => sellerReply != null && sellerReply!.isNotEmpty;

  // Yorum onaylı mı?
  bool get isVisible => isApproved;

  // Yıldız gösterimi (★)
  String get starDisplay {
    return '★' * rating + '☆' * (5 - rating);
  }

  ProductReview copyWith({
    String? id,
    String? productId,
    String? userId,
    int? rating,
    String? comment,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? userName,
    String? userAvatar,
    String? sellerReply,
    DateTime? sellerRepliedAt,
    String? orderId,
    bool? isApproved,
    int? helpfulCount,
    bool? isHelpful,
  }) {
    return ProductReview(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      userId: userId ?? this.userId,
      rating: rating ?? this.rating,
      comment: comment ?? this.comment,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      userName: userName ?? this.userName,
      userAvatar: userAvatar ?? this.userAvatar,
      sellerReply: sellerReply ?? this.sellerReply,
      sellerRepliedAt: sellerRepliedAt ?? this.sellerRepliedAt,
      orderId: orderId ?? this.orderId,
      isApproved: isApproved ?? this.isApproved,
      helpfulCount: helpfulCount ?? this.helpfulCount,
      isHelpful: isHelpful ?? this.isHelpful,
    );
  }
}
