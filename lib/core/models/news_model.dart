import 'dart:ui';

/// Haber modeli
class NewsModel {
  final String id;
  final String title;
  final String slug;
  final String content;
  final String? summary;
  final String? thumbnailUrl;
  final String? videoUrl;
  final String? categoryId;
  final String? categoryName;
  final String? institutionId;
  final String? institutionName;
  final String? institutionLogoUrl;
  final String? authorId;
  final String? authorName;
  final String? authorAvatarUrl;
  final bool isFeatured;
  final bool isPublished;
  final bool isBreaking;
  final int viewCount;
  final int likeCount;
  final int commentCount;
  final int shareCount;
  final String? locationName;
  final double? latitude;
  final double? longitude;
  final DateTime? publishedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<NewsImageModel> images;
  final bool? isLikedByUser;

  NewsModel({
    required this.id,
    required this.title,
    required this.slug,
    required this.content,
    this.summary,
    this.thumbnailUrl,
    this.videoUrl,
    this.categoryId,
    this.categoryName,
    this.institutionId,
    this.institutionName,
    this.institutionLogoUrl,
    this.authorId,
    this.authorName,
    this.authorAvatarUrl,
    this.isFeatured = false,
    this.isPublished = false,
    this.isBreaking = false,
    this.viewCount = 0,
    this.likeCount = 0,
    this.commentCount = 0,
    this.shareCount = 0,
    this.locationName,
    this.latitude,
    this.longitude,
    this.publishedAt,
    required this.createdAt,
    required this.updatedAt,
    this.images = const [],
    this.isLikedByUser,
  });

  factory NewsModel.fromJson(Map<String, dynamic> json) {
    return NewsModel(
      id: json['id'] as String,
      title: json['title'] as String,
      slug: json['slug'] as String,
      content: json['content'] as String,
      summary: json['summary'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
      videoUrl: json['video_url'] as String?,
      categoryId: json['category_id'] as String?,
      categoryName:
          (json['news_categories']?['name'] ?? json['category_name'])
              as String?,
      institutionId: json['institution_id'] as String?,
      institutionName:
          (json['institutions']?['name'] ?? json['institution_name'])
              as String?,
      institutionLogoUrl: json['institutions']?['logo_url'] as String?,
      authorId: json['author_id'] as String?,
      authorName: json['author_name'] as String?,
      authorAvatarUrl: json['author_avatar_url'] as String?,
      isFeatured: json['is_featured'] as bool? ?? false,
      isPublished: json['is_published'] as bool? ?? false,
      isBreaking: json['is_breaking'] as bool? ?? false,
      viewCount: json['view_count'] as int? ?? 0,
      likeCount: json['like_count'] as int? ?? 0,
      commentCount: json['comment_count'] as int? ?? 0,
      shareCount: json['share_count'] as int? ?? 0,
      locationName: json['location_name'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      publishedAt: json['published_at'] != null
          ? DateTime.parse(json['published_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      images: json['news_images'] != null
          ? (json['news_images'] as List)
                .map((e) => NewsImageModel.fromJson(e as Map<String, dynamic>))
                .toList()
          : [],
      isLikedByUser: json['is_liked_by_user'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'slug': slug,
      'content': content,
      'summary': summary,
      'thumbnail_url': thumbnailUrl,
      'video_url': videoUrl,
      'category_id': categoryId,
      'institution_id': institutionId,
      'author_id': authorId,
      'author_name': authorName,
      'author_avatar_url': authorAvatarUrl,
      'is_featured': isFeatured,
      'is_published': isPublished,
      'is_breaking': isBreaking,
      'location_name': locationName,
      'latitude': latitude,
      'longitude': longitude,
      'published_at': publishedAt?.toIso8601String(),
    };
  }

  NewsModel copyWith({
    String? id,
    String? title,
    String? slug,
    String? content,
    String? summary,
    String? thumbnailUrl,
    String? videoUrl,
    String? categoryId,
    String? categoryName,
    String? institutionId,
    String? institutionName,
    String? institutionLogoUrl,
    String? authorId,
    String? authorName,
    String? authorAvatarUrl,
    bool? isFeatured,
    bool? isPublished,
    bool? isBreaking,
    int? viewCount,
    int? likeCount,
    int? commentCount,
    int? shareCount,
    String? locationName,
    double? latitude,
    double? longitude,
    DateTime? publishedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<NewsImageModel>? images,
    bool? isLikedByUser,
  }) {
    return NewsModel(
      id: id ?? this.id,
      title: title ?? this.title,
      slug: slug ?? this.slug,
      content: content ?? this.content,
      summary: summary ?? this.summary,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      videoUrl: videoUrl ?? this.videoUrl,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      institutionId: institutionId ?? this.institutionId,
      institutionName: institutionName ?? this.institutionName,
      institutionLogoUrl: institutionLogoUrl ?? this.institutionLogoUrl,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      authorAvatarUrl: authorAvatarUrl ?? this.authorAvatarUrl,
      isFeatured: isFeatured ?? this.isFeatured,
      isPublished: isPublished ?? this.isPublished,
      isBreaking: isBreaking ?? this.isBreaking,
      viewCount: viewCount ?? this.viewCount,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      shareCount: shareCount ?? this.shareCount,
      locationName: locationName ?? this.locationName,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      publishedAt: publishedAt ?? this.publishedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      images: images ?? this.images,
      isLikedByUser: isLikedByUser ?? this.isLikedByUser,
    );
  }

  String get formattedDate {
    final now = DateTime.now();
    final diff = now.difference(createdAt);

    if (diff.inMinutes < 1) return 'Az önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} saat önce';
    if (diff.inDays < 7) return '${diff.inDays} gün önce';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} hafta önce';

    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }

  String get publishedFormattedDate {
    if (publishedAt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(publishedAt!);

    if (diff.inMinutes < 1) return 'Az önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} saat önce';
    if (diff.inDays < 7) return '${diff.inDays} gün önce';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} hafta önce';

    return '${publishedAt!.day}/${publishedAt!.month}/${publishedAt!.year}';
  }
}

/// Haber görsel modeli
class NewsImageModel {
  final String id;
  final String newsId;
  final String imageUrl;
  final String? thumbnailUrl;
  final String? caption;
  final int sortOrder;
  final int? width;
  final int? height;
  final int? fileSize;
  final DateTime createdAt;

  NewsImageModel({
    required this.id,
    required this.newsId,
    required this.imageUrl,
    this.thumbnailUrl,
    this.caption,
    this.sortOrder = 0,
    this.width,
    this.height,
    this.fileSize,
    required this.createdAt,
  });

  factory NewsImageModel.fromJson(Map<String, dynamic> json) {
    return NewsImageModel(
      id: json['id'] as String,
      newsId: json['news_id'] as String,
      imageUrl: json['image_url'] as String,
      thumbnailUrl: json['thumbnail_url'] as String?,
      caption: json['caption'] as String?,
      sortOrder: json['sort_order'] as int? ?? 0,
      width: json['width'] as int?,
      height: json['height'] as int?,
      fileSize: json['file_size'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'news_id': newsId,
      'image_url': imageUrl,
      'thumbnail_url': thumbnailUrl,
      'caption': caption,
      'sort_order': sortOrder,
    };
  }
}

/// Haber yorum modeli
class NewsCommentModel {
  final String id;
  final String newsId;
  final String? parentId;
  final String? userId;
  final String userName;
  final String? userAvatarUrl;
  final String content;
  final bool isEdited;
  final int likeCount;
  final int reportCount;
  final bool isHidden;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<NewsCommentModel> replies;
  final bool? isLikedByUser;

  NewsCommentModel({
    required this.id,
    required this.newsId,
    this.parentId,
    this.userId,
    required this.userName,
    this.userAvatarUrl,
    required this.content,
    this.isEdited = false,
    this.likeCount = 0,
    this.reportCount = 0,
    this.isHidden = false,
    this.isPinned = false,
    required this.createdAt,
    required this.updatedAt,
    this.replies = const [],
    this.isLikedByUser,
  });

  factory NewsCommentModel.fromJson(Map<String, dynamic> json) {
    return NewsCommentModel(
      id: json['id'] as String,
      newsId: json['news_id'] as String,
      parentId: json['parent_id'] as String?,
      userId: json['user_id'] as String?,
      userName: json['user_name'] as String,
      userAvatarUrl: json['user_avatar_url'] as String?,
      content: json['content'] as String,
      isEdited: json['is_edited'] as bool? ?? false,
      likeCount: json['like_count'] as int? ?? 0,
      reportCount: json['report_count'] as int? ?? 0,
      isHidden: json['is_hidden'] as bool? ?? false,
      isPinned: json['is_pinned'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      replies: json['replies'] != null
          ? (json['replies'] as List)
                .map(
                  (e) => NewsCommentModel.fromJson(e as Map<String, dynamic>),
                )
                .toList()
          : [],
      isLikedByUser: json['is_liked_by_user'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'news_id': newsId,
      'parent_id': parentId,
      'user_id': userId,
      'user_name': userName,
      'user_avatar_url': userAvatarUrl,
      'content': content,
    };
  }

  String get formattedDate {
    final now = DateTime.now();
    final diff = now.difference(createdAt);

    if (diff.inMinutes < 1) return 'Az önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk';
    if (diff.inHours < 24) return '${diff.inHours} s';
    if (diff.inDays < 7) return '${diff.inDays} g';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} h';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} a';

    return '${(diff.inDays / 365).floor()} y';
  }

  NewsCommentModel copyWith({
    String? id,
    String? newsId,
    String? parentId,
    String? userId,
    String? userName,
    String? userAvatarUrl,
    String? content,
    bool? isEdited,
    int? likeCount,
    int? reportCount,
    bool? isHidden,
    bool? isPinned,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<NewsCommentModel>? replies,
    bool? isLikedByUser,
  }) {
    return NewsCommentModel(
      id: id ?? this.id,
      newsId: newsId ?? this.newsId,
      parentId: parentId ?? this.parentId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userAvatarUrl: userAvatarUrl ?? this.userAvatarUrl,
      content: content ?? this.content,
      isEdited: isEdited ?? this.isEdited,
      likeCount: likeCount ?? this.likeCount,
      reportCount: reportCount ?? this.reportCount,
      isHidden: isHidden ?? this.isHidden,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      replies: replies ?? this.replies,
      isLikedByUser: isLikedByUser ?? this.isLikedByUser,
    );
  }
}

/// Haber kategorisi modeli
class NewsCategoryModel {
  final String id;
  final String name;
  final String slug;
  final String? description;
  final String? icon;
  final String? color;
  final int sortOrder;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  NewsCategoryModel({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.icon,
    this.color,
    this.sortOrder = 0,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory NewsCategoryModel.fromJson(Map<String, dynamic> json) {
    return NewsCategoryModel(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      description: json['description'] as String?,
      icon: json['icon'] as String?,
      color: json['color'] as String?,
      sortOrder: json['sort_order'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Color? get colorValue {
    if (color == null) return null;
    try {
      final hex = color!.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return null;
    }
  }
}

/// Kurum modeli
class InstitutionModel {
  final String id;
  final String name;
  final String slug;
  final String? logoUrl;
  final String? description;
  final Map<String, dynamic>? contactInfo;
  final String? website;
  final String? phone;
  final String? address;
  final bool isVerified;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  InstitutionModel({
    required this.id,
    required this.name,
    required this.slug,
    this.logoUrl,
    this.description,
    this.contactInfo,
    this.website,
    this.phone,
    this.address,
    this.isVerified = false,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory InstitutionModel.fromJson(Map<String, dynamic> json) {
    return InstitutionModel(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      logoUrl: json['logo_url'] as String?,
      description: json['description'] as String?,
      contactInfo: json['contact_info'] as Map<String, dynamic>?,
      website: json['website'] as String?,
      phone: json['phone'] as String?,
      address: json['address'] as String?,
      isVerified: json['is_verified'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
