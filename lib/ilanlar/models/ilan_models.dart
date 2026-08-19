enum IlanCategoryType { lost, sale, rent, service, other }

enum IlanPricingMode { forbidden, optional, required }

enum IlanStatus {
  draft,
  pending,
  published,
  rejected,
  sold,
  rented,
  found,
  expired,
  archived,
}

class IlanSettings {
  const IlanSettings({
    required this.isEnabled,
    required this.allowUserCreate,
    required this.requireApproval,
    required this.allowGuestView,
    required this.maxActivePerUser,
    required this.maxImagesPerIlan,
    required this.defaultExpiryDays,
    required this.homeCategoryLimit,
    required this.homeIlanLimit,
    required this.showPricesOnHome,
  });

  final bool isEnabled;
  final bool allowUserCreate;
  final bool requireApproval;
  final bool allowGuestView;
  final int maxActivePerUser;
  final int maxImagesPerIlan;
  final int defaultExpiryDays;
  final int homeCategoryLimit;
  final int homeIlanLimit;
  final bool showPricesOnHome;

  factory IlanSettings.fromJson(Map<String, dynamic> json) => IlanSettings(
    isEnabled: json['is_enabled'] as bool? ?? true,
    allowUserCreate: json['allow_user_create'] as bool? ?? true,
    requireApproval: json['require_approval'] as bool? ?? true,
    allowGuestView: json['allow_guest_view'] as bool? ?? true,
    maxActivePerUser: (json['max_active_per_user'] as num?)?.toInt() ?? 10,
    maxImagesPerIlan: (json['max_images_per_ilan'] as num?)?.toInt() ?? 8,
    defaultExpiryDays: (json['default_expiry_days'] as num?)?.toInt() ?? 30,
    homeCategoryLimit: (json['home_category_limit'] as num?)?.toInt() ?? 6,
    homeIlanLimit: (json['home_ilan_limit'] as num?)?.toInt() ?? 8,
    showPricesOnHome: json['show_prices_on_home'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'id': 1,
    'is_enabled': isEnabled,
    'allow_user_create': allowUserCreate,
    'require_approval': requireApproval,
    'allow_guest_view': allowGuestView,
    'max_active_per_user': maxActivePerUser,
    'max_images_per_ilan': maxImagesPerIlan,
    'default_expiry_days': defaultExpiryDays,
    'home_category_limit': homeCategoryLimit,
    'home_ilan_limit': homeIlanLimit,
    'show_prices_on_home': showPricesOnHome,
  };

  IlanSettings copyWith({
    bool? isEnabled,
    bool? allowUserCreate,
    bool? requireApproval,
    bool? allowGuestView,
    int? maxActivePerUser,
    int? maxImagesPerIlan,
    int? defaultExpiryDays,
    int? homeCategoryLimit,
    int? homeIlanLimit,
    bool? showPricesOnHome,
  }) => IlanSettings(
    isEnabled: isEnabled ?? this.isEnabled,
    allowUserCreate: allowUserCreate ?? this.allowUserCreate,
    requireApproval: requireApproval ?? this.requireApproval,
    allowGuestView: allowGuestView ?? this.allowGuestView,
    maxActivePerUser: maxActivePerUser ?? this.maxActivePerUser,
    maxImagesPerIlan: maxImagesPerIlan ?? this.maxImagesPerIlan,
    defaultExpiryDays: defaultExpiryDays ?? this.defaultExpiryDays,
    homeCategoryLimit: homeCategoryLimit ?? this.homeCategoryLimit,
    homeIlanLimit: homeIlanLimit ?? this.homeIlanLimit,
    showPricesOnHome: showPricesOnHome ?? this.showPricesOnHome,
  );
}

class IlanCategory {
  const IlanCategory({
    required this.id,
    required this.name,
    required this.slug,
    required this.description,
    required this.iconName,
    required this.colorHex,
    required this.type,
    required this.pricingMode,
    required this.allowedConditions,
    required this.isActive,
    required this.sortOrder,
    this.publishFee = 0,
  });

  final String id;
  final String name;
  final String slug;
  final String? description;
  final String iconName;
  final String colorHex;
  final IlanCategoryType type;
  final IlanPricingMode pricingMode;
  final List<String> allowedConditions;
  final bool isActive;
  final int sortOrder;
  final double publishFee;

  bool get allowsPrice => pricingMode != IlanPricingMode.forbidden;
  bool get requiresPrice => pricingMode == IlanPricingMode.required;
  bool get isPaidToPublish => publishFee > 0;

  factory IlanCategory.fromJson(Map<String, dynamic> json) => IlanCategory(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'Kategori',
    slug: json['slug'] as String? ?? '',
    description: json['description'] as String?,
    iconName: json['icon_name'] as String? ?? 'category',
    colorHex: json['color_hex'] as String? ?? '#6D28D9',
    type: IlanCategoryType.values.firstWhere(
      (value) => value.name == json['category_type'],
      orElse: () => IlanCategoryType.other,
    ),
    pricingMode: IlanPricingMode.values.firstWhere(
      (value) => value.name == json['pricing_mode'],
      orElse: () => IlanPricingMode.optional,
    ),
    allowedConditions: List<String>.from(
      json['allowed_conditions'] as List? ?? const [],
    ),
    isActive: json['is_active'] as bool? ?? true,
    sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    publishFee: (json['publish_fee'] as num?)?.toDouble() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    if (id.isNotEmpty) 'id': id,
    'name': name.trim(),
    'slug': slug.trim(),
    'description': description?.trim(),
    'icon_name': iconName,
    'color_hex': colorHex,
    'category_type': type.name,
    'pricing_mode': pricingMode.name,
    'allowed_conditions': allowedConditions,
    'is_active': isActive,
    'sort_order': sortOrder,
    'publish_fee': publishFee,
  };
}

class IlanImage {
  const IlanImage({
    required this.id,
    required this.url,
    required this.sortOrder,
  });
  final String id;
  final String url;
  final int sortOrder;

  factory IlanImage.fromJson(Map<String, dynamic> json) => IlanImage(
    id: json['id'] as String,
    url: json['image_url'] as String? ?? '',
    sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
  );
}

class Ilan {
  const Ilan({
    required this.id,
    required this.ownerId,
    required this.categoryId,
    required this.title,
    required this.description,
    required this.status,
    required this.city,
    required this.district,
    required this.createdAt,
    required this.viewCount,
    required this.favoriteCount,
    this.category,
    this.price,
    this.currency,
    this.isNegotiable = false,
    this.itemCondition,
    this.neighborhood,
    this.contactPhone,
    this.contactPreference = 'app',
    this.coverImageUrl,
    this.images = const [],
    this.ownerName,
    this.ownerAvatarUrl,
    this.rejectionReason,
    this.publishedAt,
    this.expiresAt,
    this.attributes = const {},
    this.paidFee = 0,
    this.feeRefunded = false,
  });

  final String id;
  final String ownerId;
  final String categoryId;
  final String title;
  final String description;
  final IlanStatus status;
  final IlanCategory? category;
  final double? price;
  final String? currency;
  final bool isNegotiable;
  final String? itemCondition;
  final String city;
  final String district;
  final String? neighborhood;
  final String? contactPhone;
  final String contactPreference;
  final String? coverImageUrl;
  final List<IlanImage> images;
  final String? ownerName;
  final String? ownerAvatarUrl;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime? publishedAt;
  final DateTime? expiresAt;
  final int viewCount;
  final int favoriteCount;
  final Map<String, dynamic> attributes;
  final double paidFee;
  final bool feeRefunded;

  bool get hasPrice => category?.allowsPrice != false && price != null;
  String get locationText => [
    neighborhood,
    district,
    city,
  ].where((value) => value != null && value.trim().isNotEmpty).join(', ');

  factory Ilan.fromJson(Map<String, dynamic> json) {
    final categoryJson = json['ilan_categories'];
    final imagesJson = json['ilan_images'];
    final profileJson = json['profiles'];
    return Ilan(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      categoryId: json['category_id'] as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      status: IlanStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => IlanStatus.pending,
      ),
      category: categoryJson is Map<String, dynamic>
          ? IlanCategory.fromJson(categoryJson)
          : categoryJson is Map
          ? IlanCategory.fromJson(Map<String, dynamic>.from(categoryJson))
          : null,
      price: (json['price'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      isNegotiable: json['is_negotiable'] as bool? ?? false,
      itemCondition: json['item_condition'] as String?,
      city: json['city'] as String? ?? 'Şırnak',
      district: json['district'] as String? ?? 'Cizre',
      neighborhood: json['neighborhood'] as String?,
      contactPhone: json['contact_phone'] as String?,
      contactPreference: json['contact_preference'] as String? ?? 'app',
      coverImageUrl: json['cover_image_url'] as String?,
      images: imagesJson is List
          ? imagesJson
                .map(
                  (item) => IlanImage.fromJson(
                    Map<String, dynamic>.from(item as Map),
                  ),
                )
                .toList()
          : const [],
      ownerName: profileJson is Map
          ? (profileJson['full_name'] ?? profileJson['username']) as String?
          : null,
      ownerAvatarUrl: profileJson is Map
          ? profileJson['avatar_url'] as String?
          : null,
      rejectionReason: json['rejection_reason'] as String?,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
      viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
      favoriteCount: (json['favorite_count'] as num?)?.toInt() ?? 0,
      attributes: Map<String, dynamic>.from(
        json['attributes'] as Map? ?? const {},
      ),
      paidFee: (json['paid_fee'] as num?)?.toDouble() ?? 0,
      feeRefunded: json['fee_refunded'] as bool? ?? false,
    );
  }
}
