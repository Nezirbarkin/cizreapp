/// Banka Hesabı Modeli
class BankAccount {
  final String id;
  final String bankName;
  final String iban;
  final String accountName;
  final String? branch;
  final String? accountNumber;
  final String? description;
  final bool isActive;
  final int displayOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  BankAccount({
    required this.id,
    required this.bankName,
    required this.iban,
    required this.accountName,
    this.branch,
    this.accountNumber,
    this.description,
    this.isActive = true,
    this.displayOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Maskelenmiş IBAN (TR12 **** 1234)
  String get maskedIban {
    if (iban.length >= 8) {
      return '${iban.substring(0, 4)} **** **** ${iban.substring(iban.length - 4)}';
    }
    return iban;
  }

  factory BankAccount.fromJson(Map<String, dynamic> json) {
    return BankAccount(
      id: json['id'] as String? ?? '',
      bankName: json['bank_name'] as String? ?? '',
      iban: json['iban'] as String? ?? '',
      accountName: json['account_name'] as String? ?? '',
      branch: json['branch'] as String?,
      accountNumber: json['account_number'] as String?,
      description: json['description'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      displayOrder: json['display_order'] as int? ?? 0,
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
      'bank_name': bankName,
      'iban': iban,
      'account_name': accountName,
      'branch': branch,
      'account_number': accountNumber,
      'description': description,
      'is_active': isActive,
      'display_order': displayOrder,
    };
  }
}