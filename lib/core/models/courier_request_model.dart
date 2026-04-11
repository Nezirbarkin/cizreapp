// Kurye Talep Modeli
// Satıcıların kurye taleplerini yönetmek için kullanılır

enum CourierRequestStatus {
  pending,   // Beklemede
  approved,  // Onaylandı
  rejected;  // Reddedildi

  String get label {
    switch (this) {
      case CourierRequestStatus.pending:
        return 'Beklemede';
      case CourierRequestStatus.approved:
        return 'Onaylandı';
      case CourierRequestStatus.rejected:
        return 'Reddedildi';
    }
  }

  String get dbValue => name;

  static CourierRequestStatus fromString(String value) {
    return CourierRequestStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => CourierRequestStatus.pending,
    );
  }
}

class CourierRequest {
  final String id;
  final String shopId;
  final String sellerId;
  final CourierRequestStatus status;
  final String? message;       // Satıcının mesajı
  final String? adminNotes;    // Admin'in notu
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? reviewedAt;  // Admin'in incelediği zaman
  final String? reviewedBy;    // Admin'in ID'si
  
  // İlişkili veriler
  final String? shopName;
  final String? sellerName;
  final String? sellerEmail;

  CourierRequest({
    required this.id,
    required this.shopId,
    required this.sellerId,
    required this.status,
    this.message,
    this.adminNotes,
    required this.createdAt,
    required this.updatedAt,
    this.reviewedAt,
    this.reviewedBy,
    this.shopName,
    this.sellerName,
    this.sellerEmail,
  });

  factory CourierRequest.fromJson(Map<String, dynamic> json) {
    // İlişkili verileri al
    final shops = json['shops'] as Map<String, dynamic>?;
    final profiles = json['profiles'] as Map<String, dynamic>?;
    
    return CourierRequest(
      id: json['id'] as String? ?? '',
      shopId: json['shop_id'] as String? ?? '',
      sellerId: json['seller_id'] as String? ?? '',
      status: CourierRequestStatus.fromString(json['status'] as String? ?? 'pending'),
      message: json['message'] as String?,
      adminNotes: json['admin_notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
      reviewedBy: json['reviewed_by'] as String?,
      shopName: shops?['name'] as String? ?? json['shop_name'] as String?,
      sellerName: profiles?['full_name'] as String? ?? 
                  profiles?['username'] as String? ??
                  json['seller_name'] as String?,
      sellerEmail: profiles?['email'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shop_id': shopId,
      'seller_id': sellerId,
      'status': status.dbValue,
      'message': message,
      'admin_notes': adminNotes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'reviewed_at': reviewedAt?.toIso8601String(),
      'reviewed_by': reviewedBy,
    };
  }

  CourierRequest copyWith({
    String? id,
    String? shopId,
    String? sellerId,
    CourierRequestStatus? status,
    String? message,
    String? adminNotes,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? reviewedAt,
    String? reviewedBy,
    String? shopName,
    String? sellerName,
    String? sellerEmail,
  }) {
    return CourierRequest(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      sellerId: sellerId ?? this.sellerId,
      status: status ?? this.status,
      message: message ?? this.message,
      adminNotes: adminNotes ?? this.adminNotes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      shopName: shopName ?? this.shopName,
      sellerName: sellerName ?? this.sellerName,
      sellerEmail: sellerEmail ?? this.sellerEmail,
    );
  }
}
