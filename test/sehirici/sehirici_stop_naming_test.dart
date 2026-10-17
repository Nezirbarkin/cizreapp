import 'dart:convert';

import 'package:cizreapp/sehirici/models/sehirici_models.dart';
import 'package:cizreapp/sehirici/services/sehirici_street_namer.dart';
import 'package:cizreapp/sehirici/utils/sehirici_line_stop_plan.dart';
import 'package:cizreapp/sehirici/utils/sehirici_stop_naming.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Durak adı kuralları ("Yafes Cad. 1, 2 …"), sokak adı servisi ve hatta
/// en az sapmalı yerleştirme.
void main() {
  group('Sokak adı kısaltma', () {
    test('cadde / sokak / bulvar / mahalle kısalır, diğerleri kalır', () {
      expect(sehiriciAbbreviateStreet('Yafes Caddesi'), 'Yafes Cad.');
      expect(sehiriciAbbreviateStreet('Orhan Doğan Cd.'), 'Orhan Doğan Cad.');
      expect(sehiriciAbbreviateStreet('Barçın Sokak'), 'Barçın Sk.');
      expect(sehiriciAbbreviateStreet('Temiz Sokağı'), 'Temiz Sk.');
      expect(sehiriciAbbreviateStreet('Mem U Zin Bulvarı'), 'Mem U Zin Blv.');
      expect(sehiriciAbbreviateStreet('Cumhuriyet Meydanı'), 'Cumhuriyet Mey.');
      expect(sehiriciAbbreviateStreet('  Mardin - Şırnak   Yolu '),
          'Mardin - Şırnak Yolu');
      // Tek kelimelik ad olduğu gibi kalır ("Cadde" adlı yer).
      expect(sehiriciAbbreviateStreet('Cadde'), 'Cadde');
      expect(sehiriciAbbreviateStreet(''), '');
    });

    test('mahalle tabanı', () {
      expect(sehiriciNeighborhoodBase('Nur'), 'Nur Mah.');
      expect(sehiriciNeighborhoodBase('Ali Bey Mahallesi'), 'Ali Bey Mah.');
      expect(sehiriciNeighborhoodBase('Konak Mah.'), 'Konak Mah.');
    });
  });

  group('Numara kaldığı yerden devam eder', () {
    test('ilk durak 1 olur', () {
      expect(sehiriciNextNumberedName('Yafes Cad.', const []), 'Yafes Cad. 1');
    });

    test('en büyük numaranın bir fazlası; yazım farkları aynı sokak sayılır', () {
      final taken = [
        'Yafes Cad. 1',
        'yafes cad3', // kullanıcı örneği gibi bitişik ve küçük harf
        'YAFES CAD. 2',
        'Yafes Sk. 9', // başka sokak
        'Belediye Önü',
      ];
      expect(sehiriciNextNumberedName('Yafes Cad.', taken), 'Yafes Cad. 4');
      expect(sehiriciNextNumberedName('Yafes Sk.', taken), 'Yafes Sk. 10');
    });

    test('numarasız aynı ad 1 sayılır; boşluk kapanmaz', () {
      expect(sehiriciNextNumberedName('Silopi Cad.', ['Silopi Cad.']),
          'Silopi Cad. 2');
      expect(sehiriciNextNumberedName('Silopi Cad.', ['Silopi Cad. 5']),
          'Silopi Cad. 6');
    });

    test('canlıdaki "Durak 15–18" serisi 19 ile sürer', () {
      final live = [for (var i = 15; i <= 18; i++) 'Durak $i'];
      expect(sehiriciNextNumberedName(kSehiriciFallbackStopBase, live),
          'Durak 19');
    });

    test('Türkçe büyük/küçük harf duyarsız eşleşir', () {
      expect(sehiriciNextNumberedName('Şehit İlhan Cad.', ['şehit ilhan cad. 7']),
          'Şehit İlhan Cad. 8');
    });
  });

  test('doğal sıralama: 2 < 10, Türkçe harf duyarsız', () {
    final names = ['Yafes Cad. 10', 'yafes cad. 2', 'Çarşı', 'Yafes Cad. 1', 'carsi 2'];
    names.sort(sehiriciNaturalCompare);
    expect(names, ['Çarşı', 'carsi 2', 'Yafes Cad. 1', 'yafes cad. 2', 'Yafes Cad. 10']);
  });

  group('Google yanıtı', () {
    Map route(String name) => {
          'address_components': [
            {'long_name': name, 'types': ['route']},
          ],
        };
    const nur = {
      'address_components': [
        {'long_name': 'Nur', 'types': ['administrative_area_level_4', 'political']},
      ],
    };

    test('yol sorgusu öncelikli; diğer yollar seçenek; yol numarası atılır', () {
      final s = SehiriciStreetNamer.parseGoogleResults(
        routeResults: [route('Belediye Caddesi')],
        addressResults: [
          route('Çevik Sokak'),
          nur,
          route('Belediye Caddesi'),
          route('D400'),
          route('Unnamed Road'),
          route('Silopi Caddesi'),
        ],
      )!;
      expect(s.street, 'Belediye Cad.');
      expect(s.alternatives, ['Çevik Sk.', 'Silopi Cad.']);
      expect(s.neighborhood, 'Nur Mah.');
      expect(s.base, 'Belediye Cad.');
      expect(s.bases, ['Belediye Cad.', 'Çevik Sk.', 'Silopi Cad.', 'Nur Mah.']);
      expect(s.address, 'Nur Mah., Belediye Cad.');
    });

    test('yol yoksa mahalle taban olur; hiçbiri yoksa null', () {
      final s = SehiriciStreetNamer.parseGoogleResults(
        routeResults: const [],
        addressResults: const [nur],
      )!;
      expect(s.street, isNull);
      expect(s.base, 'Nur Mah.');
      expect(
        SehiriciStreetNamer.parseGoogleResults(
            routeResults: const [], addressResults: const []),
        isNull,
      );
    });
  });

  group('Sokak adı servisi', () {
    http.Response google(http.Request r, List<Map> results) => http.Response.bytes(
          utf8.encode(jsonEncode({
            'status': results.isEmpty ? 'ZERO_RESULTS' : 'OK',
            'results': results,
          })),
          200,
          request: r,
        );

    test('Google: iki sorgu paralel, sonuç önbellekte (aynı noktaya tekrar gitmez)',
        () async {
      final requests = <Uri>[];
      final namer = SehiriciStreetNamer(
        apiKey: () async => 'AIza-test',
        client: MockClient((r) async {
          requests.add(r.url);
          final routeOnly = r.url.queryParameters['result_type'] == 'route';
          return google(r, [
            {
              'address_components': [
                {
                  'long_name': routeOnly ? 'Yafes Caddesi' : 'Temiz Sokak',
                  'types': ['route'],
                },
              ],
            },
          ]);
        }),
      );
      final s = await namer.lookup(const LatLng(37.33, 42.19));
      expect(s!.street, 'Yafes Cad.');
      expect(s.alternatives, ['Temiz Sk.']);
      expect(requests, hasLength(2));
      expect(requests.every((u) => u.queryParameters['language'] == 'tr'), isTrue);
      // ~11 m içindeki ikinci istek önbellekten.
      await namer.lookup(const LatLng(37.33002, 42.19002));
      expect(requests, hasLength(2));
    });

    test('Google boşsa OSRM yol adı; uzak yol adı kabul edilmez', () async {
      var osrmDistance = 12.0;
      final namer = SehiriciStreetNamer(
        apiKey: () async => 'AIza-test',
        client: MockClient((r) async {
          if (r.url.host == 'maps.googleapis.com') return google(r, const []);
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'code': 'Ok',
              'waypoints': [
                {'name': 'Yafes Caddesi', 'distance': osrmDistance},
              ],
            })),
            200,
            request: r,
          );
        }),
      );
      expect((await namer.lookup(const LatLng(37.33, 42.19)))!.street, 'Yafes Cad.');
      osrmDistance = 140;
      expect(await namer.lookup(const LatLng(37.40, 42.30)), isNull);
    });

    test('anahtar yok + ağ hatası: null döner, sonuç önbelleğe yazılmaz', () async {
      var calls = 0;
      final namer = SehiriciStreetNamer(
        apiKey: () async => null,
        client: MockClient((r) async {
          calls++;
          throw http.ClientException('ağ yok');
        }),
      );
      expect(await namer.lookup(const LatLng(37.33, 42.19)), isNull);
      expect(await namer.lookup(const LatLng(37.33, 42.19)), isNull);
      expect(calls, 2, reason: 'başarısız sonuç tekrar denenir');
    });
  });

  group('Hatta en az sapmalı sıra', () {
    SehiriciStop s(String id, double lat, double lng) =>
        SehiriciStop(id: id, name: id, lat: lat, lng: lng);
    // Doğu yönünde düz bir hat: a — b — c — d.
    final line = [
      s('a', 37.3270, 42.1880),
      s('b', 37.3270, 42.1900),
      s('c', 37.3270, 42.1920),
      s('d', 37.3270, 42.1940),
    ];

    test('ara, baş ve son', () {
      expect(sehiriciBestInsertIndex(line, 37.3271, 42.1910), 2, reason: 'b–c arası');
      expect(sehiriciBestInsertIndex(line, 37.3270, 42.1860), 0, reason: 'a öncesi');
      expect(sehiriciBestInsertIndex(line, 37.3270, 42.1960), 4, reason: 'd sonrası');
      expect(sehiriciBestInsertIndex(const [], 37.3, 42.1), 0);
    });

    test('satırlar: sıra 0..n-1, mesafe ve süre artar', () {
      final rows = sehiriciLineStopRows(sehiriciPlanLineStops(line));
      expect(rows.map((r) => r['stop_id']), ['a', 'b', 'c', 'd']);
      expect(rows.map((r) => r['stop_order']), [0, 1, 2, 3]);
      final km = rows.map((r) => r['distance_km'] as double).toList();
      expect(km.first, 0);
      for (var i = 1; i < km.length; i++) {
        expect(km[i], greaterThan(km[i - 1]));
      }
      expect(rows.last['minutes_from_start'], sehiriciMinutesFor(km.last));
    });
  });
}
