// Şoför otomasyon karar çekirdeğinin (SehiriciAutoTripEvaluator) fiziksel
// senaryolarla birebir testi.
//
// Teknik not: mesafeler testlerde "kuzeye X metre" ofsetleriyle kurulur.
// Haversine formülünde boylam farkı sıfır olduğunda mesafe tam R·Δφ'dir
// (R = 6371000 m) — dolayısıyla eşik sınırları (50 m, 300 m) kayan nokta
// belirsizliği olmadan, fiziksel olarak tam kurulabilir.
import 'dart:math' as math;

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:cizreapp/sehirici/services/sehirici_auto_trip_evaluator.dart';

const double _kEarthRadiusM = 6371000.0;

/// Meridyen (saf kuzey/güney) boyunca tam `meters` metreye karşılık gelen
/// enlem farkı (derece). Haversine'te tam R·Δφ verir.
double _latOffset(double meters) => meters / _kEarthRadiusM * 180 / math.pi;

/// Cizre merkez yakınında bir hat: A durağı ve 1 km kuzeydeki B durağı.
const double _kStopALat = 37.3320;
const double _kStopALng = 42.1900;
final LatLng _stopA = LatLng(_kStopALat, _kStopALng);
final LatLng _stopB = LatLng(_kStopALat + _latOffset(1000), _kStopALng);
final LatLng _midAB = LatLng(_kStopALat + _latOffset(500), _kStopALng);

/// A──orta──B hattı: meridyen boyunca düz rota polyline'ı.
List<LatLng> get _linePolyline => [_stopA, _midAB, _stopB];

/// `metersNorth` A durağının kuzeyi (negatifse güneyi), `metersEast` doğusu.
Position _driver({
  double metersNorth = 0,
  double metersEast = 0,
  double speed = 0,
}) {
  final lat = _kStopALat + _latOffset(metersNorth);
  final lng =
      _kStopALng + metersEast / (111320 * math.cos(_kStopALat * math.pi / 180));
  return Position(
    latitude: lat,
    longitude: lng,
    timestamp: DateTime(2026, 5, 28, 12),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: speed,
    speedAccuracy: 0.5,
  );
}

SehiriciAutoTripEvaluator _evaluator({
  TimeOfDay? workStart = const TimeOfDay(hour: 8, minute: 0),
  TimeOfDay? workEnd = const TimeOfDay(hour: 18, minute: 0),
  bool withPolyline = true,
}) {
  return SehiriciAutoTripEvaluator(
    stopPoints: [_stopA, _stopB],
    polyline: withPolyline ? _linePolyline : const [],
    workStart: workStart,
    workEnd: workEnd,
  );
}

void main() {
  // ─────────────────────────────────────────────────────────────────────
  // ÇALIŞMA SAATLERİ (vardiya penceresi)
  // ─────────────────────────────────────────────────────────────────────
  group('isWithinWorkingHours — gündüz vardiyası 08:00–18:00', () {
    final ev = _evaluator();

    test('07:59 vardiya başlamadı → dışarı', () {
      expect(
        ev.isWithinWorkingHours(const TimeOfDay(hour: 7, minute: 59)),
        isFalse,
      );
    });
    test('08:00 tam başlangıç anı → içinde (başlangıç dahil)', () {
      expect(
        ev.isWithinWorkingHours(const TimeOfDay(hour: 8, minute: 0)),
        isTrue,
      );
    });
    test('17:59 son dakika → içinde', () {
      expect(
        ev.isWithinWorkingHours(const TimeOfDay(hour: 17, minute: 59)),
        isTrue,
      );
    });
    test('18:00 tam bitiş anı → dışarı (bitiş hariç)', () {
      expect(
        ev.isWithinWorkingHours(const TimeOfDay(hour: 18, minute: 0)),
        isFalse,
      );
    });
  });

  group('isWithinWorkingHours — gece vardiyası 22:00–06:00', () {
    final ev = _evaluator(
      workStart: const TimeOfDay(hour: 22, minute: 0),
      workEnd: const TimeOfDay(hour: 6, minute: 0),
    );

    test('21:59 → dışarı', () {
      expect(
        ev.isWithinWorkingHours(const TimeOfDay(hour: 21, minute: 59)),
        isFalse,
      );
    });
    test('22:00 → içinde', () {
      expect(
        ev.isWithinWorkingHours(const TimeOfDay(hour: 22, minute: 0)),
        isTrue,
      );
    });
    test('23:30 gece yarısı öncesi → içinde', () {
      expect(
        ev.isWithinWorkingHours(const TimeOfDay(hour: 23, minute: 30)),
        isTrue,
      );
    });
    test('00:10 gece yarısı sonrası → içinde', () {
      expect(
        ev.isWithinWorkingHours(const TimeOfDay(hour: 0, minute: 10)),
        isTrue,
      );
    });
    test('05:59 son dakika → içinde', () {
      expect(
        ev.isWithinWorkingHours(const TimeOfDay(hour: 5, minute: 59)),
        isTrue,
      );
    });
    test('06:00 tam bitiş → dışarı', () {
      expect(
        ev.isWithinWorkingHours(const TimeOfDay(hour: 6, minute: 0)),
        isFalse,
      );
    });
    test('12:00 öğlen → dışarı', () {
      expect(
        ev.isWithinWorkingHours(const TimeOfDay(hour: 12, minute: 0)),
        isFalse,
      );
    });
  });

  group('isWithinWorkingHours — saat ayarlanmamışsa', () {
    final ev = _evaluator(workStart: null, workEnd: null);

    test('gece 03:00 dahil her saat içinde (koşulsuz mod)', () {
      for (final t in [
        const TimeOfDay(hour: 3, minute: 0),
        const TimeOfDay(hour: 12, minute: 0),
        const TimeOfDay(hour: 23, minute: 59),
      ]) {
        expect(ev.isWithinWorkingHours(t), isTrue);
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // HAREKET FİZİĞİ (hız ve yer değiştirme)
  // ─────────────────────────────────────────────────────────────────────
  group('isMoving — hız kanalı', () {
    final ev = _evaluator();

    test('3.0 m/s (10.8 km/s) tam eşik → hareket sayılır (>= sınırı)', () {
      expect(ev.isMoving(_driver(speed: 3.0), null), isTrue);
    });
    test('2.9 m/s yavaş sürüş, yer değiştirme yok → hareket sayılmaz', () {
      final still = _driver(metersNorth: 100, speed: 2.9);
      expect(
        ev.isMoving(_driver(metersNorth: 100, speed: 2.9), still),
        isFalse,
      );
    });
    test('8 m/s (~29 km/s) şehir içi sürüş → hareket', () {
      expect(ev.isMoving(_driver(speed: 8), null), isTrue);
    });
  });

  group('isMoving — yer değiştirme kanalı (GPS hızı okunamadığında)', () {
    final ev = _evaluator();

    test('hız 0, 50.1 m kuzeye kaymış → hareket (eşik 50 m üzeri)', () {
      // "Tam 50 m" geometric kurulamaz: haversine float zinciri son-bit
      // yuvarlamasıyla 49.999…9 dönebilir. >= sınırının dahil olduğu hız
      // kanalında (tam 3.0 m/s) deterministik test edilir.
      final prev = _driver(metersNorth: 100);
      final now = _driver(metersNorth: 150.1);
      expect(ev.isMoving(now, prev), isTrue);
    });
    test('hız 0, 49.9 m → henüz hareket sayılmaz', () {
      final prev = _driver(metersNorth: 100);
      final now = _driver(metersNorth: 149.9);
      expect(ev.isMoving(now, prev), isFalse);
    });
    test('hız NaN (okunamıyor), 80 m kaymış → hareket', () {
      final prev = _driver(metersNorth: 0);
      final now = Position(
        latitude: prev.latitude + _latOffset(80),
        longitude: prev.longitude,
        timestamp: prev.timestamp,
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: double.nan,
        speedAccuracy: 0.5,
      );
      expect(ev.isMoving(now, prev), isTrue);
    });
    test('ilk örnek (önceki yok), hız 0 → hareket sayılmaz', () {
      expect(ev.isMoving(_driver(metersNorth: 100, speed: 0), null), isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // HAT KORİDORU FİZİĞİ (durak + rota polyline'ı)
  // ─────────────────────────────────────────────────────────────────────
  group('isNearLine — koridor genişliği 300 m', () {
    final ev = _evaluator();

    test('durağın üzerinde (0 m) → hat bölgesinde', () {
      expect(ev.distanceToLineMeters(_stopA), lessThan(1));
      expect(ev.isNearLine(_driver(metersNorth: 0)), isTrue);
    });
    test(
      'duraktan ~300 m (meridyen): polyline equirectangular yaklaşımı ~2 m',
      () {
        // Fiziksel 300 m'de durak haversine'ı tam 300 verir; polyline koridoru
        // ise equirectangular sabitleri (110540 m/° vs gerçek ~111195 m/°)
        // kullandığından ~298.2 hesaplar. Yaklaşım sapması < 2 m.
        final pos = _driver(metersNorth: -300);
        expect(
          ev.distanceToLineMeters(LatLng(pos.latitude, pos.longitude)),
          closeTo(300, 2),
        );
        expect(ev.isNearLine(pos), isTrue);
      },
    );
    test('durak sınırının iki yanı: 299.9 m içeride, 300.1 m dışarıda', () {
      // Polyline'ın girişimini kaldırıp yalnız durak haversine'ı ile deterministik
      // sınır testi (polyline'sız evaluator).
      final stopsOnly = _evaluator(withPolyline: false);
      expect(stopsOnly.isNearLine(_driver(metersNorth: -299.9)), isTrue);
      expect(stopsOnly.isNearLine(_driver(metersNorth: -300.1)), isFalse);
    });
    test('duraktan 350 m → hat bölgesi dışında', () {
      expect(ev.isNearLine(_driver(metersNorth: -350)), isFalse);
    });
    test('duraklara ~2 km → dışında', () {
      expect(ev.isNearLine(_driver(metersNorth: -2000)), isFalse);
    });
    test(
      'duraklardan uzak ama rota üzerinde: orta noktadan 100 m yan → içinde',
      () {
        // A ve B'nin ortası duraklara ~500 m uzak; polyline koridoru kurtarır.
        final pos = _driver(metersNorth: 500, metersEast: 100);
        expect(
          ev.distanceToLineMeters(LatLng(pos.latitude, pos.longitude)),
          lessThan(120),
        );
        expect(ev.isNearLine(pos), isTrue);
      },
    );
  });

  group('isNearLine — rota polyline yoksa yalnız duraklar', () {
    final ev = _evaluator(withPolyline: false);

    test('duraktan 250 m → içinde', () {
      expect(ev.isNearLine(_driver(metersNorth: -250)), isTrue);
    });
    test('duraklar arası yolda, en yakın duraktan 400 m → dışında', () {
      expect(ev.isNearLine(_driver(metersNorth: -400)), isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // BAŞLATMA KARARI — M-of-N ÖRNEK BUFFER'I
  // ─────────────────────────────────────────────────────────────────────
  group('feed — sefer başlatma (2-of-3 sürdürülebilirlik)', () {
    test('iki ardışık pozitif örnek (hat üzerinde 29 km/s) → başlat', () {
      final ev = _evaluator();
      final t = const TimeOfDay(hour: 10, minute: 0);
      expect(
        ev.feed(_driver(metersNorth: 100, speed: 8), t),
        SehiriciAutoStartDecision.accumulate,
      );
      expect(
        ev.feed(_driver(metersNorth: 300, speed: 8), t),
        SehiriciAutoStartDecision.start,
      );
    });

    test(
      'kırmızı ışık: pozitif → bekleme → pozitif → yine başlat (2-of-3)',
      () {
        final ev = _evaluator();
        final t = const TimeOfDay(hour: 10, minute: 0);
        final atStop = _driver(metersNorth: 200, speed: 8);
        expect(ev.feed(atStop, t), SehiriciAutoStartDecision.accumulate);
        // Durakta bekleme: aynı konum, hız 0 → negatif sinyal.
        expect(
          ev.feed(_driver(metersNorth: 200, speed: 0), t),
          SehiriciAutoStartDecision.accumulate,
        );
        // Tekrar hareket → son 3 örnek [P, N, P] = 2 pozitif.
        expect(
          ev.feed(_driver(metersNorth: 400, speed: 8), t),
          SehiriciAutoStartDecision.start,
        );
      },
    );

    test('tek pozitif sonra sürekli durma → başlatılmaz', () {
      final ev = _evaluator();
      final t = const TimeOfDay(hour: 10, minute: 0);
      expect(
        ev.feed(_driver(metersNorth: 100, speed: 8), t),
        SehiriciAutoStartDecision.accumulate,
      );
      expect(
        ev.feed(_driver(metersNorth: 100, speed: 0), t),
        SehiriciAutoStartDecision.accumulate,
      );
      expect(
        ev.feed(_driver(metersNorth: 100, speed: 0), t),
        SehiriciAutoStartDecision.accumulate,
      );
    });

    test('hat koridorundan uzakta araç kullanmak → başlatılmaz', () {
      final ev = _evaluator();
      final t = const TimeOfDay(hour: 10, minute: 0);
      // 2 km ötede 60 km/s ile gitmek de yetmez: hat bölgesi koşulu.
      expect(
        ev.feed(_driver(metersNorth: -2000, speed: 16.7), t),
        SehiriciAutoStartDecision.accumulate,
      );
      expect(
        ev.feed(_driver(metersNorth: -1700, speed: 16.7), t),
        SehiriciAutoStartDecision.accumulate,
      );
      expect(
        ev.feed(_driver(metersNorth: -1400, speed: 16.7), t),
        SehiriciAutoStartDecision.accumulate,
      );
    });

    test(
      'çalışma saati dışında (03:00) hareket + hat üzerinde olsa bile → asla',
      () {
        final ev = _evaluator();
        final night = const TimeOfDay(hour: 3, minute: 0);
        for (var i = 0; i < 5; i++) {
          expect(
            ev.feed(_driver(metersNorth: 100.0 + i * 200, speed: 8), night),
            SehiriciAutoStartDecision.outsideWorkingHours,
          );
        }
      },
    );

    test(
      'saat dışı örnek buffer\'ı sıfırlar: akşamki pozitif sabaha taşımaz',
      () {
        final ev = _evaluator();
        // 17:58 hat üzerinde hareket → pozitif.
        expect(
          ev.feed(
            _driver(metersNorth: 100, speed: 8),
            const TimeOfDay(hour: 17, minute: 58),
          ),
          SehiriciAutoStartDecision.accumulate,
        );
        // 17:59 durdu → [P, N].
        expect(
          ev.feed(
            _driver(metersNorth: 100, speed: 0),
            const TimeOfDay(hour: 17, minute: 59),
          ),
          SehiriciAutoStartDecision.accumulate,
        );
        // 18:05 saat dışı → buffer temizlendi.
        expect(
          ev.feed(
            _driver(metersNorth: 100, speed: 8),
            const TimeOfDay(hour: 18, minute: 5),
          ),
          SehiriciAutoStartDecision.outsideWorkingHours,
        );
        // Ertesi sabah 08:01 pozitif → buffer [N, P], 1 pozitif yetmez.
        expect(
          ev.feed(
            _driver(metersNorth: 300, speed: 8),
            const TimeOfDay(hour: 8, minute: 1),
          ),
          SehiriciAutoStartDecision.accumulate,
        );
        // 08:02 pozitif → 2 pozitif → başlat.
        expect(
          ev.feed(
            _driver(metersNorth: 500, speed: 8),
            const TimeOfDay(hour: 8, minute: 2),
          ),
          SehiriciAutoStartDecision.start,
        );
      },
    );

    test('gece vardiyası 22:00–06:00: 23:00\'de iki pozitif → başlat', () {
      final ev = _evaluator(
        workStart: const TimeOfDay(hour: 22, minute: 0),
        workEnd: const TimeOfDay(hour: 6, minute: 0),
      );
      final t = const TimeOfDay(hour: 23, minute: 0);
      expect(
        ev.feed(_driver(metersNorth: 100, speed: 8), t),
        SehiriciAutoStartDecision.accumulate,
      );
      expect(
        ev.feed(_driver(metersNorth: 300, speed: 8), t),
        SehiriciAutoStartDecision.start,
      );
    });

    test('saat ayarı yoksa gece 03:00\'te de koşullar sağlanınca başlat', () {
      final ev = _evaluator(workStart: null, workEnd: null);
      final t = const TimeOfDay(hour: 3, minute: 0);
      expect(
        ev.feed(_driver(metersNorth: 100, speed: 8), t),
        SehiriciAutoStartDecision.accumulate,
      );
      expect(
        ev.feed(_driver(metersNorth: 300, speed: 8), t),
        SehiriciAutoStartDecision.start,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // BİTİŞ KARARI (yalnız çalışma saati sonu)
  // ─────────────────────────────────────────────────────────────────────
  group('evaluateEnd — çalışma saati sonu tetikleyicisi', () {
    test('gündüz vardiyası: 17:59 bitmez, 18:00 biter, 18:01 biter', () {
      final ev = _evaluator();
      expect(ev.evaluateEnd(const TimeOfDay(hour: 17, minute: 59)), isNull);
      expect(
        ev.evaluateEnd(const TimeOfDay(hour: 18, minute: 0)),
        'Çalışma saatleri bitti',
      );
      expect(
        ev.evaluateEnd(const TimeOfDay(hour: 18, minute: 1)),
        'Çalışma saatleri bitti',
      );
    });

    test('vardiya başlamadan (07:00) da saat dışı → bitiş sebebi', () {
      final ev = _evaluator();
      expect(
        ev.evaluateEnd(const TimeOfDay(hour: 7, minute: 0)),
        'Çalışma saatleri bitti',
      );
    });

    test('gece vardiyası: 05:59 bitmez, 06:00 biter', () {
      final ev = _evaluator(
        workStart: const TimeOfDay(hour: 22, minute: 0),
        workEnd: const TimeOfDay(hour: 6, minute: 0),
      );
      expect(ev.evaluateEnd(const TimeOfDay(hour: 5, minute: 59)), isNull);
      expect(
        ev.evaluateEnd(const TimeOfDay(hour: 6, minute: 0)),
        'Çalışma saatleri bitti',
      );
    });

    test(
      'saat ayarlanmamışsa hiçbir saatte otomatik bitmez (elle bitirilir)',
      () {
        final ev = _evaluator(workStart: null, workEnd: null);
        for (final t in [
          const TimeOfDay(hour: 3, minute: 0),
          const TimeOfDay(hour: 12, minute: 0),
          const TimeOfDay(hour: 23, minute: 0),
        ]) {
          expect(ev.evaluateEnd(t), isNull);
        }
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────
  // TAM GÜN SİMÜLASYONU — fiziksel akış birebir
  // ─────────────────────────────────────────────────────────────────────
  group('tam gün simülasyonu (07:30–18:00 vardiyası)', () {
    test('sabah hattına yanaşma → öğlen sürüş → akşam otomatik bitiş', () {
      final ev = _evaluator(
        workStart: const TimeOfDay(hour: 7, minute: 30),
        workEnd: const TimeOfDay(hour: 18, minute: 0),
      );

      // 07:31 — evden çıkıldı, hat 2 km ötede: saat uygun ama hat dışı.
      expect(
        ev.feed(
          _driver(metersNorth: -2000, speed: 8),
          const TimeOfDay(hour: 7, minute: 31),
        ),
        SehiriciAutoStartDecision.accumulate,
      );
      // 07:33 — hatta yaklaşıyor (1400 m) ama hâlâ dışarıda.
      expect(
        ev.feed(
          _driver(metersNorth: -1400, speed: 8),
          const TimeOfDay(hour: 7, minute: 33),
        ),
        SehiriciAutoStartDecision.accumulate,
      );
      // 07:36 — hat koridoruna girdi (250 m), hareket sürüyor → ilk pozitif.
      expect(
        ev.feed(
          _driver(metersNorth: -250, speed: 8),
          const TimeOfDay(hour: 7, minute: 36),
        ),
        SehiriciAutoStartDecision.accumulate,
      );
      // 07:39 — ikinci pozitif → otomatik sefer başlamalı.
      expect(
        ev.feed(
          _driver(metersNorth: -100, speed: 8),
          const TimeOfDay(hour: 7, minute: 39),
        ),
        SehiriciAutoStartDecision.start,
      );

      // Sürüş boyunca bitiş koşulu yok.
      expect(ev.evaluateEnd(const TimeOfDay(hour: 12, minute: 0)), isNull);
      expect(ev.evaluateEnd(const TimeOfDay(hour: 17, minute: 59)), isNull);
      // 18:00 — otomatik bitiş.
      expect(
        ev.evaluateEnd(const TimeOfDay(hour: 18, minute: 0)),
        'Çalışma saatleri bitti',
      );
    });
  });
}
