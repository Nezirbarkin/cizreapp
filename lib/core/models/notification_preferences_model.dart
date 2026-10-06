class NotificationPreferences {
  final String id;
  final String userId;
  final bool likesEnabled;
  final bool commentsEnabled;
  final bool followersEnabled;
  final bool orderUpdatesEnabled;
  final bool orderReadyEnabled;
  final bool deliveryEnabled;
  final bool promotionalEnabled;
  final bool mentionsEnabled;
  final bool groupJoinRequestsEnabled;
  final bool groupMemberJoinedEnabled;

  /// Sepetimdeki ürün indirime girince bildirim (Görev 3.3; varsayılan açık).
  final bool cartPriceDropEnabled;

  /// Takip ettiğim / abone olduğum mağaza canlı yayına başlayınca bildirim
  /// (varsayılan açık).
  final bool liveStreamsEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  NotificationPreferences({
    required this.id,
    required this.userId,
    required this.likesEnabled,
    required this.commentsEnabled,
    required this.followersEnabled,
    required this.orderUpdatesEnabled,
    required this.orderReadyEnabled,
    required this.deliveryEnabled,
    required this.promotionalEnabled,
    required this.mentionsEnabled,
    this.groupJoinRequestsEnabled = true,
    this.groupMemberJoinedEnabled = true,
    this.cartPriceDropEnabled = true,
    this.liveStreamsEnabled = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      likesEnabled: json['likes_enabled'] as bool? ?? true,
      commentsEnabled: json['comments_enabled'] as bool? ?? true,
      followersEnabled: json['followers_enabled'] as bool? ?? true,
      orderUpdatesEnabled: json['order_updates_enabled'] as bool? ?? true,
      orderReadyEnabled: json['order_ready_enabled'] as bool? ?? true,
      deliveryEnabled: json['delivery_enabled'] as bool? ?? true,
      promotionalEnabled: json['promotional_enabled'] as bool? ?? false,
      mentionsEnabled: json['mentions'] as bool? ?? true,
      groupJoinRequestsEnabled: json['group_join_requests_enabled'] as bool? ?? true,
      groupMemberJoinedEnabled: json['group_member_joined_enabled'] as bool? ?? true,
      cartPriceDropEnabled: json['cart_price_drop_enabled'] as bool? ?? true,
      liveStreamsEnabled: json['live_streams_enabled'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'likes_enabled': likesEnabled,
      'comments_enabled': commentsEnabled,
      'followers_enabled': followersEnabled,
      'order_updates_enabled': orderUpdatesEnabled,
      'order_ready_enabled': orderReadyEnabled,
      'delivery_enabled': deliveryEnabled,
      'promotional_enabled': promotionalEnabled,
      'mentions_enabled': mentionsEnabled,
      'group_join_requests_enabled': groupJoinRequestsEnabled,
      'group_member_joined_enabled': groupMemberJoinedEnabled,
      'cart_price_drop_enabled': cartPriceDropEnabled,
      'live_streams_enabled': liveStreamsEnabled,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  NotificationPreferences copyWith({
    String? id,
    String? userId,
    bool? likesEnabled,
    bool? commentsEnabled,
    bool? followersEnabled,
    bool? orderUpdatesEnabled,
    bool? orderReadyEnabled,
    bool? deliveryEnabled,
    bool? promotionalEnabled,
    bool? mentionsEnabled,
    bool? groupJoinRequestsEnabled,
    bool? groupMemberJoinedEnabled,
    bool? cartPriceDropEnabled,
    bool? liveStreamsEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NotificationPreferences(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      likesEnabled: likesEnabled ?? this.likesEnabled,
      commentsEnabled: commentsEnabled ?? this.commentsEnabled,
      followersEnabled: followersEnabled ?? this.followersEnabled,
      orderUpdatesEnabled: orderUpdatesEnabled ?? this.orderUpdatesEnabled,
      orderReadyEnabled: orderReadyEnabled ?? this.orderReadyEnabled,
      deliveryEnabled: deliveryEnabled ?? this.deliveryEnabled,
      promotionalEnabled: promotionalEnabled ?? this.promotionalEnabled,
      mentionsEnabled: mentionsEnabled ?? this.mentionsEnabled,
      groupJoinRequestsEnabled: groupJoinRequestsEnabled ?? this.groupJoinRequestsEnabled,
      groupMemberJoinedEnabled: groupMemberJoinedEnabled ?? this.groupMemberJoinedEnabled,
      cartPriceDropEnabled: cartPriceDropEnabled ?? this.cartPriceDropEnabled,
      liveStreamsEnabled: liveStreamsEnabled ?? this.liveStreamsEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
