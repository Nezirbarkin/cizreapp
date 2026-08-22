import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cizreapp/sehirici/utils/sehirici_route_geometry.dart';

/// Admin "Rotayı Ayıkla" işleminin geometri tarafı.
///
/// [sanitizeRoutePolyline], [buildTripPathSegments]'ten farklı bir sözleşme
/// taşır: hat rotası TEK ve BAĞLANTILI kalmak zorundadır. Bu yüzden gerçek bir
/// uzun atlama korunur, yalnız "git-gel" yapan tekil aykırı noktalar atılır.
void main() {
  const base = LatLng(37.3200, 42.1900);
  LatLng north(double meters) =>
      LatLng(base.latitude + meters * 0.000009, base.longitude);
  // Sadeleştirmenin düz çizgi üzerindeki ara noktaları silmemesi için hafif
  // zikzaklı (yoldan sapmalı) bir rota üretir.
  LatLng bend(double meters, double offsetMeters) => LatLng(
        base.latitude + meters * 0.000009,
        base.longitude + offsetMeters * 0.0000113,
      );

  group('sanitizeRoutePolyline', () {
    test('temiz rotayı bozmaz: uçlar ve bağlantı korunur', () {
      final route = [
        bend(0, 0),
        bend(100, 30),
        bend(200, -30),
        bend(300, 30),
        bend(400, 0),
      ];

      final cleaned = sanitizeRoutePolyline(route);

      expect(cleaned.first, route.first);
      expect(cleaned.last, route.last);
      expect(cleaned.length, greaterThanOrEqualTo(3));
    });

    test('üst üste binen noktaları eler', () {
      final route = [
        bend(0, 0),
        bend(2, 0), // 2 m — aynı yer
        bend(4, 0),
        bend(150, 40),
        bend(152, 40), // yine üst üste
        bend(300, 0),
      ];

      final cleaned = sanitizeRoutePolyline(route);

      expect(cleaned.length, lessThan(route.length));
      for (var i = 1; i < cleaned.length; i++) {
        expect(distanceMeters(cleaned[i - 1], cleaned[i]),
            greaterThanOrEqualTo(10.0));
      }
    });

    test('rotadan fırlayıp geri dönen tekil aykırı noktayı atar', () {
      final route = [
        bend(0, 0),
        bend(100, 30),
        const LatLng(41.0082, 28.9784), // İstanbul — hatalı nokta
        bend(200, -30),
        bend(300, 0),
      ];

      final cleaned = sanitizeRoutePolyline(route);

      expect(cleaned, isNot(contains(const LatLng(41.0082, 28.9784))));
      expect(cleaned.first, route.first);
      expect(cleaned.last, route.last);
    });

    test('rota gerçekten uzakta devam ediyorsa atlama KORUNUR', () {
      // Trip izinden farkı bu: rota bağlantılı kalmalı, parçalanamaz.
      final route = [
        bend(0, 0),
        bend(100, 20),
        bend(2000, 0), // ~1.9 km ötede devam ediyor
        bend(2100, 40),
        bend(2200, 0),
      ];

      final cleaned = sanitizeRoutePolyline(route);

      // Uzak bölüm aykırı sanılıp atılmamalı: rota oraya kadar uzanmalı.
      // (Tek tek noktalar sadeleştirmede düşebilir — düz çizgi üzerindeki
      // ara nokta zaten gereksizdir; önemli olan rotanın kapsadığı alan.)
      expect(cleaned.last, route.last);
      expect(
        cleaned.any((p) => distanceMeters(base, p) > 1500),
        isTrue,
        reason: 'uzak devam bölümü rotadan düşürülmüş',
      );
    });

    test('geçersiz koordinatlar elenir', () {
      final route = [
        bend(0, 0),
        const LatLng(double.nan, 42.19),
        const LatLng(95, 42.19),
        bend(150, 30),
        bend(300, 0),
      ];

      final cleaned = sanitizeRoutePolyline(route);

      for (final p in cleaned) {
        expect(isValidCoordinate(p), isTrue);
      }
      expect(cleaned.first, route.first);
      expect(cleaned.last, route.last);
    });

    test('nokta tavanını aşmaz', () {
      final route = List<LatLng>.generate(
        4000,
        (i) => LatLng(
          base.latitude + i * 0.00002,
          base.longitude + (i % 3 - 1) * 0.00002,
        ),
      );

      final cleaned = sanitizeRoutePolyline(route, maxPoints: 500);

      expect(cleaned.length, lessThanOrEqualTo(500));
      expect(cleaned.first, route.first);
      expect(cleaned.last, route.last);
    });

    test('boş ve tek noktalı girdi çökmez', () {
      expect(sanitizeRoutePolyline(const []), isEmpty);
      expect(sanitizeRoutePolyline([base]), [base]);
    });
  });
}
