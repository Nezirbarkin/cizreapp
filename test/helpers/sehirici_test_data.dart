import 'package:cizreapp/sehirici/models/sehirici_models.dart';

/// Şehiriçi widget testleri için Cizre'ye benzer örnek veri.
class SehiriciTestData {
  const SehiriciTestData._();

  static const SehiriciCity city = SehiriciCity(
    id: 'city-1',
    name: 'Cizre',
    slug: 'cizre',
    centerLat: 37.3274,
    centerLng: 42.1907,
    zoomLevel: 16,
  );

  static SehiriciLineStop stop(
    String id,
    int order,
    double lat,
    double lng, {
    String? name,
    int minutes = 0,
    String? code,
    String? address,
  }) =>
      SehiriciLineStop(
        stopId: id,
        stopOrder: order,
        minutesFromStart: minutes,
        name: name ?? 'Durak ${order + 1}',
        lat: lat,
        lng: lng,
        code: code,
        address: address,
      );

  /// 4A: mavi minibüs hattı, yol boyunca 6 durak + rota.
  static SehiriciLine lineBlue() => SehiriciLine(
        id: 'L1',
        code: '4A',
        name: 'Merkez – Hastane',
        colorHex: '#1976D2',
        vehicleType: SehiriciVehicleType.minibus,
        vehicleKeyRaw: 'minibus',
        estimatedMinutes: 22,
        fareAmount: 12,
        stops: [
          stop('s1', 0, 37.3268, 42.1885, name: 'Otogar', minutes: 0, code: 'A01'),
          stop('s2', 1, 37.3271, 42.1899, name: 'Belediye', minutes: 3),
          stop('s3', 2, 37.3275, 42.1913, name: 'Çarşı', minutes: 6),
          stop('s4', 3, 37.3281, 42.1926, name: 'Şehir Parkı', minutes: 9),
          stop('s5', 4, 37.3288, 42.1938, name: 'Devlet Hastanesi', minutes: 13,
              address: 'Cumhuriyet Mah. Hastane Cd.'),
          stop('s6', 5, 37.3296, 42.1951, name: 'Üniversite', minutes: 18),
        ],
        roadPolyline: const [
          [37.3268, 42.1885],
          [37.3268, 42.1899],
          [37.3271, 42.1899],
          [37.3271, 42.1913],
          [37.3275, 42.1913],
          [37.3275, 42.1926],
          [37.3281, 42.1926],
          [37.3281, 42.1938],
          [37.3288, 42.1938],
          [37.3288, 42.1951],
          [37.3296, 42.1951],
        ],
      );

  /// 7B: kırmızı otobüs hattı; Belediye + Çarşı duraklarını 4A ile paylaşır.
  static SehiriciLine lineRed() => SehiriciLine(
        id: 'L2',
        code: '7B',
        name: 'Çarşı – Sanayi',
        colorHex: '#E53935',
        vehicleType: SehiriciVehicleType.bus,
        vehicleKeyRaw: 'bus',
        estimatedMinutes: 15,
        fareAmount: 10,
        stops: [
          stop('s2', 0, 37.3271, 42.1899, name: 'Belediye', minutes: 0),
          stop('s3', 1, 37.3275, 42.1913, name: 'Çarşı', minutes: 3),
          stop('s7', 2, 37.3262, 42.1913, name: 'Kaymakamlık', minutes: 7),
          stop('s8', 3, 37.3255, 42.1926, name: 'Sanayi Sitesi', minutes: 11),
        ],
        roadPolyline: const [
          [37.3271, 42.1899],
          [37.3275, 42.1899],
          [37.3275, 42.1913],
          [37.3262, 42.1913],
          [37.3262, 42.1926],
          [37.3255, 42.1926],
        ],
      );

  static SehiriciActiveTrip tripBlue({int eta = 3, String? nextStopId = 's4'}) =>
      SehiriciActiveTrip(
        tripId: 't1',
        lineId: 'L1',
        lineCode: '4A',
        lineName: 'Merkez – Hastane',
        lineColor: '#1976D2',
        driverName: 'Ahmet Yılmaz',
        currentLat: 37.3277,
        currentLng: 42.1919,
        currentHeading: 62,
        currentSpeed: 31,
        startedAt: DateTime(2026, 9, 21, 8, 15),
        nextStopId: nextStopId,
        nextStopName: 'Şehir Parkı',
        etaMinutes: eta,
      );

  static SehiriciActiveTrip tripRed() => const SehiriciActiveTrip(
        tripId: 't2',
        lineId: 'L2',
        lineCode: '7B',
        lineName: 'Çarşı – Sanayi',
        lineColor: '#E53935',
        driverName: 'Mehmet Kaya',
        currentLat: 37.3264,
        currentLng: 42.1913,
        currentHeading: 178,
        currentSpeed: 24,
        nextStopId: 's8',
        nextStopName: 'Sanayi Sitesi',
        etaMinutes: 6,
      );
}
