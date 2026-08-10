import 'package:flutter_test/flutter_test.dart';
import 'package:cizreapp/sehirici/models/sehirici_models.dart';

void main() {
  group('SehiriciLineStop Model Tests', () {
    test('creates instance from JSON with all fields', () {
      final json = {
        'stop_id': 'stop-1',
        'stop_order': 1,
        'minutes_from_start': 5,
        'distance_km': 2.5,
        'name': 'Taksim',
        'lat': 41.0368,
        'lng': 29.0274,
      };

      final lineStop = SehiriciLineStop.fromJson(json);

      expect(lineStop.stopId, 'stop-1');
      expect(lineStop.stopOrder, 1);
      expect(lineStop.minutesFromStart, 5);
      expect(lineStop.distanceKm, 2.5);
      expect(lineStop.name, 'Taksim');
      expect(lineStop.lat, 41.0368);
      expect(lineStop.lng, 29.0274);
    });

    test('converts to SehiriciStop', () {
      final lineStop = SehiriciLineStop(
        stopId: 'stop-1',
        stopOrder: 1,
        minutesFromStart: 5,
        name: 'Taksim',
        lat: 41.0368,
        lng: 29.0274,
      );

      final stop = lineStop.asStop;

      expect(stop.id, 'stop-1');
      expect(stop.name, 'Taksim');
      expect(stop.lat, 41.0368);
      expect(stop.lng, 29.0274);
    });
  });

  group('SehiriciEnums Consistency', () {
    test('all vehicle types have labels', () {
      for (final type in SehiriciVehicleType.values) {
        expect(type.label, isNotEmpty);
      }
    });

    test('all vehicle types have icons', () {
      for (final type in SehiriciVehicleType.values) {
        expect(type.icon, isNotNull);
      }
    });

    test('all trip statuses have labels', () {
      for (final status in SehiriciTripStatus.values) {
        expect(status.label, isNotEmpty);
      }
    });

    test('vehicle type string conversion is reversible', () {
      for (final type in SehiriciVehicleType.values) {
        final fromString = SehiriciVehicleType.fromString(type.name);
        expect(fromString, type);
      }
    });
  });

  group('SehiriciCity Validation', () {
    test('valid city data', () {
      final city = SehiriciCity(
        id: 'city-1',
        name: 'İstanbul',
        slug: 'istanbul',
        centerLat: 41.0082,
        centerLng: 28.9784,
      );

      expect(city.id, isNotEmpty);
      expect(city.name, isNotEmpty);
      expect(city.slug, isNotEmpty);
    });

    test('city zoom level is reasonable', () {
      const minZoom = 1;
      const maxZoom = 20;

      final city = SehiriciCity(
        id: 'city-1',
        name: 'Test',
        slug: 'test',
        centerLat: 0,
        centerLng: 0,
        zoomLevel: 13,
      );

      expect(city.zoomLevel, greaterThanOrEqualTo(minZoom));
      expect(city.zoomLevel, lessThanOrEqualTo(maxZoom));
    });
  });

  group('SehiriciLine Validation', () {
    test('line code is not empty', () {
      final line = SehiriciLine(id: 'line-1', code: '1T', name: 'Hat 1');

      expect(line.code, isNotEmpty);
    });

    test('line name is not empty', () {
      final line = SehiriciLine(id: 'line-1', code: '1T', name: 'Hat 1');

      expect(line.name, isNotEmpty);
    });

    test('fare amount is non-negative', () {
      const validFares = [0.0, 5.5, 10.0, 100.0];

      for (final fare in validFares) {
        final line = SehiriciLine(
          id: 'line-1',
          code: '1T',
          name: 'Hat 1',
          fareAmount: fare,
        );

        expect(line.fareAmount, greaterThanOrEqualTo(0));
      }
    });
  });

  group('SehiriciStop Validation', () {
    test('stop coordinates are valid latitude/longitude', () {
      const validCoords = [
        (lat: 41.0082, lng: 28.9784), // Istanbul
        (lat: 39.9334, lng: 32.8597), // Ankara
        (lat: 35.1856, lng: 33.3823), // Izmir
        (lat: 0.0, lng: 0.0), // Null Island (edge case)
      ];

      for (final coord in validCoords) {
        final stop = SehiriciStop(
          id: 'stop-1',
          name: 'Test',
          lat: coord.lat,
          lng: coord.lng,
        );

        expect(stop.lat, greaterThanOrEqualTo(-90));
        expect(stop.lat, lessThanOrEqualTo(90));
        expect(stop.lng, greaterThanOrEqualTo(-180));
        expect(stop.lng, lessThanOrEqualTo(180));
      }
    });

    test('stop name is not empty', () {
      final stop = SehiriciStop(
        id: 'stop-1',
        name: 'Durak Adı',
        lat: 41.0082,
        lng: 28.9784,
      );

      expect(stop.name, isNotEmpty);
    });
  });

  group('SehiriciActiveTrip Color Parsing', () {
    test('valid hex color is parsed', () {
      final trip = SehiriciActiveTrip(
        tripId: 'trip-1',
        lineId: 'line-1',
        lineCode: '1T',
        lineName: 'Hat 1',
        lineColor: '#FF5733',
      );

      expect(trip.color, isNotNull);
    });

    test('invalid color defaults gracefully', () {
      final trip = SehiriciActiveTrip(
        tripId: 'trip-1',
        lineId: 'line-1',
        lineCode: '1T',
        lineName: 'Hat 1',
        lineColor: 'not-a-color',
      );

      expect(trip.color, isNotNull);
    });

    test('empty color string defaults gracefully', () {
      final trip = SehiriciActiveTrip(
        tripId: 'trip-1',
        lineId: 'line-1',
        lineCode: '1T',
        lineName: 'Hat 1',
        lineColor: '',
      );

      expect(trip.color, isNotNull);
    });
  });

  group('SehiriciActiveTrip Location Updates', () {
    test('copyWithLocation preserves trip metadata', () {
      final original = SehiriciActiveTrip(
        tripId: 'trip-1',
        lineId: 'line-1',
        lineCode: '1T',
        lineName: 'Hat 1',
        lineColor: '#1976D2',
        driverName: 'Ahmet',
        startedAt: DateTime.now(),
        status: SehiriciTripStatus.active,
      );

      final updated = original.copyWithLocation(lat: 41.0100, lng: 28.9800);

      expect(updated.tripId, original.tripId);
      expect(updated.lineId, original.lineId);
      expect(updated.driverName, original.driverName);
      expect(updated.startedAt, original.startedAt);
      expect(updated.status, original.status);
      expect(updated.currentLat, 41.0100);
      expect(updated.currentLng, 28.9800);
    });

    test('copyWithLocation with null values preserves originals', () {
      final original = SehiriciActiveTrip(
        tripId: 'trip-1',
        lineId: 'line-1',
        lineCode: '1T',
        lineName: 'Hat 1',
        lineColor: '#1976D2',
        currentLat: 41.0082,
        currentLng: 28.9784,
        currentSpeed: 50.0,
      );

      final updated = original.copyWithLocation();

      expect(updated.currentLat, original.currentLat);
      expect(updated.currentLng, original.currentLng);
      expect(updated.currentSpeed, original.currentSpeed);
    });
  });

  group('Data Type Conversions', () {
    test('line fromJson handles both id and line_id', () {
      final json1 = {'id': 'line-1', 'code': '1T', 'name': 'Hat'};
      final json2 = {'line_id': 'line-2', 'code': '2T', 'name': 'Hat'};

      final line1 = SehiriciLine.fromJson(json1);
      final line2 = SehiriciLine.fromJson(json2);

      expect(line1.id, 'line-1');
      expect(line2.id, 'line-2');
    });

    test('trip fromJson handles both id and trip_id', () {
      final json1 = {
        'id': 'trip-1',
        'line_id': 'line-1',
        'line_code': '1T',
        'line_name': 'Hat',
        'line_color': '#1976D2',
      };
      final json2 = {
        'trip_id': 'trip-2',
        'line_id': 'line-1',
        'line_code': '1T',
        'line_name': 'Hat',
        'line_color': '#1976D2',
      };

      final trip1 = SehiriciActiveTrip.fromJson(json1);
      final trip2 = SehiriciActiveTrip.fromJson(json2);

      expect(trip1.tripId, 'trip-1');
      expect(trip2.tripId, 'trip-2');
    });
  });
}
