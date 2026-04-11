class Post {
  final String id;
  final String userId;
  final String? content;
  final List<String> images;
  final String? location;
  final double? latitude;
  final double? longitude;
  final int likesCount;
  final int commentsCount;
  final int sharesCount;
  final bool isActive;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime updatedAt;

  Post({
    required this.id,
    required this.userId,
    this.content,
    this.images = const [],
    this.location,
    this.latitude,
    this.longitude,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.sharesCount = 0,
    this.isActive = true,
    this.isPinned = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Post copyWith({
    String? id,
    String? userId,
    String? content,
    List<String>? images,
    String? location,
    double? latitude,
    double? longitude,
    int? likesCount,
    int? commentsCount,
    int? sharesCount,
    bool? isActive,
    bool? isPinned,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Post(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      content: content ?? this.content,
      images: images ?? this.images,
      location: location ?? this.location,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      sharesCount: sharesCount ?? this.sharesCount,
      isActive: isActive ?? this.isActive,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'content': content,
      'images': images,
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'likes_count': likesCount,
      'comments_count': commentsCount,
      'shares_count': sharesCount,
      'is_active': isActive,
      'is_pinned': isPinned,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      content: json['content'] as String?,
      images: (json['images'] as List<dynamic>?)?.cast<String>() ?? [],
      location: json['location'] as String?,
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
      likesCount: json['likes_count'] as int? ?? 0,
      commentsCount: json['comments_count'] as int? ?? 0,
      sharesCount: json['shares_count'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      isPinned: json['is_pinned'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class PostComment {
  final String id;
  final String postId;
  final String userId;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  PostComment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'post_id': postId,
      'user_id': userId,
      'content': content,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory PostComment.fromJson(Map<String, dynamic> json) {
    return PostComment(
      id: json['id'] as String,
      postId: json['post_id'] as String,
      userId: json['user_id'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class Story {
  final String id;
  final String userId;
  final String imageUrl;
  final String? thumbnailUrl; // Video thumbnail URL (isteğe bağlı)
  final String mediaType; // 'image' or 'video'
  final int viewsCount;
  final int likesCount;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool isViewedByCurrentUser; // Kullanıcı bu story'yi gördü mü?
  final bool isLikedByCurrentUser; // Kullanıcı bu story'yi beğendi mi?
  final bool isPinned;
  // Profil bilgileri - StoryService tarafından doldurulur
  final String? username;
  final String? fullName;
  final String? avatarUrl;

  Story({
    required this.id,
    required this.userId,
    required this.imageUrl,
    this.thumbnailUrl,
    this.mediaType = 'image',
    this.viewsCount = 0,
    this.likesCount = 0,
    required this.createdAt,
    required this.expiresAt,
    this.isViewedByCurrentUser = false,
    this.isLikedByCurrentUser = false,
    this.isPinned = false,
    this.username,
    this.fullName,
    this.avatarUrl,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isVideo => mediaType == 'video';
  bool get isImage => mediaType == 'image';
  
  // Video için thumbnail URL, yoksa video URL
  String get displayUrl => isVideo && thumbnailUrl != null ? thumbnailUrl! : imageUrl;

  Story copyWith({
    String? id,
    String? userId,
    String? imageUrl,
    String? thumbnailUrl,
    String? mediaType,
    int? viewsCount,
    int? likesCount,
    DateTime? createdAt,
    DateTime? expiresAt,
    bool? isViewedByCurrentUser,
    bool? isLikedByCurrentUser,
    bool? isPinned,
    String? username,
    String? fullName,
    String? avatarUrl,
  }) {
    return Story(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      imageUrl: imageUrl ?? this.imageUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      mediaType: mediaType ?? this.mediaType,
      viewsCount: viewsCount ?? this.viewsCount,
      likesCount: likesCount ?? this.likesCount,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      isViewedByCurrentUser: isViewedByCurrentUser ?? this.isViewedByCurrentUser,
      isLikedByCurrentUser: isLikedByCurrentUser ?? this.isLikedByCurrentUser,
      isPinned: isPinned ?? this.isPinned,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'image_url': imageUrl,
      if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      'media_type': mediaType,
      'views_count': viewsCount,
      'likes_count': likesCount,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      if (username != null) 'username': username,
      if (fullName != null) 'full_name': fullName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      'is_pinned': isPinned,
    };
  }

  factory Story.fromJson(Map<String, dynamic> json) {
    return Story(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      imageUrl: json['image_url'] as String,
      thumbnailUrl: json['thumbnail_url'] as String?,
      mediaType: json['media_type'] as String? ?? 'image',
      viewsCount: json['views_count'] as int? ?? 0,
      likesCount: json['likes_count'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      isViewedByCurrentUser: json['is_viewed_by_current_user'] as bool? ?? false,
      isLikedByCurrentUser: json['is_liked_by_current_user'] as bool? ?? false,
      isPinned: json['is_pinned'] as bool? ?? false,
      // Profil bilgileri - varsa al
      username: json['username'] as String?,
      fullName: json['full_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}

class StoryView {
  final String id;
  final String storyId;
  final String viewerId;
  final DateTime createdAt;

  StoryView({
    required this.id,
    required this.storyId,
    required this.viewerId,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'story_id': storyId,
      'viewer_id': viewerId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory StoryView.fromJson(Map<String, dynamic> json) {
    return StoryView(
      id: json['id'] as String,
      storyId: json['story_id'] as String,
      viewerId: json['viewer_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
