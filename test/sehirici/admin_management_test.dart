import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cizreapp/sehirici/models/sehirici_models.dart';

void main() {
  group('Şehiriçi Model Tests', () {
    // ─────────────────────────────────────────────
    // SEHIRICICTY MODEL TESTS
    // ─────────────────────────────────────────────

    group('SehiriciCity Model', () {
      test('creates instance with all fields', () {
        final json = {
          'id': 'city-1',
          'name': 'İstanbul',
          'slug': 'istanbul',
          'center_lat': 41.0082,
          'center_lng': 28.9784,
          'zoom_level': 12,
          'is_active': true,
        };

        final city = SehiriciCity.fromJson(json);

        expect(city.id, 'city-1');
        expect(city.name, 'İstanbul');
        expect(city.slug, 'istanbul');
        expect(city.centerLat, 41.0082);
        expect(city.centerLng, 28.9784);
        expect(city.zoomLevel, 12);
        expect(city.isActive, true);
      });

      test('handles missing fields with defaults', () {
        final json = {
          'id': 'city-2',
          'name': 'Ankara',
        };

        final city = SehiriciCity.fromJson(json);

        expect(city.id, 'city-2');
        expect(city.name, 'Ankara');
        expect(city.slug, '');
        expect(city.centerLat, 0.0);
        expect(city.centerLng, 0.0);
        expect(city.zoomLevel, 13);
        expect(city.isActive, true);
      });
    });

    // ─────────────────────────────────────────────
    // SEHIRICILINE MODEL TESTS
    // ─────────────────────────────────────────────

    group('SehiriciLine Model', () {
      test('creates instance with all fields', () {
        final json = {
          'id': 'line-1',
          'code': '1T',
          'name': 'Taksim - Eminönü',
          'color_hex': '#FF5733',
          'vehicle_type': 'bus',
          'estimated_minutes': 45,
          'fare_amount': 6.5,
          'is_active': true,
          'stops': [],
        };

        final line = SehiriciLine.fromJson(json);

        expect(line.id, 'line-1');
        expect(line.code, '1T');
        expect(line.name, 'Taksim - Eminönü');
        expect(line.colorHex, '#FF5733');
        expect(line.vehicleType, SehiriciVehicleType.bus);
        expect(line.estimatedMinutes, 45);
        expect(line.fareAmount, 6.5);
        expect(line.isActive, true);
      });

      test('isActive defaults to true when missing', () {
        final json = {
          'id': 'line-2',
          'code': '2T',
          'name': 'Hat 2',
          'stops': [],
        };

        final line = SehiriciLine.fromJson(json);

        expect(line.isActive, true);
      });

      test('color parsing works correctly', () {
        final line = SehiriciLine(
          id: 'line-3',
          code: '3T',
          name: 'Hat 3',
          colorHex: '#1976D2',
        );

        expect(line.color, isNotNull);
        expect(line.color.runtimeType, Color);
      });

      test('handles invalid color hex with default', () {
        final line = SehiriciLine(
          id: 'line-4',
          code: '4T',
          name: 'Hat 4',
          colorHex: 'invalid-color',
        );

        expect(line.color.runtimeType, Color);
      });
    });

    // ─────────────────────────────────────────────
    // SEHIRICI STOP MODEL TESTS
    // ─────────────────────────────────────────────

    group('SehiriciStop Model', () {
      test('creates instance with all fields', () {
        final json = {
          'id': 'stop-1',
          'name': 'Taksim Meydanı',
          'code': 'TAK',
          'lat': 41.0368,
          'lng': 29.0274,
          'address': 'Taksim, İstanbul',
          'is_active': true,
        };

        final stop = SehiriciStop.fromJson(json);

        expect(stop.id, 'stop-1');
        expect(stop.name, 'Taksim Meydanı');
        expect(stop.code, 'TAK');
        expect(stop.lat, 41.0368);
        expect(stop.lng, 29.0274);
        expect(stop.address, 'Taksim, İstanbul');
        expect(stop.isActive, true);
      });

      test('handles null optional fields', () {
        final json = {
          'id': 'stop-2',
          'name': 'Durak 2',
          'lat': 40.0,
          'lng': 28.0,
        };

        final stop = SehiriciStop.fromJson(json);

        expect(stop.code, isNull);
        expect(stop.address, isNull);
        expect(stop.isActive, true);
      });
    });

    // ─────────────────────────────────────────────
    // VEHICLE TYPE TESTS
    // ─────────────────────────────────────────────

    group('SehiriciVehicleType Enum', () {
      test('labels are correct', () {
        expect(SehiriciVehicleType.bus.label, 'Otobüs');
        expect(SehiriciVehicleType.minibus.label, 'Minibüs');
        expect(SehiriciVehicleType.midibus.label, 'Midibüs');
        expect(SehiriciVehicleType.dolmus.label, 'Dolmuş');
        expect(SehiriciVehicleType.tram.label, 'Tramvay');
      });

      test('fromString conversion works', () {
        expect(SehiriciVehicleType.fromString('bus'), SehiriciVehicleType.bus);
        expect(SehiriciVehicleType.fromString('minibus'),
            SehiriciVehicleType.minibus);
        expect(SehiriciVehicleType.fromString('dolmus'),
            SehiriciVehicleType.dolmus);
        expect(
            SehiriciVehicleType.fromString('invalid'), SehiriciVehicleType.other);
      });

      test('icons are assigned correctly', () {
        expect(SehiriciVehicleType.bus.icon, Icons.directions_bus);
        expect(SehiriciVehicleType.minibus.icon, Icons.airport_shuttle);
        expect(SehiriciVehicleType.tram.icon, Icons.tram);
      });
    });

    // ─────────────────────────────────────────────
    // TRIP STATUS TESTS
    // ─────────────────────────────────────────────

    group('SehiriciTripStatus Enum', () {
      test('labels are correct', () {
        expect(SehiriciTripStatus.planned.label, 'Planlandı');
        expect(SehiriciTripStatus.active.label, 'Yolda');
        expect(SehiriciTripStatus.paused.label, 'Mola');
        expect(SehiriciTripStatus.completed.label, 'Tamamlandı');
        expect(SehiriciTripStatus.cancelled.label, 'İptal');
      });

      test('fromString conversion works', () {
        expect(SehiriciTripStatus.fromString('active'),
            SehiriciTripStatus.active);
        expect(SehiriciTripStatus.fromString('completed'),
            SehiriciTripStatus.completed);
        expect(
            SehiriciTripStatus.fromString('invalid'), SehiriciTripStatus.planned);
      });
    });

    // ─────────────────────────────────────────────
    // ACTIVE TRIP TESTS
    // ─────────────────────────────────────────────

    group('SehiriciActiveTrip Model', () {
      test('creates instance from JSON', () {
        final json = {
          'trip_id': 'trip-1',
          'line_id': 'line-1',
          'line_code': '1T',
          'line_name': 'Hat 1',
          'line_color': '#1976D2',
          'driver_name': 'Ahmet Yılmaz',
          'current_lat': 41.0082,
          'current_lng': 28.9784,
          'current_heading': 45.0,
          'current_speed': 50.0,
          'started_at': '2024-01-15T10:00:00Z',
          'next_stop_id': 'stop-2',
          'next_stop_name': 'Durak 2',
          'eta_minutes': 5,
          'status': 'active',
        };

        final trip = SehiriciActiveTrip.fromJson(json);

        expect(trip.tripId, 'trip-1');
        expect(trip.lineCode, '1T');
        expect(trip.driverName, 'Ahmet Yılmaz');
        expect(trip.currentLat, 41.0082);
        expect(trip.currentSpeed, 50.0);
        expect(trip.etaMinutes, 5);
        expect(trip.status, SehiriciTripStatus.active);
      });

      test('copyWithLocation updates location fields', () {
        final trip = SehiriciActiveTrip(
          tripId: 'trip-1',
          lineId: 'line-1',
          lineCode: '1T',
          lineName: 'Hat 1',
          lineColor: '#1976D2',
          currentLat: 41.0082,
          currentLng: 28.9784,
          currentSpeed: 50.0,
        );

        final updated = trip.copyWithLocation(
          lat: 41.0100,
          lng: 28.9800,
          speed: 60.0,
        );

        expect(updated.currentLat, 41.0100);
        expect(updated.currentLng, 28.9800);
        expect(updated.currentSpeed, 60.0);
        expect(updated.tripId, trip.tripId);
      });
    });

    // ─────────────────────────────────────────────
    // SETTINGS TESTS
    // ─────────────────────────────────────────────

    group('SehiriciSettings Model', () {
      test('parses from settings map', () {
        final map = {
          'sehirici_module_enabled': 'true',
          'sehirici_allow_user_favorites': 'true',
          'sehirici_location_update_interval_sec': '10',
          'sehirici_eta_refresh_seconds': '30',
          'sehirici_max_history_minutes': '60',
        };

        final settings = SehiriciSettings.fromSettingsMap(map);

        expect(settings.moduleEnabled, true);
        expect(settings.allowUserFavorites, true);
        expect(settings.locationUpdateIntervalSec, 10);
        expect(settings.etaRefreshSeconds, 30);
        expect(settings.maxHistoryMinutes, 60);
      });

      test('handles boolean values', () {
        final map = {
          'sehirici_module_enabled': true,
          'sehirici_allow_user_favorites': false,
        };

        final settings = SehiriciSettings.fromSettingsMap(map);

        expect(settings.moduleEnabled, true);
        expect(settings.allowUserFavorites, false);
      });

      test('uses defaults for missing values', () {
        final settings = SehiriciSettings.fromSettingsMap({});

        expect(settings.moduleEnabled, false);
        expect(settings.locationUpdateIntervalSec, 10);
        expect(settings.etaRefreshSeconds, 30);
        expect(settings.maxHistoryMinutes, 60);
      });
    });

    // ─────────────────────────────────────────────
    // FAVORITE STOP TESTS
    // ─────────────────────────────────────────────

    group('SehiriciFavoriteStop Model', () {
      test('creates instance from JSON', () {
        final json = {
          'id': 'fav-1',
          'stop_id': 'stop-1',
          'notify_minutes_before': 5,
        };

        final fav = SehiriciFavoriteStop.fromJson(json);

        expect(fav.id, 'fav-1');
        expect(fav.stopId, 'stop-1');
        expect(fav.notifyMinutesBefore, 5);
      });

      test('defaults notify_minutes_before to 5', () {
        final json = {
          'id': 'fav-2',
          'stop_id': 'stop-2',
        };

        final fav = SehiriciFavoriteStop.fromJson(json);

        expect(fav.notifyMinutesBefore, 5);
      });
    });
  });
}
