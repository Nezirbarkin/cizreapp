import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cizreapp/sehirici/utils/sehirici_route_geometry.dart';

/// "Rota her tarafa çizgi çekiyor" hatasının geometri tarafı.
///
/// Kök neden: uzun GPS izleri OSRM'nin 80 koordinat sınırına sığsın diye
/// *indeks bazlı* seyreltiliyordu; 2 saatlik bir vardiyada noktalar ~750 m
/// aralıklı kalıyor, map matching hangi yoldan gidildiğini bilemiyordu.
/// Çözümün iki parçası burada test ediliyor: izin temizlenmesi ve nokta
/// tavanına şekil bozmadan inilmesi.
void main() {
  // Cizre civarı, ~1 m ≈ 0.000009 derece enlem.
  const base = LatLng(37.3200, 42.1900);
  LatLng north(double meters) =>
      LatLng(base.latitude + meters * 0.000009, base.longitude);

  group('sanitizeGpsTrace', () {
    test('duruş bulutunu (yakın noktalar) teke indirir', () {
      // Araç durakta bekliyor: 2-3 m'lik GPS gezinmesiyle 6 nokta.
      final trace = [
        north(0),
        north(2),
        north(4),
        north(1),
        north(3),
        north(2),
      ];

      final cleaned = sanitizeGpsTrace(trace, minSpacingMeters: 12);

      // İlk nokta + korunan son nokta; aradaki gezinme atılır.
      expect(cleaned.length, lessThanOrEqualTo(2));
      expect(cleaned.first, base);
    });

    test('hareket hâlindeki noktaları aynen korur', () {
      final trace = [north(0), north(50), north(100), north(150), north(200)];

      final cleaned = sanitizeGpsTrace(trace, minSpacingMeters: 12);

      expect(cleaned.length, trace.length);
      expect(cleaned, trace);
    });

    test('ışınlanan (aykırı) fixi atar ve izi son sağlam noktadan sürdürür',
        () {
      final trace = [
        north(0),
        north(50),
        const LatLng(41.0082, 28.9784), // İstanbul — hatalı fix
        north(100),
        north(150),
      ];

      final cleaned = sanitizeGpsTrace(trace, minSpacingMeters: 12);

      expect(cleaned, isNot(contains(const LatLng(41.0082, 28.9784))));
      expect(cleaned, [north(0), north(50), north(100), north(150)]);
    });

    test('geçersiz koordinatları eler', () {
      final trace = [
        north(0),
        const LatLng(double.nan, 42.19),
        const LatLng(95, 42.19), // enlem aralık dışı
        north(50),
      ];

      final cleaned = sanitizeGpsTrace(trace, minSpacingMeters: 12);

      expect(cleaned, [north(0), north(50)]);
    });

    test('izin son noktası aralık kuralına takılsa bile korunur', () {
      // Son nokta bir önceki korunan noktaya 3 m uzakta — normalde atılırdı.
      final trace = [north(0), north(50), north(53)];

      final cleaned = sanitizeGpsTrace(trace, minSpacingMeters: 12);

      expect(cleaned.last, north(53));
    });

    test('boş ve tek noktalı iz çökmez', () {
      expect(sanitizeGpsTrace(const []), isEmpty);
      expect(sanitizeGpsTrace([base]), [base]);
    });
  });

  group('simplifyToMaxPoints', () {
    test('tavanın altındaki path aynen döner', () {
      final path = [north(0), north(100), north(200)];

      expect(simplifyToMaxPoints(path, maxPoints: 10), path);
    });

    test('nokta sayısını tavana indirir', () {
      // 600 noktalı, hafif dalgalı bir yol geometrisi.
      final path = List<LatLng>.generate(
        600,
        (i) => LatLng(
          base.latitude + i * 0.00002,
          base.longitude + (i.isEven ? 0.000004 : -0.000004),
        ),
      );

      final reduced = simplifyToMaxPoints(path, maxPoints: 100);

      expect(reduced.length, lessThanOrEqualTo(100));
      // Uçlar her zaman korunur — rotanın başı ve sonu kaymamalı.
      expect(reduced.first, path.first);
      expect(reduced.last, path.last);
    });

    test('geçersiz tavan girdiyi bozmaz', () {
      final path = [north(0), north(100), north(200)];

      expect(simplifyToMaxPoints(path, maxPoints: 1), path);
    });
  });
}
