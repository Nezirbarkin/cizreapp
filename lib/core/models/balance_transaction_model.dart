/// Bakiye İşlem Türü
enum BalanceTransactionType {
  topup,         // Bakiye yükleme
  orderPayment,  // Sipariş ödemesi
  refund,        // İade
  withdrawal,    // Çekim
  adjustment,    // Manuel düzeltme
  commission,    // Komisyon (satıcı kazancı)
  adReward,      // Reklam ödülü (izleyerek kazan)
  taskReward,    // Görev ödülü (görev yaparak kazan)
}

/// Etiket helper'ları (Dart analyzer v6.4 syntax uyumu için ayrı extension)
extension BalanceTransactionTypeLabel on BalanceTransactionType {
  String get label {
    switch (this) {
      case BalanceTransactionType.topup:
        return 'Bakiye Yükleme';
      case BalanceTransactionType.orderPayment:
        return 'Sipariş Ödemesi';
      case BalanceTransactionType.refund:
        return 'İade';
      case BalanceTransactionType.withdrawal:
        return 'Çekim';
      case BalanceTransactionType.adjustment:
        return 'Düzeltme';
      case BalanceTransactionType.commission:
        return 'Komisyon';
      case BalanceTransactionType.adReward:
        return 'Reklam Ödülü';
      case BalanceTransactionType.taskReward:
        return 'Görev Ödülü';
    }
  }

  String get dbValue {
    switch (this) {
      case BalanceTransactionType.topup:
        return 'topup';
      case BalanceTransactionType.orderPayment:
        return 'order_payment';
      case BalanceTransactionType.refund:
        return 'refund';
      case BalanceTransactionType.withdrawal:
        return 'withdrawal';
      case BalanceTransactionType.adjustment:
        return 'adjustment';
      case BalanceTransactionType.commission:
        return 'commission';
      case BalanceTransactionType.adReward:
        return 'ad_reward';
      case BalanceTransactionType.taskReward:
        return 'task_reward';
    }
  }

  /// Pozitif tutar mı? (yükleme, iade, komisyon, ödüller)
  bool get isPositive {
    return this == BalanceTransactionType.topup ||
        this == BalanceTransactionType.refund ||
        this == BalanceTransactionType.commission ||
        this == BalanceTransactionType.adReward ||
        this == BalanceTransactionType.taskReward;
  }

  /// Negatif tutar mı? (ödeme, çekim)
  bool get isNegative {
    return this == BalanceTransactionType.orderPayment ||
        this == BalanceTransactionType.withdrawal;
  }

  static BalanceTransactionType fromString(String value) {
    switch (value) {
      case 'topup':
        return BalanceTransactionType.topup;
      case 'order_payment':
        return BalanceTransactionType.orderPayment;
      case 'refund':
        return BalanceTransactionType.refund;
      case 'withdrawal':
        return BalanceTransactionType.withdrawal;
      case 'adjustment':
        return BalanceTransactionType.adjustment;
      case 'commission':
        return BalanceTransactionType.commission;
      case 'ad_reward':
        return BalanceTransactionType.adReward;
      case 'task_reward':
        return BalanceTransactionType.taskReward;
      default:
        return BalanceTransactionType.topup;
    }
  }
}

/// Bakiye İşlem Durumu
enum BalanceTransactionStatus {
  pending,
  completed,
  failed,
  cancelled,
}

/// Bakiye İşlem Modeli
class BalanceTransaction {
  final String id;
  final String userId;
  final BalanceTransactionType type;
  final double amount;
  final double fee;
  final double netAmount;
  final double balanceBefore;
  final double balanceAfter;
  final String? referenceType;
  final String? referenceId;
  final BalanceTransactionStatus status;
  final String? description;
  final String? paymentMethod;
  final String? paymentReference;
  final Map<String, dynamic>? metadata;
  final String? bankName;
  final String? bankIban;
  final String? bankAccountName;
  final DateTime createdAt;

  BalanceTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    this.fee = 0,
    required this.netAmount,
    required this.balanceBefore,
    required this.balanceAfter,
    this.referenceType,
    this.referenceId,
    required this.status,
    this.description,
    this.paymentMethod,
    this.paymentReference,
    this.metadata,
    this.bankName,
    this.bankIban,
    this.bankAccountName,
    required this.createdAt,
  });

  /// İşlem pozitif mi? (bakiye artışı)
  bool get isPositive => type.isPositive;

  /// İşlem negatif mi? (bakiye düşüşü)
  bool get isNegative => type.isNegative;

  /// Değişim tutarı (pozitif veya negatif)
  double get changeAmount => isPositive ? netAmount : -netAmount;

  /// Asıl tutar (mutlak değer)
  double get absoluteAmount => amount.abs();

  /// Tarih formatı
  String get formattedDate {
    return '${createdAt.day}.${createdAt.month.toString().padLeft(2, '0')}.${createdAt.year} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
  }

  /// Kısa tarih
  String get shortDate {
    return '${createdAt.day}.${createdAt.month.toString().padLeft(2, '0')}.${createdAt.year}';
  }

  factory BalanceTransaction.fromJson(Map<String, dynamic> json) {
    return BalanceTransaction(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      type: BalanceTransactionTypeLabel.fromString(json['type'] as String? ?? 'topup'),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      fee: (json['fee'] as num?)?.toDouble() ?? 0,
      netAmount: (json['net_amount'] as num?)?.toDouble() ?? 0,
      balanceBefore: (json['balance_before'] as num?)?.toDouble() ?? 0,
      balanceAfter: (json['balance_after'] as num?)?.toDouble() ?? 0,
      referenceType: json['reference_type'] as String?,
      referenceId: json['reference_id'] as String?,
      status: _statusFromString(json['status'] as String? ?? 'pending'),
      description: json['description'] as String?,
      paymentMethod: json['payment_method'] as String?,
      paymentReference: json['payment_reference'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      bankName: json['bank_name'] as String?,
      bankIban: json['bank_iban'] as String?,
      bankAccountName: json['bank_account_name'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'type': type.dbValue,
      'amount': amount,
      'fee': fee,
      'net_amount': netAmount,
      'balance_before': balanceBefore,
      'balance_after': balanceAfter,
      'reference_type': referenceType,
      'reference_id': referenceId,
      'status': status.name,
      'description': description,
      'payment_method': paymentMethod,
      'payment_reference': paymentReference,
      'metadata': metadata,
      'bank_name': bankName,
      'bank_iban': bankIban,
      'bank_account_name': bankAccountName,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// İşlem Geçmişi Sayfalama
class BalanceTransactionPage {
  final List<BalanceTransaction> transactions;
  final int page;
  final int limit;
  final int total;
  final int totalPages;
  final bool hasMore;

  BalanceTransactionPage({
    required this.transactions,
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
    required this.hasMore,
  });

  factory BalanceTransactionPage.fromJson(Map<String, dynamic> json) {
    final pagination = json['pagination'] as Map<String, dynamic>? ?? {};
    final transactionsList = json['transactions'] as List? ?? [];

    return BalanceTransactionPage(
      transactions: transactionsList
          .map((e) => BalanceTransaction.fromJson(e as Map<String, dynamic>))
          .toList(),
      page: pagination['page'] as int? ?? 1,
      limit: pagination['limit'] as int? ?? 20,
      total: pagination['total'] as int? ?? 0,
      totalPages: pagination['total_pages'] as int? ?? 0,
      hasMore: pagination['has_more'] as bool? ?? false,
    );
  }
}

// Yardımcı fonksiyonlar — enum extension'larını ayırdığımız için
// label/StatusString de buraya taşındı (analyzer uyumluluğu).
String _statusLabel(BalanceTransactionStatus status) {
  switch (status) {
    case BalanceTransactionStatus.pending:
      return 'Beklemede';
    case BalanceTransactionStatus.completed:
      return 'Tamamlandı';
    case BalanceTransactionStatus.failed:
      return 'Başarısız';
    case BalanceTransactionStatus.cancelled:
      return 'İptal Edildi';
  }
}

BalanceTransactionStatus _statusFromString(String value) {
  switch (value) {
    case 'pending':
      return BalanceTransactionStatus.pending;
    case 'completed':
      return BalanceTransactionStatus.completed;
    case 'failed':
      return BalanceTransactionStatus.failed;
    case 'cancelled':
      return BalanceTransactionStatus.cancelled;
    default:
      return BalanceTransactionStatus.pending;
  }
}
