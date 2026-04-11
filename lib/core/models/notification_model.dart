class NotificationModel {
  final String id;
  final String userId;
  final String type; // like, comment, follow, mention, system
  final String? title;
  final String? body;
  final String? actorId;
  final String? actorName;
  final String? actorAvatar;
  final String? entityId; // post_id, shop_id, etc.
  final String? entityType;
  final String? entityImage;
  final Map<String, dynamic>? metadata;
  final bool isRead;
  final DateTime createdAt;

  NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    this.title,
    this.body,
    this.actorId,
    this.actorName,
    this.actorAvatar,
    this.entityId,
    this.entityType,
    this.entityImage,
    this.metadata,
    required this.isRead,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      type: json['type'] as String,
      title: json['title'] as String?,
      body: json['content'] as String?, // Supabase'de 'content' kullanıyoruz
      actorId: json['actor_id'] as String?,
      actorName: json['actor_name'] as String?,
      actorAvatar: json['actor_avatar'] as String?,
      entityId: json['entity_id'] as String?,
      entityType: json['entity_type'] as String?,
      entityImage: json['entity_image'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'type': type,
      'title': title,
      'content': body,
      'actor_id': actorId,
      'actor_name': actorName,
      'actor_avatar': actorAvatar,
      'entity_id': entityId,
      'entity_type': entityType,
      'entity_image': entityImage,
      'metadata': metadata,
      'is_read': isRead,
      'created_at': createdAt.toIso8601String(),
    };
  }

  // Kullanıcı için bildirim başlığı ve içeriği oluştur
  static Map<String, String> getNotificationContent(String type, Map<String, dynamic>? metadata) {
    switch (type) {
      case 'like':
        final username = metadata?['username'] ?? 'Bir kullanıcı';
        return {
          'title': 'Yeni Beğeni',
          'body': '$username gönderini beğendi',
        };
      case 'comment':
        final username = metadata?['username'] ?? 'Bir kullanıcı';
        final comment = metadata?['comment'] ?? '';
        return {
          'title': 'Yeni Yorum',
          'body': '$username yorum yaptı: ${comment.length > 30 ? comment.substring(0, 30) + '...' : comment}',
        };
      case 'follow':
        final username = metadata?['username'] ?? 'Bir kullanıcı';
        return {
          'title': 'Yeni Takipçi',
          'body': '$username seni takip etmeye başladı',
        };
      case 'mention':
        final username = metadata?['username'] ?? 'Bir kullanıcı';
        return {
          'title': 'Etiketlendiğin',
          'body': '$username seni bir gönderide etiketledi',
        };
      case 'order':
        final shopName = metadata?['shop_name'] ?? 'Bir dükkan';
        return {
          'title': 'Sipariş Güncellemesi',
          'body': '$shopName siparişinle ilgili güncelleme',
        };
      case 'shop':
        final shopName = metadata?['shop_name'] ?? 'Bir dükkan';
        return {
          'title': 'Yeni Dükkan',
          'body': '$shopName platforma katıldı',
        };
      case 'admin_notification':
        return {
          'title': metadata?['title'] ?? 'Yeni Duyuru',
          'body': metadata?['body'] ?? 'Yeni bir duyuru var',
        };
      default:
        return {
          'title': 'Bildirim',
          'body': 'Yeni bir bildirimin var',
        };
    }
  }

  // İkon getir
  static String getIconForType(String type) {
    switch (type) {
      case 'like':
      case 'post_like':
        return 'favorite';
      case 'comment':
      case 'post_comment':
        return 'chat_bubble';
      case 'follow':
      case 'new_follower':
        return 'person_add';
      case 'follow_request':
        return 'person_add_alt_1';
      case 'mention':
      case 'comment_mention':
        return 'alternate_email';
      case 'order':
      case 'order_update':
      case 'order_status':
        return 'shopping_cart';
      case 'order_confirmed':
      case 'new_order':
        return 'shopping_bag';
      case 'delivered':
        return 'local_shipping';
      case 'shop':
        return 'store';
      case 'shop_review':
        return 'rate_review';
      case 'shop_review_reply':
        return 'reply';
      case 'review_request':
      case 'review_pending':
        return 'star_rate';
      case 'admin_notification':
        return 'campaign';
      case 'group_join_request':
        return 'group_add';
      case 'group_member_joined':
        return 'group';
      default:
        return 'notifications';
    }
  }

  // Renk getir
  static String getColorForType(String type) {
    switch (type) {
      case 'like':
      case 'post_like':
        return 'red';
      case 'comment':
      case 'post_comment':
        return 'blue';
      case 'follow':
      case 'new_follower':
        return 'purple';
      case 'follow_request':
        return 'orange';
      case 'mention':
      case 'comment_mention':
        return 'teal';
      case 'order':
      case 'order_update':
      case 'order_status':
        return 'green';
      case 'order_confirmed':
      case 'new_order':
        return 'green';
      case 'delivered':
        return 'cyan';
      case 'shop':
        return 'indigo';
      case 'shop_review':
        return 'orange';
      case 'shop_review_reply':
        return 'teal';
      case 'review_request':
      case 'review_pending':
        return 'amber';
      case 'admin_notification':
        return 'blue';
      case 'group_join_request':
        return 'deepOrange';
      case 'group_member_joined':
        return 'lightGreen';
      default:
        return 'grey';
    }
  }
}
