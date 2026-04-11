class GroupMessage {
  final String id;
  final String groupId;
  final String senderId;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Local state
  final bool isFailed;
  final bool isSending;

  // Join ile gelen sender bilgileri
  final String? senderName;
  final String? senderAvatarUrl;

  // Okunma durumu
  final int readByCount; // Bu mesajı kaç kişi okudu

  // Yanıt (reply) bilgileri
  final String? replyToId;          // Yanıtlanan mesaj ID
  final String? replyToContent;     // Yanıtlanan mesaj içeriği
  final String? replyToSenderName;  // Yanıtlanan mesaj gönderen adı

  GroupMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.isFailed = false,
    this.isSending = false,
    this.senderName,
    this.senderAvatarUrl,
    this.readByCount = 0,
    this.replyToId,
    this.replyToContent,
    this.replyToSenderName,
  });

  factory GroupMessage.fromMap(Map<String, dynamic> map) {
    return GroupMessage(
      id: map['id'] as String,
      groupId: map['group_id'] as String,
      senderId: map['sender_id'] as String,
      content: map['content'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      senderName: map['sender']?['full_name'] as String?,
      senderAvatarUrl: map['sender']?['avatar_url'] as String?,
      readByCount: map['read_by_count'] as int? ?? 0,
      replyToId: map['reply_to_id'] as String?,
      replyToContent: map['reply_to_content'] as String?,
      replyToSenderName: map['reply_to_sender_name'] as String?,
    );
  }

  String get messageStatus {
    if (isFailed) return 'failed';
    if (isSending) return 'sending';
    return 'sent';
  }

  /// Tüm üyeler mesajı okudu mu? (grup üye sayısı hariç gönderen)
  bool isReadByAll(int totalMembers) {
    if (totalMembers <= 1) return readByCount > 0;
    return readByCount >= (totalMembers - 1);
  }

  GroupMessage copyWith({
    String? id,
    String? groupId,
    String? senderId,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isFailed,
    bool? isSending,
    String? senderName,
    String? senderAvatarUrl,
    int? readByCount,
    String? replyToId,
    String? replyToContent,
    String? replyToSenderName,
  }) {
    return GroupMessage(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isFailed: isFailed ?? this.isFailed,
      isSending: isSending ?? this.isSending,
      senderName: senderName ?? this.senderName,
      senderAvatarUrl: senderAvatarUrl ?? this.senderAvatarUrl,
      readByCount: readByCount ?? this.readByCount,
      replyToId: replyToId ?? this.replyToId,
      replyToContent: replyToContent ?? this.replyToContent,
      replyToSenderName: replyToSenderName ?? this.replyToSenderName,
    );
  }

  factory GroupMessage.createTemp({
    required String groupId,
    required String senderId,
    required String content,
    String? replyToId,
    String? replyToContent,
    String? replyToSenderName,
  }) {
    final now = DateTime.now();
    return GroupMessage(
      id: 'temp_${now.millisecondsSinceEpoch}_$senderId',
      groupId: groupId,
      senderId: senderId,
      content: content,
      createdAt: now,
      updatedAt: now,
      isSending: true,
      replyToId: replyToId,
      replyToContent: replyToContent,
      replyToSenderName: replyToSenderName,
    );
  }
}

class GroupMember {
  final String id;
  final String groupId;
  final String userId;
  final String role;
  final DateTime joinedAt;
  final int unreadCount;

  // Join ile gelen profil bilgileri
  final String? fullName;
  final String? username;
  final String? avatarUrl;
  final bool? isOnline;
  final DateTime? lastSeen;

  GroupMember({
    required this.id,
    required this.groupId,
    required this.userId,
    this.role = 'member',
    required this.joinedAt,
    this.unreadCount = 0,
    this.fullName,
    this.username,
    this.avatarUrl,
    this.isOnline,
    this.lastSeen,
  });

  factory GroupMember.fromMap(Map<String, dynamic> map) {
    DateTime? lastSeen;
    final lastSeenRaw = map['profiles']?['last_seen'];
    if (lastSeenRaw is String) {
      try { lastSeen = DateTime.parse(lastSeenRaw); } catch (_) {}
    }
    return GroupMember(
      id: map['id'] as String,
      groupId: map['group_id'] as String,
      userId: map['user_id'] as String,
      role: map['role'] as String? ?? 'member',
      joinedAt: DateTime.parse(map['joined_at'] as String),
      unreadCount: map['unread_count'] as int? ?? 0,
      fullName: map['profiles']?['full_name'] as String?,
      username: map['profiles']?['username'] as String?,
      avatarUrl: map['profiles']?['avatar_url'] as String?,
      isOnline: map['profiles']?['is_online'] as bool?,
      lastSeen: lastSeen,
    );
  }

  bool get isAdmin => role == 'admin';
  bool get isModerator => role == 'moderator';
}

class GroupJoinRequest {
  final String id;
  final String groupId;
  final String userId;
  final String status; // 'pending', 'approved', 'rejected'
  final String? message;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Join ile gelen bilgiler
  final String? userName;
  final String? userAvatarUrl;

  GroupJoinRequest({
    required this.id,
    required this.groupId,
    required this.userId,
    this.status = 'pending',
    this.message,
    required this.createdAt,
    required this.updatedAt,
    this.userName,
    this.userAvatarUrl,
  });

  factory GroupJoinRequest.fromMap(Map<String, dynamic> map) {
    return GroupJoinRequest(
      id: map['id'] as String,
      groupId: map['group_id'] as String,
      userId: map['user_id'] as String,
      status: map['status'] as String? ?? 'pending',
      message: map['message'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      userName: map['profiles']?['full_name'] as String?,
      userAvatarUrl: map['profiles']?['avatar_url'] as String?,
    );
  }

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}

/// Mesaj okundu bilgisi modeli
class MessageReadReceipt {
  final String userId;
  final String? fullName;
  final String? username;
  final String? avatarUrl;
  final DateTime readAt;

  MessageReadReceipt({
    required this.userId,
    this.fullName,
    this.username,
    this.avatarUrl,
    required this.readAt,
  });

  factory MessageReadReceipt.fromMap(Map<String, dynamic> map) {
    return MessageReadReceipt(
      userId: map['user_id'] as String,
      fullName: map['full_name'] as String?,
      username: map['username'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      readAt: DateTime.parse(map['read_at'] as String),
    );
  }

  /// Gösterilecek isim (full_name yoksa username, o da yoksa 'Bilinmeyen')
  String get displayName => fullName ?? username ?? 'Bilinmeyen';
}
