class DailyDeal {
  final String id;
  final String title;
  final String? subtitle;
  final String imageUrl;
  final String linkType; // 'shop', 'campaign', 'category', 'product'
  final String? linkId;
  final String? linkUrl;
  final String dealType; // 'image' veya 'html'
  final String? htmlContent; // HTML iframe içeriği
  final int sortOrder;
  final bool isActive;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  DailyDeal({
    required this.id,
    required this.title,
    this.subtitle,
    required this.imageUrl,
    required this.linkType,
    this.linkId,
    this.linkUrl,
    this.dealType = 'image',
    this.htmlContent,
    this.sortOrder = 0,
    this.isActive = true,
    this.startDate,
    this.endDate,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DailyDeal.fromJson(Map<String, dynamic> json) {
    return DailyDeal(
      id: json['id'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String?,
      imageUrl: json['image_url'] as String,
      linkType: json['link_type'] as String? ?? 'shop',
      linkId: json['link_id'] as String?,
      linkUrl: json['link_url'] as String?,
      dealType: json['deal_type'] as String? ?? 'image',
      htmlContent: json['html_content'] as String?,
      sortOrder: json['sort_order'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      startDate: json['start_date'] != null ? DateTime.parse(json['start_date'] as String) : null,
      endDate: json['end_date'] != null ? DateTime.parse(json['end_date'] as String) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'image_url': imageUrl,
      'link_type': linkType,
      'link_id': linkId,
      'link_url': linkUrl,
      'deal_type': dealType,
      'html_content': htmlContent,
      'sort_order': sortOrder,
      'is_active': isActive,
      'start_date': startDate?.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  DailyDeal copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? imageUrl,
    String? linkType,
    String? linkId,
    String? linkUrl,
    String? dealType,
    String? htmlContent,
    int? sortOrder,
    bool? isActive,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DailyDeal(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      imageUrl: imageUrl ?? this.imageUrl,
      linkType: linkType ?? this.linkType,
      linkId: linkId ?? this.linkId,
      linkUrl: linkUrl ?? this.linkUrl,
      dealType: dealType ?? this.dealType,
      htmlContent: htmlContent ?? this.htmlContent,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
