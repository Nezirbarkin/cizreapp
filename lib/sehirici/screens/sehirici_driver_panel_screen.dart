// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../models/sehirici_models.dart';
import '../providers/sehirici_provider.dart';
import '../services/sehirici_driver_service.dart';
import '../services/sehirici_auto_trip_controller.dart';
import '../services/sehirici_line_service.dart';
import '../services/sehirici_road_snap_service.dart';
import '../services/sehirici_trip_service.dart';
import '../services/sehirici_location_tracker.dart';
import '../utils/sehirici_route_geometry.dart';
import '../utils/sehirici_time_utils.dart';
import '../widgets/sehirici_live_map.dart';

/// Şoför paneli: hat seçimi, sefer başlat/bitir, canlı konum.
class SehiriciDriverPanelScreen extends StatefulWidget {
  const SehiriciDriverPanelScreen({super.key});

  @override
  State<SehiriciDriverPanelScreen> createState() =>
      _SehiriciDriverPanelScreenState();
}

class _SehiriciDriverPanelScreenState extends State<SehiriciDriverPanelScreen>
    with WidgetsBindingObserver {
  final SehiriciDriverService _driverService = SehiriciDriverService();
  final SehiriciTripService _tripService = SehiriciTripService();
  final SehiriciLineService _lineService = SehiriciLineService();
  final SehiriciRoadSnapService _roadSnapService = SehiriciRoadSnapService();
  final SehiriciLocationTracker _tracker = SehiriciLocationTracker();

  Map<String, dynamic>? _driverProfile;
  SehiriciActiveTrip? _activeTrip;
  bool _loading = true;
  bool _busy = false;

  // Timer ve çalışma saatleri
  Timer? _tripTimer;
  Timer? _autoRouteTimer;
  bool _autoRouteBusy = false;
  bool _autoRouteSavedOnce = false;

  /// Otomatik rotanın en son kaydedildiği andaki iz uzunluğu (metre).
  double _autoRouteLastSavedMeters = 0;

  /// Otomatik rotanın yeniden hesaplanması için izin bu kadar uzaması gerekir.
  static const double _kAutoRouteGrowthMeters = 250;
  Duration _tripDuration = Duration.zero;
  LatLng? _droppedLocation;

  /// Tracker'ın DB'ye yazdığı konumlar. Panel kendi seferinin realtime
  /// kanalını dinlemediği için, bu olmadan haritadaki kendi aracı `_load()`
  /// anındaki konumda donuk kalıyordu.
  StreamSubscription<Position>? _trackerSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _trackerSub = _tracker.positions.listen(_onOwnPosition);
    _load();
  }

  /// Kendi aracımızın haritadaki marker'ını canlı tut.
  void _onOwnPosition(Position pos) {
    if (!mounted) return;
    final trip = _activeTrip;
    if (trip == null) return;
    // Molada tracker (otomatik sefer modunda) çalışmaya devam eder ama sunucu
    // konumu yazmaz. Panel "Konum paylaşımı duraklatıldı" derken marker'ın
    // kaymaya devam etmesi yanıltıcı olur — kullanıcıya gösterileni sunucudaki
    // gerçekle hizala.
    if (trip.status != SehiriciTripStatus.active) return;
    setState(() {
      _activeTrip = trip.copyWithLocation(
        lat: pos.latitude,
        lng: pos.longitude,
        heading: pos.heading,
        speed: pos.speed,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _trackerSub?.cancel();
    _tripTimer?.cancel();
    _workingHoursTimer?.cancel();
    _autoRouteTimer?.cancel();
    // Controller'ı durdurmuyoruz: tıpkı tracker gibi, panel dispose olsa bile
    // aktif sefer/otomasyon DB ile senkron kalmalı. Sadece UI callback'lerini
    // koparalım ki disposed widget'a setState yapılmasın.
    final controller = SehiriciAutoTripController.instance;
    controller.onTripAutoStarted = null;
    controller.onTripAutoEnded = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        if (_autoEnabled) {
          // Controller'ı yeniden senkronla: driving fazında tracker'ı,
          // watching fazında izleme akışını yeniden başlatır.
          _applyAutomation();
          return;
        }
        if (_activeTrip != null && !_tracker.isTracking) {
          _tracker.start(
            tripId: _activeTrip!.tripId,
            tripService: _tripService,
            interval: const Duration(seconds: 10),
          );
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // Arka planda foreground service (Android) / background mode (iOS)
        // akışı sürdürür. Ön plana dönüşte resume dalı yeniden başlatır.
        break;
      default:
        break;
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _driverProfile = await _driverService.getMyDriverProfile();
      if (_driverProfile != null) {
        final driverId = _driverProfile!['id'] as String;
        final active = await _tripService.getDriverActiveTrip(driverId);
        if (active != null) {
          _activeTrip = SehiriciActiveTrip(
            tripId: active['id'] as String,
            lineId: active['line_id'] as String,
            lineCode: '',
            lineName:
                (_driverProfile!['sehirici_lines'] as Map?)?['name'] ?? '',
            lineColor:
                (_driverProfile!['sehirici_lines'] as Map?)?['color_hex'] ??
                '#1976D2',
            currentLat: (active['current_lat'] as num?)?.toDouble(),
            currentLng: (active['current_lng'] as num?)?.toDouble(),
            status: SehiriciTripStatus.fromString(active['status'] as String?),
          );
          // BUG FIX: Eski sefer yüklenirken de çalışma saatleri set edilmeli.
          // Önceki kodda sadece _startTrip'te atanıyordu, uygulama yeniden
          // açıldığında otomatik mola çalışmıyordu.
          final whStart = _parseHhmmFromProfile('working_hours_start');
          final whEnd = _parseHhmmFromProfile('working_hours_end');
          _activeTrip = SehiriciActiveTrip(
            tripId: _activeTrip!.tripId,
            lineId: _activeTrip!.lineId,
            lineCode: _activeTrip!.lineCode,
            lineName: _activeTrip!.lineName,
            lineColor: _activeTrip!.lineColor,
            workingHoursStart: whStart,
            workingHoursEnd: whEnd,
            currentLat: _activeTrip!.currentLat,
            currentLng: _activeTrip!.currentLng,
            status: _activeTrip!.status,
          );
          _startTripTimerFromDb(active);
          _startWorkingHoursCheck();
        }
      }
    } catch (e) {
      _showError('Profil yüklenemedi: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        // Auto açıkse controller'ı senkronla (aktif sefer varsa driving,
        // yoksa watching). Auto kapalıysa durdurur.
        _applyAutomation();
      }
    }
  }

  void _startTripTimerFromDb(Map<String, dynamic> active) {
    _tripTimer?.cancel();
    _tripDuration = Duration.zero;
    final startedAt = active['started_at'] as String?;
    if (startedAt == null) return;
    final start = DateTime.tryParse(startedAt);
    if (start == null) return;
    _tripDuration = DateTime.now().difference(start);
    _tripTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _tripDuration = DateTime.now().difference(start);
        });
      }
    });
  }

  /// Çalışma saatleri string'ini TimeOfDay'a çevirir (eski sefer için).
  TimeOfDay? _parseHhmmFromProfile(String key) {
    final value = _driverProfile?[key] as String?;
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return TimeOfDay(hour: h, minute: m);
  }

  /// "Otomatik Sefer" ayarı açık mı?
  bool get _autoEnabled =>
      (_driverProfile?['auto_trip_enabled'] as bool?) ?? false;

  /// Şoförün atanmış hattını (stops + varsa polyline ile) çözer. Önce
  /// provider'daki tam satırı dener; yoksa durakları ayrı çeker.
  Future<SehiriciLine?> _resolveDriverLine() async {
    final profile = _driverProfile;
    if (profile == null) return null;
    final lineId = profile['assigned_line_id'] as String?;
    if (lineId == null) return null;
    try {
      final provider = context.read<SehiriciProvider>();
      return provider.lines.firstWhere((l) => l.id == lineId);
    } catch (_) {}
    try {
      final nested = profile['sehirici_lines'] as Map?;
      final stops = await _lineService.getLineStops(lineId);
      return SehiriciLine(
        id: lineId,
        code: nested?['code'] as String? ?? '',
        name: nested?['name'] as String? ?? '',
        colorHex: nested?['color_hex'] as String? ?? '#1976D2',
        vehicleType: SehiriciVehicleType.fromString(
            nested?['vehicle_type'] as String?),
        stops: stops,
      );
    } catch (e) {
      debugPrint('_resolveDriverLine hata: $e');
      return null;
    }
  }

  /// Otomatik sefer açıksa [SehiriciAutoTripController]'ı (yeni) konfigürasyonla
  /// senkronlar; kapalıysa durdurur. Auto açıkken sefer yaşam döngüsü
  /// (başlat/bitir + tracker) controller'a aittir — panel ile çakışmaz.
  Future<void> _applyAutomation() async {
    final profile = _driverProfile;
    if (profile == null) return;
    final controller = SehiriciAutoTripController.instance;
    if (!_autoEnabled) {
      controller.onTripAutoStarted = null;
      controller.onTripAutoEnded = null;
      await controller.stop();
      return;
    }
    final line = await _resolveDriverLine();
    if (line == null) return;
    controller.onTripAutoStarted = () {
      if (mounted) _load();
    };
    controller.onTripAutoEnded = (_) {
      if (mounted) _load();
    };
    await controller.start(
      driverId: profile['id'] as String,
      line: line,
      workStart: _parseHhmmFromProfile('working_hours_start'),
      workEnd: _parseHhmmFromProfile('working_hours_end'),
    );
  }

  Future<void> _startTrip(SehiriciLine line) async {
    if (_busy) return;
    if (_driverProfile == null) return;
    setState(() => _busy = true);
    try {
      // Konum izni kontrolü
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showError('Konum izni verin.');
          return;
        }
      }

      // Soğuk GPS'te zaman sınırsız getCurrentPosition "Başlat" butonunu
      // dakikalarca askıda bırakabiliyordu. Zaman sınırı koy, olmazsa son
      // bilinen konumla başla (tracker ilk taze fix'i zaten hemen yazacak).
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) {
        _showError('Konum alınamadı. GPS açık mı kontrol edin.');
        return;
      }
      final tripId = await _tripService.startTrip(
        driverId: _driverProfile!['id'] as String,
        lineId: line.id,
        lat: pos.latitude,
        lng: pos.longitude,
      );
      if (tripId == null) {
        _showError('Sefer başlatılamadı');
        return;
      }
      _activeTrip = SehiriciActiveTrip(
        tripId: tripId,
        lineId: line.id,
        lineCode: line.code,
        lineName: line.name,
        lineColor: line.colorHex,
        driverName: _driverProfile?['name'] as String?,
        licensePlate: _driverProfile?['license_plate'] as String?,
        workingHoursStart: _parseHhmmFromProfile('working_hours_start'),
        workingHoursEnd: _parseHhmmFromProfile('working_hours_end'),
        currentLat: pos.latitude,
        currentLng: pos.longitude,
        startedAt: DateTime.now(),
        status: SehiriciTripStatus.active,
      );
      _startTripTimer();
      if (!_autoEnabled) {
        _startWorkingHoursCheck();
      }
      _maybeStartAutoRouteWatcher(line: line, tripId: tripId);
      if (!_autoEnabled) {
        // Auto açıkken tracker'ı controller yönetir (_applyAutomation ->
        // driving). Burada elle başlatmak çift stream yaratır.
        await _tracker.start(
          tripId: tripId,
          tripService: _tripService,
          interval: const Duration(seconds: 10),
        );
      } else {
        // Manuel override: controller'ı aktif sefer üzerinden senkronla.
        unawaited(_applyAutomation());
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sefer başlatıldı. Konum paylaşılıyor.'),
            backgroundColor: Colors.green,
          ),
        );
      }
      setState(() {});
    } catch (e) {
      _showError('Hata: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// BUG FIX: yarış durumu giderildi. Önceki kodda setState içinde await
  /// olmadan iki kez state değişiyordu. Şimdi: önce setStatus async olarak
  /// tamamlanır, sonra tek atomik setState ile yeni state atanır.
  Future<void> _togglePause() async {
    if (_activeTrip == null || _busy) return;
    setState(() => _busy = true);
    try {
      final newStatus = _activeTrip!.status == SehiriciTripStatus.active
          ? SehiriciTripStatus.paused
          : SehiriciTripStatus.active;
      final ok = await _tripService.setStatus(_activeTrip!.tripId, newStatus);
      if (!ok) {
        _showError('Durum değiştirilemedi');
        return;
      }
      final old = _activeTrip!;
      setState(() {
        _activeTrip = SehiriciActiveTrip(
          tripId: old.tripId,
          lineId: old.lineId,
          lineCode: old.lineCode,
          lineName: old.lineName,
          lineColor: old.lineColor,
          driverName: old.driverName,
          licensePlate: old.licensePlate,
          workingHoursStart: old.workingHoursStart,
          workingHoursEnd: old.workingHoursEnd,
          currentLat: old.currentLat,
          currentLng: old.currentLng,
          currentHeading: old.currentHeading,
          currentSpeed: old.currentSpeed,
          startedAt: old.startedAt,
          nextStopId: old.nextStopId,
          nextStopName: old.nextStopName,
          nextStopLat: old.nextStopLat,
          nextStopLng: old.nextStopLng,
          etaMinutes: old.etaMinutes,
          status: newStatus,
        );
      });
      if (newStatus == SehiriciTripStatus.paused) {
        if (!_autoEnabled) {
          await _tracker.stop();
        }
        // Auto açıkken tracker controller'a ait; duraklatma yalnızca DB
        // status'unu değiştirir (update RPC 'active' olmayınca konum
        // yazmaz). Controller driving'de kalıp bitiş koşullarını izlemeye devam eder.
      } else {
        if (!_autoEnabled &&
            (_tracker.lastPosition != null ||
                _activeTrip!.currentLat != null)) {
          await _tracker.start(
            tripId: _activeTrip!.tripId,
            tripService: _tripService,
            interval: const Duration(seconds: 10),
          );
        }
      }
    } catch (e) {
      _showError('Hata: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _endTrip() async {
    if (_activeTrip == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seferi Bitir'),
        content: Text(
          '${formatDurationHMS(_tripDuration)} süre çalıştınız. Seferi bitirmek istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Bitir'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await _tripService.setStatus(
      _activeTrip!.tripId,
      SehiriciTripStatus.completed,
    );
    if (!_autoEnabled) {
      await _tracker.stop();
    }
    _stopTripTimer();
    _stopWorkingHoursCheck();
    _autoRouteTimer?.cancel();
    _autoRouteTimer = null;
    setState(() => _activeTrip = null);
    if (_autoEnabled) {
      // Manuel override bitirme: controller'ı yeniden senkronla ->
      // aktif sefer yok, watching'e döner.
      unawaited(_applyAutomation());
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sefer tamamlandı'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  /// Şoför "Rotamı gittiğim yerlerden oluştur" ayarını açtıysa ve hat için
  /// henüz rota_polyline yoksa, sefer boyunca her 30 saniyede bir GPS
  /// noktalarını kontrol eder. ~50 m iz birikince ilk kaydı hemen yapar ve
  /// sefer boyunca iz uzadıkça rotayı güncellemeye devam eder (GPS izi gerçek
  /// yol ağına map-match edip cacheRoutePolyline ile kaydedilir).
  Future<void> _maybeStartAutoRouteWatcher({
    required SehiriciLine line,
    required String tripId,
  }) async {
    try {
      final enabled =
          _driverProfile?['auto_route_from_traveled_path'] as bool? ?? false;
      if (!enabled) return;
      if (line.roadPolyline != null && line.roadPolyline!.length >= 2) return;
      if (line.stops.length < 2) return;

      _autoRouteTimer?.cancel();
      _autoRouteSavedOnce = false;
      _autoRouteLastSavedMeters = 0;
      _autoRouteTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _checkAutoRoute(tripId: tripId, line: line),
      );
    } catch (e) {
      debugPrint('_maybeStartAutoRouteWatcher hata: $e');
    }
  }

  Future<void> _checkAutoRoute({
    required String tripId,
    required SehiriciLine line,
  }) async {
    if (!mounted || _autoRouteBusy) return;
    _autoRouteBusy = true;
    try {
      final path = await _tripService.getTripPath(tripId);
      // İlk kayıt ~50 m'de yapılır (1 km beklenmez). Konumlar ~10 sn'de bir
      // yazıldığından 3 nokta ≈ 20-30 sn sürüş demek.
      if (path.length < 3) return;
      final coords = path
          .map((p) => LatLng(p.lat, p.lng))
          .toList(growable: false);
      final totalMeters = pathLengthMeters(coords);
      if (totalMeters < 50) return;

      // İz kayda değer biçimde uzamadıysa yeniden eşleme/kaydetme yapma.
      // Bu kontrol olmadan, 30 sn'de bir tüm iz OSRM'ye gönderilip hattın
      // rotası baştan yazılıyordu: araç durakta beklerken bile aynı iz
      // tekrar tekrar işleniyor, her yazım öncekini eziyordu.
      if (totalMeters - _autoRouteLastSavedMeters < _kAutoRouteGrowthMeters) {
        return;
      }

      // GPS noktalarını doğrudan sadeleştirip birleştirmek keskin virajlarda
      // binaların üzerinden kiriş oluşturuyordu. Önce gerçek yol ağına oturt,
      // ardından nokta sayısını makul bir tavanla sınırla.
      final roadMatched = await _roadSnapService.matchDrivenPath(coords);
      if (!mounted || roadMatched.length < 2) return;
      final simplified = simplifyToMaxPoints(roadMatched, maxPoints: 1500);
      if (simplified.length < 2) return;

      final polylinePoints = simplified
          .map((c) => <double>[c.latitude, c.longitude])
          .toList(growable: false);

      final ok = await _lineService.cacheRoutePolyline(
        lineId: line.id,
        lineStopsInOrder: line.stops,
        points: polylinePoints,
        source: 'auto_traveled_road_matched',
      );
      if (ok) {
        _autoRouteLastSavedMeters = totalMeters;
        // Zamanlayıcı bilerek durdurulmuyor: ~50 m'lik ilk taslak kayıttan
        // sonra sefer boyunca iz uzadıkça rota güncellenir. Bildirim yalnızca
        // ilk kayıtta gösterilir.
        if (!_autoRouteSavedOnce) {
          _autoRouteSavedOnce = true;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Otomatik rota kaydedildi; sefer boyunca güncelleniyor',
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('_checkAutoRoute hata: $e');
    } finally {
      _autoRouteBusy = false;
    }
  }

  void _startTripTimer() {
    _tripTimer?.cancel();
    _tripDuration = Duration.zero;
    _tripTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _activeTrip?.startedAt != null) {
        setState(() {
          _tripDuration = DateTime.now().difference(_activeTrip!.startedAt!);
        });
      }
    });
  }

  void _stopTripTimer() {
    _tripTimer?.cancel();
    _tripTimer = null;
    _tripDuration = Duration.zero;
  }

  /// Çalışma saatleri kontrolü: saat dışında otomatik konum izlemeyi durdur
  /// (auto_location_enabled=true ise).
  Timer? _workingHoursTimer;
  void _startWorkingHoursCheck() {
    _workingHoursTimer?.cancel();
    _workingHoursTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted || _activeTrip == null) return;
      _checkAndApplyWorkingHours();
    });
  }

  void _stopWorkingHoursCheck() {
    _workingHoursTimer?.cancel();
    _workingHoursTimer = null;
  }

  void _checkAndApplyWorkingHours() {
    if (_activeTrip?.workingHoursStart == null ||
        _activeTrip?.workingHoursEnd == null) {
      return;
    }
    final auto = _driverProfile?['auto_location_enabled'] as bool? ?? true;
    if (!auto) return;
    final now = TimeOfDay.now();
    final start = _activeTrip!.workingHoursStart!;
    final end = _activeTrip!.workingHoursEnd!;
    final isWithin = isTimeWithinRange(
      currentHour: now.hour,
      currentMinute: now.minute,
      startHour: start.hour,
      startMinute: start.minute,
      endHour: end.hour,
      endMinute: end.minute,
    );
    if (isWithin && !_tracker.isTracking) {
      _tracker.start(
        tripId: _activeTrip!.tripId,
        tripService: _tripService,
        interval: const Duration(seconds: 10),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Çalışma saatleri başladı. Konum paylaşımı başlatıldı.',
            ),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } else if (!isWithin && _tracker.isTracking) {
      _tracker.stop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Çalışma saatleri bitti. Konum paylaşımı durduruldu.',
            ),
            backgroundColor: Colors.amber,
          ),
        );
      }
    }
  }

  /// BUG FIX: Bu metod artık gerçekten DB'ye yazıyor. Önceki kod sadece
  /// snackbar gösteriyordu — ayar dekoratifti.
  Future<void> _showSettingsDialog() async {
    final initialStart = _parseHhmmFromProfile('working_hours_start');
    final initialEnd = _parseHhmmFromProfile('working_hours_end');
    bool autoLocation =
        _driverProfile?['auto_location_enabled'] as bool? ?? true;
    bool autoRt =
        _driverProfile?['auto_route_from_traveled_path'] as bool? ?? false;
    bool autoTrip =
        _driverProfile?['auto_trip_enabled'] as bool? ?? false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        TimeOfDay? workStart = initialStart;
        TimeOfDay? workEnd = initialEnd;
        bool autoLoc = autoLocation;
        bool saving = false;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Şoför Ayarları'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Çalışma Saatleri',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          title: const Text('Başlangıç'),
                          subtitle: Text(workStart?.format(ctx) ?? '--:--'),
                          trailing: const Icon(Icons.access_time),
                          onTap: saving
                              ? null
                              : () async {
                                  final picked = await showTimePicker(
                                    context: ctx,
                                    initialTime: workStart ?? TimeOfDay.now(),
                                  );
                                  if (picked != null) {
                                    setState(() => workStart = picked);
                                  }
                                },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ListTile(
                          title: const Text('Bitiş'),
                          subtitle: Text(workEnd?.format(ctx) ?? '--:--'),
                          trailing: const Icon(Icons.access_time),
                          onTap: saving
                              ? null
                              : () async {
                                  final picked = await showTimePicker(
                                    context: ctx,
                                    initialTime: workEnd ?? TimeOfDay.now(),
                                  );
                                  if (picked != null) {
                                    setState(() => workEnd = picked);
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text(
                    'Otomatik Konum',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text(
                      'Çalışma Saatleri Dışında Otomatik Kapat',
                    ),
                    subtitle: const Text(
                      'Çalışma saatleri dışında konum paylaşımı otomatik durur',
                    ),
                    value: autoLoc,
                    onChanged: saving
                        ? null
                        : (v) => setState(() => autoLoc = v),
                  ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text(
                    'Otomatik Rota',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Rotamı gittiğim yerlerden oluştur'),
                    subtitle: const Text(
                      'Hat için henüz rota yoksa, ~50 m gittikten sonra GPS '
                      'noktalarım otomatik rota olarak kaydedilir ve sefer '
                      'boyunca güncellenir',
                    ),
                    value: autoRt,
                    onChanged: saving
                        ? null
                        : (v) => setState(() => autoRt = v),
                  ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text(
                    'Otomatik Sefer',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Seferleri kendiliğinden başlat/bitir'),
                    subtitle: const Text(
                      'Açıksa uygulama GPS, çalışma saati ve hat bölgenizi '
                      'izler; uygun koşullarda seferi otomatik başlatır, '
                      'çalışma saati bitince otomatik bitirir. Telefon cebinizde '
                      'kalabilir. (Çalışma saatleri ayarlanmazsa otomatik bitiş '
                      'olmaz — elle bitirin.)',
                    ),
                    value: autoTrip,
                    onChanged: saving
                        ? null
                        : (v) => setState(() => autoTrip = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx, false),
                child: const Text('İptal'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (_driverProfile == null) {
                          Navigator.pop(ctx, false);
                          return;
                        }
                        setState(() => saving = true);
                        final driverId = _driverProfile!['id'] as String;
                        final startStr = workStart != null
                            ? formatHhmm(workStart!.hour, workStart!.minute)
                            : null;
                        final endStr = workEnd != null
                            ? formatHhmm(workEnd!.hour, workEnd!.minute)
                            : null;
                        final ok = await _driverService.updateDriverSettings(
                          driverId: driverId,
                          workingHoursStart: startStr,
                          workingHoursEnd: endStr,
                          autoLocationEnabled: autoLoc,
                          autoRouteFromTraveledPath: autoRt,
                          autoTripEnabled: autoTrip,
                        );
                        if (!context.mounted) return;
                        if (ok) {
                          Navigator.pop(ctx, true);
                        } else {
                          setState(() => saving = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Ayarlar kaydedilemedi'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                child: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Kaydet'),
              ),
            ],
          ),
        );
      },
    );

    if (result == true && mounted) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ayarlar kaydedildi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
    // autoLocation değişkeni result'tan bağımsız, sadece compiler için
    // (UI'da kullanılıyor)
    autoLocation = autoLocation;
  }

  Widget _buildDroppedLocationCard(SehiriciActiveTrip trip, SehiriciLine line) {
    if (_droppedLocation == null ||
        trip.currentLat == null ||
        trip.currentLng == null) {
      return const SizedBox.shrink();
    }

    final vehiclePos = LatLng(trip.currentLat!, trip.currentLng!);
    final distance = _calculateDistance(vehiclePos, _droppedLocation!);
    final eta = calculateEtaMinutes(distance.round());

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.location_on, color: Colors.blue, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Düşürülen Konum',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                  Text(
                    '${(distance / 1000).toStringAsFixed(1)} km uzakta • '
                    '~$eta dk sonra varış',
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => setState(() => _droppedLocation = null),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }

  double _calculateDistance(LatLng start, LatLng end) {
    const earthRadius = 6371000.0;
    final dLat = _toRadians(end.latitude - start.latitude);
    final dLng = _toRadians(end.longitude - start.longitude);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(start.latitude)) *
            math.cos(_toRadians(end.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SehiriciProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Şoför Paneli'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: _showSettingsDialog,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _driverProfile == null
          ? _notDriverView()
          : _activeTrip == null
          ? _selectLineView(provider)
          : _activeTripView(),
    );
  }

  Widget _notDriverView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.directions_bus_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            const Text(
              'Şoför kaydınız bulunamadı',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Yönetici tarafından şoför olarak atanmalısınız.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutomationBanner() {
    final watching = SehiriciAutoTripController.instance.isWatching;
    final wh = _driverProfile?['working_hours_start'] as String?;
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Icon(
              watching ? Icons.gps_fixed : Icons.gps_not_fixed,
              color: Colors.green.shade700,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Otomatik sefer açık',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  Text(
                    watching
                        ? (wh == null
                            ? 'Sistem sizi izliyor — harekete geçince sefer '
                              'kendiliğinden başlayacak.'
                            : 'Sistem sizi izliyor — çalışma saatinde '
                              'harekete geçince sefer kendiliğinden başlayacak.')
                        : 'Hazırlanıyor…',
                    style: TextStyle(
                      color: Colors.green.shade800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectLineView(SehiriciProvider provider) {
    final assignedLine = _driverProfile!['sehirici_lines'] as Map?;
    final assignedLineId = _driverProfile!['assigned_line_id'] as String?;

    SehiriciLine? driverLine;
    if (assignedLineId != null) {
      try {
        driverLine = provider.lines.firstWhere((l) => l.id == assignedLineId);
      } catch (_) {
        driverLine = null;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (_autoEnabled)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildAutomationBanner(),
          ),
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.person, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _driverProfile!['license_number'] ?? 'Şoför',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      if (assignedLine != null)
                        Text(
                          'Atanmış Hat: ${assignedLine['code']} — ${assignedLine['name']}',
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (driverLine != null) ...[
          const Text(
            'Seferi Başlatmak İçin',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: driverLine.color.withValues(alpha: 0.15),
                child: Icon(
                  driverLine.vehicleType.icon,
                  color: driverLine.color,
                ),
              ),
              title: Text('${driverLine.code} — ${driverLine.name}'),
              subtitle: Text('${driverLine.stops.length} durak'),
              trailing: FilledButton.icon(
                onPressed: _busy ? null : () => _startTrip(driverLine!),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Başlat'),
              ),
            ),
          ),
        ] else ...[
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.warning, size: 48, color: Colors.amber),
                  const SizedBox(height: 12),
                  const Text(
                    'Hat Ataması Yapılmamış',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Yönetici tarafından size bir hat atanmalıdır.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _activeTripView() {
    final trip = _activeTrip!;
    final provider = context.watch<SehiriciProvider>();
    final city = provider.selectedCity;
    final line = provider.lines.firstWhere(
      (l) => l.id == trip.lineId,
      orElse: () => SehiriciLine(
        id: trip.lineId,
        code: trip.lineCode,
        name: trip.lineName,
        colorHex: trip.lineColor,
        stops: const [],
      ),
    );

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: trip.status == SehiriciTripStatus.active
              ? Colors.green.shade50
              : Colors.orange.shade50,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    trip.status == SehiriciTripStatus.active
                        ? Icons.check_circle
                        : Icons.pause_circle,
                    color: trip.status == SehiriciTripStatus.active
                        ? Colors.green
                        : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Aktif Sefer: ${line.code} — ${line.name}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Kronometre: ${formatDurationHMS(_tripDuration)}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (trip.licensePlate != null)
                    Chip(
                      label: Text(
                        trip.licensePlate!,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: Colors.blue.shade100,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                trip.status == SehiriciTripStatus.active
                    ? (_tracker.isTracking
                          ? 'Yolda — Konum paylaşılıyor'
                          : 'Yolda — Konum bekleniyor')
                    : 'Mola — Konum paylaşımı duraklatıldı',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              if (_autoEnabled)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _activeTrip?.workingHoursStart == null
                        ? 'Otomatik sefer açık — elle bitirene kadar sürer.'
                        : 'Otomatik sefer açık — çalışma saati bitince '
                          'kendiliğinden bitecek.',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _togglePause,
                      icon: Icon(
                        trip.status == SehiriciTripStatus.active
                            ? Icons.pause
                            : Icons.play_arrow,
                      ),
                      label: Text(
                        trip.status == SehiriciTripStatus.active
                            ? 'Mola'
                            : 'Devam',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _endTrip,
                      icon: const Icon(Icons.stop),
                      label: const Text('Seferi Bitir'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: city != null
              ? Stack(
                  children: [
                    SehiriciLiveMap(
                      lines: [line],
                      activeTrips: [trip],
                      center: city,
                      zoomLevel: city.zoomLevel,
                      height: double.infinity,
                      interactive: true,
                      // Şoför paneli: admin tarafından tanımlanmış hat rotasını
                      // göster (duraklar arası veya roadPolyline), ama şoförün
                      // o an geçtiği canlı rota polyline'ını gösterme.
                      showRoute: true,
                      showLiveTripPath: false,
                      // Şoförün kendi kurye/paket bilgisi gereksiz, sadece
                      // kendi hattına odaklansın.
                      showCouriers: false,
                      onLongPress: (pos) =>
                          setState(() => _droppedLocation = pos),
                    ),
                    if (_droppedLocation != null)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: _buildDroppedLocationCard(trip, line),
                      ),
                  ],
                )
              : const Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }
}
