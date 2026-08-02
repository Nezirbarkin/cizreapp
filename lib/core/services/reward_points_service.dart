import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/reward_points_model.dart';
import '../models/reward_session_model.dart';

abstract interface class RewardPointsGateway {
  Future<UserPointAccount?> getMyAccount();
  Future<List<PointLedgerEntry>> getMyLedger({int limit = 50});
  Future<RewardSession> createRewardSession({required String idempotencyKey});
  Future<RewardSession?> getRewardSession(String rewardSessionId);
}

class RewardPointsService implements RewardPointsGateway {
  final SupabaseClient? _client;

  RewardPointsService({SupabaseClient? client}) : _client = client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  @override
  Future<UserPointAccount?> getMyAccount() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await _supabase
        .from('user_point_accounts')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    return row == null ? null : UserPointAccount.fromJson(row);
  }

  @override
  Future<List<PointLedgerEntry>> getMyLedger({int limit = 50}) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return const [];
    final safeLimit = limit.clamp(1, 100).toInt();
    final rows = await _supabase
        .from('my_point_ledger_entries')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(safeLimit);
    return rows
        .map((row) => PointLedgerEntry.fromJson(row))
        .toList(growable: false);
  }

  @override
  Future<RewardSession> createRewardSession({
    required String idempotencyKey,
  }) async {
    final accessToken = _supabase.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw const AuthException('Oturum bulunamadı.');
    }
    final response = await _supabase.functions.invoke(
      'admob-reward-session',
      headers: {'Authorization': 'Bearer $accessToken'},
      body: {'idempotency_key': idempotencyKey},
    );
    if (response.status != 201 || response.data is! Map) {
      throw StateError('Reward session oluşturulamadı.');
    }
    final session = RewardSession.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
    if (session.customData == null || session.customData!.isEmpty) {
      throw StateError('Reward session custom data içermiyor.');
    }
    return session;
  }

  @override
  Future<RewardSession?> getRewardSession(String rewardSessionId) async {
    final row = await _supabase
        .from('my_ad_reward_sessions')
        .select()
        .eq('id', rewardSessionId)
        .maybeSingle();
    return row == null ? null : RewardSession.fromJson(row);
  }
}

typedef RewardPollDelay = Future<void> Function(Duration duration);

/// SSV callback'inin server-side sonucunu güvenli read surface üzerinden
/// sorgular. Ağ hatası veya timeout ekonomik başarı sayılmaz.
class RewardVerificationPoller {
  final RewardPointsGateway gateway;
  final RewardPollDelay delay;

  RewardVerificationPoller({required this.gateway, RewardPollDelay? delay})
    : delay = delay ?? Future<void>.delayed;

  Future<RewardVerificationOutcome> waitForTerminal({
    required String rewardSessionId,
    int maxAttempts = 15,
    Duration interval = const Duration(seconds: 2),
  }) async {
    RewardSession? lastSession;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        lastSession = await gateway.getRewardSession(rewardSessionId);
        final status = lastSession?.status;
        if (status == RewardSessionStatus.credited) {
          return RewardVerificationOutcome(
            RewardVerificationState.credited,
            session: lastSession,
          );
        }
        if (status == RewardSessionStatus.duplicate) {
          return RewardVerificationOutcome(
            RewardVerificationState.duplicate,
            session: lastSession,
          );
        }
        if (status == RewardSessionStatus.blocked ||
            status == RewardSessionStatus.rejected) {
          return RewardVerificationOutcome(
            RewardVerificationState.rejected,
            session: lastSession,
          );
        }
        if (status == RewardSessionStatus.expired) {
          return RewardVerificationOutcome(
            RewardVerificationState.expired,
            session: lastSession,
          );
        }
      } catch (_) {
        // Fail-closed: geçici okuma hatalarında kalan denemeler kullanılır.
      }
      if (attempt + 1 < maxAttempts) await delay(interval);
    }
    return RewardVerificationOutcome(
      RewardVerificationState.pending,
      session: lastSession,
    );
  }
}
