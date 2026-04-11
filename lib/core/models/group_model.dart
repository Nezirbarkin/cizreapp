class ChatGroup {
  final String id;
  final String name;
  final String? description;
  final String? avatarUrl;
  final String? coverUrl;
  final bool isPrivate;
  final bool isDiscoverable; // Grupun tüm kullanıcılara görünür olup olmadığı
  final bool hideCreator; // Grup kurucusu gizli mi
  final String createdBy;
  final int memberCount;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Kullanıcı-spesifik alanlar (join ile gelir)
  final int unreadCount;
  final String? userRole; // 'admin', 'moderator', 'member'
  final bool isMuted; // Grup sessize alındı mı
  final bool hasPendingJoinRequest; // Bekleyen katılma isteği var mı

  ChatGroup({
    required this.id,
    required this.name,
    this.description,
    this.avatarUrl,
    this.coverUrl,
    this.isPrivate = false,
    this.isDiscoverable = true,
    this.hideCreator = false,
    required this.createdBy,
    this.memberCount = 1,
    this.lastMessage,
    this.lastMessageTime,
    required this.createdAt,
    required this.updatedAt,
    this.unreadCount = 0,
    this.userRole,
    this.isMuted = false,
    this.hasPendingJoinRequest = false,
  });

  factory ChatGroup.fromMap(Map<String, dynamic> map) {
    return ChatGroup(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      coverUrl: map['cover_url'] as String?,
      isPrivate: map['is_private'] as bool? ?? false,
      isDiscoverable: map['is_discoverable'] as bool? ?? true,
      hideCreator: map['hide_creator'] as bool? ?? false,
      createdBy: map['created_by'] as String,
      memberCount: map['member_count'] as int? ?? 1,
      lastMessage: map['last_message'] as String?,
      lastMessageTime: map['last_message_time'] != null
          ? DateTime.parse(map['last_message_time'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      unreadCount: map['unread_count'] as int? ?? 0,
      userRole: map['user_role'] as String?,
      isMuted: map['is_muted'] as bool? ?? false,
      hasPendingJoinRequest: map['has_pending_join_request'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'avatar_url': avatarUrl,
      'cover_url': coverUrl,
      'is_private': isPrivate,
      'is_discoverable': isDiscoverable,
      'hide_creator': hideCreator,
      'created_by': createdBy,
    };
  }

  ChatGroup copyWith({
    String? id,
    String? name,
    String? description,
    String? avatarUrl,
    String? coverUrl,
    bool? isPrivate,
    bool? isDiscoverable,
    bool? hideCreator,
    String? createdBy,
    int? memberCount,
    String? lastMessage,
    DateTime? lastMessageTime,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? unreadCount,
    String? userRole,
    bool? isMuted,
    bool? hasPendingJoinRequest,
  }) {
    return ChatGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      coverUrl: coverUrl ?? this.coverUrl,
      isPrivate: isPrivate ?? this.isPrivate,
      isDiscoverable: isDiscoverable ?? this.isDiscoverable,
      hideCreator: hideCreator ?? this.hideCreator,
      createdBy: createdBy ?? this.createdBy,
      memberCount: memberCount ?? this.memberCount,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      unreadCount: unreadCount ?? this.unreadCount,
      userRole: userRole ?? this.userRole,
      isMuted: isMuted ?? this.isMuted,
      hasPendingJoinRequest: hasPendingJoinRequest ?? this.hasPendingJoinRequest,
    );
  }

  bool get isAdmin => userRole == 'admin';
  bool get isModerator => userRole == 'moderator';
  bool get isMember => userRole != null;
}
