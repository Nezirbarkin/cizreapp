// Canlı Yayın oturum modeli (Agora kanalı + Supabase metadata)
class LiveSession {
  final String id;
  final String hostUserId;
  final String shopId;
  final String title;
  final String? description;
  final String? coverImageUrl;
  final String channelName;
  final String status; // 'scheduled' | 'live' | 'ended'
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int peakViewerCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Join ile gelen alanlar
  final String? shopName;
  final String? hostUserName;
  final String? hostAvatarUrl;
  final String? pinnedProductName;
  final String? pinnedProductImageUrl;
  final double? pinnedProductPrice;
  final String? pinnedProductId;

  LiveSession({
    required this.id,
    required this.hostUserId,
    required this.shopId,
    required this.title,
    this.description,
    this.coverImageUrl,
    required this.channelName,
    required this.status,
    this.startedAt,
    this.endedAt,
    required this.peakViewerCount,
    required this.createdAt,
    required this.updatedAt,
    this.shopName,
    this.hostUserName,
    this.hostAvatarUrl,
    this.pinnedProductName,
    this.pinnedProductImageUrl,
    this.pinnedProductPrice,
    this.pinnedProductId,
  });

  factory LiveSession.fromJson(Map<String, dynamic> json) {
    final shopJson = json['shops'] as Map<String, dynamic>?;
    final hostJson = json['users'] as Map<String, dynamic>?;
    final pinnedJson = json['live_pinned_products'] as List?;
    Map<String, dynamic>? pinnedRow;
    if (pinnedJson != null && pinnedJson.isNotEmpty) {
      pinnedRow = (pinnedJson.first as Map)['products'] as Map<String, dynamic>?;
    }
    double? pinnedPrice;
    String? pinnedProductId;
    if (pinnedRow != null) {
      final discount = pinnedRow['discount_price'] as num?;
      final price = pinnedRow['price'] as num?;
      pinnedPrice = (discount ?? price)?.toDouble();
      pinnedProductId = pinnedRow['id'] as String?;
    }

    return LiveSession(
      id: json['id'] as String,
      hostUserId: json['host_user_id'] as String,
      shopId: json['shop_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      coverImageUrl: json['cover_image_url'] as String?,
      channelName: json['channel_name'] as String,
      status: json['status'] as String,
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      endedAt: json['ended_at'] != null
          ? DateTime.parse(json['ended_at'] as String)
          : null,
      peakViewerCount: (json['peak_viewer_count'] as num? ?? 0).toInt(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      shopName: shopJson?['name'] as String?,
      hostUserName: hostJson?['full_name'] as String? ??
          hostJson?['username'] as String? ??
          'Satıcı',
      hostAvatarUrl: hostJson?['avatar_url'] as String?,
      pinnedProductName: pinnedRow?['name'] as String?,
      pinnedProductImageUrl: pinnedRow?['image_url'] as String?,
      pinnedProductPrice: pinnedPrice,
      pinnedProductId: pinnedProductId,
    );
  }

  bool get isLive => status == 'live';
  bool get isEnded => status == 'ended';

  Duration? get duration {
    if (startedAt == null) return null;
    final end = endedAt ?? DateTime.now();
    return end.difference(startedAt!);
  }
}

// Canlı yayın yorum mesajı
class LiveMessage {
  final String id;
  final String sessionId;
  final String userId;
  final String message;
  final bool isHost;
  final DateTime createdAt;
  final String? userName;
  final String? userAvatarUrl;

  LiveMessage({
    required this.id,
    required this.sessionId,
    required this.userId,
    required this.message,
    required this.isHost,
    required this.createdAt,
    this.userName,
    this.userAvatarUrl,
  });

  factory LiveMessage.fromJson(Map<String, dynamic> json) {
    final userJson = json['users'] as Map<String, dynamic>?;
    return LiveMessage(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      userId: json['user_id'] as String,
      message: json['message'] as String,
      isHost: json['is_host'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      userName: userJson?['full_name'] as String? ??
          userJson?['username'] as String?,
      userAvatarUrl: userJson?['avatar_url'] as String?,
    );
  }
}