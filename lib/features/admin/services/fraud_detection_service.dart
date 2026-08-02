import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/fraud_signal.dart';

class FraudScanResult {
  const FraudScanResult({required this.detected, required this.scannedAt});

  final int detected;
  final DateTime scannedAt;
}

class FraudDetectionService {
  FraudDetectionService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<FraudSignal>> listSignals({
    FraudSignalStatus? status,
    FraudSignalType? type,
    int limit = 100,
    int offset = 0,
  }) async {
    final response = await _client.rpc(
      'admin_list_fraud_signals',
      params: {
        'p_status': status?.databaseValue,
        'p_signal_type': type?.databaseValue,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    return (response as List)
        .map(
          (item) =>
              FraudSignal.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  Future<FraudScanResult> scan() async {
    final response = Map<String, dynamic>.from(
      await _client.rpc('admin_scan_fraud_signals') as Map,
    );
    return FraudScanResult(
      detected: (response['detected'] as num?)?.toInt() ?? 0,
      scannedAt: DateTime.parse(response['scanned_at'] as String),
    );
  }

  Future<void> review({
    required String signalId,
    required FraudSignalStatus status,
    String? note,
  }) {
    return _client.rpc(
      'admin_review_fraud_signal',
      params: {
        'p_signal_id': signalId,
        'p_status': status.databaseValue,
        'p_admin_note': note,
      },
    );
  }
}
