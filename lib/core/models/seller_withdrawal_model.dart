/// Çekim Durumu
enum WithdrawalStatus {
  pending,
  processing,
  completed,
  failed,
  cancelled;

  String get label {
    switch (this) {
      case WithdrawalStatus.pending:
        return 'Beklemede';
      case WithdrawalStatus.processing:
        return 'İşleniyor';
      case WithdrawalStatus.completed:
        return 'Tamamlandı';
      case WithdrawalStatus.failed:
        return 'Başarısız';
      case WithdrawalStatus.cancelled:
        return 'İptal Edildi';
    }
  }

  String get dbValue {
    switch (this) {
      case WithdrawalStatus.pending:
        return 'pending';
      case WithdrawalStatus.processing:
        return 'processing';
      case WithdrawalStatus.completed:
        return 'completed';
      case WithdrawalStatus.failed:
        return 'failed';
      case WithdrawalStatus.cancelled:
        return 'cancelled';
    }
  }

  static WithdrawalStatus fromString(String value) {
    switch (value) {
      case 'pending':
        return WithdrawalStatus.pending;
      case 'processing':
        return WithdrawalStatus.processing;
      case 'completed':
        return WithdrawalStatus.completed;
      case 'failed':
        return WithdrawalStatus.failed;
      case 'cancelled':
        return WithdrawalStatus.cancelled;
      default:
        return WithdrawalStatus.pending;
    }
  }
}

/// Satıcı Çekim Modeli
class SellerWithdrawal {
  final String id;
  final String sellerId;
  final double amount;
  final double feePercent;
  final double fee;
  final double netAmount;
  final WithdrawalStatus status;
  final String? bankAccountName;
  final String? bankAccountNumber;
  final String? bankName;
  final String? iban;
  final DateTime? processedAt;
  final String? failureReason;
  final String? adminNotes;
  final String? adminId;
  final DateTime createdAt;
  final DateTime updatedAt;

  SellerWithdrawal({
    required this.id,
    required this.sellerId,
    required this.amount,
    this.feePercent = 2,
    this.fee = 0,
    required this.netAmount,
    required this.status,
    this.bankAccountName,
    this.bankAccountNumber,
    this.bankName,
    this.iban,
    this.processedAt,
    this.failureReason,
    this.adminNotes,
    this.adminId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// IBAN maskelenmiş gösterim
  String get maskedIban {
    if (iban == null || iban!.length < 8) return iban ?? '';
    final start = iban!.substring(0, 4);
    final end = iban!.substring(iban!.length - 4);
    return '$start****$end';
  }

  /// Tarih formatı
  String get formattedDate {
    return '${createdAt.day}.${createdAt.month.toString().padLeft(2, '0')}.${createdAt.year}';
  }

  /// İşlem tarihi
  String? get formattedProcessDate {
    if (processedAt == null) return null;
    return '${processedAt!.day}.${processedAt!.month.toString().padLeft(2, '0')}.${processedAt!.year}';
  }

  /// Aktif mi? (işlem bekliyor)
  bool get isActive => status == WithdrawalStatus.pending || status == WithdrawalStatus.processing;

  factory SellerWithdrawal.fromJson(Map<String, dynamic> json) {
    return SellerWithdrawal(
      id: json['id'] as String? ?? '',
      sellerId: json['seller_id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      feePercent: (json['fee_percent'] as num?)?.toDouble() ?? 2,
      fee: (json['fee'] as num?)?.toDouble() ?? 0,
      netAmount: (json['net_amount'] as num?)?.toDouble() ?? 0,
      status: WithdrawalStatus.fromString(json['status'] as String? ?? 'pending'),
      bankAccountName: json['bank_account_name'] as String?,
      bankAccountNumber: json['bank_account_number'] as String?,
      bankName: json['bank_name'] as String?,
      iban: json['iban'] as String?,
      processedAt: json['processed_at'] != null
          ? DateTime.parse(json['processed_at'] as String)
          : null,
      failureReason: json['failure_reason'] as String?,
      adminNotes: json['admin_notes'] as String?,
      adminId: json['admin_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'seller_id': sellerId,
      'amount': amount,
      'fee_percent': feePercent,
      'fee': fee,
      'net_amount': netAmount,
      'status': status.dbValue,
      'bank_account_name': bankAccountName,
      'bank_account_number': bankAccountNumber,
      'bank_name': bankName,
      'iban': iban,
      'processed_at': processedAt?.toIso8601String(),
      'failure_reason': failureReason,
      'admin_notes': adminNotes,
      'admin_id': adminId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  SellerWithdrawal copyWith({
    String? id,
    String? sellerId,
    double? amount,
    double? feePercent,
    double? fee,
    double? netAmount,
    WithdrawalStatus? status,
    String? bankAccountName,
    String? bankAccountNumber,
    String? bankName,
    String? iban,
    DateTime? processedAt,
    String? failureReason,
    String? adminNotes,
    String? adminId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SellerWithdrawal(
      id: id ?? this.id,
      sellerId: sellerId ?? this.sellerId,
      amount: amount ?? this.amount,
      feePercent: feePercent ?? this.feePercent,
      fee: fee ?? this.fee,
      netAmount: netAmount ?? this.netAmount,
      status: status ?? this.status,
      bankAccountName: bankAccountName ?? this.bankAccountName,
      bankAccountNumber: bankAccountNumber ?? this.bankAccountNumber,
      bankName: bankName ?? this.bankName,
      iban: iban ?? this.iban,
      processedAt: processedAt ?? this.processedAt,
      failureReason: failureReason ?? this.failureReason,
      adminNotes: adminNotes ?? this.adminNotes,
      adminId: adminId ?? this.adminId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
