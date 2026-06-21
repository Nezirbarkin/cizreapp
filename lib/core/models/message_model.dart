// ignore_for_file: avoid_print

import 'dart:convert';

class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final bool isRead;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  // Mesaj durumu (local state - veritabanında tutulmaz)
  final bool isFailed;
  final bool isSending;
  
  // Yanıt (reply) özelliği için
  final String? replyToId;
  final String? replyToContent;
  final String? replyToSenderName;
  
  // Gönderi paylaşımı için ekstra alanlar (content içinden parse edilir)
  String? sharedPostId;
  String? sharedPostContent;
  String? sharedPostImageUrl;
  String? sharedPostAuthorName;

  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    this.isRead = false,
    required this.createdAt,
    required this.updatedAt,
    this.isFailed = false,
    this.isSending = false,
    this.replyToId,
    this.replyToContent,
    this.replyToSenderName,
    this.sharedPostId,
    this.sharedPostContent,
    this.sharedPostImageUrl,
    this.sharedPostAuthorName,
  });

  /// WhatsApp benzeri mesaj durumu
  /// - 'failed'  : Gönderilemedi (tek gri tik)
  /// - 'sending' : Gönderiliyor (saat ikonu)
  /// - 'sent'    : Gönderildi (çift tik)
  /// - 'read'    : Görüldü (mavi çift tik)
  String get messageStatus {
    if (isFailed) return 'failed';
    if (isSending) return 'sending';
    if (isRead) return 'read';
    return 'sent';
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    String content = map['content'] as String;
    String? sharedPostId;
    String? sharedPostContent;
    String? sharedPostImageUrl;
    String? sharedPostAuthorName;
    
    // Content'in gönderi paylaşımı olup olmadığını kontrol et
    if (content.startsWith('SHARED_POST:')) {
      try {
        final jsonStr = content.substring('SHARED_POST:'.length);
        print('🔍 DEBUG Message.fromMap - JSON string: $jsonStr');
        
        final postData = json.decode(jsonStr) as Map<String, dynamic>;
        sharedPostId = postData['postId'] as String?;
        sharedPostContent = postData['content'] as String?;
        sharedPostImageUrl = postData['imageUrl'] as String?;
        sharedPostAuthorName = postData['authorName'] as String?;
        
        print('🔍 DEBUG Message.fromMap - Parsed: postId=$sharedPostId, content=$sharedPostContent');
        
        // Gösterilecek içerik - paylaşılan gönderi için daha temiz bir metin
        content = '📎 Gönderi paylaşıldı';
      } catch (e, stack) {
        // Parse hatası - normal mesaj olarak devam et
        print('❌ ERROR Message.fromMap - Parse failed: $e');
        print('Stack: $stack');
      }
    }
    
    return Message(
      id: map['id'] as String,
      conversationId: map['conversation_id'] as String,
      senderId: map['sender_id'] as String,
      content: content,
      isRead: map['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      replyToId: map['reply_to_id'] as String?,
      replyToContent: map['reply_to_content'] as String?,
      replyToSenderName: map['reply_to_sender_name'] as String?,
      sharedPostId: sharedPostId,
      sharedPostContent: sharedPostContent,
      sharedPostImageUrl: sharedPostImageUrl,
      sharedPostAuthorName: sharedPostAuthorName,
    );
  }
  
  // Gönderi paylaşımı mı kontrol et
  bool get isSharedPost => sharedPostId != null;

  Message copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? content,
    bool? isRead,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isFailed,
    bool? isSending,
    String? replyToId,
    String? replyToContent,
    String? replyToSenderName,
    String? sharedPostId,
    String? sharedPostContent,
    String? sharedPostImageUrl,
    String? sharedPostAuthorName,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isFailed: isFailed ?? this.isFailed,
      isSending: isSending ?? this.isSending,
      replyToId: replyToId ?? this.replyToId,
      replyToContent: replyToContent ?? this.replyToContent,
      replyToSenderName: replyToSenderName ?? this.replyToSenderName,
      sharedPostId: sharedPostId ?? this.sharedPostId,
      sharedPostContent: sharedPostContent ?? this.sharedPostContent,
      sharedPostImageUrl: sharedPostImageUrl ?? this.sharedPostImageUrl,
      sharedPostAuthorName: sharedPostAuthorName ?? this.sharedPostAuthorName,
    );
  }

  /// Geçici mesaj oluştur (gönderilirken)
  factory Message.createTemp({
    required String conversationId,
    required String senderId,
    required String content,
  }) {
    final now = DateTime.now();
    return Message(
      // ignore: unnecessary_brace_in_string_interps
      id: 'temp_${now.millisecondsSinceEpoch}_${senderId}',
      conversationId: conversationId,
      senderId: senderId,
      content: content,
      createdAt: now,
      updatedAt: now,
      isSending: true,
    );
  }
}
