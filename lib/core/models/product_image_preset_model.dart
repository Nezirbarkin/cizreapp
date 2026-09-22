class ProductImagePreset {
  final String id;
  final String name;
  final String? description;
  final String imageUrl;
  final bool isActive;
  final int displayOrder;
  final DateTime createdAt;

  ProductImagePreset({
    required this.id,
    required this.name,
    this.description,
    required this.imageUrl,
    this.isActive = true,
    this.displayOrder = 0,
    required this.createdAt,
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
    );
  }
}
