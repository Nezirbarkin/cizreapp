import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/profile_feature.dart';

/// purchase-profile-feature Edge Function'ından dönen `error_code` (ör.
/// 'INSUFFICIENT_POINTS', 'REWARD_FEATURE_DISABLED') — UI bunu string
/// eşleştirme yerine doğrudan koda göre dallandırır.
class ProfileFeaturePurchaseException implements Exception {
  final String code;
  const ProfileFeaturePurchaseException(this.code);

  @override
  String toString() => 'ProfileFeaturePurchaseException($code)';
}

class ProfileFeatureService {
  ProfileFeatureService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get client => _client ?? Supabase.instance.client;

  static final Map<String, _FeatureCache> _cache = {};
  static final Map<String, Future<List<ProfileFeature>>> _pending = {};
  static const _cacheDuration = Duration(minutes: 3);

  Future<List<ProfileFeature>> getUserFeatures(
    String userId, {
    bool forceRefresh = false,
  }) async {
    final cached = _cache[userId];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.createdAt) < _cacheDuration) {
      return cached.features;
    }

    final pending = _pending[userId];
    if (!forceRefresh && pending != null) return pending;

    final request = _fetchUserFeatures(userId);
    _pending[userId] = request;
    try {
      return await request;
    } finally {
      _pending.remove(userId);
    }
  }

  Future<List<ProfileFeature>> _fetchUserFeatures(String userId) async {
    final response = await client.rpc(
      'get_user_profile_features',
      params: {'p_user_id': userId},
    );
    final features = (response as List<dynamic>)
        .map((item) => ProfileFeature.fromMap(Map<String, dynamic>.from(item)))
        .toList(growable: false);
    _cache[userId] = _FeatureCache(features, DateTime.now());
    return features;
  }

  Future<List<ProfileFeatureUser>> searchUsers(String search) async {
    final response = await client.rpc(
      'admin_profile_feature_users',
      params: {'p_search': search.trim(), 'p_limit': 40},
    );
    return (response as List<dynamic>)
        .map(
          (item) => ProfileFeatureUser.fromMap(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  Future<List<ProfileFeature>> getCatalog({
    String? kind,
    String search = '',
  }) async {
    final response = await client.rpc(
      'admin_profile_feature_catalog',
      params: {'p_kind': kind, 'p_search': search.trim()},
    );
    return (response as List<dynamic>)
        .map((item) => ProfileFeature.fromMap(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<List<ProfileFeature>> getAdminAssignments(String userId) async {
    final response = await client.rpc(
      'admin_profile_feature_assignments',
      params: {'p_user_id': userId},
    );
    return (response as List<dynamic>)
        .map((item) => ProfileFeature.fromMap(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<void> setMyFeatureEnabled({
    required String featureId,
    required bool enabled,
  }) async {
    await client.rpc(
      'set_my_profile_feature_enabled',
      params: {'p_feature_id': featureId, 'p_enabled': enabled},
    );
    final userId = client.auth.currentUser?.id;
    if (userId != null) _cache.remove(userId);
  }

  Future<void> claimMyFeature(String featureId) async {
    await client.rpc(
      'claim_my_profile_feature',
      params: {'p_feature_id': featureId},
    );
    final userId = client.auth.currentUser?.id;
    if (userId != null) _cache.remove(userId);
  }

  Future<void> releaseMyFeature(String featureId) async {
    await client.rpc(
      'release_my_claimed_profile_feature',
      params: {'p_feature_id': featureId},
    );
    final userId = client.auth.currentUser?.id;
    if (userId != null) _cache.remove(userId);
  }

  Future<void> assign({
    required String userId,
    required String featureId,
    DateTime? expiresAt,
  }) async {
    await client.rpc(
      'admin_assign_profile_feature',
      params: {
        'p_user_id': userId,
        'p_feature_id': featureId,
        'p_expires_at': expiresAt?.toUtc().toIso8601String(),
        'p_config_override': <String, dynamic>{},
      },
    );
    _cache.remove(userId);
  }

  Future<void> setEnabled({
    required String userId,
    required String featureId,
    required bool enabled,
  }) async {
    await client.rpc(
      'admin_set_profile_feature_enabled',
      params: {
        'p_user_id': userId,
        'p_feature_id': featureId,
        'p_enabled': enabled,
      },
    );
    _cache.remove(userId);
  }

  Future<void> revoke({
    required String userId,
    required String featureId,
  }) async {
    await client.rpc(
      'admin_revoke_profile_feature',
      params: {'p_user_id': userId, 'p_feature_id': featureId},
    );
    _cache.remove(userId);
  }

  Future<void> setCatalogClaimable({
    required String featureId,
    required bool claimable,
    int? durationDays,
  }) async {
    await client.rpc(
      'admin_set_profile_feature_claimable',
      params: {
        'p_feature_id': featureId,
        'p_claimable': claimable,
        // Süre verilmezse ücretsiz özellik SÜRESİZ olur (bkz. migration
        // 20260819000001) — eskiden burada 30 gün zorlanıyordu.
        'p_duration_days': claimable ? durationDays : null,
      },
    );
  }

  /// Puanla satın alma — service_role-only RPC'ye dokunmadan
  /// purchase-profile-feature Edge Function'ı üzerinden gider (gerçek
  /// kullanıcı kimliği orada doğrulanmış JWT'den alınır).
  Future<void> purchaseMyFeature({
    required String featureId,
    required String plan,
  }) async {
    final accessToken = client.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw const ProfileFeaturePurchaseException('UNAUTHORIZED');
    }
    final idempotencyKey = const Uuid().v4();
    final response = await client.functions.invoke(
      'purchase-profile-feature',
      headers: {'Authorization': 'Bearer $accessToken'},
      body: {
        'feature_id': featureId,
        'plan': plan,
        'idempotency_key': idempotencyKey,
      },
    );
    if (response.status != 200) {
      final data = response.data;
      final errorCode = data is Map ? data['error_code']?.toString() : null;
      throw ProfileFeaturePurchaseException(errorCode ?? 'PURCHASE_FAILED');
    }
    final userId = client.auth.currentUser?.id;
    if (userId != null) _cache.remove(userId);
  }

  Future<void> setCatalogPointsPricing({
    required String featureId,
    int? pointsMonthly,
    int? pointsYearly,
  }) async {
    await client.rpc(
      'admin_set_profile_feature_points_pricing',
      params: {
        'p_feature_id': featureId,
        'p_points_monthly': pointsMonthly,
        'p_points_yearly': pointsYearly,
      },
    );
  }

  Future<void> setCatalogOrderUnlock({
    required String featureId,
    int? unlockAfterOrders,
  }) async {
    await client.rpc(
      'admin_set_profile_feature_order_unlock',
      params: {
        'p_feature_id': featureId,
        'p_unlock_after_orders': unlockAfterOrders,
      },
    );
  }

  /// Bir kategorinin tamamını (sahip olunan + kilitli) tek çağrıda getirir.
  /// Ekran kategori sekmesi başına bir kez çağırır; eski üç ayrı RPC'yi
  /// (assignments/claimable/purchasable) tek yerde birleştirir.
  Future<List<ProfileFeature>> getCatalogForKind(ProfileFeatureKind kind) async {
    final response = await client.rpc(
      'get_my_profile_feature_catalog',
      params: {'p_kind': kindToDbValue(kind), 'p_limit': 300, 'p_offset': 0},
    );
    return (response as List<dynamic>)
        .map((item) => ProfileFeature.fromMap(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<ProfileFeatureSummary> getMySummary() async {
    final response = await client.rpc('get_my_profile_feature_summary');
    return ProfileFeatureSummary.fromMap(Map<String, dynamic>.from(response as Map));
  }

}

/// `get_my_profile_feature_summary()` çıktısı — ekran başlığı ve sekme
/// sayaçları tek çağrıdan beslenir.
class ProfileFeatureSummary {
  final int completedOrders;
  final int balancePoints;
  final bool pointsEarnEnabled;
  final bool pointsSpendEnabled;
  final Map<ProfileFeatureKind, KindSummary> kinds;

  const ProfileFeatureSummary({
    required this.completedOrders,
    required this.balancePoints,
    required this.pointsEarnEnabled,
    required this.pointsSpendEnabled,
    required this.kinds,
  });

  static const empty = ProfileFeatureSummary(
    completedOrders: 0,
    balancePoints: 0,
    pointsEarnEnabled: false,
    pointsSpendEnabled: false,
    kinds: {},
  );

  factory ProfileFeatureSummary.fromMap(Map<String, dynamic> map) {
    final rawKinds = Map<String, dynamic>.from(map['kinds'] as Map? ?? const {});
    final kinds = <ProfileFeatureKind, KindSummary>{};
    for (final kind in ProfileFeatureKind.values) {
      final entry = rawKinds[kindToDbValue(kind)];
      if (entry is Map) {
        kinds[kind] = KindSummary.fromMap(Map<String, dynamic>.from(entry));
      }
    }
    return ProfileFeatureSummary(
      completedOrders: (map['completed_orders'] as num?)?.toInt() ?? 0,
      balancePoints: (map['balance_points'] as num?)?.toInt() ?? 0,
      pointsEarnEnabled: map['points_earn_enabled'] as bool? ?? false,
      pointsSpendEnabled: map['points_spend_enabled'] as bool? ?? false,
      kinds: kinds,
    );
  }
}

class KindSummary {
  final int total;
  final int owned;
  final int? nextUnlockAt;
  final String? nextUnlockName;

  const KindSummary({
    required this.total,
    required this.owned,
    this.nextUnlockAt,
    this.nextUnlockName,
  });

  factory KindSummary.fromMap(Map<String, dynamic> map) => KindSummary(
    total: (map['total'] as num?)?.toInt() ?? 0,
    owned: (map['owned'] as num?)?.toInt() ?? 0,
    nextUnlockAt: (map['next_unlock_at'] as num?)?.toInt(),
    nextUnlockName: map['next_unlock_name']?.toString(),
  );
}

class _FeatureCache {
  final List<ProfileFeature> features;
  final DateTime createdAt;

  const _FeatureCache(this.features, this.createdAt);
}
