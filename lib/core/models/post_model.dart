// Yazar rolü enum'u (profiles.role ile uyumlu)
enum AuthorRole {
  customer,
  seller,
  admin,
  courier,
  driver,
  unknown;

  static AuthorRole fromString(String? value) {
    switch (value) {
      case 'customer':
        return AuthorRole.customer;
      case 'seller':
        return AuthorRole.seller;
      case 'admin':
        return AuthorRole.admin;
      case 'courier':
        return AuthorRole.courier;
      case 'driver':
        return AuthorRole.driver;
      default:
        return AuthorRole.unknown;
    }
  }

  /// UI'da gösterilecek etiket
  String get displayLabel {
    switch (this) {
      case AuthorRole.seller:
        return 'Satıcı';
      case AuthorRole.courier:
        return 'Kurye';
      case AuthorRole.driver:
        return 'Sürücü';
      case AuthorRole.admin:
        return 'Admin';
      case AuthorRole.customer:
        return 'Kullanıcı';
      case AuthorRole.unknown:
        return 'Bilinmeyen';
    }
  }

  /// Rozet rengini döndürür
  bool get isStaff =>
      this == AuthorRole.seller ||
      this == AuthorRole.courier ||
      this == AuthorRole.driver ||
      this == AuthorRole.admin;
}

/// Verilen değerler arasında null/boş (trim sonrası) olmayan ilk değeri döndürür.
/// Hepsi boşsa [fallback] döndürür. Yazar adı gösteriminde full_name eksikse
/// username'e, o da yoksa "Bilinmeyen Kullanıcı"ya düşmek için kullanılır.
/// Not: DB'de full_name NULL (ama username dolu) olan yazarların "Bilinmeyen
/// Kullanıcı" olarak görünmesini önler.
String firstNonEmpty(
  List<String?> values, {
  String fallback = 'Bilinmeyen Kullanıcı',
}) {
  for (final v in values) {
    if (v != null && v.trim().isNotEmpty) return v;
  }
  return fallback;
}

class Post {
  final String id;
  final String userId;
  final String? content;
  final List<String> images;
  // Legacy tek-görsel kolonu (DB: posts.image_url). Yeni gönderiler images[]
  // kullanır; bu alan yalnızca eski satırları temsil eder ve görselin
  // kaybolmaması için fromJson'de images'a katılır.
  final String? imageUrl;
  final String? location;
  final double? latitude;
  final double? longitude;
  final int likesCount;
  final int commentsCount;
  final int sharesCount;
  final bool isActive;
  final bool isPinned;
  final bool adminPinned; // Admin sabitledi (feed'de sabitlenmiş görünür)
  final DateTime createdAt;
  final DateTime updatedAt;

  // ✅ Yazar bilgileri (posts_with_profiles view'ından gelir)
  final String? authorUsername;
  final String? authorFullName;
  final String? authorAvatarUrl;
  final bool authorIsVerified;
  final AuthorRole authorRole;
  final bool authorProfileExists;

  Post({
    required this.id,
    required this.userId,
    this.content,
    this.images = const [],
    this.imageUrl,
    this.location,
    this.latitude,
    this.longitude,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.sharesCount = 0,
    this.isActive = true,
    this.isPinned = false,
    this.adminPinned = false,
    this.authorUsername,
    this.authorFullName,
    this.authorAvatarUrl,
    this.authorIsVerified = false,
    this.authorRole = AuthorRole.unknown,
    this.authorProfileExists = true,
    required this.createdAt,
    required this.updatedAt,
  });

  Post copyWith({
    String? id,
    String? userId,
    String? content,
    List<String>? images,
    String? imageUrl,
    String? location,
    double? latitude,
    double? longitude,
    int? likesCount,
    int? commentsCount,
    int? sharesCount,
    bool? isActive,
    bool? isPinned,
    bool? adminPinned,
    String? authorUsername,
    String? authorFullName,
    String? authorAvatarUrl,
    bool? authorIsVerified,
    AuthorRole? authorRole,
    bool? authorProfileExists,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Post(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      content: content ?? this.content,
      images: images ?? this.images,
      imageUrl: imageUrl ?? this.imageUrl,
      location: location ?? this.location,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      sharesCount: sharesCount ?? this.sharesCount,
      isActive: isActive ?? this.isActive,
      isPinned: isPinned ?? this.isPinned,
      adminPinned: adminPinned ?? this.adminPinned,
      authorUsername: authorUsername ?? this.authorUsername,
      authorFullName: authorFullName ?? this.authorFullName,
      authorAvatarUrl: authorAvatarUrl ?? this.authorAvatarUrl,
      authorIsVerified: authorIsVerified ?? this.authorIsVerified,
      authorRole: authorRole ?? this.authorRole,
      authorProfileExists: authorProfileExists ?? this.authorProfileExists,
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
      if (imageUrl != null) 'image_url': imageUrl,
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'likes_count': likesCount,
      'comments_count': commentsCount,
      'shares_count': sharesCount,
      'is_active': isActive,
      'is_pinned': isPinned,
      'admin_pinned': adminPinned,
      // Yazar bilgileri (view'dan okunduğunda cache için serialize edilir)
      if (authorUsername != null) 'author_username': authorUsername,
      if (authorFullName != null) 'author_full_name': authorFullName,
      if (authorAvatarUrl != null) 'author_avatar_url': authorAvatarUrl,
      'author_is_verified': authorIsVerified,
      'author_role': authorRole.name,
      'author_profile_exists': authorProfileExists,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// ✅ posts_with_profiles view'ından GELEN JSON'u parse eder.
  /// Hem view'dan (username, full_name, avatar_url, role, is_verified düz alanlar)
  /// hem de düz posts tablosundan (yazar alanları null) çalışır.
  /// Geriye dönük uyumluluk: author_username/author_full_name/author_avatar_url
  /// de okunur (cache restore senaryoları için).
  factory Post.fromJson(Map<String, dynamic> json) {
    // View'dan gelen düz alanlar: username, full_name, avatar_url, role, is_verified
    // Veya cache'den gelen: author_username, author_full_name, ...
    final username = json['author_username'] as String? ??
        json['username'] as String?;
    final fullName = json['author_full_name'] as String? ??
        json['full_name'] as String?;
    final avatarUrl = json['author_avatar_url'] as String? ??
        json['avatar_url'] as String?;
    final isVerified = json['author_is_verified'] as bool? ??
        json['is_verified'] as bool? ??
        false;
    final role = AuthorRole.fromString(
      json['author_role'] as String? ?? json['role'] as String?,
    );
    final profileExists = json['author_profile_exists'] as bool? ?? true;

    // Görseller: ana kolon images[] (text[]). image_url legacy tek-görsel
    // kolonudur; images boş ama image_url varsa onu gösterim için images'a
    // katlıyoruz ki eski gönderilerdeki görsel kaybolmasın.
    final imageUrl = json['image_url'] as String?;
    var images = (json['images'] as List<dynamic>?)?.cast<String>() ?? <String>[];
    if (images.isEmpty && imageUrl != null && imageUrl.isNotEmpty) {
      images = [imageUrl];
    }

    return Post(
      id: json['id'] as String,
      // Şema: user_id NULL olabilir (orphan post). Null gelirse feed çökmesin
      // diye boş string'e düşürürüz; UI "Bilinmeyen Kullanıcı" fallback'i ile
      // başa çıkar (author_profile_exists=false).
      userId: json['user_id'] as String? ?? '',
      content: json['content'] as String?,
      images: images,
      imageUrl: imageUrl,
      location: json['location'] as String?,
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
      likesCount: json['likes_count'] as int? ?? 0,
      commentsCount: json['comments_count'] as int? ?? 0,
      sharesCount: json['shares_count'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      isPinned: json['is_pinned'] as bool? ?? false,
      adminPinned: json['admin_pinned'] as bool? ?? false,
      authorUsername: username,
      authorFullName: fullName,
      authorAvatarUrl: avatarUrl,
      authorIsVerified: isVerified,
      authorRole: role,
      authorProfileExists: profileExists,
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

  // Yazar bilgileri — yorumlar profiles ile JOIN'lenerek tek sorguda gelir.
  // Eskiden her yorum için ayrı profil sorgusu atılıyordu (N+1); 20 yorumlu
  // bir gönderide 20 ek istek anlamına geliyordu.
  final String? authorUsername;
  final String? authorFullName;
  final String? authorAvatarUrl;

  PostComment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.authorUsername,
    this.authorFullName,
    this.authorAvatarUrl,
  });

  /// Gösterilecek ad: tam ad > kullanıcı adı > jenerik.
  String get displayName {
    final full = authorFullName?.trim();
    if (full != null && full.isNotEmpty) return full;
    final uname = authorUsername?.trim();
    if (uname != null && uname.isNotEmpty) return uname;
    return 'Kullanıcı';
  }

  /// @handle için kullanıcı adı (yoksa jenerik).
  String get displayUsername {
    final uname = authorUsername?.trim();
    return (uname != null && uname.isNotEmpty) ? uname : 'kullanici';
  }

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
    // PostgREST embed'i: profiles!post_comments_user_id_fkey(...)
    final profile = json['profiles'];
    final profileMap = profile is Map ? profile : const {};

    return PostComment(
      id: json['id'] as String,
      postId: json['post_id'] as String,
      userId: json['user_id'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(
        (json['updated_at'] ?? json['created_at']) as String,
      ),
      authorUsername:
          (json['author_username'] ?? profileMap['username']) as String?,
      authorFullName:
          (json['author_full_name'] ?? profileMap['full_name']) as String?,
      authorAvatarUrl:
          (json['author_avatar_url'] ?? profileMap['avatar_url']) as String?,
    );
  }
}

/// copyWith'te "parametre verilmedi" ile "null verildi"yi ayirt eden sentinel.
const Object _unset = Object();

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
  /// Kullanıcının bu hikayeye verdiği tepki emojisi (yoksa null).
  /// Klasik beğeni ❤️ olarak saklanır.
  final String? myReaction;
  final bool isPinned;
  final bool adminPinned; // Admin sabitledi (feed'de sabitlenmiş görünür)
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
    this.myReaction,
    this.isPinned = false,
    this.adminPinned = false,
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
    // Tepki KALDIRILDIĞINDA null'a çekilebilmesi için sentinel kullanılıyor:
    // normal `String? myReaction` ile null geçmek "değiştirme" anlamına gelir.
    Object? myReaction = _unset,
    bool? isPinned,
    bool? adminPinned,
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
      myReaction: identical(myReaction, _unset)
          ? this.myReaction
          : myReaction as String?,
      isPinned: isPinned ?? this.isPinned,
      adminPinned: adminPinned ?? this.adminPinned,
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
      myReaction: json['my_reaction'] as String?,
      isPinned: json['is_pinned'] as bool? ?? false,
      adminPinned: json['admin_pinned'] as bool? ?? false,
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
