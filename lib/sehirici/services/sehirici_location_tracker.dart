import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../services/sehirici_trip_service.dart';

/// iOS'ta uygulama arka plana alındığında Geolocator stream'inin
/// duraklatılmasını önlemek için platforma özel ayarlar üretir.
LocationSettings _driverLocationSettings({
  required int distanceFilter,
  Duration? timeLimit,
}) {
  if (!kIsWeb && Platform.isIOS) {
    return AppleSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilter,
      timeLimit: timeLimit,
      pauseLocationUpdatesAutomatically: false,
      allowBackgroundLocationUpdates: true,
      showBackgroundLocationIndicator: true,
      activityType: ActivityType.automotiveNavigation,
    );
  }
  return LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: distanceFilter,
    timeLimit: timeLimit,
  );
}

/// Şoför için canlı konum takip servisi.
/// Geolocator'dan konum alıp SehiriciTripService üzerinden DB'ye yazar.
/// Singleton — uygulama genelinde tek instance.
class SehiriciLocationTracker {
  static final SehiriciLocationTracker _instance =
      SehiriciLocationTracker._internal();
  factory SehiriciLocationTracker() => _instance;
  SehiriciLocationTracker._internal();

  StreamSubscription<Position>? _streamSub;
  Timer? _fallbackTimer;
  Position? _lastPosition;
  bool _isTracking = false;
  String? _currentTripId;
  int _passengerCount = 0;

  bool get isTracking => _isTracking;
  Position? get lastPosition => _lastPosition;

  /// İzlemeyi başlatır. Mevcut izleme varsa yeniden başlatır.
  Future<void> start({
    required String tripId,
    required SehiriciTripService tripService,
    Duration interval = const Duration(seconds: 10),
    int passengerCount = 0,
  }) async {
    if (_isTracking) {
      await stop();
    }

    // Konum izni kontrol
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('Şehirici konum izni reddedildi');
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      debugPrint('Şehirici konum izni kalıcı reddedildi');
      return;
    }

    _currentTripId = tripId;
    _passengerCount = passengerCount;
    _isTracking = true;

    // İlk konumu hemen al
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: _driverLocationSettings(distanceFilter: 0),
      );
      _lastPosition = pos;
      await tripService.updateLocation(
        tripId: tripId,
        lat: pos.latitude,
        lng: pos.longitude,
        heading: pos.heading,
        speed: pos.speed,
        passengerCount: passengerCount,
      );
    } catch (e) {
      debugPrint('İlk konum alınamadı: $e');
    }

    // Stream
    _streamSub = Geolocator.getPositionStream(
      locationSettings: _driverLocationSettings(
        distanceFilter: 5,
        timeLimit: interval * 3,
      ),
    ).listen((pos) async {
      _lastPosition = pos;
      if (_currentTripId == null) return;
      await tripService.updateLocation(
        tripId: _currentTripId!,
        lat: pos.latitude,
        lng: pos.longitude,
        heading: pos.heading,
        speed: pos.speed,
        passengerCount: _passengerCount,
      );
    });

    // Fallback timer (stream tetiklenmezse zorla gönder)
    _fallbackTimer = Timer.periodic(interval, (_) async {
      if (_currentTripId == null) return;
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: _driverLocationSettings(distanceFilter: 0),
        );
        _lastPosition = pos;
        await tripService.updateLocation(
          tripId: _currentTripId!,
          lat: pos.latitude,
          lng: pos.longitude,
          heading: pos.heading,
          speed: pos.speed,
          passengerCount: _passengerCount,
        );
      } catch (e) {
        debugPrint('Fallback konum güncellemesi hatası: $e');
      }
    });
  }

  Future<void> stop() async {
    _isTracking = false;
    _currentTripId = null;
    await _streamSub?.cancel();
    _streamSub = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
  }
}
