// ignore_for_file: deprecated_member_use, prefer_interpolation_to_compose_strings

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart' show EagerGestureRecognizer, OneSequenceGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/sehirici_models.dart';
import '../services/sehirici_line_service.dart';

/// Şehir içi servis canlı harita widget'ı.
/// Aktif seferleri ve durakları harita üzerinde gösterir.
///
/// Dinamik Özellikler:
/// • Animasyonlu Araç Hareketi: LatLng lerp ile smooth geçiş
/// • Nabız/Pulse Efekti: Canlı araçlarda Circle overlay animasyonu
/// • 3D Tilt Modu: 45 derece camera tilt
/// • Traffic Overlay: Google Maps traffic layer
/// • Live ETA Updates: Timer ile otomatik güncelleme
///
/// Performans: yalnızca görünür marker'ları günceller, controller tek seferde oluşturulur.
class SehiriciLiveMap extends StatefulWidget {
  final List<SehiriciLine> lines;
  final List<SehiriciActiveTrip> activeTrips;
  final SehiriciCity center;
  final int zoomLevel;
  final String? selectedStopId;
  final bool interactive;
  final double height;
  
  /// 3D tilt açısı (derece cinsinden)
  final double tiltAngle;
  
  /// Trafik katmanını göster/gizle
  final bool showTraffic;
  
  /// Canlı güncellemeleri etkinleştir
  final bool enableLiveUpdates;
  
  /// Live update aralığı (saniye)
  final int updateIntervalSeconds;

  const SehiriciLiveMap({
    super.key,
    required this.lines,
    required this.activeTrips,
    required this.center,
    this.zoomLevel = 13,
    this.selectedStopId,
    this.interactive = true,
    this.height = 220,
    this.tiltAngle = 45.0,
    this.showTraffic = true,
    this.enableLiveUpdates = true,
    this.updateIntervalSeconds = 30,
  });

  @override
  State<SehiriciLiveMap> createState() => _SehiriciLiveMapState();
}

class _SehiriciLiveMapState extends State<SehiriciLiveMap> with TickerProviderStateMixin {
  static final Map<String, BitmapDescriptor> _iconCache = {};
  static final Map<String, List<List<double>>> _roadRouteCache = {};
  static final Set<String> _roadRoutesFetching = {};

  // Animasyon durumları
  final Map<String, LatLng> _previousPositions = {};
  final Map<String, LatLng> _targetPositions = {};
  final Map<String, AnimationController> _positionAnimControllers = {};
  final Map<String, Animation<LatLng>> _positionAnimations = {};

  // Pulse animasyon durumları
  final Map<String, AnimationController> _pulseControllers = {};
  final Map<String, Animation<double>> _pulseAnimations = {};

  // Timer durumları
  Timer? _liveUpdateTimer;
  Timer? _etaUpdateTimer;

  // Mevcut trip verileri (ETA hesaplaması için)
  final Map<String, SehiriciActiveTrip> _currentTripData = {};

  final SehiriciLineService _lineService = SehiriciLineService();
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  Set<Circle> _circles = {}; // Pulse efektleri için
  bool _initialFit = true;
  bool _isMapReady = false;
  bool _roadRoutesLoaded = false;

  // Kullanıcının kendi konumu ve seçili hat için canlı takip
  Position? _userPosition;
  LatLng? _draggedPosition;
  StreamSubscription<Position>? _userPositionSub;
  SehiriciLine? _selectedLine;
  String? _selectedLineId;
  String? _selectedTripId;
  BitmapDescriptor? _userLocationIcon;

  @override
  void initState() {
    super.initState();
    _initializeTripData();
    _rebuild();
    _initUserLocationOnEntry();

    // Live update timer başlat
    if (widget.enableLiveUpdates) {
      _startLiveUpdates();
    }
  }

  /// Harita açılır açılmaz konum iznini ister ve kullanıcının konumunu
  /// haritada gösterip canlı takibe başlar.
  Future<void> _initUserLocationOnEntry() async {
    final pos = await SehiriciUserLocation.getCurrent();
    if (pos == null || !mounted) return;
    setState(() => _userPosition = pos);
    _startUserLocationStream();
    _rebuildUserOverlay();
  }

  void _initializeTripData() {
    for (final trip in widget.activeTrips) {
      if (trip.currentLat != null && trip.currentLng != null) {
        _currentTripData[trip.tripId] = trip;
        _previousPositions[trip.tripId] = LatLng(trip.currentLat!, trip.currentLng!);
        _targetPositions[trip.tripId] = LatLng(trip.currentLat!, trip.currentLng!);
      }
    }
  }

  void _startLiveUpdates() {
    // Araç konum güncelleme timer (50+ metre değişim başında)
    _liveUpdateTimer = Timer.periodic(
      Duration(seconds: widget.updateIntervalSeconds),
      (_) => _refreshTripPositions(),
    );

    // ETA güncelleme timer (her 60 saniyede bir — sadece marker metinleri)
    _etaUpdateTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refreshETAs(),
    );
  }

  void _refreshTripPositions() {
    if (!mounted || widget.activeTrips.isEmpty) return;

    bool needsRedraw = false;

    // Yeni trip verilerini al ve animasyonları başlat (pozisyon değiştiğinde)
    for (final trip in widget.activeTrips) {
      if (trip.currentLat == null || trip.currentLng == null) continue;

      final newPosition = LatLng(trip.currentLat!, trip.currentLng!);
      final tripId = trip.tripId;
      final currentTarget = _targetPositions[tripId];

      // Sadece pozisyon 50+ metre değişmişse animasyon başlat
      if (currentTarget == null || calculateDistance(currentTarget, newPosition) > 50) {
        _previousPositions[tripId] = currentTarget ?? newPosition;
        _targetPositions[tripId] = newPosition;
        _animateVehicleToPosition(tripId, newPosition);
        needsRedraw = true;
      }

      // Trip verisini güncelle
      _currentTripData[tripId] = trip;
    }

    // Eski trip'leri temizle
    final currentTripIds = widget.activeTrips.map((t) => t.tripId).toSet();
    _previousPositions.removeWhere((key, _) => !currentTripIds.contains(key));
    _targetPositions.removeWhere((key, _) => !currentTripIds.contains(key));
    _currentTripData.removeWhere((key, _) => !currentTripIds.contains(key));

    // Seçili hat için kullanıcı konumuna olan bağlantı çizgisini/ETA'yı güncelle
    if ((needsRedraw || _selectedLineId != null) && _userPosition != null) {
      _rebuildUserOverlay();
    }
  }

  void _refreshETAs() {
    if (!mounted) return;
    
    // Sadece marker'ları güncelle (animasyon tetiklemeden)
    _rebuildTripMarkersOnly();
  }

  void _animateVehicleToPosition(String tripId, LatLng targetPosition) {
    // Mevcut animasyonu kontrol et
    final existingController = _positionAnimControllers[tripId];
    if (existingController != null && existingController.isAnimating) {
      // Animasyon devam ediyorsa, mevcut pozisyonu yeni başlangıç yap
      final currentPosition = _positionAnimations[tripId]?.value ?? targetPosition;
      _previousPositions[tripId] = currentPosition;
      existingController.stop();
    }
    
    // Yeni animasyon oluştur
    final controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    final animation = LatLngTween(
      begin: _previousPositions[tripId] ?? targetPosition,
      end: targetPosition,
    ).animate(CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
    ));
    
    animation.addListener(() {
      if (mounted) {
        setState(() {
          _updateVehicleMarkerPosition(tripId, animation.value);
        });
      }
    });
    
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _previousPositions[tripId] = targetPosition;
      }
    });
    
    _positionAnimControllers[tripId] = controller;
    _positionAnimations[tripId] = animation;
    
    controller.forward();
  }

  void _updateVehicleMarkerPosition(String tripId, LatLng position) {
    // Marker pozisyonunu güncelle
    _markers = _markers.map((marker) {
      if (marker.markerId.value == 'trip_$tripId') {
        return marker.copyWith(positionParam: position);
      }
      return marker;
    }).toSet();
  }

  /// Pulse animasyonunu başlat
  void _startPulseAnimation(String tripId, Color pulseColor) {
    // Mevcut pulse controller'ı temizle
    _pulseControllers[tripId]?.dispose();
    
    final controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    final animation = Tween<double>(begin: 1.0, end: 2.5).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeOut),
    );
    
    controller.addListener(() {
      if (mounted && _isMapReady) {
        setState(() {
          _updatePulseCircle(tripId, animation.value, pulseColor);
        });
      }
    });
    
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        controller.repeat();
      }
    });
    
    controller.repeat();
    _pulseControllers[tripId] = controller;
    _pulseAnimations[tripId] = animation;
  }

  void _updatePulseCircle(String tripId, double scale, Color color) {
    final targetPos = _targetPositions[tripId];
    if (targetPos == null) return;
    
    _circles = _circles.where((c) => c.circleId.value != 'pulse_$tripId').toSet();
    
    final circle = Circle(
      circleId: CircleId('pulse_$tripId'),
      center: targetPos,
      radius: 25 * scale,
      fillColor: color.withOpacity(0.3 * (1 - (scale - 1) / 1.5)),
      strokeColor: color.withOpacity(0.6 * (1 - (scale - 1) / 1.5)),
      strokeWidth: 2,
      consumeTapEvents: false,
    );
    
    _circles = {..._circles, circle};
  }

  /// Pulse animasyonunu durdur
  void _stopPulseAnimation(String tripId) {
    _pulseControllers[tripId]?.dispose();
    _pulseControllers.remove(tripId);
    _pulseAnimations.remove(tripId);
    
    _circles = _circles.where((c) => c.circleId.value != 'pulse_$tripId').toSet();
  }

  @override
  void didUpdateWidget(covariant SehiriciLiveMap old) {
    super.didUpdateWidget(old);

    // Trip değişikliklerini kontrol et
    if (old.activeTrips != widget.activeTrips) {
      _handleTripChanges(old.activeTrips);
    }

    // Tilt değişikliği
    if (old.tiltAngle != widget.tiltAngle && _mapController != null) {
      _updateCameraTilt();
    }

    // Live update değişikliği
    if (old.enableLiveUpdates != widget.enableLiveUpdates) {
      if (widget.enableLiveUpdates) {
        _startLiveUpdates();
      } else {
        _stopLiveUpdates();
      }
    }

    // Sadece hat değiştiğinde _rebuild çağır (trip değişiklikleri _handleTripChanges tarafından işlenecek)
    if (old.lines != widget.lines) {
      _roadRoutesLoaded = false;
      _rebuild();
    }
  }

  void _handleTripChanges(List<SehiriciActiveTrip> oldTrips) {
    final oldTripIds = oldTrips.map((t) => t.tripId).toSet();
    final newTripIds = widget.activeTrips.map((t) => t.tripId).toSet();
    
    // Yeni eklenen trip'ler
    for (final trip in widget.activeTrips) {
      if (!oldTripIds.contains(trip.tripId)) {
        if (trip.currentLat != null && trip.currentLng != null) {
          _currentTripData[trip.tripId] = trip;
          _previousPositions[trip.tripId] = LatLng(trip.currentLat!, trip.currentLng!);
          _targetPositions[trip.tripId] = LatLng(trip.currentLat!, trip.currentLng!);
          
          // Pulse başlat
          final line = widget.lines.firstWhere(
            (l) => l.id == trip.lineId,
            orElse: () => SehiriciLine(id: trip.lineId, code: trip.lineCode, name: trip.lineName, colorHex: trip.lineColor),
          );
          _startPulseAnimation(trip.tripId, line.color);
        }
      }
    }
    
    // Kaldırılan trip'ler
    for (final tripId in oldTripIds.difference(newTripIds)) {
      _stopPulseAnimation(tripId);
      _positionAnimControllers[tripId]?.dispose();
      _positionAnimControllers.remove(tripId);
      _positionAnimations.remove(tripId);
      _previousPositions.remove(tripId);
      _targetPositions.remove(tripId);
      _currentTripData.remove(tripId);
    }
  }

  void _stopLiveUpdates() {
    _liveUpdateTimer?.cancel();
    _etaUpdateTimer?.cancel();
    _liveUpdateTimer = null;
    _etaUpdateTimer = null;
  }

  void _updateCameraTilt() {
    if (_mapController == null) return;
    
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _mapController != null ? (_markers.isNotEmpty ? _markers.first.position : LatLng(widget.center.centerLat, widget.center.centerLng)) : LatLng(widget.center.centerLat, widget.center.centerLng),
          zoom: widget.zoomLevel.toDouble(),
          tilt: widget.tiltAngle,
        ),
      ),
    );
  }

  void _rebuild() {
    final markers = <Marker>{};
    final polylines = <Polyline>{};

    // 1) Hat polylines (düz çizgi — hızlı ilk çizim) + durak marker'ları
    for (final line in widget.lines) {
      if (line.stops.length >= 2) {
        // Önce cache'de kontrol et, yoksa düz çizgi kullan
        final cachedRoute = _roadRouteCache[line.id];
        final points = (cachedRoute != null && cachedRoute.length >= 2)
            ? cachedRoute.map((p) => LatLng(p[0], p[1])).toList()
            : line.stops.map((s) => LatLng(s.lat, s.lng)).toList();

        polylines.add(Polyline(
          polylineId: PolylineId('line_${line.id}'),
          points: points,
          color: line.color.withOpacity(0.7),
          width: 5,
          consumeTapEvents: true,
          onTap: () => _onLineTapped(line),
        ));
      }

      // Durak marker'ları — tek duraklı hatlarda da gösterilmeli.
      for (final stop in line.stops) {
        final isSelected = widget.selectedStopId == stop.stopId;
        final stopKey = isSelected ? 'stop_sel' : 'stop_default';
        markers.add(Marker(
          markerId: MarkerId('stop_${stop.stopId}'),
          position: LatLng(stop.lat, stop.lng),
          icon: _iconCache[stopKey] ??
              BitmapDescriptor.defaultMarkerWithHue(
                isSelected
                    ? BitmapDescriptor.hueOrange
                    : BitmapDescriptor.hueViolet,
              ),
          anchor: const Offset(0.5, 0.5),
          consumeTapEvents: true,
          onTap: () => _showStopSheet(line, stop),
        ));
      }
    }

    // 2) Aktif sefer marker'ları (araç konumu)
    for (final trip in widget.activeTrips) {
      if (trip.currentLat == null || trip.currentLng == null) continue;

      final line = widget.lines.firstWhere(
        (l) => l.id == trip.lineId,
        orElse: () => SehiriciLine(id: trip.lineId, code: trip.lineCode, name: trip.lineName, colorHex: trip.lineColor),
      );
      final cacheKey = '${line.vehicleType.name}_${trip.lineColor}';
      final cachedIcon = _iconCache[cacheKey];

      // Animasyonlu pozisyon kullan
      final animatedPosition = _targetPositions[trip.tripId] ?? LatLng(trip.currentLat!, trip.currentLng!);

      markers.add(Marker(
        markerId: MarkerId('trip_${trip.tripId}'),
        position: animatedPosition,
        icon: cachedIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        anchor: const Offset(0.5, 0.5),
        consumeTapEvents: true,
        onTap: () => _showTripDetailsDialog(trip),
        rotation: trip.currentHeading ?? 0,
        flat: true,
        infoWindow: InfoWindow(
          title: trip.lineCode + ' — ' + trip.lineName,
          snippet: trip.nextStopName != null
              ? 'Sonraki: ${trip.nextStopName}'
                  '${trip.etaMinutes != null ? ' (${trip.etaMinutes} dk)' : ''}'
              : 'Yolda',
        ),
      ));

      // Pulse efekti başlat
      _startPulseAnimation(trip.tripId, line.color);
    }

    _markers = markers;
    _polylines = polylines;

    if (_mapController != null && _initialFit) {
      _fitBounds();
    }

    _loadVehicleIcons();
    _loadStopIcons();

    // Rota yüklemesini sadece bir kez yap
    if (!_roadRoutesLoaded) {
      _loadRoadRoutes();
      _roadRoutesLoaded = true;
    }
  }

  /// Durak marker'ları için küçük, tıklanabilir bir durak ikonu üretir
  Future<void> _loadStopIcons() async {
    final needed = <String>{'stop_default', 'stop_sel'};
    needed.removeWhere(_iconCache.containsKey);
    if (needed.isEmpty) {
      if (_markers.any((m) => m.markerId.value.startsWith('stop_'))) {
        _rebuildStopMarkersOnly();
      }
      return;
    }
    if (needed.contains('stop_default')) {
      _iconCache['stop_default'] =
          await _createStopBitmap(Colors.red);
    }
    if (needed.contains('stop_sel')) {
      _iconCache['stop_sel'] = await _createStopBitmap(Colors.orange);
    }
    if (mounted) _rebuildStopMarkersOnly();
  }

  /// Sadece durak marker'larını (yeni ikonlarla) yeniden oluşturup setState eder.
  void _rebuildStopMarkersOnly() {
    final markers = {
      ..._markers.where((m) => !m.markerId.value.startsWith('stop_')),
    };
    for (final line in widget.lines) {
      for (final stop in line.stops) {
        final isSelected = widget.selectedStopId == stop.stopId;
        final stopKey = isSelected ? 'stop_sel' : 'stop_default';
        markers.add(Marker(
          markerId: MarkerId('stop_${stop.stopId}'),
          position: LatLng(stop.lat, stop.lng),
          icon: _iconCache[stopKey] ??
              BitmapDescriptor.defaultMarkerWithHue(
                isSelected
                    ? BitmapDescriptor.hueOrange
                    : BitmapDescriptor.hueViolet,
              ),
          anchor: const Offset(0.5, 0.5),
          consumeTapEvents: true,
          onTap: () => _showStopSheet(line, stop),
        ));
      }
    }
    setState(() => _markers = markers);
  }

  /// Küçük, yuvarlak bir "durak" ikonu (otobüs durağı işareti) çizer.
  Future<BitmapDescriptor> _createStopBitmap(Color color) async {
    const double size = 48;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    canvas.drawCircle(
        const Offset(size / 2, size / 2), size / 2 - 2, Paint()..color = color);
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2 - 2,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    const icon = Icons.location_on;
    final textPainter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size * 0.5,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
        ),
      )
      ..layout();
    textPainter.paint(
      canvas,
      Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  /// Durağa tıklandığında bilgi kartı gösterir
  void _showStopSheet(SehiriciLine line, SehiriciLineStop stop) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: line.color,
                  child: Text(
                    '${stop.stopOrder + 1}',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stop.name,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      Text('${line.code} — ${line.name} · ${stop.stopOrder + 1}. durak'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Araç konumu marker'ları için gerçek araç ikonu (bus/minibüs vb.) üretir.
  Future<void> _loadVehicleIcons() async {
    final needed = <String, ({IconData icon, Color color})>{};
    for (final trip in widget.activeTrips) {
      final line = widget.lines.firstWhere(
        (l) => l.id == trip.lineId,
        orElse: () => SehiriciLine(id: trip.lineId, code: trip.lineCode, name: trip.lineName, colorHex: trip.lineColor),
      );
      final key = '${line.vehicleType.name}_${trip.lineColor}';
      if (!_iconCache.containsKey(key) && !needed.containsKey(key)) {
        needed[key] = (icon: line.vehicleType.icon, color: line.color);
      }
    }
    if (needed.isEmpty) {
      if (widget.activeTrips.isNotEmpty && mounted) _rebuildTripMarkersOnly();
      return;
    }
    for (final entry in needed.entries) {
      _iconCache[entry.key] =
          await _createVehicleBitmap(entry.value.icon, entry.value.color);
    }
    if (mounted) _rebuildTripMarkersOnly();
  }

  /// Sadece araç marker'larını (yeni ikonlarla) yeniden oluşturup setState eder
  void _rebuildTripMarkersOnly() {
    final markers = {
      ..._markers.where((m) => !m.markerId.value.startsWith('trip_')),
    };
    for (final trip in widget.activeTrips) {
      if (trip.currentLat == null || trip.currentLng == null) continue;
      final line = widget.lines.firstWhere(
        (l) => l.id == trip.lineId,
        orElse: () => SehiriciLine(id: trip.lineId, code: trip.lineCode, name: trip.lineName, colorHex: trip.lineColor),
      );
      final cacheKey = '${line.vehicleType.name}_${trip.lineColor}';
      
      // Animasyonlu pozisyon kullan
      final animatedPosition = _targetPositions[trip.tripId] ?? LatLng(trip.currentLat!, trip.currentLng!);
      
      markers.add(Marker(
        markerId: MarkerId('trip_${trip.tripId}'),
        position: animatedPosition,
        icon: _iconCache[cacheKey] ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        anchor: const Offset(0.5, 0.5),
        consumeTapEvents: true,
        onTap: () => _showTripDetailsDialog(trip),
        rotation: trip.currentHeading ?? 0,
        flat: true,
        infoWindow: InfoWindow(
          title: trip.lineCode + ' — ' + trip.lineName,
          snippet: trip.nextStopName != null
              ? 'Sonraki: ${trip.nextStopName}'
                  '${trip.etaMinutes != null ? ' (${trip.etaMinutes} dk)' : ''}'
              : 'Yolda',
        ),
      ));
    }
    setState(() => _markers = markers);
  }

  /// Daire içinde araç ikonu çizip bir marker bitmap'i üretir.
  Future<BitmapDescriptor> _createVehicleBitmap(IconData icon, Color color) async {
    const double size = 64;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2 - 4,
        Paint()..color = color);
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2 - 4,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );

    final textPainter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size * 0.55,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
        ),
      )
      ..layout();
    textPainter.paint(
      canvas,
      Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  /// Hat başına yol-takip eden (cadde bazlı) rotayı yükler (sadece bir kez)
  Future<void> _loadRoadRoutes() async {
    final linesToFetch = <SehiriciLine>[];

    // Henüz cache'de olmayan hatları bul
    for (final line in widget.lines) {
      if (line.stops.length < 2) continue;
      if (!_roadRouteCache.containsKey(line.id) && !_roadRoutesFetching.contains(line.id)) {
        linesToFetch.add(line);
        _roadRoutesFetching.add(line.id);
      }
    }

    if (linesToFetch.isEmpty) return;

    // Rotalara paralel erişim (max 3 eşzamanlı)
    for (var i = 0; i < linesToFetch.length; i += 3) {
      final batch = linesToFetch.sublist(i, math.min(i + 3, linesToFetch.length));
      final results = await Future.wait(
        batch.map((line) => _lineService.getRoadRoute(line)),
        eagerError: false,
      );

      if (!mounted) return;

      for (var j = 0; j < batch.length; j++) {
        final line = batch[j];
        final points = results[j];

        if (points.length < 2) continue;

        _roadRouteCache[line.id] = points;

        setState(() {
          _polylines = {
            ..._polylines.where((p) => p.polylineId.value != 'line_${line.id}'),
            Polyline(
              polylineId: PolylineId('line_${line.id}'),
              points: points.map((p) => LatLng(p[0], p[1])).toList(),
              color: line.color.withOpacity(0.7),
              width: 5,
              consumeTapEvents: true,
              onTap: () => _onLineTapped(line),
            ),
          };
        });
      }
    }

    _roadRoutesFetching.clear();
  }

  /// Kullanıcı bir hatta tıkladığında: konumunu paylaşır, canlı takibe başlar
  /// ve hattaki en yakın araca olan tahmini varış süresini gösterir.
  Future<void> _onLineTapped(SehiriciLine line) async {
    setState(() {
      _selectedLine = line;
      _selectedLineId = line.id;
    });

    if (_userPosition == null) {
      final pos = await SehiriciUserLocation.getCurrent();
      if (pos == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Konumunuz alınamadı. Lütfen konum izni verin.'),
            ),
          );
        }
        return;
      }
      if (!mounted) return;
      setState(() => _userPosition = pos);
    }

    _startUserLocationStream();
    _rebuildUserOverlay();
  }

  /// Araç marker'ına tıklanıp detaylı bilgi gösterir, ardından seçilir.
  void _showTripDetailsDialog(SehiriciActiveTrip trip) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Başlık: Hat bilgisi
              Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: trip.color,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        trip.lineCode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trip.lineName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (trip.driverName != null)
                          Text(
                            'Şoför: ${trip.driverName}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              // Detaylar
              _buildDetailRow('🚍 Araç Türü', trip.lineCode),
              _buildDetailRow('📍 Konum Durumu', _getLocationStatus(trip)),
              if (trip.currentSpeed != null && trip.currentSpeed! > 0)
                _buildDetailRow('⚡ Hız', '${trip.currentSpeed!.toStringAsFixed(0)} km/s'),
              if (trip.licensePlate != null)
                _buildDetailRow('🏷️ Plaka', trip.licensePlate!),
              if (trip.workingHoursStart != null && trip.workingHoursEnd != null)
                _buildDetailRow(
                  '⏰ Çalışma Saatleri',
                  '${trip.workingHoursStart!.format(ctx)} - ${trip.workingHoursEnd!.format(ctx)}',
                ),
              if (trip.nextStopName != null)
                _buildDetailRow('🎯 Sonraki Durak', trip.nextStopName!),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _onTripTapped(trip);
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Takip Et'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  String _getLocationStatus(SehiriciActiveTrip trip) {
    return trip.status == SehiriciTripStatus.active ? 'Yolda 🟢' : 'Mola 🟡';
  }

  /// Kullanıcı bir araç ikonuna tıkladığında: o seferi hedef olarak kilitler
  /// ve aracın kendisine hangi hızla, kaç dakikada yaklaştığını gösterir.
  Future<void> _onTripTapped(SehiriciActiveTrip trip) async {
    final line = widget.lines.firstWhere(
      (l) => l.id == trip.lineId,
      orElse: () => SehiriciLine(id: trip.lineId, code: trip.lineCode, name: trip.lineName, colorHex: trip.lineColor),
    );
    setState(() {
      _selectedLine = line;
      _selectedLineId = line.id;
      _selectedTripId = trip.tripId;
    });

    if (_userPosition == null) {
      final pos = await SehiriciUserLocation.getCurrent();
      if (pos == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Konumunuz alınamadı. Lütfen konum izni verin.'),
            ),
          );
        }
        return;
      }
      if (!mounted) return;
      setState(() => _userPosition = pos);
    }

    _startUserLocationStream();
    _rebuildUserOverlay();
  }

  void _startUserLocationStream() {
    if (_userPositionSub != null) return;
    _userPositionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      if (!mounted) return;
      _userPosition = pos;
      _rebuildUserOverlay();
    });
  }

  void _stopUserLocationStream() {
    _userPositionSub?.cancel();
    _userPositionSub = null;
  }

  void _clearSelectedLine() {
    setState(() {
      _selectedLine = null;
      _selectedLineId = null;
      _selectedTripId = null;
      _draggedPosition = null;
      _markers = _markers.where((m) => m.markerId.value != 'user_location').toSet();
      _polylines = _polylines.where((p) => p.polylineId.value != 'user_connector').toSet();
    });
    _stopUserLocationStream();
  }

  /// Seçili hattaki, kullanıcıya en yakın aktif seferi bulur.
  SehiriciActiveTrip? _nearestTripForLine(String lineId, LatLng userLatLng) {
    final trips = widget.activeTrips
        .where((t) => t.lineId == lineId && t.currentLat != null && t.currentLng != null)
        .toList();
    if (trips.isEmpty) return null;
    trips.sort((a, b) {
      final da = calculateDistance(userLatLng, LatLng(a.currentLat!, a.currentLng!));
      final db = calculateDistance(userLatLng, LatLng(b.currentLat!, b.currentLng!));
      return da.compareTo(db);
    });
    return trips.first;
  }

  /// Seçim modunu belirler: bir araç ikonuna doğrudan tıklandıysa o sefere
  /// kilitlenir, sadece hat seçiliyse kullanıcıya en yakın seferi bulur.
  SehiriciActiveTrip? _targetTripForSelection(LatLng userLatLng) {
    if (_selectedTripId != null) {
      final matches = widget.activeTrips.where((t) =>
          t.tripId == _selectedTripId && t.currentLat != null && t.currentLng != null);
      if (matches.isEmpty) return null;
      return matches.first;
    }
    if (_selectedLineId != null) return _nearestTripForLine(_selectedLineId!, userLatLng);
    return null;
  }

  /// Seçili sefer/hat için kullanıcıya olan mesafe, hız ve ETA bilgisini döndürür.
  /// Sürüklenen konum varsa onu kullanır, aksi halde gerçek konumu kullanır.
  ({SehiriciActiveTrip trip, int distanceMeters, int etaMinutes, double? speedKmh})?
      _selectedLineEta() {
    if (_userPosition == null || (_selectedLineId == null && _selectedTripId == null)) {
      return null;
    }
    // Sürüklenen konum varsa onu, yoksa gerçek konumu kullan
    final userLatLng = _draggedPosition ?? LatLng(_userPosition!.latitude, _userPosition!.longitude);
    final trip = _targetTripForSelection(userLatLng);
    if (trip == null) return null;
    final dist = calculateDistance(
      userLatLng,
      LatLng(trip.currentLat!, trip.currentLng!),
    ).round();
    final speed = trip.currentSpeed;
    final eta = (speed != null && speed > 1)
        ? calculateETA(dist, speedKmh: speed)
        : calculateETA(dist);
    return (trip: trip, distanceMeters: dist, etaMinutes: eta, speedKmh: speed);
  }

  /// Kullanıcı konum marker'ını ve seçili hattaki en yakın araca giden
  /// bağlantı çizgisini günceller. Marker sürüklenebilirdir.
  void _rebuildUserOverlay() {
    if (_userPosition == null || !mounted) return;
    final userLatLng = _draggedPosition ?? LatLng(_userPosition!.latitude, _userPosition!.longitude);

    final isDraggable = _selectedLineId != null || _selectedTripId != null;

    final markers = {
      ..._markers.where((m) => m.markerId.value != 'user_location'),
      Marker(
        markerId: const MarkerId('user_location'),
        position: userLatLng,
        icon: _userLocationIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        anchor: const Offset(0.5, 0.5),
        zIndex: 2,
        draggable: isDraggable,
        onDragStart: (initialPos) {},
        onDrag: (LatLng pos) {
          if (mounted) {
            setState(() => _draggedPosition = pos);
          }
        },
        onDragEnd: (LatLng newPos) {
          if (mounted) {
            setState(() => _draggedPosition = newPos);
          }
        },
        consumeTapEvents: !isDraggable,
        infoWindow: InfoWindow(
          title: isDraggable ? 'Konumum (sürükleyebilirsiniz)' : 'Konumum',
        ),
      ),
    };

    var polylines = _polylines.where((p) => p.polylineId.value != 'user_connector').toSet();
    if (_selectedLineId != null || _selectedTripId != null) {
      final trip = _targetTripForSelection(userLatLng);
      if (trip != null) {
        polylines = {
          ...polylines,
          Polyline(
            polylineId: const PolylineId('user_connector'),
            points: [userLatLng, LatLng(trip.currentLat!, trip.currentLng!)],
            color: Colors.green,
            width: 3,
            patterns: [PatternItem.dash(12), PatternItem.gap(8)],
            consumeTapEvents: false,
          ),
        };
      }
    }

    setState(() {
      _markers = markers;
      _polylines = polylines;
    });

    _loadUserLocationIcon();
  }

  Future<void> _loadUserLocationIcon() async {
    if (_userLocationIcon != null) return;
    _userLocationIcon = await _createUserLocationBitmap();
    if (mounted && _markers.any((m) => m.markerId.value == 'user_location')) {
      setState(() {
        _markers = _markers.map((m) {
          if (m.markerId.value == 'user_location') {
            return m.copyWith(iconParam: _userLocationIcon);
          }
          return m;
        }).toSet();
      });
    }
  }

  Future<BitmapDescriptor> _createUserLocationBitmap() async {
    const double size = 56;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2 - 2,
        Paint()..color = Colors.blue.withOpacity(0.25));
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 4,
        Paint()..color = Colors.blueAccent);
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 4,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  Future<void> _fitBounds() async {
    if (_mapController == null) return;
    if (_markers.isEmpty) {
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(widget.center.centerLat, widget.center.centerLng),
            zoom: widget.zoomLevel.toDouble(),
            tilt: widget.tiltAngle,
          ),
        ),
      );
      return;
    }
    try {
      final bounds = _computeBounds();
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: bounds == null 
                ? LatLng(widget.center.centerLat, widget.center.centerLng) 
                : LatLng(
                    (bounds.northeast.latitude + bounds.southwest.latitude) / 2,
                    (bounds.northeast.longitude + bounds.southwest.longitude) / 2,
                  ),
            zoom: widget.zoomLevel.toDouble(),
            tilt: widget.tiltAngle,
          ),
        ),
      );
      _initialFit = false;
    } catch (_) {}
  }

  LatLngBounds? _computeBounds() {
    if (_markers.isEmpty) return null;
    
    double minLat = double.infinity, maxLat = -double.infinity;
    double minLng = double.infinity, maxLng = -double.infinity;
    for (final m in _markers) {
      if (m.position.latitude < minLat) minLat = m.position.latitude;
      if (m.position.latitude > maxLat) maxLat = m.position.latitude;
      if (m.position.longitude < minLng) minLng = m.position.longitude;
      if (m.position.longitude > maxLng) maxLng = m.position.longitude;
    }
    
    if (minLat == double.infinity) return null;
    
    return LatLngBounds(
      southwest: LatLng(minLat - 0.005, minLng - 0.005),
      northeast: LatLng(maxLat + 0.005, maxLng + 0.005),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: LatLng(widget.center.centerLat, widget.center.centerLng),
                zoom: widget.zoomLevel.toDouble(),
                tilt: widget.tiltAngle,
              ),
              onMapCreated: (c) {
                _mapController = c;
                _isMapReady = true;

                // Dark mode stil uygula
                if (isDark) {
                  c.setMapStyle(_darkMapStyle);
                }

                if (_markers.isNotEmpty) {
                  Future.delayed(const Duration(milliseconds: 300), _fitBounds);
                }
              },
              markers: _markers,
              polylines: _polylines,
              circles: _circles,
              trafficEnabled: widget.showTraffic,
              zoomControlsEnabled: false,
              myLocationButtonEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
              scrollGesturesEnabled: widget.interactive,
              zoomGesturesEnabled: widget.interactive,
              rotateGesturesEnabled: widget.interactive,
              tiltGesturesEnabled: widget.interactive,
              gestureRecognizers: widget.interactive
                  ? <Factory<OneSequenceGestureRecognizer>>{
                      Factory<EagerGestureRecognizer>(
                          () => EagerGestureRecognizer()),
                    }
                  : const <Factory<OneSequenceGestureRecognizer>>{},
            ),
            if (_selectedLine != null)
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: _buildLineEtaCard(),
              ),
          ],
        ),
      ),
    );
  }

  /// Seçili hat için canlı ETA/mesafe bilgisini gösteren kart.
  Widget _buildLineEtaCard() {
    final line = _selectedLine!;
    final eta = _selectedLineEta();
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: line.color,
              child: Icon(line.vehicleType.icon, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${line.code} — ${line.name}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    eta == null
                        ? (_userPosition == null
                            ? 'Konum alınıyor...'
                            : 'Şu an yaklaşan araç bulunamadı')
                        : '${(eta.distanceMeters / 1000).toStringAsFixed(1)} km uzakta • '
                            '${eta.speedKmh != null && eta.speedKmh! > 1 ? '${eta.speedKmh!.toStringAsFixed(0)} km/sa ile' : 'tahminen'} '
                            '~${eta.etaMinutes} dk sonra'
                            '${_draggedPosition != null ? ' (sürüklü konum)' : ''}',
                    style: TextStyle(
                      color: eta == null ? Colors.grey : Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: _clearSelectedLine,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _isMapReady = false;
    
    // Timers'ı temizle
    _stopLiveUpdates();
    _stopUserLocationStream();

    // Animasyon controller'larını temizle
    for (final controller in _positionAnimControllers.values) {
      controller.dispose();
    }
    _positionAnimControllers.clear();
    _positionAnimations.clear();
    
    for (final controller in _pulseControllers.values) {
      controller.dispose();
    }
    _pulseControllers.clear();
    _pulseAnimations.clear();
    
    _mapController?.dispose();
    super.dispose();
  }
}

/// Kullanıcının mevcut konumunu hızlıca alıp merkez olarak kullanmak için.
class SehiriciUserLocation {
  static Future<Position?> getCurrent() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final r = await Geolocator.requestPermission();
        if (r == LocationPermission.denied) return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 6),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

/// İki LatLng arasında interpolasyon yapar (Linear Interpolation)
/// Progress: 0.0 = start, 1.0 = end
LatLng lerpLatLng(LatLng start, LatLng end, double progress) {
  return LatLng(
    start.latitude + (end.latitude - start.latitude) * progress,
    start.longitude + (end.longitude - start.longitude) * progress,
  );
}

/// [LatLng] operatör tabanlı aritmetiği desteklemediği için varsayılan
/// [Tween.lerp] "Cannot lerp between..." hatası fırlatır. Bu sınıf
/// [lerpLatLng] kullanarak manuel interpolasyon yapar.
class LatLngTween extends Tween<LatLng> {
  LatLngTween({required LatLng super.begin, required LatLng super.end});

  @override
  LatLng lerp(double t) => lerpLatLng(begin!, end!, t);
}

/// İki LatLng arasındaki mesafeyi metre cinsinden hesaplar
double calculateDistance(LatLng start, LatLng end) {
  const double earthRadius = 6371000; // metre
  final double dLat = _toRadians(end.latitude - start.latitude);
  final double dLng = _toRadians(end.longitude - start.longitude);
  final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRadians(start.latitude)) *
          math.cos(_toRadians(end.latitude)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadius * c;
}

double _toRadians(double degrees) => degrees * math.pi / 180;

/// Tahmini varış süresini dakika cinsinden hesaplar
/// distance: metre cinsinden mesafe
/// speedKmh: ortalama hız (km/saat)
int calculateETA(int distanceMeters, {double speedKmh = 30.0}) {
  if (distanceMeters <= 0) return 0;
  final distanceKm = distanceMeters / 1000;
  final hours = distanceKm / speedKmh;
  return (hours * 60).round();
}

/// Dark mode harita stili
const String _darkMapStyle = '''
[
  {
    "elementType": "geometry",
    "stylers": [{"color": "#212121"}]
  },
  {
    "elementType": "labels.icon",
    "stylers": [{"visibility": "off"}]
  },
  {
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#757575"}]
  },
  {
    "elementType": "labels.text.stroke",
    "stylers": [{"color": "#212121"}]
  },
  {
    "featureType": "administrative",
    "elementType": "geometry",
    "stylers": [{"color": "#757575"}]
  },
  {
    "featureType": "administrative.country",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#9e9e9e"}]
  },
  {
    "featureType": "administrative.locality",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#bdbdbd"}]
  },
  {
    "featureType": "poi",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#757575"}]
  },
  {
    "featureType": "poi.park",
    "elementType": "geometry",
    "stylers": [{"color": "#181818"}]
  },
  {
    "featureType": "poi.park",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#616161"}]
  },
  {
    "featureType": "poi.park",
    "elementType": "labels.text.stroke",
    "stylers": [{"color": "#1b1b1b"}]
  },
  {
    "featureType": "road",
    "elementType": "geometry.fill",
    "stylers": [{"color": "#2c2c2c"}]
  },
  {
    "featureType": "road",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#8a8a8a"}]
  },
  {
    "featureType": "road.arterial",
    "elementType": "geometry",
    "stylers": [{"color": "#373737"}]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry",
    "stylers": [{"color": "#3c3c3c"}]
  },
  {
    "featureType": "road.highway.controlled_access",
    "elementType": "geometry",
    "stylers": [{"color": "#4e4e4e"}]
  },
  {
    "featureType": "road.local",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#616161"}]
  },
  {
    "featureType": "transit",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#757575"}]
  },
  {
    "featureType": "water",
    "elementType": "geometry",
    "stylers": [{"color": "#000000"}]
  },
  {
    "featureType": "water",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#3d3d3d"}]
  }
]
''';
