import 'package:supabase_flutter/supabase_flutter.dart';

class Conversation {
  final String id;
  final String userId;
  final String otherUserId;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic>? otherUser;
  final bool lastMessageByMe;
  final bool lastMessageRead;

  Conversation({
    required this.id,
    required this.userId,
    required this.otherUserId,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.otherUser,
    this.lastMessageByMe = false,
    this.lastMessageRead = false,
  });

  factory Conversation.fromMap(Map<String, dynamic> map) {
    return Conversation(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      otherUserId: map['other_user_id'] as String,
      lastMessage: map['last_message'] as String?,
      lastMessageTime: map['last_message_time'] != null
          ? DateTime.parse(map['last_message_time'] as String)
          : null,
      unreadCount: map['unread_count'] as int? ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      otherUser: map['other_user'] as Map<String, dynamic>?,
      lastMessageByMe: map['last_message_by_me'] as bool? ?? false,
      lastMessageRead: map['last_message_read'] as bool? ?? false,
    );
  }

  Conversation copyWith({
    String? id,
    String? userId,
    String? otherUserId,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? otherUser,
    bool? lastMessageByMe,
    bool? lastMessageRead,
  }) {
    return Conversation(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      otherUserId: otherUserId ?? this.otherUserId,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      otherUser: otherUser ?? this.otherUser,
      lastMessageByMe: lastMessageByMe ?? this.lastMessageByMe,
      lastMessageRead: lastMessageRead ?? this.lastMessageRead,
    );
  }
}
