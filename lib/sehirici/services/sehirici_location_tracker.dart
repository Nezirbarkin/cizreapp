import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../services/sehirici_trip_service.dart';

/// iOS'ta uygulama arka plana alındığında Geolocator stream'inin
/// duraklatılmasını önlemek için platforma özel ayarlar üretir.
/// Android'de foreground notification ile arka plan konum paylaşımını sürdürür
/// (geolocator kendi foreground service'ını manifest merge ile bildirir).
///
/// Public: hem tracker (driving fazı) hem de SehiriciAutoTripController
/// (watching fazı) aynı ayarı kullanır — tek kaynak.
LocationSettings sehiriciLocationSettings({
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
  if (!kIsWeb && Platform.isAndroid) {
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilter,
      timeLimit: timeLimit,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationText: 'Sefer takibi devam ediyor',
        notificationTitle: 'CizreApp Şoför',
        enableWakeLock: true,
      ),
    );
  }
  return LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: distanceFilter,
    timeLimit: timeLimit,
  );
}

/// İki yazma arasındaki minimum süre. 10 sn hedefi için 8 sn güvenlik marjı
/// bırakılır (network/RPC gecikmesi dahil).
const _kMinWriteInterval = Duration(seconds: 8);

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
  DateTime? _lastWriteAt;
  bool _isTracking = false;
  String? _currentTripId;
  int _passengerCount = 0;

  /// Her başarılı DB konum yazımından sonra çağrılır. SehiriciAutoTripController
  /// bunu driving fazında bitiş koşullarını değerlendirmek için kullanır.
  /// Atanmazsa no-op.
  void Function(Position position)? onPositionWritten;

  bool get isTracking => _isTracking;
  Position? get lastPosition => _lastPosition;
  String? get currentTripId => _currentTripId;
  DateTime? get lastWriteAt => _lastWriteAt;

  /// İzlemeyi başlatır. Mevcut izleme varsa yeniden başlatır.
  /// [interval] varsayılan 10 sn — hem stream hem fallback timer bunu kullanır.
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
    _lastWriteAt = null;
    _isTracking = true;

    // İlk konumu hemen al (mevcut mantık korunur)
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: sehiriciLocationSettings(distanceFilter: 0),
      );
      _lastPosition = pos;
      await _writePosition(tripService, pos);
    } catch (e) {
      debugPrint('İlk konum alınamadı: $e');
    }

    // Stream: distanceFilter=0 ile her konum değişimini al, çift yazma koruması
    // _writePosition içinde (zamanlama ile) yapılır.
    _streamSub = Geolocator.getPositionStream(
      locationSettings: sehiriciLocationSettings(
        distanceFilter: 0,
        timeLimit: interval * 3,
      ),
    ).listen((pos) async {
      _lastPosition = pos;
      if (_currentTripId == null) return;
      await _writePosition(tripService, pos);
    });

    // Fallback timer: stream tetiklenmezse zorla konum al.
    _fallbackTimer = Timer.periodic(interval, (_) async {
      if (_currentTripId == null) return;
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: sehiriciLocationSettings(distanceFilter: 0),
        );
        _lastPosition = pos;
        await _writePosition(tripService, pos);
      } catch (e) {
        debugPrint('Fallback konum güncellemesi hatası: $e');
      }
    });
  }

  /// Konumu DB'ye yazar. _kMinWriteInterval içinde tekrar yazma yapılmaz
  /// (stream + fallback çakışmasını engeller).
  Future<void> _writePosition(
    SehiriciTripService tripService,
    Position pos,
  ) async {
    final tripId = _currentTripId;
    if (tripId == null) return;
    final now = DateTime.now();
    if (_lastWriteAt != null && now.difference(_lastWriteAt!) < _kMinWriteInterval) {
      return;
    }
    _lastWriteAt = now;
    try {
      await tripService.updateLocation(
        tripId: tripId,
        lat: pos.latitude,
        lng: pos.longitude,
        heading: pos.heading,
        speed: pos.speed,
        passengerCount: _passengerCount,
      );
      final cb = onPositionWritten;
      if (cb != null) {
        // UI/dispatch hatası konum akışını bozmamalı; no-await, fire-and-forget.
        try {
          cb(pos);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Konum yazma hatası: $e');
      // Hata olursa son yazma zamanını sıfırla ki bir sonraki tick'te tekrar denesin
      _lastWriteAt = null;
    }
  }

  Future<void> stop() async {
    _isTracking = false;
    _currentTripId = null;
    _lastWriteAt = null;
    onPositionWritten = null;
    await _streamSub?.cancel();
    _streamSub = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
  }
}
