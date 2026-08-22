import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cizreapp/sehirici/utils/sehirici_route_geometry.dart';

/// "Şehiriçi haritasında rota saçmalıyor" hatasının çizim tarafı.
///
/// Ekran görüntülerinde iki ayrı belirti vardı:
///   • duran araç çevresinde birbirine dolanmış yüzlerce kısa çizgi (duruş
///     bulutu / GPS gezinmesi),
///   • haritayı bir uçtan diğerine kesen uzun düz çizgiler (aykırı fix ve
///     kopukluk uçlarının tek polyline içinde birleştirilmesi).
///
/// [buildTripPathSegments] her ikisini de kaynağında keser.
void main() {
  // Cizre civarı; ~1 m ≈ 0.000009 derece enlem.
  const base = LatLng(37.3200, 42.1900);
  LatLng north(double meters) =>
      LatLng(base.latitude + meters * 0.000009, base.longitude);

  group('buildTripPathSegments', () {
    test('duruş bulutu tek parçaya bile dönüşmez', () {
      // Araç durakta bekliyor: 10 sn'de bir nokta, 3-8 m'lik GPS gezinmesi.
      final trace = [
        north(0),
        north(5),
        north(2),
        north(8),
        north(3),
        north(6),
        north(1),
      ];

      final segments = buildTripPathSegments(trace);

      // Hiçbir nokta minSpacing'i aşmadı → çizilecek çizgi yok.
      expect(segments, isEmpty);
    });

    test('hareket hâlindeki iz tek parça olarak korunur', () {
      final trace = [
        north(0),
        north(60),
        north(120),
        north(180),
        north(240),
      ];

      final segments = buildTripPathSegments(trace);

      expect(segments.length, 1);
      expect(segments.first.first, north(0));
      expect(segments.first.last, north(240));
    });

    test('tek atımlık aykırı fix izi bölmeden atılır', () {
      final trace = [
        north(0),
        north(60),
        const LatLng(41.0082, 28.9784), // İstanbul — hatalı fix
        north(120),
        north(180),
      ];

      final segments = buildTripPathSegments(trace);

      // Aykırı nokta yok sayılır, iz kesintisiz devam eder.
      expect(segments.length, 1);
      expect(segments.first, isNot(contains(const LatLng(41.0082, 28.9784))));
      expect(segments.first.first, north(0));
      expect(segments.first.last, north(180));
    });

    test('gerçek kopukluk kiriş çizmek yerine yeni parça başlatır', () {
      // Uygulama arka planda uyutuldu: iz 3 km ötede devam ediyor.
      final trace = [
        north(0),
        north(60),
        north(120),
        north(3000),
        north(3060),
        north(3120),
      ];

      final segments = buildTripPathSegments(trace);

      expect(segments.length, 2);
      expect(segments.first.last, north(120));
      expect(segments.last.first, north(3000));
      // Kritik: iki parçanın uçlarını birleştiren nokta çifti hiçbir
      // polyline'da yan yana bulunmamalı.
      for (final segment in segments) {
        for (var i = 1; i < segment.length; i++) {
          expect(
            distanceMeters(segment[i - 1], segment[i]),
            lessThanOrEqualTo(500.0),
          );
        }
      }
    });

    test('geçersiz koordinatlar elenir', () {
      final trace = [
        north(0),
        const LatLng(double.nan, 42.19),
        const LatLng(95, 42.19), // enlem aralık dışı
        north(60),
        north(120),
      ];

      final segments = buildTripPathSegments(trace);

      expect(segments.length, 1);
      // Geçerli noktalar arasında düz çizgi olduğu için ara nokta
      // sadeleştirmede düşebilir; önemli olan bozuk koordinatın hiç
      // girmemesi ve izin uçlarının doğru olması.
      expect(segments.first.first, north(0));
      expect(segments.first.last, north(120));
      for (final p in segments.first) {
        expect(isValidCoordinate(p), isTrue);
        expect(p.latitude, closeTo(base.latitude, 0.01));
      }
    });

    test('yalnız bir aykırı fixten ibaret parça düşürülür', () {
      final trace = [
        north(0),
        north(60),
        const LatLng(41.0082, 28.9784),
      ];

      final segments = buildTripPathSegments(trace);

      expect(segments.length, 1);
      expect(segments.first, [north(0), north(60)]);
    });

    test('boş / tek noktalı iz çökmez ve çizim üretmez', () {
      expect(buildTripPathSegments(const []), isEmpty);
      expect(buildTripPathSegments([base]), isEmpty);
    });

    test('uzun vardiya izi parça başına nokta tavanına iner', () {
      // ~8 km'lik, 1600 noktalı hafif dalgalı bir iz.
      final trace = List<LatLng>.generate(
        1600,
        (i) => LatLng(
          base.latitude + i * 0.000045,
          base.longitude + (i.isEven ? 0.000005 : -0.000005),
        ),
      );

      final segments = buildTripPathSegments(trace, maxPointsPerSegment: 200);

      expect(segments.length, 1);
      expect(segments.first.length, lessThanOrEqualTo(200));
      // Uçlar kaymamalı — izin başladığı yer ve aracın şu anki yeri anlamlıdır.
      // Son nokta aralık kuralına takılsa bile kuyruk olarak korunur.
      expect(segments.first.first, trace.first);
      expect(segments.first.last, trace.last);
    });
  });
}
