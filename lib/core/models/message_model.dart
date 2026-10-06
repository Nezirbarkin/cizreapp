// ignore_for_file: avoid_print

import 'dart:convert';

/// Mesaj türü (DB: `messages.message_type`, Görev 3.1).
///
/// Paylaşılan gönderi/ilan kartları eski düzende [text] türünde içerik
/// önekiyle (`SHARED_POST:` / `SHARED_ILAN:`) gelir.
enum MessageType {
  text,
  image,
  location;

  /// Tanınmayan değer (daha yeni bir sürümün türü) metin gibi gösterilir:
  /// içerik her türde okunabilir bir önizleme metnidir.
  static MessageType fromDb(Object? value) => switch (value) {
    'image' => MessageType.image,
    'location' => MessageType.location,
    _ => MessageType.text,
  };

  String get dbValue => name;
}

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

  /// Mesaj türü; fotoğraf ve konumda [attachment] doludur, [content] ise
  /// önizleme metnidir ("📷 Fotoğraf", "📍 Konum: …").
  final MessageType messageType;

  /// Türe özgü veri (DB: `messages.attachment` jsonb):
  /// fotoğraf → `{path, w, h, caption?}`, konum → `{lat, lng, label?}`.
  final Map<String, dynamic>? attachment;

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
    this.messageType = MessageType.text,
    this.attachment,
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
      messageType: MessageType.fromDb(map['message_type']),
      attachment: _parseAttachment(map['attachment']),
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

  /// jsonb sütunu REST'ten harita, bazı realtime yüklerinde metin gelebilir.
  static Map<String, dynamic>? _parseAttachment(Object? raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = json.decode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  String? _attachmentText(String key) {
    final value = attachment?[key];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  double? _attachmentNumber(String key) {
    final value = attachment?[key];
    return value is num ? value.toDouble() : null;
  }

  /// Gösterilebilir fotoğraf mesajı (yolu olan).
  bool get isImage => messageType == MessageType.image && imagePath != null;

  /// Gösterilebilir konum mesajı (koordinatı olan).
  bool get isLocation =>
      messageType == MessageType.location && latitude != null && longitude != null;

  /// `chat_attachments` kovasındaki yol: `<gönderen>/<alıcı>/<dosya>`.
  String? get imagePath => _attachmentText('path');
  int? get imageWidth => _attachmentNumber('w')?.round();
  int? get imageHeight => _attachmentNumber('h')?.round();
  String? get imageCaption => _attachmentText('caption');

  /// Fotoğrafın oranı (genişlik/yükseklik); ölçü yoksa null.
  double? get imageAspectRatio {
    final w = imageWidth, h = imageHeight;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }

  double? get latitude => _attachmentNumber('lat');
  double? get longitude => _attachmentNumber('lng');
  String? get locationLabel => _attachmentText('label');

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
    MessageType? messageType,
    Map<String, dynamic>? attachment,
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
      messageType: messageType ?? this.messageType,
      attachment: attachment ?? this.attachment,
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
    MessageType messageType = MessageType.text,
    Map<String, dynamic>? attachment,
    String? replyToId,
    String? replyToContent,
    String? replyToSenderName,
  }) {
    final now = DateTime.now();
    return Message(
      // Mikrosaniye: art arda gönderilen iki fotoğrafın geçici kimliği çakışmasın.
      // ignore: unnecessary_brace_in_string_interps
      id: 'temp_${now.microsecondsSinceEpoch}_${senderId}',
      conversationId: conversationId,
      senderId: senderId,
      content: content,
      createdAt: now.toUtc(),
      updatedAt: now.toUtc(),
      isSending: true,
      messageType: messageType,
      attachment: attachment,
      replyToId: replyToId,
      replyToContent: replyToContent,
      replyToSenderName: replyToSenderName,
    );
  }
}
