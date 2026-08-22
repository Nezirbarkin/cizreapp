import 'dart:convert';

import 'package:cizreapp/sehirici/sehirici.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('SehiriciRoadSnapService.matchDrivenPath', () {
    test('OSRM GeoJSON koordinatlarını LatLng sırasına çevirir', () async {
      late Uri requestedUri;
      final client = MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          jsonEncode({
            'code': 'Ok',
            'matchings': [
              {
                'confidence': 0.92,
                'geometry': {
                  'type': 'LineString',
                  'coordinates': [
                    [42.19000, 37.33000],
                    [42.19060, 37.33030],
                    [42.19120, 37.33000],
                  ],
                },
              },
            ],
          }),
          200,
        );
      });
      final service = SehiriciRoadSnapService(client: client);

      final result = await service.matchDrivenPath(const [
        LatLng(37.33000, 42.19000),
        LatLng(37.33030, 42.19060),
        LatLng(37.33000, 42.19120),
      ]);

      expect(result, hasLength(3));
      expect(result.first.latitude, 37.33);
      expect(result.first.longitude, 42.19);
      expect(requestedUri.path, contains('/match/v1/driving/'));
      expect(requestedUri.queryParameters['geometries'], 'geojson');
      expect(requestedUri.queryParameters['radiuses'], '35;35;35');
    });

    test('düşük güvenli eşleşmeyi kaydetmek üzere döndürmez', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'code': 'Ok',
            'matchings': [
              {
                'confidence': 0.1,
                'geometry': {
                  'coordinates': [
                    [42.19, 37.33],
                    [42.191, 37.33],
                  ],
                },
              },
            ],
          }),
          200,
        ),
      );

      final result = await SehiriciRoadSnapService(
        client: client,
      ).matchDrivenPath(const [LatLng(37.33, 42.19), LatLng(37.33, 42.191)]);

      expect(result, isEmpty);
    });

    test(
      'birbirinden kopuk matching parçalarını düz çizgiyle bağlamaz',
      () async {
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode({
              'code': 'Ok',
              'matchings': [
                {
                  'confidence': 0.9,
                  'geometry': {
                    'coordinates': [
                      [42.19, 37.33],
                      [42.1905, 37.33],
                    ],
                  },
                },
                {
                  'confidence': 0.9,
                  'geometry': {
                    'coordinates': [
                      [42.1907, 37.33],
                      [42.191, 37.33],
                    ],
                  },
                },
              ],
            }),
            200,
          ),
        );

        final result = await SehiriciRoadSnapService(
          client: client,
        ).matchDrivenPath(const [LatLng(37.33, 42.19), LatLng(37.33, 42.191)]);

        expect(result, isEmpty);
      },
    );
  });

  group('SehiriciRoadSnapService.routeThroughWaypoints', () {
    test('durakları route servisiyle yol geometrisine dönüştürür', () async {
      final client = MockClient((request) async {
        expect(request.url.path, contains('/route/v1/driving/'));
        return http.Response(
          jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'geometry': {
                  'type': 'LineString',
                  'coordinates': [
                    [42.19000, 37.33000],
                    [42.19050, 37.33020],
                    [42.19100, 37.33000],
                  ],
                },
              },
            ],
          }),
          200,
        );
      });

      final result = await SehiriciRoadSnapService(client: client)
          .routeThroughWaypoints(const [
            LatLng(37.33, 42.19),
            LatLng(37.33, 42.191),
          ]);

      expect(result, hasLength(3));
      expect(result[1], const LatLng(37.3302, 42.1905));
    });
  });
}
