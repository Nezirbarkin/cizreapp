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

  // İlan paylaşımı için ekstra alanlar (content içinden parse edilir)
  String? sharedIlanId;
  String? sharedIlanTitle;
  String? sharedIlanPriceText;
  String? sharedIlanLocationText;
  String? sharedIlanImageUrl;

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
    this.sharedIlanId,
    this.sharedIlanTitle,
    this.sharedIlanPriceText,
    this.sharedIlanLocationText,
    this.sharedIlanImageUrl,
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
    final content = (map['content'] as String?) ?? '';

    String? sharedPostId;
    String? sharedPostContent;
    String? sharedPostImageUrl;
    String? sharedPostAuthorName;
    String? sharedIlanId;
    String? sharedIlanTitle;
    String? sharedIlanPriceText;
    String? sharedIlanLocationText;
    String? sharedIlanImageUrl;

    // Content'in gönderi paylaşımı olup olmadığını kontrol et
    if (content.startsWith('SHARED_POST:')) {
      try {
        final jsonStr = content.substring('SHARED_POST:'.length);
        final postData = json.decode(jsonStr) as Map<String, dynamic>;
        sharedPostId = postData['postId'] as String?;
        sharedPostContent = postData['content'] as String?;
        sharedPostImageUrl = postData['imageUrl'] as String?;
        sharedPostAuthorName = postData['authorName'] as String?;

        // Gösterilecek içerik - paylaşılan gönderi için daha temiz bir metin
      } catch (e, stack) {
        // Parse hatası - normal mesaj olarak devam et
        print('❌ ERROR Message.fromMap - SharedPost parse failed: $e\n$stack');
      }
    }

    if (content.startsWith('SHARED_ILAN:')) {
      try {
        final jsonStr = content.substring('SHARED_ILAN:'.length);
        final ilanData = json.decode(jsonStr) as Map<String, dynamic>;
        sharedIlanId = ilanData['ilanId'] as String?;
        sharedIlanTitle = ilanData['title'] as String?;
        sharedIlanPriceText = ilanData['priceText'] as String?;
        sharedIlanLocationText = ilanData['locationText'] as String?;
        sharedIlanImageUrl = ilanData['imageUrl'] as String?;
      } catch (e, stack) {
        print('❌ ERROR Message.fromMap - SharedIlan parse failed: $e\n$stack');
      }
    }

    final createdAtStr = map['created_at'] as String?;
    if (createdAtStr == null) {
      throw FormatException('created_at missing for message ${map['id']}');
    }

    final createdAt = DateTime.parse(createdAtStr);
    final updatedAtStr = map['updated_at'] as String?;
    final updatedAt = updatedAtStr != null
        ? DateTime.parse(updatedAtStr)
        : createdAt;

    return Message(
      id: map['id'] as String,
      conversationId: map['conversation_id'] as String,
      senderId: map['sender_id'] as String,
      content: content,
      isRead: (map['is_read'] as bool?) ?? false,
      createdAt: createdAt,
      updatedAt: updatedAt,
      replyToId: map['reply_to_id'] as String?,
      replyToContent: map['reply_to_content'] as String?,
      replyToSenderName: map['reply_to_sender_name'] as String?,
      sharedPostId: sharedPostId,
      sharedPostContent: sharedPostContent,
      sharedPostImageUrl: sharedPostImageUrl,
      sharedPostAuthorName: sharedPostAuthorName,
      sharedIlanId: sharedIlanId,
      sharedIlanTitle: sharedIlanTitle,
      sharedIlanPriceText: sharedIlanPriceText,
      sharedIlanLocationText: sharedIlanLocationText,
      sharedIlanImageUrl: sharedIlanImageUrl,
    );
  }

  // Gönderi paylaşımı mı kontrol et
  bool get isSharedPost => sharedPostId != null;
  bool get isSharedIlan => sharedIlanId != null;

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
    String? sharedIlanId,
    String? sharedIlanTitle,
    String? sharedIlanPriceText,
    String? sharedIlanLocationText,
    String? sharedIlanImageUrl,
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
      sharedIlanId: sharedIlanId ?? this.sharedIlanId,
      sharedIlanTitle: sharedIlanTitle ?? this.sharedIlanTitle,
      sharedIlanPriceText: sharedIlanPriceText ?? this.sharedIlanPriceText,
      sharedIlanLocationText:
          sharedIlanLocationText ?? this.sharedIlanLocationText,
      sharedIlanImageUrl: sharedIlanImageUrl ?? this.sharedIlanImageUrl,
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
