// ignore_for_file: deprecated_member_use, prefer_interpolation_to_compose_strings

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart' show EagerGestureRecognizer, OneSequenceGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/sehirici_models.dart';
import '../services/sehirici_trip_service.dart';
import '../../core/services/courier_stream_service.dart';

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

  /// Long press callback (konum düşürme)
  final ValueChanged<LatLng>? onLongPress;

  /// Hat yol rotasını (duraklar arası çizgi / yol takip) göster/gizle.
  /// Şoför paneli, şoför henüz gerçek rota çizmediği sürece false verir;
  /// durak marker'ları yine görünür.
  final bool showRoute;

  /// Aktif kuryeleri (role='courier', konum paylaşan) haritada motor ikonuyla
  /// göster. Kuryeler sefer/hattından bağımsız, `profiles` tablosundan canlı
  /// okunur. Şoförün kendi panelinde kapatılabilir.
  final bool showCouriers;

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
    this.showTraffic = false,
    this.enableLiveUpdates = true,
    this.updateIntervalSeconds = 30,
    this.onLongPress,
    this.showRoute = true,
    this.showCouriers = true,
  });

  @override
  State<SehiriciLiveMap> createState() => _SehiriciLiveMapState();
}

class _SehiriciLiveMapState extends State<SehiriciLiveMap> with TickerProviderStateMixin {
  static final Map<String, BitmapDescriptor> _iconCache = {};

  // Animasyon durumları
  final Map<String, LatLng> _previousPositions = {};
  final Map<String, LatLng> _targetPositions = {};
  final Map<String, AnimationController> _positionAnimControllers = {};
  final Map<String, Animation<LatLng>> _positionAnimations = {};

  // Pulse animasyonu: TÜM canlı araçlar için TEK shared controller.
  // Önceden her araç ayrı bir controller + kendi setState'ini çağırıyordu
  // (N araçta saniyede ~60×N full harita rebuild'i). Artık frame başına
  // tek setState ve tek _circles yeniden kurulumu var; araç yoksa animasyon
  // durur (sıfır ek yük).
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  final Map<String, Color> _pulseColors = {}; // tripId -> pulse rengi

  // Pulse setState'ini ~20fps'de tutmak için frame sayacı. Aksi halde her
  // frame'de setState → tüm GoogleMap widget'ı yeniden çiziliyor; bu hem
  // açılışta hem etkileşimde ciddi jank üretiyordu.
  int _pulseFrame = 0;

  // Timer durumları
  Timer? _liveUpdateTimer;
  Timer? _etaUpdateTimer;

  // Mevcut trip verileri (ETA hesaplaması için)
  final Map<String, SehiriciActiveTrip> _currentTripData = {};

  // Her aktif sefer için şoförün geçtiği gerçek yol (polyline).
  // Realtime ile yeni noktalar eklenir, haritada arkasında çizilir.
  final Map<String, List<LatLng>> _tripPaths = {};
  final Set<String> _tripPathsLoading = {};

  final SehiriciTripService _tripService = SehiriciTripService();
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  Set<Circle> _circles = {}; // Pulse efektleri için
  bool _initialFit = true;
  bool _isMapReady = false;

  // Kullanıcının kendi konumu ve seçili hat için canlı takip
  Position? _userPosition;
  LatLng? _draggedPosition;
  StreamSubscription<Position>? _userPositionSub;
  SehiriciLine? _selectedLine;
  String? _selectedLineId;
  String? _selectedTripId;
  BitmapDescriptor? _userLocationIcon;

  // Cihazın konum servisi (GPS) kapalı mı? Harita açıldığında
  // kontrol edilir, banner göstermek için kullanılır.
  bool _locationServiceOff = false;

  // Kuryeler: role='courier' + konum paylaşan kullanıcılar. Sefer/hattan
  // bağımsız, CourierStreamService üzerinden canlı dinlenir. Haritada
  // motor ikonu olarak gösterilir.
  Map<String, CourierInfo> _couriers = const {};
  void Function(Map<String, CourierInfo>)? _courierListener;
  BitmapDescriptor? _courierIcon;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 2.5).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
    _pulseController.addListener(_onPulseTick);

    _initializeTripData();
    _rebuild();
    _initUserLocationOnEntry();

    // Şoför konum güncellemelerini realtime dinle; yeni nokta geldiğinde
    // o seferin polyline'ına ekle (şoförün arkasında çizilen gerçek yol).
    _tripService.watchTripPaths(
      onPoint: _onTripPathPoint,
    );

    // Live update timer başlat
    if (widget.enableLiveUpdates) {
      _startLiveUpdates();
    }

    // Kuryeleri (role='courier') canlı izle ve haritada göster.
    if (widget.showCouriers) {
      _startCourierTracking();
    }
  }

  /// Realtime: bir sefere yeni konum noktası eklendi.
  void _onTripPathPoint(String tripId, double lat, double lng) {
    final newPoint = LatLng(lat, lng);
    final list = _tripPaths.putIfAbsent(tripId, () => <LatLng>[]);
    // Aynı noktayı tekrar ekleme (GPS aynı noktayı iki kez gönderebilir)
    if (list.isNotEmpty) {
      final last = list.last;
      if ((last.latitude - lat).abs() < 0.00001 &&
          (last.longitude - lng).abs() < 0.00001) {
        return;
      }
    }
    list.add(newPoint);
    // İlgili trip için polyline'ı yeniden çiz
    final trip = widget.activeTrips.firstWhere(
      (t) => t.tripId == tripId,
      orElse: () => SehiriciActiveTrip(
        tripId: tripId,
        lineId: '',
        lineCode: '',
        lineName: '',
        lineColor: '#1976D2',
      ),
    );
    _rebuildTripPathPolyline(trip);
  }

  /// Harita açılışında konum otomatik istenmez. Banner da otomatik
  /// gösterilmez — kullanıcı "Konumuma git" butonuna, haritanın boş
  /// bir noktasına tıkladığında veya bir hatta/araca dokunduğunda
  /// [_ensureUserLocation] üzerinden konum istenir; bu sırada servis
  /// kapalıysa banner [_onMapTapped] tarafından gösterilir.
  Future<void> _initUserLocationOnEntry() async {
    // Bilinçli olarak boş: hiçbir otomatik konum/servis kontrolü yok.
  }

  /// Kullanıcı haritanın boş bir noktasına dokunduğunda çağrılır.
  /// Konum servisi kapalıysa [_locationServiceOff] banner'ı gösterir —
  /// otomatik değil, sadece kullanıcı etkileşiminden sonra.
  void _onMapTapped(LatLng _) {
    _checkLocationServiceAndShowBanner();
  }

  /// Konum servisinin açık olup olmadığını kontrol eder; kapalıysa
  /// banner gösterir. Butona basılınca veya haritaya tıklanınca tetiklenir.
  Future<void> _checkLocationServiceAndShowBanner() async {
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!mounted) return;
      if (!serviceOn && !_locationServiceOff) {
        setState(() => _locationServiceOff = true);
      }
    } catch (_) {
      // kontrol edilemedi — sessizce geç
    }
  }

  /// Kullanıcı bir aksiyonu (buton, hat/araç tıklaması) sonucu konum
  /// istediğinde çağrılır. İzin verilmişse sessizce konum alır; verilmemişse
  /// sistem diyaloğunu açar. Sonuca göre uygun SnackBar/eylem gösterir.
  /// [source] SnackBar mesajlarında aksiyonun ne olduğunu belirtir
  /// (örn. "Konumuma git", "Hattı seç").
  Future<bool> _ensureUserLocation({String source = 'konum'}) async {
    final result = await SehiriciUserLocation.requestCurrent();
    if (!mounted) return false;
    final newPos = result.position;

    switch (result.outcome) {
      case _LocationOutcome.granted:
        if (newPos != null) {
          setState(() => _userPosition = newPos);
        }
        // Konum alındıysa "konum kapalı" banner'ı kapat.
        if (_locationServiceOff) {
          setState(() => _locationServiceOff = false);
        }
        return newPos != null;
      case _LocationOutcome.denied:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Konum izni reddedildi. $source için konum gerekli.',
            ),
          ),
        );
        return false;
      case _LocationOutcome.permanentlyDenied:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Konum izni kalıcı olarak reddedildi. Ayarlardan açabilirsiniz.',
            ),
            action: SnackBarAction(
              label: 'Ayarlar',
              onPressed: () => Geolocator.openAppSettings(),
            ),
          ),
        );
        return false;
      case _LocationOutcome.serviceOff:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Cihazınızın konum servisi kapalı. Açmak ister misiniz?',
            ),
            action: SnackBarAction(
              label: 'Aç',
              onPressed: () async {
                try {
                  await Geolocator.openLocationSettings();
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Konum ayarları açılamadı: $e')),
                  );
                }
              },
            ),
            duration: const Duration(seconds: 6),
          ),
        );
        // Banner da göster (zaten açıksa dokunma)
        if (!_locationServiceOff) {
          setState(() => _locationServiceOff = true);
        }
        return false;
    }
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

  /// Bir aracı pulse kümesine ekler. Shared controller zaten çalışmıyorsa
  /// başlatır. İdempotent'tir — tekrar tekrar çağrılsa controller'ı
  /// sıfırlamaz (eski sürüm dispose edip yeniden başlatıyordu).
  void _startPulseAnimation(String tripId, Color pulseColor) {
    _pulseColors[tripId] = pulseColor;
    if (!_pulseController.isAnimating) {
      _pulseController.repeat();
    }
  }

  /// Shared pulse controller'ın her frame'inde bir kez çağrılır. Tüm
  /// pulse circle'larını tek bir setState ile yeniden kurar. Tam 60fps
  /// yerine ~20fps (3 frame'de bir) günceller — nabız efektini korurken
  /// GoogleMap rebuild yükünü ~3 kat düşürür.
  void _onPulseTick() {
    if (!mounted || !_isMapReady || _pulseColors.isEmpty) return;
    if (++_pulseFrame % 3 != 0) return;
    setState(_rebuildPulseCircles);
  }

  void _rebuildPulseCircles() {
    // Pulse olmayan circle'ları koru, pulse_* olanları yeniden kur.
    final others =
        _circles.where((c) => !c.circleId.value.startsWith('pulse_')).toSet();
    final scale = _pulseAnimation.value;
    final fade = (1 - (scale - 1) / 1.5).clamp(0.0, 1.0);
    for (final entry in _pulseColors.entries) {
      final pos = _targetPositions[entry.key];
      if (pos == null) continue;
      others.add(Circle(
        circleId: CircleId('pulse_${entry.key}'),
        center: pos,
        radius: 25 * scale,
        fillColor: entry.value.withOpacity(0.3 * fade),
        strokeColor: entry.value.withOpacity(0.6 * fade),
        strokeWidth: 2,
        consumeTapEvents: false,
      ));
    }
    _circles = others;
  }

  /// Bir aracı pulse kümesinden çıkarır. Küme boşalırsa controller'ı durdurur
  /// (idle → ek yük yok).
  void _stopPulseAnimation(String tripId) {
    _pulseColors.remove(tripId);
    _circles = _circles.where((c) => c.circleId.value != 'pulse_$tripId').toSet();
    if (_pulseColors.isEmpty && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }
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

    // Kurye gösterimi değişikliği: açılışta kapalıysa abonelik başlamamıştır;
    // runtime'da açılırsa başlat, kapanırsa aboneliği durdur ve marker'ları kaldır.
    if (old.showCouriers != widget.showCouriers) {
      if (widget.showCouriers && _courierListener == null) {
        _startCourierTracking();
      } else if (!widget.showCouriers && _courierListener != null) {
        final l = _courierListener!;
        CourierStreamService().unsubscribe(l);
        _courierListener = null;
        _couriers = const {};
        setState(() {
          _markers = _markers
              .where((m) => !m.markerId.value.startsWith('courier_'))
              .toSet();
        });
      }
    }

    // Sadece hat değiştiğinde _rebuild çağır (trip değişiklikleri _handleTripChanges tarafından işlenecek)
    if (old.lines != widget.lines) {
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
      // Şoförün geçtiği yol polyline'ını da temizle
      _tripPaths.remove(tripId);
      _polylines = _polylines
          .where((p) => p.polylineId.value != 'trip_path_$tripId')
          .toSet();
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

    // 1) Durak marker'ları. Hat polylines'ı (kuş uçuşu düz çizgi) artık
    // çizilmiyor — sadece şoförün geçtiği gerçek yol polyline'ı görünür.
    for (final line in widget.lines) {
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

    // 3) Kurye marker'ları (role='courier', konum paylaşan). Seferden bağımsız
    // realtime akışla güncellenir; _rebuild çağrılsa da cache'ten tekrar çizilir.
    markers.addAll(_courierMarkers());

    _markers = markers;
    _polylines = polylines;

    if (_mapController != null && _initialFit) {
      _fitBounds();
    }

    // Ağır async işleri (özel ikon üretimi + sefer yolu yükleme) ilk frame'i
    // bloklamadan, ilk çizim sonrasına bırakıyoruz. Böylece harita açılışta
    // anında varsayılan renk marker'larıyla çizilir; özel ikonlar ve yol
    // polyline'ları arka planda gelir. Çoklu aktif seferde her biri için
    // ayrı atılan getTripPath RPC'leri de açılışla yarışmaz.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadVehicleIcons();
      _loadStopIcons();
      _loadInitialTripPaths();
    });
  }

  /// Aktif seferlerin şoförünün geçtiği yol noktalarını (konum geçmişi)
  /// sunucudan yükler. Realtime zaten initState'te başlatıldı, bu sadece
  /// ilk açılışta / sayfa yenilemede eksik noktaları çeker.
  Future<void> _loadInitialTripPaths() async {
    for (final trip in widget.activeTrips) {
      if (_tripPaths.containsKey(trip.tripId)) continue;
      if (_tripPathsLoading.contains(trip.tripId)) continue;
      _tripPathsLoading.add(trip.tripId);
      try {
        final path = await _tripService.getTripPath(trip.tripId);
        if (!mounted) return;
        _tripPaths[trip.tripId] =
            path.map((p) => LatLng(p.lat, p.lng)).toList();
        _rebuildTripPathPolyline(trip);
      } catch (e) {
        debugPrint('_loadInitialTripPaths hata: $e');
      } finally {
        _tripPathsLoading.remove(trip.tripId);
      }
    }
  }

  /// Belirli bir seferin polyline'ını haritaya ekler (güncel nokta listesiyle).
  void _rebuildTripPathPolyline(SehiriciActiveTrip trip) {
    final line = widget.lines.firstWhere(
      (l) => l.id == trip.lineId,
      orElse: () => SehiriciLine(
        id: trip.lineId,
        code: trip.lineCode,
        name: trip.lineName,
        colorHex: trip.lineColor,
      ),
    );
    final points = _tripPaths[trip.tripId] ?? const <LatLng>[];
    if (points.length < 2) return;
    setState(() {
      _polylines = {
        ..._polylines
            .where((p) => p.polylineId.value != 'trip_path_${trip.tripId}'),
        Polyline(
          polylineId: PolylineId('trip_path_${trip.tripId}'),
          points: points,
          color: line.color,
          width: 4,
          consumeTapEvents: false,
        ),
      };
    });
  }

  /// Durak marker'ları için küçük, tıklanabilir bir durak ikonu üretir
  Future<void> _loadStopIcons() async {
    final needed = <String>{'stop_default', 'stop_sel'};
    needed.removeWhere(_iconCache.containsKey);
    // Cache sıcakken _rebuild() zaten durak marker'larını cached ikonla kurdu;
    // burada tekrar setState etmek (özellikle initState sırasında) gereksiz.
    if (needed.isEmpty) return;
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

  /// Modern "durak" ikonu: yumuşak gölgeli, kalın beyaz halkalı renkli nokta.
  Future<BitmapDescriptor> _createStopBitmap(Color color) async {
    const double size = 56;
    const center = Offset(size / 2, size / 2);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    // Yumuşak gölge
    canvas.drawCircle(
      center + const Offset(0, 3),
      size / 2 - 6,
      Paint()
        ..color = Colors.black.withOpacity(0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    // Beyaz dış halka (kart zemin)
    canvas.drawCircle(center, size / 2 - 4, Paint()..color = Colors.white);
    // Renkli iç dolgu
    canvas.drawCircle(center, size / 2 - 8, Paint()..color = color);

    const icon = Icons.location_on;
    final textPainter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size * 0.34,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
        ),
      )
      ..layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
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
    if (needed.isEmpty) return;
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

  // ─────────────────────────────────────────────
  // Kuryeler (role='courier') — seferden bağımsız canlı konum
  // ─────────────────────────────────────────────

  /// Kuryeleri CourierStreamService üzerinden dinler. İlk abone geldiğinde
  /// servis `profiles` tablosunu realtime dinlemeye başlar; biz sadece
  /// snapshot'a subscribe oluruz. Kurye geldiğinde harita onu da kapsayacak
  /// şekilde bounds fit yaparız (ilk harita açılışında kurye henüz yoksa
  /// fit bounds sadece durakları kapsar; sonradan kurye gelince haritayı
  /// kaydırmak rahatsız edici olurdu — bu yüzden fit sadece harita ilk
  /// hazır olduğunda tetiklenir, sonradan gelen kuryeler marker olarak
  /// eklenir ama kamera kaydırılmaz).
  Future<void> _startCourierTracking() async {
    _ensureCourierIcon();
    void onChange(Map<String, CourierInfo> snap) {
      if (!mounted) return;
      _couriers = snap;
      _rebuildCourierMarkersOnly();
    }
    _courierListener = onChange;
    CourierStreamService().subscribe(onChange);
  }

  /// Kurye marker'larını cache'lenen `_couriers`'den üretir.
  Set<Marker> _courierMarkers() {
    if (!widget.showCouriers || _couriers.isEmpty) return const {};
    final out = <Marker>{};
    for (final c in _couriers.values) {
      out.add(Marker(
        markerId: MarkerId('courier_${c.id}'),
        position: LatLng(c.lat, c.lng),
        icon: _courierIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        anchor: const Offset(0.5, 0.5),
        zIndex: 1.5,
        consumeTapEvents: true,
        onTap: () => _showCourierSheet(c),
        infoWindow: InfoWindow(
          title: c.name,
          snippet: '🏍️ Kurye',
        ),
      ));
    }
    return out;
  }

  /// Sadece kurye marker'larını yeniden kurar; durak/araç/kullanıcı
  /// marker'larını korur. Realtime güncelleme ve ikon yüklenmesi bittiğinde
  /// çağrılır.
  void _rebuildCourierMarkersOnly() {
    final markers = {
      ..._markers.where((m) => !m.markerId.value.startsWith('courier_')),
    };
    markers.addAll(_courierMarkers());
    setState(() => _markers = markers);
  }

  Future<void> _ensureCourierIcon() async {
    if (_courierIcon != null) return;
    _courierIcon = await _createCourierBitmap();
    if (mounted && _couriers.isNotEmpty) _rebuildCourierMarkersOnly();
  }

  /// Kurye marker ikonu: araç diskleriyle uyumlu, turuncu zeminli disk +
  /// ortada motor simgesi. Araç marker'larından rengiyle ayrışır.
  Future<BitmapDescriptor> _createCourierBitmap() async {
    const double size = 72;
    const center = Offset(size / 2, size / 2);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    canvas.drawCircle(
      center + const Offset(0, 4),
      size / 2 - 6,
      Paint()
        ..color = Colors.black.withOpacity(0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(center, size / 2 - 4, Paint()..color = Colors.white);
    // Kurye rengi: turuncu — araçlardan (hat rengi) ayrışır.
    canvas.drawCircle(center, size / 2 - 9, Paint()..color = const Color(0xFFFB8C00));

    const icon = Icons.two_wheeler;
    final textPainter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size * 0.42,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
        ),
      )
      ..layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
    }
    return BitmapDescriptor.bytes(bytes.buffer.asUint8List());
  }

  /// Kurye marker'ına dokunulduğunda bilgi kartı gösterir. Kullanıcı konumu
  /// biliniyorsa kuryeye olan mesafe ve tahmini varış da hesaplanır.
  void _showCourierSheet(CourierInfo courier) {
    final hasUserPos = _userPosition != null;
    int? distMeters;
    int? etaMinutes;
    if (hasUserPos) {
      final userLatLng =
          _draggedPosition ?? LatLng(_userPosition!.latitude, _userPosition!.longitude);
      distMeters = calculateDistance(
        userLatLng,
        LatLng(courier.lat, courier.lng),
      ).round();
      // Kurye ortalaması kentsel motor: ~25 km/sa.
      etaMinutes = calculateETA(distMeters, speedKmh: 25.0);
    }
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
                  backgroundColor: const Color(0xFFFB8C00),
                  child: const Icon(Icons.two_wheeler, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(courier.name,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const Text('Kurye · Konum paylaşılıyor'),
                    ],
                  ),
                ),
              ],
            ),
            if (courier.updatedAt != null) ...[
              const SizedBox(height: 12),
              Text(
                'Son güncelleme: ${_formatTimeAgo(courier.updatedAt!)}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
            if (distMeters != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.place, size: 18, color: Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${(distMeters / 1000).toStringAsFixed(distMeters < 1000 ? 2 : 1)} km uzakta'
                      '${etaMinutes! > 0 ? ' · ~$etaMinutes dk' : ''}',
                      style: TextStyle(color: Colors.green.shade700),
                    ),
                  ),
                ],
              ),
            ] else if (!hasUserPos) ...[
              const SizedBox(height: 12),
              const Text(
                'Mesafe için konumunuz gerekli. "Konumuma git" butonunu kullanın.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Verilen zamanı "x dk önce / x sa önce" biçiminde döndürür.
  String _formatTimeAgo(DateTime time) {
    // Realtime'den gelen damga genelde UTC'dir; yerel saate çevir.
    final dt = time.toLocal();
    // Date.now()/DateTime.now() yasak değil — bu normal uygulama akışı,
    // workflow ortamı değil. Güvenli kullanım.
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'az önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} sa önce';
    return '${diff.inDays} gün önce';
  }
  /// ortada araç simgesi. Çevresindeki pulse halkasıyla canlı görünür.
  Future<BitmapDescriptor> _createVehicleBitmap(IconData icon, Color color) async {
    const double size = 72;
    const center = Offset(size / 2, size / 2);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    // Yumuşak gölge
    canvas.drawCircle(
      center + const Offset(0, 4),
      size / 2 - 6,
      Paint()
        ..color = Colors.black.withOpacity(0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    // Beyaz kart zemin
    canvas.drawCircle(center, size / 2 - 4, Paint()..color = Colors.white);
    // Renkli disk
    canvas.drawCircle(center, size / 2 - 9, Paint()..color = color);

    final textPainter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size * 0.42,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
        ),
      )
      ..layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  /// Eski: Hat başına yol-takip eden (cadde bazlı) rotayı OSRM'den yükler.
  /// OSRM önbelleği kaldırıldığı için artık çağrılmıyor; hat polylines'ı
  /// _rebuild içinde sadece durakları düz çizgiyle bağlar. Şoförün geçtiği
  /// asıl yol ayrıca _rebuildTripPathPolyline ile realtime çizilir.
  Future<void> _loadRoadRoutes() async {
    // no-op
  }

  /// Kullanıcı bir hatta tıkladığında: konumunu paylaşır, canlı takibe başlar
  /// ve hattaki en yakın araca olan tahmini varış süresini gösterir.
  Future<void> _onLineTapped(SehiriciLine line) async {
    setState(() {
      _selectedLine = line;
      _selectedLineId = line.id;
    });

    if (_userPosition == null) {
      final ok = await _ensureUserLocation(source: 'Hattı seçmek');
      if (!ok) return;
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
      final ok = await _ensureUserLocation(source: 'Aracı takip etmek');
      if (!ok) return;
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
    try {
      final bounds = _markers.isEmpty ? null : _computeBounds();
      final target = bounds == null
          ? LatLng(widget.center.centerLat, widget.center.centerLng)
          : LatLng(
              (bounds.northeast.latitude + bounds.southwest.latitude) / 2,
              (bounds.northeast.longitude + bounds.southwest.longitude) / 2,
            );
      // Açılışta kamera animasyonsuz anında o konuma otursun (ağır açılışı
      // engeller). Sonraki odaklamalar (_recenterToUser vb.) animateCamera
      // kullanmaya devam eder.
      await _mapController!.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: target,
            zoom: widget.zoomLevel.toDouble(),
            tilt: widget.tiltAngle,
          ),
        ),
      );
    } catch (_) {}
    _initialFit = false;
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

                // Modern sade harita stili ( açık/koyu tema farkı )
                c.setMapStyle(isDark ? _darkMapStyle : _lightMapStyle);

                // İlk odaklamayı anında, animasyonsuz yap (açılışı hızlandırır;
                // _fitBounds moveCamera kullanır). 300ms gecikme kaldırıldı.
                if (_markers.isNotEmpty && _initialFit) {
                  _fitBounds();
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
              onLongPress: (LatLng pos) {
                setState(() => _draggedPosition = pos);
                widget.onLongPress?.call(pos);
              },
              // Boş haritaya tıklanınca: konum servisi kapalıysa banner göster.
              onTap: _onMapTapped,
            ),
            // Konum servisi kapalı uyarı banner'ı (harita üstünde, tıklanabilir)
            if (_locationServiceOff)
              Positioned(
                top: 10,
                left: 10,
                right: 10,
                child: _buildLocationServiceOffBanner(isDark),
              ),
            // Yüzen modern kontroller (sadece etkileşimli görünümlerde)
            if (widget.interactive)
              Positioned(
                right: 10,
                bottom: _selectedLine != null ? 76 : 12,
                child: _buildMapControls(isDark),
              ),
            if (_selectedLine != null)
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: _buildLineEtaCard(isDark),
              ),
          ],
        ),
      ),
    );
  }

  /// Yüzen cam-tarzı harita kontrolleri: konumuma git + zoom +/-.
  Widget _buildMapControls(bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _mapControlButton(
          isDark: isDark,
          icon: Icons.my_location,
          onTap: _recenterToUser,
        ),
        const SizedBox(height: 8),
        _mapControlButton(
          isDark: isDark,
          icon: Icons.add,
          onTap: () => _mapController?.animateCamera(CameraUpdate.zoomIn()),
        ),
        const SizedBox(height: 8),
        _mapControlButton(
          isDark: isDark,
          icon: Icons.remove,
          onTap: () => _mapController?.animateCamera(CameraUpdate.zoomOut()),
        ),
      ],
    );
  }

  /// Cihazın konum servisi kapalıyken harita üstünde gösterilen uyarı
  /// banner'ı. "Aç" butonuyla kullanıcıyı doğrudan cihazın konum
  /// ayarlarına gönderebilir; kapat (×) butonu sadece banner'ı gizler
  /// (servis durumu değişmediği için butona tekrar basınca geri gelir).
  Widget _buildLocationServiceOffBanner(bool isDark) {
    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(isDark ? 0.85 : 0.92),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.location_off,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Konum servisi kapalı',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withOpacity(0.22),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    try {
                      await Geolocator.openLocationSettings();
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Konum ayarları açılamadı: $e')),
                      );
                    }
                  },
                  child: const Text(
                    'Aç',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 18),
                  onPressed: () =>
                      setState(() => _locationServiceOff = false),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: 'Bildirimi kapat',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mapControlButton({
    required bool isDark,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: (isDark ? Colors.black : Colors.white).withOpacity(0.55),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
                ),
              ),
              child: Icon(
                icon,
                size: 20,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _recenterToUser() async {
    if (_mapController == null) return;

    // Kullanıcı konum butonuna BASMIŞ olabilir — daha önce konum
    // alınmadıysa (örn. harita ilk kez açıldığında) burada izin istenir.
    // Bu noktada sistem diyaloğu açılır.
    if (_userPosition == null) {
      final ok = await _ensureUserLocation(source: 'Konumuma git');
      if (!ok) return;
      if (_userPosition == null) return;
    }

    final pos = _userPosition!;
    await _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 16),
    );
  }

  /// Seçili hat için canlı ETA/mesafe bilgisini gösteren, cam efektli
  /// modern kart. "CANLI" rozetiyle canlı takip vurgulanır.
  Widget _buildLineEtaCard(bool isDark) {
    final line = _selectedLine!;
    final eta = _selectedLineEta();
    final hasEta = eta != null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: (isDark ? Colors.black : Colors.white).withOpacity(0.7),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Canlı rozet: araç ikonu + nabız halkası
                SizedBox(
                  width: 34,
                  height: 34,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: line.color.withOpacity(0.18),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: line.color,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(line.vehicleType.icon,
                            color: Colors.white, size: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // CANLI pill
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: hasEta
                                  ? Colors.green.withOpacity(0.16)
                                  : Colors.grey.withOpacity(0.16),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: hasEta ? Colors.green : Colors.grey,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  hasEta ? 'CANLI' : 'BEKLENİYOR',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                    color: hasEta
                                        ? Colors.green.shade700
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${line.code} — ${line.name}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        eta == null
                            ? (_userPosition == null
                                ? 'Konum alınıyor...'
                                : 'Şu an yaklaşan araç bulunamadı')
                            : '${(eta.distanceMeters / 1000).toStringAsFixed(1)} km uzakta • '
                                '${eta.speedKmh != null && eta.speedKmh! > 1 ? '${eta.speedKmh!.toStringAsFixed(0)} km/sa' : 'tahminen'} • '
                                '~${eta.etaMinutes} dk'
                                '${_draggedPosition != null ? ' · sürüklü' : ''}',
                        style: TextStyle(
                          color: hasEta ? Colors.green.shade700 : Colors.grey,
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
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _isMapReady = false;

    // Realtime kanallarını kapat
    _tripService.stopWatching();
    final l = _courierListener;
    if (l != null) {
      CourierStreamService().unsubscribe(l);
      _courierListener = null;
    }

    // Timers'ı temizle
    _stopLiveUpdates();
    _stopUserLocationStream();

    // Animasyon controller'larını temizle
    for (final controller in _positionAnimControllers.values) {
      controller.dispose();
    }
    _positionAnimControllers.clear();
    _positionAnimations.clear();

    _pulseController.dispose();

    _mapController?.dispose();
    super.dispose();
  }
}

/// Kullanıcının mevcut konumunu hızlıca alıp merkez olarak kullanmak için.
/// Konum izni AKSİYONLA (örn. "Konumuma git" butonu) tetiklenir;
/// harita açılır açılmaz otomatik sorulmaz.
class SehiriciUserLocation {
  /// Konum isteği sonucu.
  /// - [granted] + [position]: izin verildi, konum alındı.
  /// - [granted] + [position]=null: izin verildi ama konum alınamadı.
  /// - [denied]: kullanıcı bu seferlik reddetti (tekrar sorulabilir).
  /// - [permanentlyDenied]: kalıcı red — ayarlardan açılmalı.
  /// - [serviceOff]: cihazın konum servisi kapalı.
  static Future<({Position? position, _LocationOutcome outcome})> requestCurrent() async {
    try {
      // 1) Konum servisi açık mı?
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return (position: null, outcome: _LocationOutcome.serviceOff);
      }

      // 2) Mevcut izin durumunu kontrol et
      var permission = await Geolocator.checkPermission();

      // 3) Hiç sorulmamışsa veya reddedilmişse ŞİMDİ sor.
      //    Bu metot sadece kullanıcının butona basmasıyla tetiklenir;
      //    harita açılışında çağrılmaz.
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        return (position: null, outcome: _LocationOutcome.permanentlyDenied);
      }
      if (permission == LocationPermission.denied) {
        return (position: null, outcome: _LocationOutcome.denied);
      }

      // 4) İzin verildi — konumu al
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 6),
          ),
        );
        return (position: pos, outcome: _LocationOutcome.granted);
      } catch (_) {
        return (position: null, outcome: _LocationOutcome.granted);
      }
    } catch (_) {
      return (position: null, outcome: _LocationOutcome.denied);
    }
  }
}

/// `SehiriciUserLocation.requestCurrent()` sonucu.
enum _LocationOutcome {
  granted,
  denied,
  permanentlyDenied,
  serviceOff,
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

/// Modern sade açık harita stili — düşük doygunluklu, okunabilirlik ön planda.
/// Yoğun Google varsayılanını bastırır; polyline/marker renkleri öne çıkar.
const String _lightMapStyle = '''
[
  {
    "elementType": "geometry",
    "stylers": [{"color": "#f5f5f5"}]
  },
  {
    "elementType": "labels.icon",
    "stylers": [{"visibility": "off"}]
  },
  {
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#8a8a8a"}]
  },
  {
    "elementType": "labels.text.stroke",
    "stylers": [{"color": "#f5f5f5"}]
  },
  {
    "featureType": "administrative",
    "elementType": "geometry",
    "stylers": [{"color": "#e6e6e6"}]
  },
  {
    "featureType": "administrative.locality",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#7a7a7a"}]
  },
  {
    "featureType": "poi",
    "elementType": "labels",
    "stylers": [{"visibility": "simplified"}]
  },
  {
    "featureType": "poi",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#9e9e9e"}]
  },
  {
    "featureType": "poi.park",
    "elementType": "geometry",
    "stylers": [{"color": "#e8f0e4"}]
  },
  {
    "featureType": "road",
    "elementType": "geometry",
    "stylers": [{"color": "#ffffff"}]
  },
  {
    "featureType": "road.arterial",
    "elementType": "geometry",
    "stylers": [{"color": "#ededed"}]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry",
    "stylers": [{"color": "#dadada"}]
  },
  {
    "featureType": "road.highway.controlled_access",
    "elementType": "geometry",
    "stylers": [{"color": "#cfcfcf"}]
  },
  {
    "featureType": "road",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#8a8a8a"}]
  },
  {
    "featureType": "transit",
    "elementType": "labels.icon",
    "stylers": [{"visibility": "off"}]
  },
  {
    "featureType": "transit",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#9e9e9e"}]
  },
  {
    "featureType": "water",
    "elementType": "geometry",
    "stylers": [{"color": "#cfe3f0"}]
  },
  {
    "featureType": "water",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#7fa6c0"}]
  }
]
''';
