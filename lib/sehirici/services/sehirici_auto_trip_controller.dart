import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import '../models/sehirici_models.dart';
import '../utils/sehirici_route_geometry.dart';
import '../utils/sehirici_time_utils.dart';
import 'sehirici_location_tracker.dart';
import 'sehirici_trip_service.dart';

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
class SehiriciAutoTripController {
  SehiriciAutoTripController._internal();
  static final SehiriciAutoTripController instance =
      SehiriciAutoTripController._internal();

  enum Phase { stopped, watching, driving }

  final SehiriciTripService _tripService = SehiriciTripService();
  final SehiriciLocationTracker _tracker = SehiriciLocationTracker();

  Phase _phase = Phase.stopped;
  Phase get phase => _phase;
  bool get isActive => _phase != Phase.stopped;
  bool get isWatching => _phase == Phase.watching;
  bool get isDriving => _phase == Phase.driving;

  // ── Ayarlanabilir eşikler ────────────────────────────────────────────
  /// Hareket sayılan minimum hız (m/s, ~10.8 km/s).
  static const double kMoveSpeedMs = 3.0;
  /// Hareket sayılan minimum yer değiştirme (metre, hız okunamazsa).
  static const double kMoveDistanceM = 50.0;
  /// "Hat bölgesinde" sayılmak için rota/durak koridoru genişliği (metre).
  static const double kCorridorM = 300.0;
  /// Watching fazı örnek aralığı (stream tetiklenmezse fallback timer).
  static const Duration kSampleInterval = Duration(seconds: 25);
  /// Sürdürülebilirlik: son K örnekten en az M'i koşulları sağlamalı.
  static const int kBufferLen = 3;
  static const int kBufferNeed = 2;
  /// Driving fazı bitiş kontrolü periyodu (tracker'a ek olarak zaman-bazlı).
  static const Duration kEndCheckInterval = Duration(seconds: 60);

  // (Opsiyonel, mimaride hazır — kullanıcı seçmedi. Açmak için koşulu
  //  _evaluateEndConditions içine ekleyin.)
  // static const double kLastStopRadiusM = 150.0;

  // ── Konfigürasyon (start ile verilir) ─────────────────────────────────
  String? _driverId;
  SehiriciLine? _line;
  TimeOfDay? _workStart;
  TimeOfDay? _workEnd;
  List<LatLng> _stopPoints = const [];
  List<LatLng> _polyline = const [];

  // ── Dinamik durum ─────────────────────────────────────────────────────
  StreamSubscription<Position>? _watchSub;
  Timer? _watchFallback;
  Timer? _endCheckTimer;
  Position? _lastWatchPosition;
  final List<bool> _startBuffer = [];
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
    if (_phase != Phase.stopped) {
      await stop();
    }
    _driverId = driverId;
    _line = line;
    _workStart = workStart;
    _workEnd = workEnd;
    _stopPoints = line.stops.map((s) => LatLng(s.lat, s.lng)).toList();
    _polyline = _decodePolyline(line.roadPolyline);
    _startBuffer.clear();

    // Konum izni (arka plan dahil). Reddedilirse yine de deneyelim — ön plan
    // içinde çalışır.
    await _ensurePermission();

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
    _phase = Phase.stopped;
    await _watchSub?.cancel();
    _watchSub = null;
    _watchFallback?.cancel();
    _watchFallback = null;
    _endCheckTimer?.cancel();
    _endCheckTimer = null;
    _tracker.onPositionWritten = null;
    _lastWatchPosition = null;
    _startBuffer.clear();
    _busy = false;
  }

  // ─────────────────────────────────────────────────────────────────────
  // Watching fazı
  // ─────────────────────────────────────────────────────────────────────

  void _enterWatching() {
    _phase = Phase.watching;
    _startBuffer.clear();
    _lastWatchPosition = null;

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
      if (_phase != Phase.watching) return;
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
    if (_phase != Phase.watching || _busy) return;
    final signal = _evaluateStartSignal(pos);
    _lastWatchPosition = pos;
    _startBuffer.add(signal);
    if (_startBuffer.length > kBufferLen) {
      _startBuffer.removeAt(0);
    }

    final positives = _startBuffer.where((s) => s).length;
    if (_startBuffer.length >= kBufferNeed && positives >= kBufferNeed) {
      await _autoStart(pos);
    }
  }

  /// 4 koşulun hepsi sağlanıyor mu? (sürdürülebilirlik ayrıca M-of-N ile)
  bool _evaluateStartSignal(Position pos) {
    if (!_isWithinWorkingHours()) {
      _startBuffer.clear();
      return false;
    }
    final moved = _isMoving(pos);
    final near = _isNearLine(pos);
    return moved && near;
  }

  Future<void> _autoStart(Position pos) async {
    if (_busy || _phase != Phase.watching) return;
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
        debugPrint('[AutoTrip] startTrip başarısız → watching'e geri dönülüyor');
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
    _phase = Phase.driving;

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
    if (_phase != Phase.driving || _busy) return;
    final reason = _evaluateEndConditions(pos);
    if (reason != null) {
      _autoEnd(reason);
    }
  }

  /// Bitiş koşulları. Onaylanan tek tetikleyici: çalışma saati sonu.
  /// (Son-durak varışı mimaride hazırdır; açmak için buraya ekleyin.)
  String? _evaluateEndConditions(Position? pos) {
    if (_workStart != null && _workEnd != null && !_isWithinWorkingHours()) {
      return 'Çalışma saatleri bitti';
    }
    // ── Opsiyonel: son durak varışı (kullanıcı seçmedi) ───────────────
    // if (pos != null && _stopPoints.isNotEmpty) {
    //   final last = _stopPoints.last;
    //   if (distanceMeters(LatLng(pos.latitude, pos.longitude), last)
    //         <= kLastStopRadiusM &&
    //       (pos.speed < 1.0)) {
    //     return 'Son durağa ulaşıldı';
    //   }
    // }
    return null;
  }

  Future<void> _autoEnd(String reason) async {
    if (_busy || _phase != Phase.driving) return;
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
      if (_phase != Phase.stopped) _enterWatching();
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Koşul yardımcıları
  // ─────────────────────────────────────────────────────────────────────

  bool _isWithinWorkingHours() {
    if (_workStart == null || _workEnd == null) return true; // ayar yoksa sürekli uygun
    final now = TimeOfDay.now();
    return isTimeWithinRange(
      currentHour: now.hour,
      currentMinute: now.minute,
      startHour: _workStart!.hour,
      startMinute: _workStart!.minute,
      endHour: _workEnd!.hour,
      endMinute: _workEnd!.minute,
    );
  }

  bool _isMoving(Position pos) {
    // GPS hız okunabilir ve eşik üstündeyse kesin hareket.
    if (!pos.speed.isNaN && pos.speed > 0 && pos.speed >= kMoveSpeedMs) {
      return true;
    }
    // Hız yoksa/yetersizse yer değiştirmeye bak.
    final last = _lastWatchPosition;
    if (last == null) return false;
    final d = distanceMeters(
      LatLng(last.latitude, last.longitude),
      LatLng(pos.latitude, pos.longitude),
    );
    return d >= kMoveDistanceM;
  }

  bool _isNearLine(Position pos) {
    final p = LatLng(pos.latitude, pos.longitude);
    double best = double.infinity;
    for (final s in _stopPoints) {
      final d = distanceMeters(p, s);
      if (d < best) best = d;
    }
    if (_polyline.length >= 2) {
      final pd = nearestDistanceToPolylineMeters(p, _polyline);
      if (pd < best) best = pd;
    }
    return best <= kCorridorM;
  }

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

  Future<void> _ensurePermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      // Arka plan izni (Android "Her zaman izin ver" / iOS) kullanıcı tarafından
      // sistem ayarlarından verilir; burada while-in-use talep ederiz.
    } catch (e) {
      debugPrint('[AutoTrip] izin kontrolü hatası: $e');
    }
  }
}
