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

/// Admin görsel listesinin durum süzgeci (`p_status`).
enum ProductImageAdminStatus { all, active, passive }

/// Admin görsel listesinin sıralaması (`p_sort`): sıra numarası ya da en
/// yeni önce.
enum ProductImageAdminSort { order, newest }

/// Admin görsel listesinin süzgeci ve sıralaması; sunucuda uygulanır
/// (`admin_product_image_presets_page`).
class ProductImageAdminQuery {
  const ProductImageAdminQuery({
    this.folderId,
    this.unfiled = false,
    this.status = ProductImageAdminStatus.all,
    this.search = '',
    this.sort = ProductImageAdminSort.order,
  });

  /// Yalnız bu klasör; null = tüm klasörler ([unfiled] değilse).
  final String? folderId;

  /// Yalnız klasörsüz görseller.
  final bool unfiled;

  final ProductImageAdminStatus status;

  /// Ad + arama kelimelerinde aranır: Türkçe harf/aksan duyarsız, her kelime
  /// geçmeli (sırası önemsiz).
  final String search;

  final ProductImageAdminSort sort;

  @override
  bool operator ==(Object other) =>
      other is ProductImageAdminQuery &&
      other.folderId == folderId &&
      other.unfiled == unfiled &&
      other.status == status &&
      other.search == search &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(folderId, unfiled, status, search, sort);
}

/// Kütüphanenin tamamının sayaçları (süzgeçten bağımsız): klasörler
/// ([ProductImageFolder.imageCount] / [ProductImageFolder.activeImageCount]
/// dolu), klasörsüzler ve en büyük sıra numarası.
class ProductImageLibrarySummary {
  const ProductImageLibrarySummary({
    this.folders = const [],
    this.unfiledCount = 0,
    this.unfiledActiveCount = 0,
    this.maxDisplayOrder = 0,
  });

  final List<ProductImageFolder> folders;
  final int unfiledCount;
  final int unfiledActiveCount;
  final int maxDisplayOrder;

  /// Kütüphanedeki tüm görseller.
  int get totalCount => folders.fold(unfiledCount, (n, f) => n + f.imageCount);

  /// Yayındaki görseller.
  int get activeCount =>
      folders.fold(unfiledActiveCount, (n, f) => n + f.activeImageCount);

  ProductImageLibrarySummary copyWith({List<ProductImageFolder>? folders}) {
    return ProductImageLibrarySummary(
      folders: folders ?? this.folders,
      unfiledCount: unfiledCount,
      unfiledActiveCount: unfiledActiveCount,
      maxDisplayOrder: maxDisplayOrder,
    );
  }

  factory ProductImageLibrarySummary.fromJson(Map<String, dynamic> json) {
    return ProductImageLibrarySummary(
      folders: [
        for (final f in (json['folders'] as List? ?? const []))
          ProductImageFolder.fromJson(Map<String, dynamic>.from(f as Map)),
      ],
      unfiledCount: (json['unfiled_count'] as num?)?.toInt() ?? 0,
      unfiledActiveCount: (json['unfiled_active_count'] as num?)?.toInt() ?? 0,
      maxDisplayOrder: (json['max_display_order'] as num?)?.toInt() ?? 0,
    );
  }
}

/// `admin_product_image_presets_page` yanıtı: bir sayfa, süzgece uyan toplam
/// ve (istendiyse) kütüphane özeti.
class ProductImageAdminPage {
  const ProductImageAdminPage({
    required this.items,
    required this.total,
    this.summary,
  });

  final List<ProductImagePreset> items;

  /// Süzgece uyan görsel sayısı (tüm sayfalar).
  final int total;

  final ProductImageLibrarySummary? summary;

  factory ProductImageAdminPage.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'];
    return ProductImageAdminPage(
      items: [
        for (final p in (json['items'] as List? ?? const []))
          ProductImagePreset.fromJson(Map<String, dynamic>.from(p as Map)),
      ],
      total: (json['total'] as num?)?.toInt() ?? 0,
      summary: summary is Map
          ? ProductImageLibrarySummary.fromJson(
              Map<String, dynamic>.from(summary),
            )
          : null,
    );
  }
}
