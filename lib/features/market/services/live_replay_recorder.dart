import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/models/live_shopping_model.dart';
import 'agora_service.dart';
import 'live_replay_uploader.dart';
import 'live_shopping_service.dart';

/// Yayıncı tarafı: yayın canlıyken görüntüyü parça parça kaydeder ve biten
/// her parçayı [LiveReplayUploader] kuyruğuna verir (tekrar izleme).
///
/// Kayıt yayını asla engellemez: yönetim kaydı kapattıysa, motor kaydı
/// başlatamazsa ya da dosyaya yazılamazsa yayın kayıtsız sürer. Akış kesilirse
/// (kamera+mikrofon kapalı, uygulama arka planda) artan aralıklarla yeniden
/// denenir; parça numarası yalnız kuyruğa giren parçada ilerler.
class LiveReplayRecorder {
  LiveReplayRecorder({
    required this.engine,
    required this.service,
    LiveReplayUploader? uploader,
    DateTime Function()? now,
    this.stopTimeout = const Duration(seconds: 3),
    this.retryBase = const Duration(seconds: 5),
  }) : uploader = uploader ?? LiveReplayUploader.instance,
       _now = now ?? DateTime.now;

  final LiveVideoEngine engine;
  final LiveShoppingService service;
  final LiveReplayUploader uploader;
  final DateTime Function() _now;
  final Duration stopTimeout;

  /// Başarısız parçadan sonra ilk bekleme; her başarısızlıkta ikiye katlanır
  /// (en çok 6 katı).
  final Duration retryBase;

  String? _sessionId;
  int _partNo = 1;
  int _maxParts = 999;
  int _days = 30;
  Duration _partLength = const Duration(minutes: 3);
  bool _active = false;
  bool _stopping = false;
  bool _finishSent = false;
  int _failures = 0;

  String? _currentPath;
  int _currentMs = 0;
  DateTime? _partStartedAt;
  Timer? _retry;
  Completer<void>? _stopped;

  /// Kayıt sürüyor mu (yönetim kapattıysa ya da başlatılamadıysa false).
  bool get isActive => _active;

  /// Kaydı başlamış yayın (özet ekranı yükleme durumunu gösterir); kayıt hiç
  /// başlamadıysa null.
  String? get sessionId => _sessionId;

  /// Kaydın kaç gün saklanacağı (yönetici ayarı).
  int get days => _days;

  @visibleForTesting
  int get nextPartForTest => _partNo;

  /// Yayın canlı olunca çağrılır.
  Future<void> start(String sessionId) async {
    if (_active || kIsWeb) return;
    LiveReplayStart begin;
    try {
      begin = await service.beginReplay(sessionId);
    } catch (e) {
      debugPrint('live replay begin: $e');
      return;
    }
    if (!begin.enabled) return;
    // Bağlantı kopup yeniden katılınca aynı yayın sürer: numara geri gitmesin.
    final ownNext = _sessionId == sessionId ? _partNo : 1;
    _sessionId = sessionId;
    _partLength = begin.partLength;
    _maxParts = begin.maxParts;
    _days = begin.days;
    _partNo = math.max(math.max(begin.nextPart, ownNext), await uploader.nextPartFor(sessionId));
    _active = true;
    _stopping = false;
    _finishSent = false;
    _failures = 0;
    uploader.markRecording(sessionId, true);
    await _startPart();
  }

  Future<void> _startPart() async {
    final sessionId = _sessionId;
    if (!_active || _stopping || sessionId == null) return;
    if (_partNo > _maxParts) {
      _active = false;
      uploader.markRecording(sessionId, false);
      return;
    }
    final dir = await uploader.directoryFor(sessionId);
    final path = '${dir.path}${Platform.pathSeparator}part-${_partNo.toString().padLeft(4, '0')}.mp4';
    final stale = File(path);
    if (stale.existsSync()) {
      try {
        stale.deleteSync();
      } catch (_) {}
    }
    if (!_active || _stopping) return;
    _currentPath = path;
    _currentMs = 0;
    _partStartedAt = _now();
    var started = false;
    try {
      started = await engine.startLocalRecording(
        path,
        maxDuration: _partLength,
        events: LiveRecordingEvents(onInfo: (ms, _) => _currentMs = ms, onStopped: _onPartStopped),
      );
    } catch (e) {
      debugPrint('live replay start part: $e');
    }
    if (!started && _currentPath == path) {
      _currentPath = null;
      _failures++;
      _scheduleRetry();
    }
  }

  void _onPartStopped(LiveRecordingStop reason) {
    final path = _currentPath;
    if (path == null) return;
    _currentPath = null;
    final queued = _finalize(path);
    if (queued) {
      _partNo++;
      _failures = 0;
    } else {
      _failures++;
    }
    if (_stopping || !_active) {
      final waiter = _stopped;
      if (waiter != null && !waiter.isCompleted) waiter.complete();
      return;
    }
    if (reason == LiveRecordingStop.writeFailed) {
      // Yer kalmadı vb.: yayın kayıtsız sürer.
      _active = false;
      final id = _sessionId;
      if (id != null) uploader.markRecording(id, false);
      return;
    }
    if (queued && reason == LiveRecordingStop.maxDuration) {
      unawaited(_startPart());
    } else {
      _scheduleRetry();
    }
  }

  /// Dosya geçerliyse kuyruğa verir; boş/bozuk dosya silinir.
  bool _finalize(String path) {
    final sessionId = _sessionId;
    final userId = service.currentUserId;
    final file = File(path);
    final size = file.existsSync() ? file.lengthSync() : 0;
    var ms = _currentMs;
    final startedAt = _partStartedAt;
    if (ms <= 0 && startedAt != null) ms = _now().difference(startedAt).inMilliseconds;
    if (sessionId == null || userId == null || size < 1024 || ms < 1000) {
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
      return false;
    }
    unawaited(
      uploader.enqueue(
        LiveReplayPendingPart(
          sessionId: sessionId,
          partNo: _partNo,
          filePath: path,
          durationMs: ms.clamp(1, 3600000),
          userId: userId,
        ),
      ),
    );
    return true;
  }

  void _scheduleRetry() {
    _retry?.cancel();
    if (!_active || _stopping) return;
    final factor = math.min(6, 1 << math.min(_failures, 3));
    _retry = Timer(retryBase * factor, () {
      _retry = null;
      unawaited(_startPart());
    });
  }

  /// Yayın bitti ya da yayıncı ekranı kapanıyor: süren parçayı kapatıp
  /// kuyruğa verir. [finished]: yayın sona erdi → kuyruk boşalınca kayıt
  /// sunucuda sonlandırılır. Bağlantı koptuysa (yayın sürüyor) false.
  Future<void> stop({required bool finished}) async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    _retry?.cancel();
    _retry = null;
    if (_active) {
      _stopping = true;
      if (_currentPath != null) {
        final waiter = _stopped = Completer<void>();
        try {
          await engine.stopLocalRecording();
        } catch (_) {}
        try {
          await waiter.future.timeout(stopTimeout);
        } on TimeoutException {
          // Motor "durdu" demediyse dosya yine de kapanmıştır: elle işle.
          _onPartStopped(LiveRecordingStop.stopped);
        }
      }
    }
    _active = false;
    _stopping = false;
    uploader.markRecording(sessionId, false);
    if (finished) {
      if (_finishSent) return;
      _finishSent = true;
      await uploader.finish(sessionId);
    } else {
      uploader.kick();
    }
  }

  void dispose() {
    _retry?.cancel();
    _retry = null;
  }
}
