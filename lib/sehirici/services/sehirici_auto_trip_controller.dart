import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import '../models/sehirici_models.dart';
import 'sehirici_auto_trip_evaluator.dart';
import 'sehirici_location_tracker.dart';
import 'sehirici_trip_service.dart';

/// Otomasyon durum makinesinin fazları.
enum SehiriciAutoTripPhase { stopped, watching, driving }

/// Şoför paneli tam otomasyonu: GPS/çalışma saati/hat bölgesi sinyallerine
/// göre seferleri **kendiliğinden** başlatıp bitiren durum makinesi.
///
/// Fazlar:
///   stopped  → kapalı.
///   watching → düşük frekanslı GPS ile (çalışma saati + hareket + hat bölgesi)
///              sinyalini izler. M-of-N örneklem sağlanınca sefer başlatır.
///   driving  → [SehiriciLocationTracker] yüksek frekansla konum yazar; her
///              yazımda bitiş koşulları (çalışma saati sonu) değerlendirilir.
///
/// Singleton — uygulama genelinde tek instance. [SehiriciLocationTracker]
/// ile aynı deseni izler.
///
/// Başlatma/bitirme **kararları** [SehiriciAutoTripEvaluator] içindedir (saf,
/// saat/konum parametreli, fiziksel senaryolarla test edilebilir); bu sınıf
/// yalnızca fazları, timer'ları ve tracker'ı yönetir.
class SehiriciAutoTripController {
  SehiriciAutoTripController._internal();
  static final SehiriciAutoTripController instance =
      SehiriciAutoTripController._internal();

  final SehiriciTripService _tripService = SehiriciTripService();
  final SehiriciLocationTracker _tracker = SehiriciLocationTracker();

  SehiriciAutoTripPhase _phase = SehiriciAutoTripPhase.stopped;
  SehiriciAutoTripPhase get phase => _phase;
  bool get isActive => _phase != SehiriciAutoTripPhase.stopped;
  bool get isWatching => _phase == SehiriciAutoTripPhase.watching;
  bool get isDriving => _phase == SehiriciAutoTripPhase.driving;

  // ── Zamanlama sabitleri ─────────────────────────────────────────────
  /// Karar eşikleri (hareket hızı/yer değiştirme, hat koridoru, M-of-N)
  /// [SehiriciAutoTripEvaluator] üzerindedir.
  /// Watching fazı örnek aralığı (stream tetiklenmezse fallback timer).
  static const Duration kSampleInterval = Duration(seconds: 25);
  /// Driving fazı bitiş kontrolü periyodu (tracker'a ek olarak zaman-bazlı).
  static const Duration kEndCheckInterval = Duration(seconds: 60);

  // ── Konfigürasyon (start ile verilir) ─────────────────────────────────
  String? _driverId;
  SehiriciLine? _line;
  SehiriciAutoTripEvaluator? _evaluator;

  // ── Dinamik durum ─────────────────────────────────────────────────────
  StreamSubscription<Position>? _watchSub;
  Timer? _watchFallback;
  Timer? _endCheckTimer;
  bool _busy = false;

  // UI bildirimleri (panel bu callback'leri set eder).
  void Function()? onTripAutoStarted;
  void Function(String reason)? onTripAutoEnded;

  /// Otomasyonu başlat. Mevcut aktif sefer varsa doğrudan driving fazına girer
  /// (uygulama yeniden açıldığında veya manuel başlatılmışken auto açıldığında).
  Future<void> start({
    required String driverId,
    required SehiriciLine line,
    TimeOfDay? workStart,
    TimeOfDay? workEnd,
  }) async {
    if (_phase != SehiriciAutoTripPhase.stopped) {
      await stop();
    }
    _driverId = driverId;
    _line = line;
    _evaluator = SehiriciAutoTripEvaluator(
      stopPoints: line.stops.map((s) => LatLng(s.lat, s.lng)).toList(),
      polyline: _decodePolyline(line.roadPolyline),
      workStart: workStart,
      workEnd: workEnd,
    );

    // İzin, otomasyonu açan panel tarafından Prominent Disclosure ekranıyla
    // birlikte alınmış olmalı. Yoksa otomasyon başlatılmaz.
    if (!await _hasPermission()) {
      debugPrint('[AutoTrip] konum izni yok; otomasyon başlatılmadı');
      _phase = SehiriciAutoTripPhase.stopped;
      return;
    }

    // Devam eden aktif sefer varsa onun üzerinden driving'e geç.
    final active = await _tripService.getDriverActiveTrip(driverId);
    if (active != null) {
      debugPrint('[AutoTrip] start: devam eden aktif sefer var → driving');
      await _enterDriving(active['id'] as String);
    } else {
      debugPrint('[AutoTrip] start: watching fazına geçiliyor');
      _enterWatching();
    }
  }

  /// Otomasyonu tamamen durdur. Aktif sefere dokunmaz (bitirmez).
  Future<void> stop() async {
    // Controller yalnızca driving fazında tracker'ı başlattığı için onu sahiplenir.
    // Watching/stopped fazında tracker panel'e ait olabilir (auto kapalı manuel
    // akış) — ona dokunmayalım.
    final ownedTracker = _phase == SehiriciAutoTripPhase.driving;
    _phase = SehiriciAutoTripPhase.stopped;
    await _watchSub?.cancel();
    _watchSub = null;
    _watchFallback?.cancel();
    _watchFallback = null;
    _endCheckTimer?.cancel();
    _endCheckTimer = null;
    _tracker.onPositionWritten = null;
    if (ownedTracker) {
      await _tracker.stop();
    }
    _evaluator = null;
    _busy = false;
  }

  // ─────────────────────────────────────────────────────────────────────
  // Watching fazı
  // ─────────────────────────────────────────────────────────────────────

  void _enterWatching() {
    _phase = SehiriciAutoTripPhase.watching;
    _evaluator?.reset();

    _watchSub = Geolocator.getPositionStream(
      locationSettings: sehiriciLocationSettings(
        distanceFilter: 40,
        timeLimit: kSampleInterval * 3,
      ),
    ).listen(_onWatchPosition, onError: (e) {
      debugPrint('[AutoTrip] watch stream hata: $e');
    });

    // Stream tetiklenmezse (sabit kalırsa) periyodik örnek al.
    _watchFallback = Timer.periodic(kSampleInterval, (_) async {
      if (_phase != SehiriciAutoTripPhase.watching) return;
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: sehiriciLocationSettings(distanceFilter: 0),
        );
        _onWatchPosition(pos);
      } catch (e) {
        debugPrint('[AutoTrip] fallback örnek hata: $e');
      }
    });
  }

  Future<void> _onWatchPosition(Position pos) async {
    if (_phase != SehiriciAutoTripPhase.watching || _busy) return;
    final evaluator = _evaluator;
    if (evaluator == null) return;
    final decision = evaluator.feed(pos, TimeOfDay.now());
    if (decision == SehiriciAutoStartDecision.start) {
      await _autoStart(pos);
    }
  }

  Future<void> _autoStart(Position pos) async {
    if (_busy || _phase != SehiriciAutoTripPhase.watching) return;
    final driverId = _driverId;
    final line = _line;
    if (driverId == null || line == null) return;
    _busy = true;
    try {
      // Watching akışını durdur; tracker (yazıcı) devralacak.
      await _watchSub?.cancel();
      _watchSub = null;
      _watchFallback?.cancel();
      _watchFallback = null;

      final tripId = await _tripService.startTrip(
        driverId: driverId,
        lineId: line.id,
        lat: pos.latitude,
        lng: pos.longitude,
      );
      if (tripId == null) {
        debugPrint('[AutoTrip] startTrip basarili degil, watching fazina donuluyor');
        _enterWatching();
        return;
      }
      debugPrint('[AutoTrip] otomatik sefer başlatıldı: $tripId');
      await _enterDriving(tripId);
      final cb = onTripAutoStarted;
      if (cb != null) {
        try {
          cb();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[AutoTrip] _autoStart hata: $e');
      _enterWatching();
    } finally {
      _busy = false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Driving fazı
  // ─────────────────────────────────────────────────────────────────────

  Future<void> _enterDriving(String tripId) async {
    _phase = SehiriciAutoTripPhase.driving;

    // Her başarılı konum yazımında bitiş koşullarını değerlendir.
    _tracker.onPositionWritten = _onDrivingPosition;
    await _tracker.start(
      tripId: tripId,
      tripService: _tripService,
      interval: const Duration(seconds: 10),
    );

    // Tracker konum yazmazsa bile (örn. ağ kopması) zaman-bazlı bitiş
    // (çalışma saati sonu) çalışsın.
    _endCheckTimer?.cancel();
    _endCheckTimer = Timer.periodic(kEndCheckInterval, (_) => _checkEnd(null));
    // Girişe hemen bir kontrol: saat zaten dışındaysa hemen bitsin.
    _checkEnd(null);
  }

  void _onDrivingPosition(Position pos) => _checkEnd(pos);

  void _checkEnd(Position? pos) {
    if (_phase != SehiriciAutoTripPhase.driving || _busy) return;
    final reason = _evaluateEndConditions(pos);
    if (reason != null) {
      _autoEnd(reason);
    }
  }

  /// Bitiş koşulları kararı [SehiriciAutoTripEvaluator.evaluateEnd] verir
  /// (onaylanan tek tetikleyici: çalışma saati sonu; son-durak varışı
  /// mimaride hazır ama bilinçli olarak kapalı).
  String? _evaluateEndConditions(Position? pos) {
    return _evaluator?.evaluateEnd(TimeOfDay.now());
  }

  Future<void> _autoEnd(String reason) async {
    if (_busy || _phase != SehiriciAutoTripPhase.driving) return;
    final tripId = _tracker.currentTripId;
    _busy = true;
    try {
      _endCheckTimer?.cancel();
      _endCheckTimer = null;
      if (tripId != null) {
        await _tripService.setStatus(tripId, SehiriciTripStatus.completed);
      }
      await _tracker.stop(); // onPositionWritten callback'i temizler
      debugPrint('[AutoTrip] otomatik sefer bitirildi: $tripId ($reason)');
      final cb = onTripAutoEnded;
      if (cb != null) {
        try {
          cb(reason);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[AutoTrip] _autoEnd hata: $e');
    } finally {
      _busy = false;
      // Çalışma saati bittiyse watching yeniden sefer başlatmaz (saat dışı).
      // Yine de fazı watching'e alalım: saat tekrar girerse otomatik devam.
      if (_phase != SehiriciAutoTripPhase.stopped) _enterWatching();
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Yardımcılar
  // ─────────────────────────────────────────────────────────────────────

  List<LatLng> _decodePolyline(List<List<double>>? raw) {
    if (raw == null) return const [];
    final out = <LatLng>[];
    for (final pair in raw) {
      if (pair.length == 2) {
        out.add(LatLng(pair[0], pair[1]));
      }
    }
    return out;
  }

  /// İzin burada İSTENMEZ, yalnız doğrulanır. Google Play'in Prominent
  /// Disclosure şartı, konum toplanmadan önce uygulama içi açıklamanın
  /// gösterilmesini zorunlu kılar; açıklama ekranı context gerektirdiği için
  /// izin akışı otomasyonu açan panelde yürütülür
  /// (LocationDisclosureService.ensure → LocationPurpose.driverTrip).
  /// İzin yoksa otomasyon hiç başlatılmaz — aksi halde watching fazı sessizce
  /// GPS dinlemeye çalışırdı.
  Future<bool> _hasPermission() async {
    try {
      final permission = await Geolocator.checkPermission();
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (e) {
      debugPrint('[AutoTrip] izin kontrolü hatası: $e');
      return false;
    }
  }
}
