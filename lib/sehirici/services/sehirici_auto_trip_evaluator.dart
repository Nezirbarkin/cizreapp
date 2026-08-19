import 'package:flutter/material.dart' show TimeOfDay;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import '../utils/sehirici_route_geometry.dart';
import '../utils/sehirici_time_utils.dart';

/// Watching fazının bir GPS örneğini işlettikten sonra verilen karar.
enum SehiriciAutoStartDecision {
  /// Çalışma saati dışı — buffer sıfırlandı, sefer başlatılmaz.
  outsideWorkingHours,

  /// Sinyal buffer'a eklendi ama M-of-N henüz sağlanmadı.
  accumulate,

  /// Son k örnekten en az m'i pozitif — sefer başlatılmalı.
  start,
}

/// Şoför otomasyonunun **karar çekirdeği**: "sefer başlatmalı mıyım /
/// bitirmeli miyim?" sorusunun tamamı burada, saf fonksiyonlar halinde.
///
/// [SehiriciAutoTripController] faz/timer/tracker yönetimini üstlenir ve saat
/// ile konumu dışarıdan vererek bu sınıfı çağırır (`TimeOfDay.now()` yalnız
/// controller'da çağrılır). Böylece karar mantığı gerçek fiziksel senaryolarla
/// (konum metreleri, hız m/s, saat/dakika) birebir test edilebilir.
///
/// Eşikler ve M-of-N parametreleri controller'dan birebir taşınmıştır;
/// davranış değişikliği değildir.
class SehiriciAutoTripEvaluator {
  SehiriciAutoTripEvaluator({
    required List<LatLng> stopPoints,
    List<LatLng> polyline = const [],
    this.workStart,
    this.workEnd,
  }) : stopPoints = List.unmodifiable(stopPoints),
       polyline = List.unmodifiable(polyline);

  // ── Ayarlanabilir eşikler ────────────────────────────────────────────
  /// Hareket sayılan minimum hız (m/s, ~10.8 km/s).
  static const double kMoveSpeedMs = 3.0;
  /// Hareket sayılan minimum yer değiştirme (metre, hız okunamazsa).
  static const double kMoveDistanceM = 50.0;
  /// "Hat bölgesinde" sayılmak için rota/durak koridoru genişliği (metre).
  static const double kCorridorM = 300.0;
  /// Sürdürülebilirlik: son K örnekten en az M'i koşulları sağlamalı.
  static const int kBufferLen = 3;
  static const int kBufferNeed = 2;

  // (Opsiyonel, mimaride hazır — kullanıcı seçmedi. Açmak için koşulu
  //  evaluateEnd içine ekleyin.)
  // static const double kLastStopRadiusM = 150.0;

  /// Hat durakları ve (varsa) rota polyline'ı.
  final List<LatLng> stopPoints;
  final List<LatLng> polyline;

  /// Çalışma saatleri. İkisi de null ise saat koşulu sürekli sağlanır.
  final TimeOfDay? workStart;
  final TimeOfDay? workEnd;

  // ── Dinamik durum (yalnızca feed günceller) ─────────────────────────
  final List<bool> _buffer = [];
  Position? _lastSample;

  /// Örnek buffer'ını ve son örneği sıfırlar (watching fazına girişte).
  void reset() {
    _buffer.clear();
    _lastSample = null;
  }

  /// Watching fazının bir GPS örneğini işler: başlatma sinyalini hesaplar,
  /// M-of-N buffer'ına ekler ve karar döner.
  ///
  /// Çalışma saati dışındaki örnek buffer'ı sıfırlar (yarım kalan pozitif
  /// seriler saat dışına/sonrasına taşınmaz) ve asla [SehiriciAutoStartDecision.start]
  /// dönmez — controller'daki `_onWatchPosition` akışının birebir kendisidir.
  SehiriciAutoStartDecision feed(Position pos, TimeOfDay now) {
    final previous = _lastSample;
    final withinHours = isWithinWorkingHours(now);
    bool signal;
    if (!withinHours) {
      _buffer.clear();
      signal = false;
    } else {
      signal = isMoving(pos, previous) && isNearLine(pos);
    }
    _lastSample = pos;
    _buffer.add(signal);
    if (_buffer.length > kBufferLen) {
      _buffer.removeAt(0);
    }

    final positives = _buffer.where((s) => s).length;
    if (_buffer.length >= kBufferNeed && positives >= kBufferNeed) {
      return SehiriciAutoStartDecision.start;
    }
    return withinHours
        ? SehiriciAutoStartDecision.accumulate
        : SehiriciAutoStartDecision.outsideWorkingHours;
  }

  /// Bitiş koşulları. Onaylanan tek tetikleyici: çalışma saati sonu.
  /// (Son-durak varışı mimaride hazırdır; açmak için buraya ekleyin.)
  String? evaluateEnd(TimeOfDay now) {
    if (workStart != null && workEnd != null && !isWithinWorkingHours(now)) {
      return 'Çalışma saatleri bitti';
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────
  // Koşul yardımcıları (controller'dan birebir taşındı)
  // ─────────────────────────────────────────────────────────────────────

  bool isWithinWorkingHours(TimeOfDay now) {
    if (workStart == null || workEnd == null) return true; // ayar yoksa sürekli uygun
    return isTimeWithinRange(
      currentHour: now.hour,
      currentMinute: now.minute,
      startHour: workStart!.hour,
      startMinute: workStart!.minute,
      endHour: workEnd!.hour,
      endMinute: workEnd!.minute,
    );
  }

  bool isMoving(Position pos, Position? previous) {
    // GPS hız okunabilir ve eşik üstündeyse kesin hareket.
    if (!pos.speed.isNaN && pos.speed > 0 && pos.speed >= kMoveSpeedMs) {
      return true;
    }
    // Hız yoksa/yetersizse yer değiştirmeye bak.
    if (previous == null) return false;
    final d = distanceMeters(
      LatLng(previous.latitude, previous.longitude),
      LatLng(pos.latitude, pos.longitude),
    );
    return d >= kMoveDistanceM;
  }

  bool isNearLine(Position pos) =>
      distanceToLineMeters(LatLng(pos.latitude, pos.longitude)) <= kCorridorM;

  /// Konumun duraklara/rotaya en yakın kuş uçuşu mesafesi (metre).
  double distanceToLineMeters(LatLng p) {
    double best = double.infinity;
    for (final s in stopPoints) {
      final d = distanceMeters(p, s);
      if (d < best) best = d;
    }
    if (polyline.length >= 2) {
      final pd = nearestDistanceToPolylineMeters(p, polyline);
      if (pd < best) best = pd;
    }
    return best;
  }
}
