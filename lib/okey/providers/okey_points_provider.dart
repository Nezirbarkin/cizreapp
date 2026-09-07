import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/okey_points_service.dart';

/// Okey cüzdanı + saatlik hediye + reklam ödülü + skor tablosu state'i.
class OkeyPointsProvider with ChangeNotifier {
  final OkeyPointsService _service = OkeyPointsService();

  OkeyWallet _wallet = OkeyWallet.empty;
  List<OkeyLeaderboardEntry> _leaderboard = [];
  bool _isLoading = false;
  bool _isBusy = false;
  String? _error;
  String? _info;
  Timer? _countdown;

  bool _notifyScheduled = false;
  bool _disposed = false;

  OkeyPointsProvider() {
    // Bildirimler asla senkron yapılmaz (bkz. OkeyGameProvider._notify).
    Future.microtask(refresh);
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _notify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _countdown?.cancel();
    super.dispose();
  }

  OkeyWallet get wallet => _wallet;
  List<OkeyLeaderboardEntry> get leaderboard => _leaderboard;
  bool get isLoading => _isLoading;
  bool get isBusy => _isBusy;
  String? get error => _error;
  String? get info => _info;

  int get points => _wallet.points;
  bool get canClaimGift => _wallet.canClaimHourly;
  int get secondsUntilGift => _wallet.secondsUntilNextGift;

  /// "12:34" biçiminde kalan süre.
  String get giftCountdownText {
    final s = _wallet.secondsUntilNextGift;
    if (s <= 0) return 'Hazır';
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  void _tick() {
    if (_wallet.secondsUntilNextGift <= 0) return;
    _wallet = OkeyWallet(
      points: _wallet.points,
      lastHourlyClaimAt: _wallet.lastHourlyClaimAt,
      canClaimHourly: _wallet.secondsUntilNextGift - 1 <= 0,
      secondsUntilNextGift: _wallet.secondsUntilNextGift - 1,
      hourlyGiftPoints: _wallet.hourlyGiftPoints,
      adRewardPoints: _wallet.adRewardPoints,
    );
    _notify();
  }

  void consumeMessages() {
    _error = null;
    _info = null;
  }

  Future<void> refresh() async {
    _isLoading = true;
    _notify();
    try {
      _wallet = await _service.getWallet();
      _error = null;
    } catch (e) {
      _error = 'Çip bilgisi alınamadı: $e';
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  Future<void> refreshLeaderboard() async {
    try {
      _leaderboard = await _service.leaderboard();
      _error = null;
    } catch (e) {
      _error = 'Skor tablosu alınamadı: $e';
    }
    _notify();
  }

  /// Saatlik hediyeyi al. Süre dolmadıysa sunucu reddeder.
  Future<void> claimHourlyGift() async {
    if (_isBusy) return;
    _isBusy = true;
    _error = null;
    _notify();
    try {
      final newPoints = await _service.claimHourlyGift();
      _info = '+${_wallet.hourlyGiftPoints} çip kazandın!';
      _wallet = OkeyWallet(
        points: newPoints,
        lastHourlyClaimAt: DateTime.now(),
        canClaimHourly: false,
        secondsUntilNextGift: 3600,
        hourlyGiftPoints: _wallet.hourlyGiftPoints,
        adRewardPoints: _wallet.adRewardPoints,
      );
    } catch (e) {
      _error = '$e'.contains('gift_not_ready')
          ? 'Hediye için henüz erken.'
          : 'Hediye alınamadı: $e';
    } finally {
      _isBusy = false;
      _notify();
    }
  }

  /// Reklam izlendikten SONRA çağrılır; [sessionId] sunucu tarafında
  /// doğrulanmış reklam oturumudur.
  Future<void> claimAdReward(String sessionId) async {
    if (_isBusy) return;
    _isBusy = true;
    _error = null;
    _notify();
    try {
      final newPoints = await _service.claimAdReward(sessionId);
      _info = '+${_wallet.adRewardPoints} çip kazandın!';
      _wallet = OkeyWallet(
        points: newPoints,
        lastHourlyClaimAt: _wallet.lastHourlyClaimAt,
        canClaimHourly: _wallet.canClaimHourly,
        secondsUntilNextGift: _wallet.secondsUntilNextGift,
        hourlyGiftPoints: _wallet.hourlyGiftPoints,
        adRewardPoints: _wallet.adRewardPoints,
      );
    } catch (e) {
      _error = '$e'.contains('ad_not_verified')
          ? 'Reklam doğrulanamadı.'
          : 'Ödül alınamadı: $e';
    } finally {
      _isBusy = false;
      _notify();
    }
  }
}
