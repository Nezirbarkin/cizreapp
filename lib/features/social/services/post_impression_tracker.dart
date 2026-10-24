import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef ImpressionSender = Future<void> Function(List<String> postIds);

/// Akışta görülen gönderileri toplayıp `record_post_impressions` RPC'sine
/// toplu gönderir (20261024000002_post_insights_and_edits).
///
/// Sunucu kişi başına günde bir sayar; istemci aynı gün aynı gönderiyi bir
/// daha göndermez (istek tasarrufu). Kendi gönderisi ve misafir atlanır.
/// Gönderim: [debounce] sonra ya da [batchSize] dolunca; uygulama arka plana
/// geçince [flush] çağrılır.
class PostImpressionTracker {
  PostImpressionTracker({
    ImpressionSender? sender,
    String? Function()? currentUserId,
    this.debounce = const Duration(seconds: 4),
    this.batchSize = 50,
  })  : _sender = sender,
        _currentUserId = currentUserId;

  static final PostImpressionTracker instance = PostImpressionTracker();

  final ImpressionSender? _sender;
  final String? Function()? _currentUserId;
  final Duration debounce;
  final int batchSize;

  /// false iken hiçbir şey kaydedilmez (ör. testler).
  bool enabled = true;

  final Set<String> _pending = <String>{};
  final Set<String> _sentToday = <String>{};
  String? _day;
  Timer? _timer;
  bool _sending = false;

  @visibleForTesting
  Set<String> get pending => Set.unmodifiable(_pending);

  /// Gönderi ekranda görüldü.
  void markSeen(String postId, {required String authorId}) {
    if (!enabled || postId.isEmpty) return;
    final uid = _uid();
    if (uid == null || authorId == uid) return;
    _rollDay();
    if (_sentToday.contains(postId) || !_pending.add(postId)) return;
    if (_pending.length >= batchSize) {
      unawaited(flush());
      return;
    }
    _timer ??= Timer(debounce, () => unawaited(flush()));
  }

  /// Bekleyenleri hemen gönderir.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty || _sending) return;
    _sending = true;
    final ids = _pending.take(batchSize).toList();
    _pending.removeAll(ids);
    _sentToday.addAll(ids);
    try {
      await (_sender ?? _defaultSend)(ids);
    } catch (e) {
      // Ağ hatası: bir sonraki görülmede yeniden denensin.
      _sentToday.removeAll(ids);
      debugPrint('⚠️ Gösterimler gönderilemedi: $e');
    } finally {
      _sending = false;
    }
    if (_pending.isNotEmpty) {
      _timer ??= Timer(debounce, () => unawaited(flush()));
    }
  }

  /// Oturum kapanınca: bekleyenler ve bugünün listesi atılır.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    _sentToday.clear();
    _day = null;
  }

  String? _uid() {
    final f = _currentUserId;
    if (f != null) return f();
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  // Sunucu Türkiye gününe göre sayar; istemci yerel günle yetinir.
  void _rollDay() {
    final now = DateTime.now();
    final day = '${now.year}-${now.month}-${now.day}';
    if (_day != day) {
      _day = day;
      _sentToday.clear();
    }
  }

  static Future<void> _defaultSend(List<String> ids) async {
    await Supabase.instance.client.rpc(
      'record_post_impressions',
      params: {'p_post_ids': ids},
    );
  }
}
