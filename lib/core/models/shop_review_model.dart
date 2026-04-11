class ShopReview {
  final String id;
  final String shopId;
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

  ShopReview({
    required this.id,
    required this.shopId,
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
  });

  factory ShopReview.fromJson(Map<String, dynamic> json) {
    return ShopReview(
      id: json['id'] as String,
      shopId: json['shop_id'] as String,
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shop_id': shopId,
      'user_id': userId,
      'rating': rating,
      'comment': comment,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'seller_reply': sellerReply,
      'seller_replied_at': sellerRepliedAt?.toIso8601String(),
      'order_id': orderId,
    };
  }
  
  // Satıcı cevabı var mı?
  bool get hasSellerReply => sellerReply != null && sellerReply!.isNotEmpty;
}
