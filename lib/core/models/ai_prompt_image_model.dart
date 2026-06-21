/// AI Prompt Görsel Kütüphanesi Modeli
/// Admin panelde yüklenen görseller için
class AIPromptImage {
  final String id;
  final String imageUrl;
  final String? thumbnailUrl;
  final String category;
  final List<String> tags;
  final String? altText;
  final int? width;
  final int? height;
  final int? fileSize;
  final String? createdBy;
  final bool isActive;
  final int usageCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  AIPromptImage({
    required this.id,
    required this.imageUrl,
    this.thumbnailUrl,
    this.category = 'general',
    this.tags = const [],
    this.altText,
    this.width,
    this.height,
    this.fileSize,
    this.createdBy,
    this.isActive = true,
    this.usageCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AIPromptImage.fromMap(Map<String, dynamic> map) {
    return AIPromptImage(
      id: map['id'] as String,
      imageUrl: map['image_url'] as String,
      thumbnailUrl: map['thumbnail_url'] as String?,
      category: (map['category'] as String?) ?? 'general',
      tags: (map['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      altText: map['alt_text'] as String?,
      width: map['width'] as int?,
      height: map['height'] as int?,
      fileSize: map['file_size'] as int?,
      createdBy: map['created_by'] as String?,
      isActive: (map['is_active'] as bool?) ?? true,
      usageCount: (map['usage_count'] as int?) ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'image_url': imageUrl,
      'thumbnail_url': thumbnailUrl,
      'category': category,
      'tags': tags,
      'alt_text': altText,
      'width': width,
      'height': height,
      'file_size': fileSize,
      'created_by': createdBy,
      'is_active': isActive,
      'usage_count': usageCount,
    };
  }

  AIPromptImage copyWith({
    String? id,
    String? imageUrl,
    String? thumbnailUrl,
    String? category,
    List<String>? tags,
    String? altText,
    int? width,
    int? height,
    int? fileSize,
    String? createdBy,
    bool? isActive,
    int? usageCount,
  }) {
    return AIPromptImage(
      id: id ?? this.id,
      imageUrl: imageUrl ?? this.imageUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      altText: altText ?? this.altText,
      width: width ?? this.width,
      height: height ?? this.height,
      fileSize: fileSize ?? this.fileSize,
      createdBy: createdBy ?? this.createdBy,
      isActive: isActive ?? this.isActive,
      usageCount: usageCount ?? this.usageCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Dosya boyutunu okunabilir formata dönüştür
  String get fileSizeFormatted {
    if (fileSize == null) return '';
    if (fileSize! < 1024) return '$fileSize B';
    if (fileSize! < 1024 * 1024) return '${(fileSize! / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Görsel en boy oranı
  double? get aspectRatio {
    if (width == null || height == null || height == 0) return null;
    return width! / height!;
  }

  /// Kategoriler sabit listesi (Admin panel için)
  static const List<Map<String, String>> categoryPresets = [
    {'name': 'Genel', 'value': 'general', 'icon': 'image'},
    {'name': 'Alışveriş', 'value': 'shopping', 'icon': 'shopping_bag'},
    {'name': 'Yemek', 'value': 'food', 'icon': 'restaurant'},
    {'name': 'Yaratıcı', 'value': 'creative', 'icon': 'palette'},
    {'name': 'Teknoloji', 'value': 'tech', 'icon': 'computer'},
    {'name': 'Doğa', 'value': 'nature', 'icon': 'nature'},
    {'name': 'İnsanlar', 'value': 'people', 'icon': 'people'},
    {'name': 'Mimari', 'value': 'architecture', 'icon': 'apartment'},
  ];
}
