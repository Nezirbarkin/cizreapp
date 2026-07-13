enum DigitalOrderStatus {
  pending,
  inProgress,
  completed,
  partial,
  canceled,
  refunded,
  failed;

  static DigitalOrderStatus fromDbValue(String value) {
    switch (value) {
      case 'pending':
        return DigitalOrderStatus.pending;
      case 'in_progress':
        return DigitalOrderStatus.inProgress;
      case 'completed':
        return DigitalOrderStatus.completed;
      case 'partial':
        return DigitalOrderStatus.partial;
      case 'canceled':
        return DigitalOrderStatus.canceled;
      case 'refunded':
        return DigitalOrderStatus.refunded;
      case 'failed':
        return DigitalOrderStatus.failed;
      default:
        return DigitalOrderStatus.pending;
    }
  }

  String get dbValue {
    switch (this) {
      case DigitalOrderStatus.pending:
        return 'pending';
      case DigitalOrderStatus.inProgress:
        return 'in_progress';
      case DigitalOrderStatus.completed:
        return 'completed';
      case DigitalOrderStatus.partial:
        return 'partial';
      case DigitalOrderStatus.canceled:
        return 'canceled';
      case DigitalOrderStatus.refunded:
        return 'refunded';
      case DigitalOrderStatus.failed:
        return 'failed';
    }
  }

  String get label {
    switch (this) {
      case DigitalOrderStatus.pending:
        return 'Bekliyor';
      case DigitalOrderStatus.inProgress:
        return 'İşlemde';
      case DigitalOrderStatus.completed:
        return 'Tamamlandı';
      case DigitalOrderStatus.partial:
        return 'Kısmi Tamamlandı';
      case DigitalOrderStatus.canceled:
        return 'İptal Edildi';
      case DigitalOrderStatus.refunded:
        return 'İade Edildi';
      case DigitalOrderStatus.failed:
        return 'Başarısız';
    }
  }
}

class DigitalOrder {
  final String id;
  final String userId;
  final String productId;
  final String providerId;
  final String targetUrl;
  final int quantity;
  final double unitPrice;
  final double totalPrice;
  final String? externalOrderId;
  final DigitalOrderStatus status;
  final int? startCount;
  final int? remains;
  final DateTime? lastCheckedAt;
  final String? errorMessage;
  final DateTime createdAt;
  final bool sellerCredited;
  final double? commissionAmount;
  final double? netSellerAmount;

  // Sipariş listesinde gösterim için join edilen ürün adı (opsiyonel)
  final String? productName;

  DigitalOrder({
    required this.id,
    required this.userId,
    required this.productId,
    required this.providerId,
    required this.targetUrl,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    this.externalOrderId,
    required this.status,
    this.startCount,
    this.remains,
    this.lastCheckedAt,
    this.errorMessage,
    required this.createdAt,
    this.sellerCredited = false,
    this.commissionAmount,
    this.netSellerAmount,
    this.productName,
  });

  factory DigitalOrder.fromJson(Map<String, dynamic> json) {
    return DigitalOrder(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      productId: json['product_id'] as String,
      providerId: json['provider_id'] as String,
      targetUrl: json['target_url'] as String,
      quantity: json['quantity'] as int,
      unitPrice: (json['unit_price'] as num).toDouble(),
      totalPrice: (json['total_price'] as num).toDouble(),
      externalOrderId: json['external_order_id'] as String?,
      status: DigitalOrderStatus.fromDbValue(json['status'] as String),
      startCount: json['start_count'] as int?,
      remains: json['remains'] as int?,
      lastCheckedAt: json['last_checked_at'] != null
          ? DateTime.parse(json['last_checked_at'] as String)
          : null,
      errorMessage: json['error_message'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      sellerCredited: json['seller_credited'] as bool? ?? false,
      commissionAmount: (json['commission_amount'] as num?)?.toDouble(),
      netSellerAmount: (json['net_seller_amount'] as num?)?.toDouble(),
      productName: json['products'] != null
          ? (json['products'] as Map<String, dynamic>)['name'] as String?
          : null,
    );
  }
}
