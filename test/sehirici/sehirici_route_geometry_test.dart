import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cizreapp/sehirici/sehirici.dart';

void main() {
  group('simplifyPath', () {
    test('0 ve 1 nokta aynen döner', () {
      expect(simplifyPath(const []), isEmpty);
      expect(simplifyPath(const [LatLng(0, 0)]), [const LatLng(0, 0)]);
    });

    test('2 nokta aynen döner (sadeleştirme yok)', () {
      const input = [LatLng(0, 0), LatLng(0, 0.001)];
      final out = simplifyPath(input);
      expect(out, input);
    });

    test('toleranceMeters <= 0 identity döner', () {
      const input = [
        LatLng(0, 0),
        LatLng(0, 0.0001),
        LatLng(0, 0.0002),
        LatLng(0, 0.0003),
      ];
      final out = simplifyPath(input, toleranceMeters: -1);
      expect(out, input);
    });

    test('düz çizgi üzerindeki orta noktalar kaldırılır', () {
      // Gerçek koordinatlar değil, sadece Douglas-Peucker mantığı test ediliyor.
      const input = [
        LatLng(0, 0),
        LatLng(0, 0.0001),
        LatLng(0, 0.0002),
        LatLng(0, 0.0003),
      ];
      final out = simplifyPath(input, toleranceMeters: 5);
      // Yeterince geniş tolerance ile sadece uç noktalar kalmalı
      expect(out.length, 2);
      expect(out.first, const LatLng(0, 0));
      expect(out.last, const LatLng(0, 0.0003));
    });

    test('köşe noktası korunur', () {
      // L şeklinde: ortadaki köşe noktası belirgin bir sapma
      const input = [LatLng(0, 0), LatLng(0, 0.001), LatLng(0.002, 0.001)];
      final out = simplifyPath(input, toleranceMeters: 0.5);
      expect(out.length, 3);
      expect(out[1], const LatLng(0, 0.001));
    });

    test('boş path hata vermez', () {
      expect(() => simplifyPath(const []), returnsNormally);
    });
  });

  group('pathLengthMeters', () {
    test('tek nokta için 0 döner', () {
      expect(pathLengthMeters(const [LatLng(0, 0)]), 0);
    });

    test('boş path 0 döner', () {
      expect(pathLengthMeters(const []), 0);
    });

    test('yaklaşık 1 km kuzey için ~1000 m döner', () {
      // 0.009 derece enlem ≈ 1000 m
      final path = [const LatLng(37.0, 42.0), const LatLng(37.009, 42.0)];
      final m = pathLengthMeters(path);
      expect(m, greaterThan(990));
      expect(m, lessThan(1010));
    });
  });

  group('estimateDurationMinutes', () {
    test('0 metre 0 dakika', () {
      expect(estimateDurationMinutes(0), 0);
    });

    test('1000 metre varsayılan 30 km/h ile 2 dakika', () {
      expect(estimateDurationMinutes(1000), 2);
    });

    test('özel hız: 60 km/h, 1000 m = 1 dakika', () {
      expect(estimateDurationMinutes(1000, averageSpeedKmh: 60), 1);
    });
  });

  group('bearingDegrees', () {
    test('kuzey yönü yaklaşık 0° döner', () {
      final b = bearingDegrees(const LatLng(0, 0), const LatLng(0.01, 0));
      expect(b, closeTo(0, 1));
    });

    test('doğu yönü yaklaşık 90° döner', () {
      final b = bearingDegrees(const LatLng(0, 0), const LatLng(0, 0.01));
      expect(b, closeTo(90, 1));
    });

    test('güney yönü yaklaşık 180° döner', () {
      final b = bearingDegrees(const LatLng(0.01, 0), const LatLng(0, 0));
      expect(b, closeTo(180, 1));
    });

    test('batı yönü yaklaşık 270° döner', () {
      final b = bearingDegrees(const LatLng(0, 0.01), const LatLng(0, 0));
      expect(b, closeTo(270, 1));
    });
  });

  group('bearingToCardinal', () {
    test('0° K', () => expect(bearingToCardinal(0), 'K'));
    test('90° D', () => expect(bearingToCardinal(90), 'D'));
    test('180° G', () => expect(bearingToCardinal(180), 'G'));
    test('270° B', () => expect(bearingToCardinal(270), 'B'));
    test('45° KD', () => expect(bearingToCardinal(45), 'KD'));
    test('360° K (dairesel)', () => expect(bearingToCardinal(360), 'K'));
  });
}
