import 'package:flutter_test/flutter_test.dart';
import 'package:cizreapp/sehirici/models/sehirici_models.dart';

void main() {
  group('SehiriciVehicleType', () {
    test('fromString tüm enum değerlerini doğru eşler', () {
      expect(
        SehiriciVehicleType.fromString('minibus'),
        SehiriciVehicleType.minibus,
      );
      expect(SehiriciVehicleType.fromString('bus'), SehiriciVehicleType.bus);
      expect(
        SehiriciVehicleType.fromString('midibus'),
        SehiriciVehicleType.midibus,
      );
      expect(
        SehiriciVehicleType.fromString('dolmus'),
        SehiriciVehicleType.dolmus,
      );
      expect(SehiriciVehicleType.fromString('tram'), SehiriciVehicleType.tram);
    });

    test('fromString bilinmeyen değer other döner', () {
      expect(SehiriciVehicleType.fromString('xxx'), SehiriciVehicleType.other);
      expect(SehiriciVehicleType.fromString(null), SehiriciVehicleType.other);
    });

    test('label boş değildir', () {
      for (final v in SehiriciVehicleType.values) {
        expect(v.label.isNotEmpty, true);
      }
    });
  });

  group('SehiriciTripStatus', () {
    test('fromString doğru eşler', () {
      expect(
        SehiriciTripStatus.fromString('active'),
        SehiriciTripStatus.active,
      );
      expect(
        SehiriciTripStatus.fromString('paused'),
        SehiriciTripStatus.paused,
      );
      expect(
        SehiriciTripStatus.fromString('completed'),
        SehiriciTripStatus.completed,
      );
    });

    test('dbValue name ile aynıdır', () {
      expect(SehiriciTripStatus.active.dbValue, 'active');
      expect(SehiriciTripStatus.completed.dbValue, 'completed');
    });
  });

  group('SehiriciCity.fromJson', () {
    test('tüm alanları parse eder', () {
      final city = SehiriciCity.fromJson({
        'id': 'c1',
        'name': 'Cizre',
        'slug': 'cizre',
        'center_lat': 37.3255,
        'center_lng': 42.1876,
        'zoom_level': 14,
        'is_active': true,
      });
      expect(city.id, 'c1');
      expect(city.name, 'Cizre');
      expect(city.centerLat, 37.3255);
      expect(city.centerLng, 42.1876);
      expect(city.zoomLevel, 14);
      expect(city.isActive, true);
    });

    test('eksik alanlar güvenli varsayılan', () {
      final city = SehiriciCity.fromJson({'id': 'c1'});
      expect(city.id, 'c1');
      expect(city.name, '');
      expect(city.centerLat, 0);
      expect(city.zoomLevel, 13);
      expect(city.isActive, true);
    });
  });

  group('SehiriciLine.fromJson', () {
    test('hat ve durak listesi parse edilir', () {
      final line = SehiriciLine.fromJson({
        'line_id': 'l1',
        'code': '1A',
        'name': 'Hastane - Üniversite',
        'color_hex': '#FF0000',
        'vehicle_type': 'bus',
        'estimated_minutes': 45,
        'fare_amount': 12.5,
        'stops': [
          {
            'stop_id': 's1',
            'stop_order': 0,
            'minutes_from_start': 0,
            'name': 'Başlangıç',
            'lat': 37.3,
            'lng': 42.1,
          },
          {
            'stop_id': 's2',
            'stop_order': 1,
            'minutes_from_start': 10,
            'name': 'Hastane',
            'lat': 37.31,
            'lng': 42.11,
          },
        ],
      });
      expect(line.id, 'l1');
      expect(line.code, '1A');
      expect(line.name, 'Hastane - Üniversite');
      expect(line.vehicleType, SehiriciVehicleType.bus);
      expect(line.fareAmount, 12.5);
      expect(line.stops.length, 2);
      expect(line.stops.first.stopOrder, 0);
      expect(line.stops.last.name, 'Hastane');
    });

    test('color hex geçersizse varsayılan renk döner', () {
      final line = SehiriciLine.fromJson({
        'id': 'l1',
        'code': '1A',
        'name': 'Test',
        'color_hex': 'INVALID',
      });
      // Varsayılan mavi (0xFF1976D2)
      expect(line.color.toARGB32(), 0xFF1976D2);
    });

    test('stops yoksa boş liste', () {
      final line = SehiriciLine.fromJson({
        'id': 'l1',
        'code': '1A',
        'name': 'Test',
      });
      expect(line.stops, isEmpty);
    });
  });

  group('SehiriciActiveTrip.fromJson', () {
    test('tüm alanlar parse edilir', () {
      final trip = SehiriciActiveTrip.fromJson({
        'trip_id': 't1',
        'line_id': 'l1',
        'line_code': '1A',
        'line_name': 'Hat 1',
        'line_color': '#2196F3',
        'driver_name': 'Ahmet',
        'current_lat': 37.3,
        'current_lng': 42.1,
        'current_heading': 90.0,
        'current_speed': 8.0,
        'started_at': '2026-07-24T10:00:00Z',
        'next_stop_id': 's2',
        'next_stop_name': 'Hastane',
        'eta_minutes': 5,
        'status': 'active',
      });
      expect(trip.tripId, 't1');
      expect(trip.lineCode, '1A');
      expect(trip.driverName, 'Ahmet');
      expect(trip.currentLat, 37.3);
      expect(trip.etaMinutes, 5);
      expect(trip.status, SehiriciTripStatus.active);
    });

    test('copyWithLocation mevcut alanları korur', () {
      final trip = SehiriciActiveTrip.fromJson({
        'trip_id': 't1',
        'line_id': 'l1',
        'line_code': '1A',
        'line_name': 'Hat 1',
        'line_color': '#2196F3',
      });
      final updated = trip.copyWithLocation(
        lat: 38.0,
        lng: 43.0,
        etaMinutes: 7,
      );
      expect(updated.currentLat, 38.0);
      expect(updated.currentLng, 43.0);
      expect(updated.etaMinutes, 7);
      // Line bilgisi korunmalı
      expect(updated.lineCode, '1A');
      expect(updated.lineName, 'Hat 1');
    });
  });

  group('SehiriciSettings.fromSettingsMap', () {
    test('string "true" boolean olarak parse edilir', () {
      final s = SehiriciSettings.fromSettingsMap({
        'sehirici_module_enabled': 'true',
        'sehirici_allow_user_favorites': 'false',
        'sehirici_location_update_interval_sec': '15',
        'sehirici_eta_refresh_seconds': '45',
        'sehirici_max_history_minutes': '120',
        'sehirici_default_city_id': 'c1',
      });
      expect(s.moduleEnabled, true);
      expect(s.allowUserFavorites, false);
      expect(s.locationUpdateIntervalSec, 15);
      expect(s.etaRefreshSeconds, 45);
      expect(s.maxHistoryMinutes, 120);
      expect(s.defaultCityId, 'c1');
    });

    test('eksik anahtarlar güvenli varsayılan', () {
      final s = SehiriciSettings.fromSettingsMap({});
      expect(s.moduleEnabled, false);
      expect(s.locationUpdateIntervalSec, 10);
      expect(s.etaRefreshSeconds, 30);
      expect(s.maxHistoryMinutes, 60);
      expect(s.defaultCityId, isNull);
    });

    test('gerçek boolean da kabul edilir', () {
      final s = SehiriciSettings.fromSettingsMap({
        'sehirici_module_enabled': true,
      });
      expect(s.moduleEnabled, true);
    });
  });
}
