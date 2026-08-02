enum FraudSignalType {
  multipleAccounts,
  unusualReturns,
  couponAbuse,
  fakeReviews,
}

enum FraudSignalStatus { open, reviewing, confirmed, dismissed }

class FraudSignal {
  const FraudSignal({
    required this.id,
    required this.userId,
    required this.signalType,
    required this.severity,
    required this.riskScore,
    required this.status,
    required this.title,
    required this.description,
    required this.evidence,
    required this.occurrenceCount,
    required this.firstDetectedAt,
    required this.lastDetectedAt,
    this.userName,
    this.userEmail,
    this.reviewedAt,
    this.adminNote,
  });

  final String id;
  final String userId;
  final String? userName;
  final String? userEmail;
  final FraudSignalType signalType;
  final String severity;
  final int riskScore;
  final FraudSignalStatus status;
  final String title;
  final String description;
  final Map<String, dynamic> evidence;
  final int occurrenceCount;
  final DateTime firstDetectedAt;
  final DateTime lastDetectedAt;
  final DateTime? reviewedAt;
  final String? adminNote;

  factory FraudSignal.fromJson(Map<String, dynamic> json) {
    return FraudSignal(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      userName: json['user_name'] as String?,
      userEmail: json['user_email'] as String?,
      signalType: _parseType(json['signal_type'] as String?),
      severity: json['severity'] as String? ?? 'low',
      riskScore: (json['risk_score'] as num?)?.toInt() ?? 0,
      status: _parseStatus(json['status'] as String?),
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      evidence: Map<String, dynamic>.from(
        json['evidence'] as Map? ?? const <String, dynamic>{},
      ),
      occurrenceCount: (json['occurrence_count'] as num?)?.toInt() ?? 1,
      firstDetectedAt: DateTime.parse(json['first_detected_at'] as String),
      lastDetectedAt: DateTime.parse(json['last_detected_at'] as String),
      reviewedAt: json['reviewed_at'] == null
          ? null
          : DateTime.parse(json['reviewed_at'] as String),
      adminNote: json['admin_note'] as String?,
    );
  }

  static FraudSignalType _parseType(String? value) => switch (value) {
    'multiple_accounts' => FraudSignalType.multipleAccounts,
    'unusual_returns' => FraudSignalType.unusualReturns,
    'coupon_abuse' => FraudSignalType.couponAbuse,
    _ => FraudSignalType.fakeReviews,
  };

  static FraudSignalStatus _parseStatus(String? value) => switch (value) {
    'reviewing' => FraudSignalStatus.reviewing,
    'confirmed' => FraudSignalStatus.confirmed,
    'dismissed' => FraudSignalStatus.dismissed,
    _ => FraudSignalStatus.open,
  };
}

extension FraudSignalTypeX on FraudSignalType {
  String get databaseValue => switch (this) {
    FraudSignalType.multipleAccounts => 'multiple_accounts',
    FraudSignalType.unusualReturns => 'unusual_returns',
    FraudSignalType.couponAbuse => 'coupon_abuse',
    FraudSignalType.fakeReviews => 'fake_reviews',
  };

  String get label => switch (this) {
    FraudSignalType.multipleAccounts => 'Çoklu hesap',
    FraudSignalType.unusualReturns => 'Sıra dışı iade',
    FraudSignalType.couponAbuse => 'Kupon suistimali',
    FraudSignalType.fakeReviews => 'Sahte değerlendirme',
  };
}

extension FraudSignalStatusX on FraudSignalStatus {
  String get databaseValue => name;

  String get label => switch (this) {
    FraudSignalStatus.open => 'Açık',
    FraudSignalStatus.reviewing => 'İnceleniyor',
    FraudSignalStatus.confirmed => 'Onaylandı',
    FraudSignalStatus.dismissed => 'Reddedildi',
  };
}
