import 'product_model.dart';
import 'post_model.dart' show Post;

/// Ürün favorisi modeli
class ProductFavorite {
  final String id;
  final String userId;
  final String productId;
  final DateTime createdAt;
  final Product? product; // Ürün bilgisi (join ile gelir)

  ProductFavorite({
    required this.id,
    required this.userId,
    required this.productId,
    required this.createdAt,
    this.product,
  });

  factory ProductFavorite.fromJson(Map<String, dynamic> json) {
    return ProductFavorite(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      productId: json['product_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      product: json['products'] != null
          ? Product.fromJson(json['products'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'product_id': productId,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// Gönderi favorisi modeli
class PostFavorite {
  final String id;
  final String userId;
  final String postId;
  final DateTime createdAt;
  final Post? post; // Gönderi bilgisi (join ile gelir)

  PostFavorite({
    required this.id,
    required this.userId,
    required this.postId,
    required this.createdAt,
    this.post,
  });

  factory PostFavorite.fromJson(Map<String, dynamic> json) {
    return PostFavorite(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      postId: json['post_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      post: json['posts'] != null
          ? Post.fromJson(json['posts'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'post_id': postId,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
