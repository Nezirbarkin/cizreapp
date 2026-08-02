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

enum DigitalOrderReconciliationStatus {
  notRequired,
  pendingProvider,
  reconciliationPending,
  settled,
  refundComplete,
  unknown;

  static DigitalOrderReconciliationStatus fromDbValue(Object? value) =>
      switch (value) {
        'not_required' => DigitalOrderReconciliationStatus.notRequired,
        'pending_provider' => DigitalOrderReconciliationStatus.pendingProvider,
        'reconciliation_pending' =>
          DigitalOrderReconciliationStatus.reconciliationPending,
        'settled' => DigitalOrderReconciliationStatus.settled,
        'refund_complete' => DigitalOrderReconciliationStatus.refundComplete,
        _ => DigitalOrderReconciliationStatus.unknown,
      };

  bool get isPending =>
      this == DigitalOrderReconciliationStatus.reconciliationPending;
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
  final double grossTotalTry;
  final int pointsSpent;
  final int pointsPerTrySnapshot;
  final double pointsDiscountTry;
  final double cashBalancePaidTry;
  final int paymentCompositionVersion;
  final int refundPointsTotal;
  final double refundCashTotalTry;
  final double refundGrossTotalTry;
  final DigitalOrderReconciliationStatus reconciliationStatus;
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
    required this.grossTotalTry,
    this.pointsSpent = 0,
    this.pointsPerTrySnapshot = 100,
    this.pointsDiscountTry = 0,
    required this.cashBalancePaidTry,
    this.paymentCompositionVersion = 1,
    this.refundPointsTotal = 0,
    this.refundCashTotalTry = 0,
    this.refundGrossTotalTry = 0,
    this.reconciliationStatus = DigitalOrderReconciliationStatus.notRequired,
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
    final total =
        (json['total_price'] as num?)?.toDouble() ??
        (json['gross_total_try'] as num?)?.toDouble() ??
        0;
    return DigitalOrder(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      productId: json['product_id'] as String,
      providerId: json['provider_id'] as String,
      targetUrl: json['target_url'] as String,
      quantity: json['quantity'] as int,
      unitPrice: (json['unit_price'] as num).toDouble(),
      totalPrice: total,
      grossTotalTry: (json['gross_total_try'] as num?)?.toDouble() ?? total,
      pointsSpent: (json['points_spent'] as num?)?.toInt() ?? 0,
      pointsPerTrySnapshot:
          (json['points_per_try_snapshot'] as num?)?.toInt() ?? 100,
      pointsDiscountTry: (json['points_discount_try'] as num?)?.toDouble() ?? 0,
      cashBalancePaidTry:
          (json['cash_balance_paid_try'] as num?)?.toDouble() ?? total,
      paymentCompositionVersion:
          (json['payment_composition_version'] as num?)?.toInt() ?? 1,
      refundPointsTotal: (json['refund_points_total'] as num?)?.toInt() ?? 0,
      refundCashTotalTry:
          (json['refund_cash_total_try'] as num?)?.toDouble() ?? 0,
      refundGrossTotalTry:
          (json['refund_gross_total_try'] as num?)?.toDouble() ?? 0,
      reconciliationStatus: DigitalOrderReconciliationStatus.fromDbValue(
        json['reconciliation_status'],
      ),
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

  bool get hasPointComponent => pointsSpent > 0;
  bool get hasRefund => refundPointsTotal > 0 || refundCashTotalTry > 0;
  bool get reconciliationPending => reconciliationStatus.isPending;

  String get paymentCompositionLabel {
    final parts = <String>[];
    if (pointsSpent > 0) parts.add('$pointsSpent puan');
    if (cashBalancePaidTry > 0 || parts.isEmpty) {
      parts.add('${cashBalancePaidTry.toStringAsFixed(2)} TL');
    }
    return parts.join(' + ');
  }

  String get refundCompositionLabel {
    final parts = <String>[];
    if (refundPointsTotal > 0) parts.add('$refundPointsTotal puan');
    if (refundCashTotalTry > 0) {
      parts.add('${refundCashTotalTry.toStringAsFixed(2)} TL');
    }
    return parts.join(' + ');
  }
}
