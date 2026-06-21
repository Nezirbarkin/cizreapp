/// AI sohbet mesajı modeli
class AIMessage {
  final String id;
  final String conversationId;
  final String userId;
  final String role; // 'user' | 'assistant' | 'system'
  final String content;
  final List<AIAttachment> attachments;
  final List<String> generatedImages;
  final int tokensUsed;
  final String? provider;
  final String? model;
  final String? error;
  final DateTime createdAt;

  AIMessage({
    required this.id,
    required this.conversationId,
    required this.userId,
    required this.role,
    required this.content,
    this.attachments = const [],
    this.generatedImages = const [],
    this.tokensUsed = 0,
    this.provider,
    this.model,
    this.error,
    required this.createdAt,
  });

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
  bool get isError => error != null && error!.isNotEmpty;
  bool get hasGeneratedImages => generatedImages.isNotEmpty;
  bool get hasAttachments => attachments.isNotEmpty;

  factory AIMessage.fromMap(Map<String, dynamic> map) {
    return AIMessage(
      id: map['id'] as String,
      conversationId: map['conversation_id'] as String,
      userId: map['user_id'] as String,
      role: map['role'] as String,
      content: (map['content'] as String?) ?? '',
      attachments: _parseAttachments(map['attachments']),
      generatedImages: _parseGeneratedImages(map['generated_images']),
      tokensUsed: (map['tokens_used'] as num?)?.toInt() ?? 0,
      provider: map['provider'] as String?,
      model: map['model'] as String?,
      error: map['error'] as String?,
      createdAt: _parseDate(map['created_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'user_id': userId,
      'role': role,
      'content': content,
      'attachments': attachments.map((a) => a.toMap()).toList(),
      'generated_images': generatedImages.map((u) => {'url': u}).toList(),
      'tokens_used': tokensUsed,
      'provider': provider,
      'model': model,
      'error': error,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Geçici (henüz kaydedilmemiş) mesaj oluşturur — UI optimistic update için
  factory AIMessage.tempUser({
    required String conversationId,
    required String userId,
    required String content,
    List<AIAttachment> attachments = const [],
  }) {
    return AIMessage(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      conversationId: conversationId,
      userId: userId,
      role: 'user',
      content: content,
      attachments: attachments,
      createdAt: DateTime.now(),
    );
  }

  /// Hata mesajı oluşturur
  factory AIMessage.error({
    required String conversationId,
    required String userId,
    required String errorMessage,
    String? provider,
  }) {
    return AIMessage(
      id: 'error_${DateTime.now().millisecondsSinceEpoch}',
      conversationId: conversationId,
      userId: userId,
      role: 'assistant',
      content: 'Bir hata oluştu',
      error: errorMessage,
      provider: provider,
      createdAt: DateTime.now(),
    );
  }

  AIMessage copyWith({
    String? id,
    String? conversationId,
    String? userId,
    String? role,
    String? content,
    List<AIAttachment>? attachments,
    List<String>? generatedImages,
    int? tokensUsed,
    String? provider,
    String? model,
    String? error,
    DateTime? createdAt,
  }) {
    return AIMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      content: content ?? this.content,
      attachments: attachments ?? this.attachments,
      generatedImages: generatedImages ?? this.generatedImages,
      tokensUsed: tokensUsed ?? this.tokensUsed,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      error: error ?? this.error,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static List<AIAttachment> _parseAttachments(dynamic value) {
    if (value == null) return [];
    if (value is! List) return [];
    return value
        .map((e) => e is Map<String, dynamic> ? AIAttachment.fromMap(e) : null)
        .whereType<AIAttachment>()
        .toList();
  }

  static List<String> _parseGeneratedImages(dynamic value) {
    if (value == null) return [];
    if (value is! List) return [];
    return value.map((e) {
      if (e is String) return e;
      if (e is Map<String, dynamic>) return e['url'] as String? ?? '';
      return '';
    }).where((u) => u.isNotEmpty).toList();
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }
}

/// Mesaja ekli dosya (resim)
class AIAttachment {
  final String? type; // genelde 'image'
  final String? path; // storage path
  final String? mime;
  final String? url; // signed URL (UI için)

  AIAttachment({this.type, this.path, this.mime, this.url});

  factory AIAttachment.fromMap(Map<String, dynamic> map) {
    return AIAttachment(
      type: map['type'] as String?,
      path: map['path'] as String?,
      mime: map['mime'] as String?,
      url: map['url'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (type != null) 'type': type,
      if (path != null) 'path': path,
      if (mime != null) 'mime': mime,
      if (url != null) 'url': url,
    };
  }
}