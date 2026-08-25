import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/sehirici_models.dart';
import '../services/sehirici_route_service.dart';

/// Şöför konum takibi provider'ı
class SehiriciLocationProvider extends ChangeNotifier {
  final SehiriciRouteService _routeService = SehiriciRouteService();

  Position? _currentPosition;
  String? _activeRouteId;
  bool _isTracking = false;
  String? _errorMessage;

  /// Abonelik saklanmazsa `stopTracking` yalnızca bayrağı indiriyor, GPS akışı
  /// uygulama ömrü boyunca açık kalıyordu; `startTracking` her çağrıldığında
  /// üstüne bir akış daha ekleniyordu.
  StreamSubscription<Position>? _positionSub;

  Position? get currentPosition => _currentPosition;
  bool get isTracking => _isTracking;
  String? get errorMessage => _errorMessage;

  /// Konum takibini başlat
  Future<bool> startTracking(String routeId) async {
    try {
      _activeRouteId = routeId;
      _isTracking = true;
      _errorMessage = null;
      notifyListeners();

      // İzin burada İSTENMEZ, yalnız doğrulanır. Google Play'in Prominent
      // Disclosure şartı, konum toplanmadan önce uygulama içi açıklamanın
      // gösterilmesini zorunlu kılar; açıklama ekranı context gerektirdiği
      // için izin akışı UI katmanındadır (LocationDisclosureService.ensure →
      // LocationPurpose.driverTrip). Provider izinsiz çağrılırsa durur.
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        _errorMessage = 'Konum izni yok';
        _isTracking = false;
        notifyListeners();
        return false;
      }

      // İlk konumu al
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // 10 metre değişimde güncelle
        ),
      );

      _currentPosition = position;
      await _updateRouteLocation(position, 0);

      // Stream'i dinle (realtime)
      await _positionSub?.cancel();
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((Position position) async {
        if (_isTracking && _activeRouteId != null) {
          _currentPosition = position;
          notifyListeners();

          // Veritabanını güncelle
          await _updateRouteLocation(position, 0);
        }
      });

      return true;
    } catch (e) {
      _errorMessage = 'Konum alınamadı: $e';
      _isTracking = false;
      notifyListeners();
      return false;
    }
  }

  /// Konum takibini durdur
  Future<void> stopTracking() async {
    _isTracking = false;
    _activeRouteId = null;
    await _positionSub?.cancel();
    _positionSub = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _positionSub = null;
    super.dispose();
  }

  /// Rota konumunu veritabanında güncelle
  Future<void> _updateRouteLocation(Position position, int order) async {
    if (_activeRouteId == null) return;

    try {
      await _routeService.updateRoutePoint(
        _activeRouteId!,
        order,
        position.latitude,
        position.longitude,
        position.accuracy,
      );
    } catch (e) {
      debugPrint('Konum güncellenirken hata: $e');
    }
  }

  /// Mesafe hesapla (harita'da göstermek için)
  double? getDistanceToStop(SehiriciStop stop) {
    if (_currentPosition == null) return null;

    final distance = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      stop.lat,
      stop.lng,
    );

    return distance; // metre cinsinden
  }
}
