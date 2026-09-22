import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chat_presence.dart';
import 'presence_service.dart';
import 'user_presence_service.dart';

/// Tek bir kullanıcının GÖRÜNÜR durumunu canlı tutar (sohbet başlığı, profil).
///
/// İki kaynağı birleştirir:
///  * sunucunun kural uygulanmış cevabı (`get_user_presence`): kimin neyi
///    görebileceği, son görülme, admin ayarları — periyodik yenilenir;
///  * canlı presence akışı: birinin çevrimiçi olduğu ya da ayrıldığı anı gecikmesiz
///    yansıtır.
///
/// Canlı akış HİÇBİR ZAMAN tek başına yetmez: sunucu "bu kişiyi göremezsin" dediyse
/// (engel, hayalet, gizli hesap, admin kapattı) akışta görünse bile hiçbir şey
/// gösterilmez.
class PresenceTracker extends ChangeNotifier {
  PresenceTracker(
    this.userId, {
    this.context = PresenceContext.chat,
    UserPresenceService? service,
    Stream<List<String>>? liveStream,
    bool Function(String userId)? liveIsOnline,
    this.refreshEvery = const Duration(seconds: 90),
    this.tickEvery = const Duration(seconds: 30),
    this.settleDelay = const Duration(seconds: 2),
    DateTime Function()? clock,
  }) : _service = service ?? UserPresenceService.instance,
       _liveStream = liveStream ?? PresenceService.instance.onlineUsersStream,
       _liveIsOnline = liveIsOnline ?? PresenceService.instance.isOnline,
       _clock = clock ?? DateTime.now;

  final String userId;
  final PresenceContext context;

  /// Sunucudan yeniden okuma aralığı.
  final Duration refreshEvery;

  /// "12 dk önce" gibi göreli metinlerin yenilenme aralığı (ağ isteği yok).
  final Duration tickEvery;

  /// Biri çevrimdışı olunca, sunucudaki son görülme güncellensin diye beklenen süre.
  final Duration settleDelay;

  final UserPresenceService _service;
  final Stream<List<String>> _liveStream;
  final bool Function(String userId) _liveIsOnline;
  final DateTime Function() _clock;

  UserPresence? _presence;
  ChatPresenceSettings _settings = const ChatPresenceSettings();
  bool _started = false;
  bool _disposed = false;
  bool _lastLive = false;

  /// Canlı akış "çevrimdışı oldu" dedi ama sunucu cevabı henüz yenilenmedi:
  /// bayat `online=true` bir süre daha "çevrimiçi" gösterilmesin.
  bool _liveDroppedSinceFetch = false;

  StreamSubscription<List<String>>? _liveSub;
  Timer? _refreshTimer;
  Timer? _tickTimer;
  Timer? _settleTimer;

  /// Sunucudan en az bir cevap alındı mı?
  bool get isLoaded => _presence != null;

  bool get canSeeOnline => _presence?.canSeeOnline ?? false;

  /// Şu an "çevrimiçi" gösterilmeli mi?
  bool get isOnline {
    final presence = _presence;
    if (presence == null || !presence.canSeeOnline) return false;
    if (_lastLive) return true;
    return presence.online && !_liveDroppedSinceFetch;
  }

  /// Çevrimdışıyken gösterilecek son görülme (yoksa null).
  DateTime? get lastSeen => isOnline ? null : _presence?.lastSeen;

  /// Gösterilecek metin: "çevrimiçi", "son görülme …" ya da null (hiçbir şey).
  String? get label {
    if (isOnline) return PresenceLabels.online;
    final seen = lastSeen;
    if (seen == null) return null;
    return PresenceLabels.lastSeen(seen, now: _clock());
  }

  /// Ekran görünür olunca çağrılır; ayarları okur, durumu çeker, zamanlayıcıları
  /// başlatır. Birden çok kez çağrılırsa ilkinden sonrası etkisizdir.
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;

    _lastLive = _liveIsOnline(userId);
    _liveSub = _liveStream.listen((_) => _onLive(), onError: (_) {});

    final settings = await _service.loadSettings();
    if (_disposed) return;
    _settings = settings;

    // Admin bu bağlamda hiçbir durumu göstermiyorsa sunucuya sormaya gerek yok.
    if (!_settings.showsAnyPresence(context)) {
      _presence = UserPresence.hidden(userId);
      _notify();
      return;
    }

    await refresh();
    if (_disposed) return;
    _refreshTimer = Timer.periodic(refreshEvery, (_) => refresh());
    _tickTimer = Timer.periodic(tickEvery, (_) => _notify());
  }

  /// Sunucudan yeniden okur. Hata olursa önceki cevap korunur; hiç cevap yoksa
  /// "gizli" sayılır (güvenli taraf).
  Future<void> refresh() async {
    final fresh = await _service.fetchOne(userId, context: context);
    if (_disposed) return;
    if (fresh != null) {
      _presence = fresh;
      _liveDroppedSinceFetch = false;
    } else {
      _presence ??= UserPresence.hidden(userId);
    }
    _notify();
  }

  void _onLive() {
    final now = _liveIsOnline(userId);
    if (now == _lastLive) return; // başka kullanıcıların olayları
    final wasOnline = _lastLive;
    _lastLive = now;

    if (wasOnline && !now) {
      _liveDroppedSinceFetch = true;
      _settleTimer?.cancel();
      _settleTimer = Timer(settleDelay, refresh);
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _liveSub?.cancel();
    _refreshTimer?.cancel();
    _tickTimer?.cancel();
    _settleTimer?.cancel();
    super.dispose();
  }
}
