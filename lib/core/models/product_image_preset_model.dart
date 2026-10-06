class ProductImagePreset {
  final String id;
  final String name;
  final String? description;
  final String imageUrl;
  final bool isActive;
  final int displayOrder;
  final DateTime createdAt;

  /// Görselin klasörü (`product_image_folders.id`); null = klasörsüz.
  final String? folderId;

  ProductImagePreset({
    required this.id,
    required this.name,
    this.description,
    required this.imageUrl,
    this.isActive = true,
    this.displayOrder = 0,
    required this.createdAt,
    this.folderId,
  });

  ProductImagePreset copyWith({
    String? id,
    String? name,
    String? description,
    String? imageUrl,
    bool? isActive,
    int? displayOrder,
    DateTime? createdAt,
  }) {
    return ProductImagePreset(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      isActive: isActive ?? this.isActive,
      displayOrder: displayOrder ?? this.displayOrder,
      createdAt: createdAt ?? this.createdAt,
      folderId: folderId,
    );
  }

  /// Klasörü değiştirilmiş kopya; [folderId] null ise klasörsüz olur
  /// (`copyWith` null'ı "değiştirme" diye yorumladığı için ayrı).
  ProductImagePreset withFolder(String? folderId) {
    return ProductImagePreset(
      id: id,
      name: name,
      description: description,
      imageUrl: imageUrl,
      isActive: isActive,
      displayOrder: displayOrder,
      createdAt: createdAt,
      folderId: folderId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'image_url': imageUrl,
      'is_active': isActive,
      'display_order': displayOrder,
      'created_at': createdAt.toIso8601String(),
      'folder_id': folderId,
    };
  }

  factory ProductImagePreset.fromJson(Map<String, dynamic> json) {
    return ProductImagePreset(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      imageUrl: json['image_url'] as String,
      isActive: json['is_active'] as bool? ?? true,
      displayOrder: json['display_order'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      folderId: json['folder_id'] as String?,
    );
  }
}

/// Görsel kütüphanesi klasörü (Market, Kozmetik…). Kapalı klasörün
/// görselleri satıcılara gösterilmez (RLS).
class ProductImageFolder {
  final String id;
  final String name;
  final int displayOrder;
  final bool isActive;

  /// Çağıranın görebildiği görsel sayısı: satıcıda yalnız yayındakiler,
  /// adminde tümü.
  final int imageCount;

  /// Yayındaki görsel sayısı.
  final int activeImageCount;

  const ProductImageFolder({
    required this.id,
    required this.name,
    this.displayOrder = 0,
    this.isActive = true,
    this.imageCount = 0,
    this.activeImageCount = 0,
  });

  ProductImageFolder copyWith({
    String? name,
    int? displayOrder,
    bool? isActive,
    int? imageCount,
    int? activeImageCount,
  }) {
    return ProductImageFolder(
      id: id,
      name: name ?? this.name,
      displayOrder: displayOrder ?? this.displayOrder,
      isActive: isActive ?? this.isActive,
      imageCount: imageCount ?? this.imageCount,
      activeImageCount: activeImageCount ?? this.activeImageCount,
    );
  }

  /// `product_image_folder_summary` RPC satırından ya da tablo satırından.
  factory ProductImageFolder.fromJson(Map<String, dynamic> json) {
    return ProductImageFolder(
      id: json['id'] as String,
      name: json['name'] as String,
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      imageCount: (json['image_count'] as num?)?.toInt() ?? 0,
      activeImageCount: (json['active_image_count'] as num?)?.toInt() ?? 0,
    );
  }
}
