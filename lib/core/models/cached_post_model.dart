import 'package:hive/hive.dart';
import 'post_model.dart';

part 'cached_post_model.g.dart';

@HiveType(typeId: 0)
class CachedPost extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String userId;

  @HiveField(2)
  final String? content;

  @HiveField(3)
  final List<String> images;

  @HiveField(4)
  final String? location;

  @HiveField(5)
  final int likesCount;

  @HiveField(6)
  final int commentsCount;

  @HiveField(7)
  final int sharesCount;

  @HiveField(8)
  final DateTime createdAt;

  @HiveField(9)
  final DateTime updatedAt;

  @HiveField(10)
  final DateTime cachedAt;

  @HiveField(11)
  final bool isActive;

  CachedPost({
    required this.id,
    required this.userId,
    this.content,
    required this.images,
    this.location,
    required this.likesCount,
    required this.commentsCount,
    required this.sharesCount,
    required this.createdAt,
    required this.updatedAt,
    required this.cachedAt,
    this.isActive = true,
  });

  factory CachedPost.fromPost(Post post) {
    return CachedPost(
      id: post.id,
      userId: post.userId,
      content: post.content,
      images: post.images,
      location: post.location,
      likesCount: post.likesCount,
      commentsCount: post.commentsCount,
      sharesCount: post.sharesCount,
      createdAt: post.createdAt,
      updatedAt: post.updatedAt,
      cachedAt: DateTime.now(),
      isActive: post.isActive,
    );
  }

  Post toPost() {
    return Post(
      id: id,
      userId: userId,
      content: content,
      images: images,
      location: location,
      likesCount: likesCount,
      commentsCount: commentsCount,
      sharesCount: sharesCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
      isActive: isActive,
    );
  }

  bool isExpired({Duration maxAge = const Duration(hours: 1)}) {
    return DateTime.now().difference(cachedAt) > maxAge;
  }
}
