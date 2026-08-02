enum RewardSessionStatus {
  initiated,
  pendingSsv,
  verified,
  credited,
  blocked,
  rejected,
  duplicate,
  expired,
  unknown;

  static RewardSessionStatus fromJson(Object? value) => switch (value) {
    'initiated' => RewardSessionStatus.initiated,
    'pending_ssv' => RewardSessionStatus.pendingSsv,
    'verified' => RewardSessionStatus.verified,
    'credited' => RewardSessionStatus.credited,
    'blocked' => RewardSessionStatus.blocked,
    'rejected' => RewardSessionStatus.rejected,
    'duplicate' => RewardSessionStatus.duplicate,
    'expired' => RewardSessionStatus.expired,
    _ => RewardSessionStatus.unknown,
  };

  bool get isTerminal => switch (this) {
    RewardSessionStatus.credited ||
    RewardSessionStatus.blocked ||
    RewardSessionStatus.rejected ||
    RewardSessionStatus.duplicate ||
    RewardSessionStatus.expired => true,
    _ => false,
  };
}

enum RewardSessionEnvironment {
  production,
  test,
  unknown;

  static RewardSessionEnvironment fromJson(Object? value) => switch (value) {
    'production' => RewardSessionEnvironment.production,
    'test' => RewardSessionEnvironment.test,
    _ => RewardSessionEnvironment.unknown,
  };
}

class RewardSession {
  final String id;
  final RewardSessionStatus status;
  final DateTime expiresAt;
  final int policyVersion;
  final int? creditedPoints;
  final String? customData;
  final RewardSessionEnvironment environment;

  const RewardSession({
    required this.id,
    required this.status,
    required this.expiresAt,
    required this.policyVersion,
    this.creditedPoints,
    this.customData,
    this.environment = RewardSessionEnvironment.unknown,
  });

  factory RewardSession.fromJson(Map<String, dynamic> json) {
    return RewardSession(
      id: (json['reward_session_id'] ?? json['id']) as String,
      status: RewardSessionStatus.fromJson(json['status']),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      policyVersion: (json['policy_version'] as num?)?.toInt() ?? 0,
      creditedPoints:
          (json['credited_points'] as num?)?.toInt() ??
          (json['reward_points'] as num?)?.toInt(),
      customData: json['custom_data'] as String?,
      environment: RewardSessionEnvironment.fromJson(json['environment']),
    );
  }
}

enum RewardVerificationState { credited, duplicate, rejected, expired, pending }

class RewardVerificationOutcome {
  final RewardVerificationState state;
  final RewardSession? session;

  const RewardVerificationOutcome(this.state, {this.session});

  int? get creditedPoints => session?.creditedPoints;
}
