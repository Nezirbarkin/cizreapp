import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show StorageException;

import '../../../core/models/live_shopping_model.dart';
import 'live_shopping_service.dart';

/// Yüklenmeyi bekleyen kayıt parçası (telefonda duran MP4).
class LiveReplayPendingPart {
  const LiveReplayPendingPart({
    required this.sessionId,
    required this.partNo,
    required this.filePath,
    required this.durationMs,
    required this.userId,
  });

  final String sessionId;
  final int partNo;
  final String filePath;
  final int durationMs;

  /// Yalnız bu hesap oturumdayken yüklenir (depo politikası yayıncıya açık).
  final String userId;

  Map<String, dynamic> toJson() => {'s': sessionId, 'n': partNo, 'f': filePath, 'd': durationMs, 'u': userId};

  static LiveReplayPendingPart? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final s = json['s'], n = json['n'], f = json['f'], d = json['d'], u = json['u'];
    if (s is! String || n is! int || f is! String || d is! int || u is! String) return null;
    return LiveReplayPendingPart(sessionId: s, partNo: n, filePath: f, durationMs: d, userId: u);
  }
}

/// Bir yayının kayıt yükleme durumu (yayıncının özet ekranı gösterir).
@immutable
class LiveReplayUploadStatus {
  const LiveReplayUploadStatus({
    this.pending = 0,
    this.uploaded = 0,
    this.uploading = false,
    this.waitingNetwork = false,
    this.finished = false,
    this.dropped = 0,
    this.replay,
  });

  /// Kuyrukta bekleyen parça sayısı.
  final int pending;

  /// Bu açılışta yüklenen parça sayısı.
  final int uploaded;
  final bool uploading;

  /// Son deneme ağ hatasıyla bitti; biraz sonra yeniden denenecek.
  final bool waitingNetwork;

  /// Kayıt sunucuda sonlandırıldı (izleyiciler tamamını izleyebilir).
  final bool finished;

  /// Kalıcı hatayla düşen parça (kayıt kapandı, dosya bozuk…).
  final int dropped;

  /// Sunucunun son bildirdiği kayıt özeti.
  final LiveReplay? replay;

  bool get idle => pending == 0 && !uploading;

  LiveReplayUploadStatus copyWith({
    int? pending,
    int? uploaded,
    bool? uploading,
    bool? waitingNetwork,
    bool? finished,
    int? dropped,
    LiveReplay? replay,
  }) => LiveReplayUploadStatus(
    pending: pending ?? this.pending,
    uploaded: uploaded ?? this.uploaded,
    uploading: uploading ?? this.uploading,
    waitingNetwork: waitingNetwork ?? this.waitingNetwork,
    finished: finished ?? this.finished,
    dropped: dropped ?? this.dropped,
    replay: replay ?? this.replay,
  );
}

/// Kuyruğun kalıcı deposu (varsayılan SharedPreferences; testte bellek).
abstract class LiveReplayQueueStore {
  Future<String?> read();
  Future<void> write(String value);
}

class _PrefsQueueStore implements LiveReplayQueueStore {
  static const _key = 'live_replay_queue_v1';

  @override
  Future<String?> read() async => (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String value) async => (await SharedPreferences.getInstance()).setString(_key, value);
}

enum _Outcome { done, retryLater }

/// Yayın kaydının parçalarını sırayla `live-replays` kovasına yükler.
///
/// Kuyruk telefonda kalıcıdır: yayıncı uygulamayı kapatsa da sonraki açılışta
/// ([resume], oturum açılınca çağrılır) kalan parçalar yüklenir; sunucu
/// bitişten sonra 7 gün yüklemeye izin verir. Ağ hatasında [retryDelay] sonra
/// yeniden denenir; kalıcı hatada (kayıt silindi/kapandı, dosya çok büyük)
/// parça düşürülür. Yayın bitip kuyruğu boşalınca kayıt sunucuda sonlandırılır
/// (`live_replay_finish`).
class LiveReplayUploader {
  LiveReplayUploader({
    LiveShoppingService? service,
    LiveReplayQueueStore? store,
    Future<Directory> Function()? baseDirectory,
    this.retryDelay = const Duration(seconds: 20),
  }) : _service = service,
       _store = store ?? _PrefsQueueStore(),
       _baseDirectory = baseDirectory ?? getApplicationSupportDirectory;

  static final LiveReplayUploader instance = LiveReplayUploader();

  LiveShoppingService? _service;
  final LiveReplayQueueStore _store;
  final Future<Directory> Function() _baseDirectory;
  final Duration retryDelay;

  LiveShoppingService get service => _service ??= LiveShoppingService();

  final List<LiveReplayPendingPart> _parts = [];

  /// Bitirilecek yayınlar → yayıncı hesabı.
  final Map<String, String> _finishing = {};

  /// Bu açılışta kaydı süren yayınlar (bitirilmez, klasörü temizlenmez).
  final Set<String> _recording = {};
  final Map<String, ValueNotifier<LiveReplayUploadStatus>> _status = {};

  Future<void>? _loading;
  bool _draining = false;
  bool _swept = false;
  Timer? _retryTimer;

  /// Parçaların telefonda durduğu klasör.
  Future<Directory> directoryFor(String sessionId) async {
    final base = await _baseDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}live_replays${Platform.pathSeparator}$sessionId');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  ValueListenable<LiveReplayUploadStatus> statusFor(String sessionId) => _notifier(sessionId);

  ValueNotifier<LiveReplayUploadStatus> _notifier(String sessionId) =>
      _status.putIfAbsent(sessionId, () => ValueNotifier(LiveReplayUploadStatus(pending: _pendingFor(sessionId))));

  int _pendingFor(String sessionId) => _parts.where((p) => p.sessionId == sessionId).length;

  void _update(String sessionId, LiveReplayUploadStatus Function(LiveReplayUploadStatus s) change) {
    final notifier = _notifier(sessionId);
    notifier.value = change(notifier.value).copyWith(pending: _pendingFor(sessionId));
  }

  /// Kuyruktaki en büyük parça numarasının bir fazlası (yoksa 1). Sürdürülen
  /// yayında sunucunun bildirdiği numarayla karşılaştırılır.
  Future<int> nextPartFor(String sessionId) async {
    await _load();
    var max = 0;
    for (final p in _parts) {
      if (p.sessionId == sessionId && p.partNo > max) max = p.partNo;
    }
    return max + 1;
  }

  void markRecording(String sessionId, bool recording) {
    if (recording) {
      _recording.add(sessionId);
    } else {
      _recording.remove(sessionId);
    }
  }

  Future<void> enqueue(LiveReplayPendingPart part) async {
    await _load();
    _parts.removeWhere((p) => p.sessionId == part.sessionId && p.partNo == part.partNo);
    _parts.add(part);
    _parts.sort((a, b) {
      final bySession = a.sessionId.compareTo(b.sessionId);
      return bySession != 0 ? bySession : a.partNo.compareTo(b.partNo);
    });
    await _save();
    _update(part.sessionId, (s) => s);
    kick();
  }

  /// Yayın bitti: kuyruk boşalınca kayıt sunucuda sonlandırılır.
  Future<void> finish(String sessionId) async {
    await _load();
    final userId = service.currentUserId;
    if (userId == null) return;
    _finishing[sessionId] = userId;
    await _save();
    kick();
  }

  /// Uygulama açılışında / oturum açılınca: kalan parçaları yükle.
  Future<void> resume() async {
    if (kIsWeb) return;
    await _load();
    if (!_swept) {
      _swept = true;
      await _sweepOrphans();
    }
    kick();
  }

  void kick() {
    _retryTimer?.cancel();
    _retryTimer = null;
    unawaited(_drain());
  }

  /// Testler için: süren turu bekler, sonra kuyruk boşalana (ya da beklemeye
  /// geçene) kadar bir tur daha çalıştırır.
  @visibleForTesting
  Future<void> drainForTest() async {
    while (_draining) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await _drain();
  }

  @visibleForTesting
  List<LiveReplayPendingPart> get pendingForTest => List.unmodifiable(_parts);

  @visibleForTesting
  Map<String, String> get finishingForTest => Map.unmodifiable(_finishing);

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      await _load();
      while (true) {
        final userId = service.currentUserId;
        if (userId == null) break;
        LiveReplayPendingPart? next;
        for (final p in _parts) {
          if (p.userId == userId) {
            next = p;
            break;
          }
        }
        if (next != null) {
          if (await _uploadOne(next) == _Outcome.retryLater) {
            _scheduleRetry();
            break;
          }
          continue;
        }
        String? done;
        for (final entry in _finishing.entries) {
          final id = entry.key;
          if (entry.value == userId && !_recording.contains(id) && _parts.every((p) => p.sessionId != id)) {
            done = id;
            break;
          }
        }
        if (done == null) break;
        if (await _finishOne(done) == _Outcome.retryLater) {
          _scheduleRetry();
          break;
        }
      }
    } finally {
      _draining = false;
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(retryDelay, () {
      _retryTimer = null;
      unawaited(_drain());
    });
  }

  Future<_Outcome> _uploadOne(LiveReplayPendingPart part) async {
    final file = File(part.filePath);
    if (!file.existsSync()) {
      await _drop(part, deleteFile: false);
      return _Outcome.done;
    }
    _update(part.sessionId, (s) => s.copyWith(uploading: true, waitingNetwork: false));
    try {
      await service.uploadReplayPart(part.sessionId, part.partNo, file);
      final replay = await service.addReplayPart(part.sessionId, part.partNo, part.durationMs);
      _parts.remove(part);
      await _save();
      _deleteQuietly(file);
      _update(part.sessionId, (s) => s.copyWith(uploading: false, uploaded: s.uploaded + 1, replay: replay));
      // Uygulama yayın sırasında kapanıp açıldıysa bitiş işareti yoktur: yayın
      // bu açılışta kaydedilmiyorsa kuyruk boşalınca sonlandırmayı dene
      // (yayın hâlâ sürüyorsa sunucu bir şey değiştirmez).
      if (!_recording.contains(part.sessionId) && !_finishing.containsKey(part.sessionId)) {
        _finishing[part.sessionId] = part.userId;
        await _save();
      }
      return _Outcome.done;
    } catch (e) {
      if (_isPermanent(e)) {
        debugPrint('live replay part dropped (${part.sessionId}#${part.partNo}): $e');
        await _drop(part, deleteFile: true);
        return _Outcome.done;
      }
      debugPrint('live replay upload retry (${part.sessionId}#${part.partNo}): $e');
      _update(part.sessionId, (s) => s.copyWith(uploading: false, waitingNetwork: true));
      return _Outcome.retryLater;
    }
  }

  Future<_Outcome> _finishOne(String sessionId) async {
    try {
      final replay = await service.finishReplay(sessionId);
      _finishing.remove(sessionId);
      await _save();
      _update(
        sessionId,
        (s) => s.copyWith(finished: replay?.state != 'recording', waitingNetwork: false, replay: replay),
      );
      return _Outcome.done;
    } catch (e) {
      if (_isPermanent(e)) {
        _finishing.remove(sessionId);
        await _save();
        return _Outcome.done;
      }
      _update(sessionId, (s) => s.copyWith(waitingNetwork: true));
      return _Outcome.retryLater;
    }
  }

  Future<void> _drop(LiveReplayPendingPart part, {required bool deleteFile}) async {
    _parts.remove(part);
    await _save();
    if (deleteFile) _deleteQuietly(File(part.filePath));
    _update(part.sessionId, (s) => s.copyWith(uploading: false, dropped: s.dropped + 1));
  }

  /// Yeniden denemenin işe yaramayacağı hatalar: depo politikası/boyut
  /// reddi ve kaydın kapanması. Ağ hataları ve 5xx yeniden denenir.
  static bool _isPermanent(Object error) {
    if (error is StorageException) {
      final code = int.tryParse(error.statusCode ?? '');
      return code != null && code >= 400 && code < 500 && code != 408 && code != 429;
    }
    if (error is LiveException) {
      return switch (error.failure) {
        LiveFailure.replayClosed ||
        LiveFailure.replayPartInvalid ||
        LiveFailure.replayPartMissing ||
        LiveFailure.notHost ||
        LiveFailure.notFound => true,
        _ => false,
      };
    }
    return false;
  }

  static void _deleteQuietly(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  /// Kuyrukta olmayan (yarıda kalmış kayıt) dosyaları ve boş klasörleri siler.
  Future<void> _sweepOrphans() async {
    try {
      final base = await _baseDirectory();
      final root = Directory('${base.path}${Platform.pathSeparator}live_replays');
      if (!root.existsSync()) return;
      final keep = _parts.map((p) => File(p.filePath).absolute.path).toSet();
      for (final dir in root.listSync().whereType<Directory>()) {
        final sessionId = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (_recording.contains(sessionId)) continue;
        for (final file in dir.listSync().whereType<File>()) {
          if (!keep.contains(file.absolute.path)) _deleteQuietly(file);
        }
        if (dir.listSync().isEmpty) dir.deleteSync();
      }
    } catch (e) {
      debugPrint('live replay sweep: $e');
    }
  }

  Future<void> _load() => _loading ??= () async {
    try {
      final raw = await _store.read();
      if (raw == null || raw.isEmpty) return;
      final json = jsonDecode(raw);
      if (json is! Map) return;
      for (final p in (json['parts'] as List? ?? const [])) {
        final part = LiveReplayPendingPart.tryFromJson(p);
        if (part != null) _parts.add(part);
      }
      final finishing = json['finishing'];
      if (finishing is Map) {
        finishing.forEach((k, v) {
          if (k is String && v is String) _finishing[k] = v;
        });
      }
    } catch (e) {
      debugPrint('live replay queue load: $e');
    }
  }();

  Future<void> _save() async {
    try {
      await _store.write(
        jsonEncode({
          'parts': [for (final p in _parts) p.toJson()],
          'finishing': _finishing,
        }),
      );
    } catch (e) {
      debugPrint('live replay queue save: $e');
    }
  }
}
