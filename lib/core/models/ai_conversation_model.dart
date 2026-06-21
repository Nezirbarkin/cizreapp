/// AI sohbet konuşma modeli
class AIConversation {
  final String id;
  final String userId;
  final String? title;
  final String provider;
  final int messageCount;
  final DateTime lastMessageAt;
  final bool isArchived;
  final DateTime createdAt;
  final String? lastMessagePreview;

  AIConversation({
    required this.id,
    required this.userId,
    this.title,
    required this.provider,
    required this.messageCount,
    required this.lastMessageAt,
    required this.isArchived,
    required this.createdAt,
    this.lastMessagePreview,
  });

  factory AIConversation.fromMap(Map<String, dynamic> map) {
    return AIConversation(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      title: map['title'] as String?,
      provider: (map['provider'] as String?) ?? 'gemini',
      messageCount: (map['message_count'] as num?)?.toInt() ?? 0,
      lastMessageAt: _parseDate(map['last_message_at']) ?? DateTime.now(),
      isArchived: (map['is_archived'] as bool?) ?? false,
      createdAt: _parseDate(map['created_at']) ?? DateTime.now(),
      lastMessagePreview: map['last_message_preview'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'provider': provider,
      'message_count': messageCount,
      'last_message_at': lastMessageAt.toIso8601String(),
      'is_archived': isArchived,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Sağlayıcı için okunabilir ad
  String get providerLabel {
    switch (provider.toLowerCase()) {
      case 'gemini':
        return 'Gemini';
      case 'groq':
        return 'Groq';
      case 'openrouter':
        return 'OpenRouter';
      case 'openai':
        return 'OpenAI';
      case 'auto':
        return 'Otomatik';
      default:
        return provider;
    }
  }

  /// Başlık yoksa varsayılan
  String get displayTitle => (title == null || title!.isEmpty) ? 'Yeni Sohbet' : title!;

  /// Son mesaj önizlemesi
  String get preview {
    if (lastMessagePreview != null && lastMessagePreview!.isNotEmpty) {
      return lastMessagePreview!;
    }
    return '$messageCount mesaj';
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  AIConversation copyWith({
    String? id,
    String? userId,
    String? title,
    String? provider,
    int? messageCount,
    DateTime? lastMessageAt,
    bool? isArchived,
    DateTime? createdAt,
    String? lastMessagePreview,
  }) {
    return AIConversation(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      provider: provider ?? this.provider,
      messageCount: messageCount ?? this.messageCount,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
    );
  }
}