import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class CourierLocationService {
  static final CourierLocationService _instance = CourierLocationService._internal();

  factory CourierLocationService() {
    return _instance;
  }

  CourierLocationService._internal();

  StreamSubscription<Position>? _positionStream;
  Timer? _updateTimer;
  bool _isTracking = false;

  bool get isTracking => _isTracking;

  Future<void> startTracking() async {
    if (_isTracking) return;

    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final result = await Geolocator.requestPermission();
        if (result == LocationPermission.denied) {
          debugPrint('❌ Konum izni reddedildi');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('❌ Konum izni kalıcı olarak reddedildi');
        return;
      }

      _isTracking = true;

      // İlk konumu al
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
        ),
      );

      await _updateLocationInDatabase(position);

      // Konumu düzenli olarak güncelle
      _updateTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        _updateLocationPeriodically();
      });

      // Gerçek zamanlı akış
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 10, // 10 metrelik değişim
          timeLimit: Duration(seconds: 5),
        ),
      ).listen((Position position) {
        _updateLocationInDatabase(position);
      });

      debugPrint('✅ Kurye konum takibi başladı');
    } catch (e) {
      debugPrint('❌ Konum takibi başlama hatası: $e');
      _isTracking = false;
    }
  }

  Future<void> _updateLocationPeriodically() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
        ),
      );
      await _updateLocationInDatabase(position);
    } catch (e) {
      debugPrint('⚠️ Konum güncelleme hatası: $e');
    }
  }

  Future<void> _updateLocationInDatabase(Position position) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      await Supabase.instance.client
          .from('profiles')
          .update({
            'last_known_lat': position.latitude,
            'last_known_lng': position.longitude,
            'last_location_update': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);

      debugPrint('📍 Konum güncellendi: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      debugPrint('❌ Veritabanında konum güncelleme hatası: $e');
    }
  }

  Future<void> stopTracking() async {
    _isTracking = false;
    await _positionStream?.cancel();
    _updateTimer?.cancel();
    _positionStream = null;
    _updateTimer = null;
    debugPrint('✅ Kurye konum takibi durduruldu');
  }

  Future<Position?> getCurrentLocation() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
        ),
      );
    } catch (e) {
      debugPrint('❌ Geçerli konum alma hatası: $e');
      return null;
    }
  }
}
