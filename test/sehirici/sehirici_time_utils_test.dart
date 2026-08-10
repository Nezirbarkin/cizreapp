import 'package:flutter_test/flutter_test.dart';
import 'package:cizreapp/sehirici/sehirici.dart';

void main() {
  group('parseHhmm', () {
    test('geçerli "HH:mm" değerlerini parse eder', () {
      expect(parseHhmm('08:30'), (hour: 8, minute: 30));
      expect(parseHhmm('00:00'), (hour: 0, minute: 0));
      expect(parseHhmm('23:59'), (hour: 23, minute: 59));
      expect(parseHhmm('17:05'), (hour: 17, minute: 5));
    });

    test('null ve boş string null döner', () {
      expect(parseHhmm(null), isNull);
      expect(parseHhmm(''), isNull);
    });

    test('geçersiz formatlar null döner', () {
      expect(parseHhmm('24:00'), isNull);
      expect(parseHhmm('12:60'), isNull);
      // '1:30' geçerli (1 saat 30 dakika) — mevcut uygulama "1:30" → 01:30 olarak parse eder
      expect(parseHhmm('1:30'), (hour: 1, minute: 30));
      expect(parseHhmm('abc'), isNull);
      expect(parseHhmm('12'), isNull);
      expect(parseHhmm('12:30:45'), (hour: 12, minute: 30));
    });
  });

  group('formatHhmm', () {
    test('sayıları sıfır dolgulu "HH:mm" yapar', () {
      expect(formatHhmm(8, 5), '08:05');
      expect(formatHhmm(0, 0), '00:00');
      expect(formatHhmm(23, 59), '23:59');
      expect(formatHhmm(17, 30), '17:30');
    });
  });

  group('isValidHhmm', () {
    test('parseHhmm ile tutarlı', () {
      expect(isValidHhmm('08:30'), true);
      expect(isValidHhmm('24:00'), false);
      expect(isValidHhmm(null), false);
      expect(isValidHhmm(''), false);
      expect(isValidHhmm('12:60'), false);
    });
  });

  group('formatHhmm + parseHhmm roundtrip', () {
    test('tüm geçerli saatler için birebir döner', () {
      for (int h = 0; h < 24; h++) {
        for (int m = 0; m < 60; m += 13) {
          final formatted = formatHhmm(h, m);
          final parsed = parseHhmm(formatted);
          expect(parsed, (hour: h, minute: m), reason: 'h=$h m=$m');
        }
      }
    });
  });

  group('isTimeWithinRange', () {
    test('aynı gün aralığında doğru çalışır (08:00-17:00)', () {
      expect(
        isTimeWithinRange(
          currentHour: 7,
          currentMinute: 59,
          startHour: 8,
          startMinute: 0,
          endHour: 17,
          endMinute: 0,
        ),
        false,
      );
      expect(
        isTimeWithinRange(
          currentHour: 8,
          currentMinute: 0,
          startHour: 8,
          startMinute: 0,
          endHour: 17,
          endMinute: 0,
        ),
        true,
      );
      expect(
        isTimeWithinRange(
          currentHour: 12,
          currentMinute: 30,
          startHour: 8,
          startMinute: 0,
          endHour: 17,
          endMinute: 0,
        ),
        true,
      );
      expect(
        isTimeWithinRange(
          currentHour: 17,
          currentMinute: 0,
          startHour: 8,
          startMinute: 0,
          endHour: 17,
          endMinute: 0,
        ),
        false,
      );
    });

    test('gece yarısını geçen aralığı destekler (22:00-06:00)', () {
      expect(
        isTimeWithinRange(
          currentHour: 23,
          currentMinute: 0,
          startHour: 22,
          startMinute: 0,
          endHour: 6,
          endMinute: 0,
        ),
        true,
      );
      expect(
        isTimeWithinRange(
          currentHour: 2,
          currentMinute: 0,
          startHour: 22,
          startMinute: 0,
          endHour: 6,
          endMinute: 0,
        ),
        true,
      );
      expect(
        isTimeWithinRange(
          currentHour: 6,
          currentMinute: 0,
          startHour: 22,
          startMinute: 0,
          endHour: 6,
          endMinute: 0,
        ),
        false,
      );
      expect(
        isTimeWithinRange(
          currentHour: 10,
          currentMinute: 0,
          startHour: 22,
          startMinute: 0,
          endHour: 6,
          endMinute: 0,
        ),
        false,
      );
    });

    test('eşit başlangıç-bitiş (24 saat aktif) doğru çalışır', () {
      // 00:00-00:00 — start == end, mantık: ya >=start ya <end → her zaman true
      // (mevcut kodda startMinutes < endMinutes false olur, OR branch'ına girer)
      // Bu edge case test edilebilir olsun.
      final result = isTimeWithinRange(
        currentHour: 12,
        currentMinute: 0,
        startHour: 0,
        startMinute: 0,
        endHour: 0,
        endMinute: 0,
      );
      // start==end ise her zaman true (mevcut uygulama)
      expect(result, true);
    });
  });

  group('formatDurationHMS', () {
    test('sıfır süre', () {
      expect(formatDurationHMS(Duration.zero), '0:00:00');
    });

    test('dakika ve saniye', () {
      expect(formatDurationHMS(const Duration(seconds: 5)), '0:00:05');
      expect(formatDurationHMS(const Duration(minutes: 3)), '0:03:00');
      expect(
        formatDurationHMS(const Duration(minutes: 3, seconds: 5)),
        '0:03:05',
      );
    });

    test('saat', () {
      expect(formatDurationHMS(const Duration(hours: 1)), '1:00:00');
      expect(
        formatDurationHMS(const Duration(hours: 1, minutes: 1, seconds: 1)),
        '1:01:01',
      );
      expect(
        formatDurationHMS(const Duration(hours: 25, minutes: 30)),
        '25:30:00',
      );
    });
  });

  group('calculateEtaMinutes', () {
    test('sıfır mesafe sıfır ETA', () {
      expect(calculateEtaMinutes(0), 0);
    });

    test('negatif mesafe sıfır ETA', () {
      expect(calculateEtaMinutes(-100), 0);
    });

    test('30 km/s hızla 1 km = 2 dakika', () {
      expect(calculateEtaMinutes(1000), 2);
    });

    test('30 km/s hızla 5 km = 10 dakika', () {
      expect(calculateEtaMinutes(5000), 10);
    });

    test('60 km/s hızla 30 km = 30 dakika', () {
      expect(calculateEtaMinutes(30000, speedKmh: 60), 30);
    });

    test('yuvarlama yakın değerlerde doğru', () {
      // 333 metre @ 30 km/h = 0.666 dk → 1 dk'ya yuvarlanır
      expect(calculateEtaMinutes(333), 1);
      // 167 metre @ 30 km/h = 0.334 dk → 0 dk'ya yuvarlanır
      expect(calculateEtaMinutes(167), 0);
    });
  });
}
