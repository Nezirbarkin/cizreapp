import 'dart:math' as math;

import '../models/sehirici_models.dart';

/// Hat durak listesinin sıra / mesafe / süre hesabı. Hat durak düzenleyicisi,
/// durak formundaki "Hatlara bağla" ve Duraklar sekmesinin "hatta ekle"si
/// sunucuya aynı satırları yazsın diye tek yerde.

/// Otobüs/minibüs için ortalama şehir içi hız (km/sa): duraklar arası süre
/// tahmini bundan hesaplanır.
const double kSehiriciAvgSpeedKmh = 25;

/// İki durak arası kuş uçuşu mesafe (km, haversine).
double sehiriciStopDistanceKm(SehiriciStop a, SehiriciStop b) =>
    _haversineKm(a.lat, a.lng, b.lat, b.lng);

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final p1 = lat1 * math.pi / 180;
  final p2 = lat2 * math.pi / 180;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return r * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

/// Her durağın hat başından itibaren kümülatif mesafesi (km, 3 hane).
List<double> sehiriciCumulativeKm(List<SehiriciStop> ordered) {
  final out = <double>[];
  var total = 0.0;
  for (var i = 0; i < ordered.length; i++) {
    if (i > 0) total += sehiriciStopDistanceKm(ordered[i - 1], ordered[i]);
    out.add(double.parse(total.toStringAsFixed(3)));
  }
  return out;
}

int sehiriciMinutesFor(double km) => ((km / kSehiriciAvgSpeedKmh) * 60).round();

/// Sıralı durakların [SehiriciLineStop] karşılığı (sıra, mesafe, süre dolu).
List<SehiriciLineStop> sehiriciPlanLineStops(List<SehiriciStop> ordered) {
  final km = sehiriciCumulativeKm(ordered);
  return [
    for (var i = 0; i < ordered.length; i++)
      SehiriciLineStop(
        stopId: ordered[i].id,
        stopOrder: i,
        minutesFromStart: sehiriciMinutesFor(km[i]),
        distanceKm: km[i],
        name: ordered[i].name,
        lat: ordered[i].lat,
        lng: ordered[i].lng,
        code: ordered[i].code,
        address: ordered[i].address,
      ),
  ];
}

/// `admin_set_sehirici_line_stops` satırları.
List<Map<String, dynamic>> sehiriciLineStopRows(List<SehiriciLineStop> planned) => [
      for (final s in planned)
        {
          'stop_id': s.stopId,
          'stop_order': s.stopOrder,
          'minutes_from_start': s.minutesFromStart,
          'distance_km': s.distanceKm ?? 0,
        },
    ];

/// Yeni bir durağın hatta en az sapmayla gireceği sıra (0..n).
///
/// Her aralık için eklenen yol `d(önceki, yeni) + d(yeni, sonraki) −
/// d(önceki, sonraki)`; uçlarda yalnız uca uzaklık. Eşitlikte sona yakın olan
/// seçilir — hattın son durağından ileri uzanan bir durak sona eklenir.
int sehiriciBestInsertIndex(List<SehiriciStop> ordered, double lat, double lng) {
  if (ordered.isEmpty) return 0;
  double d(SehiriciStop s) => _haversineKm(s.lat, s.lng, lat, lng);
  var bestIndex = ordered.length;
  var bestCost = d(ordered.last);
  for (var i = ordered.length - 1; i >= 0; i--) {
    final cost = i == 0
        ? d(ordered.first)
        : d(ordered[i - 1]) + d(ordered[i]) -
            sehiriciStopDistanceKm(ordered[i - 1], ordered[i]);
    if (cost < bestCost - 1e-9) {
      bestCost = cost;
      bestIndex = i;
    }
  }
  return bestIndex;
}
