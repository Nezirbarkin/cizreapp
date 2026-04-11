class Category {
  final String id;
  final String name;
  final String slug;
  final String? icon;
  final String? imageUrl;
  final String? description;
  final bool isActive;
  final int displayOrder;
  final DateTime createdAt;

  Category({
    required this.id,
    required this.name,
    required this.slug,
    this.icon,
    this.imageUrl,
    this.description,
    this.isActive = true,
    this.displayOrder = 0,
    required this.createdAt,
  });

  Category copyWith({
    String? id,
    String? name,
    String? slug,
    String? icon,
    String? imageUrl,
    String? description,
    bool? isActive,
    int? displayOrder,
    DateTime? createdAt,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      icon: icon ?? this.icon,
      imageUrl: imageUrl ?? this.imageUrl,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      displayOrder: displayOrder ?? this.displayOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'icon': icon,
      'image_url': imageUrl,
      'description': description,
      'is_active': isActive,
      'display_order': displayOrder,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      icon: json['icon'] as String?,
      imageUrl: json['image_url'] as String?,
      description: json['description'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      displayOrder: json['display_order'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
