import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart'
    show EagerGestureRecognizer, OneSequenceGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/courier_stream_service.dart';
import '../../core/services/location_disclosure_service.dart';
import '../../core/theme/app_map_style.dart';
import '../../core/utils/map_marker_icons.dart';
import '../../core/widgets/map_controls.dart';
import '../models/sehirici_icon_models.dart';
import '../models/sehirici_models.dart';
import '../providers/sehirici_provider.dart';
import '../services/sehirici_icon_catalog.dart';
import '../services/sehirici_line_service.dart';
import '../services/sehirici_trip_service.dart';
import '../utils/sehirici_marker_bitmaps.dart';
import '../utils/sehirici_route_geometry.dart';
import 'sehirici_common_widgets.dart';
import 'sehirici_map_sheets.dart';

/// Şehir içi servis canlı harita widget'ı.
/// Aktif seferleri, durakları ve hat güzergâhlarını harita üzerinde gösterir.
///
/// Görünüm:
/// • Tepeden görünüm, yüksek çözünürlüklü GERÇEKÇİ araç ikonları (ikonlar
///   admin panelindeki ikon kütüphanesinden gelir; hazır çizim ya da yüklenmiş
///   görsel) — yönlerine göre döner.
/// • Direkli durak levhaları; yakınlaştıkça sade noktadan levhaya, hat renk
///   plakasına ve durak adına geçer. Seçili durak / seçili aracın sıradaki
///   durağı turuncu vurgulanır.
/// • Güzergâh çizgileri beyaz/koyu kenarlıklı ("kasing"); vurgulu hatta yön okları.
/// • Cam kontroller, hat çipleri, canlı araç sayacı, katmanlar sayfası
///   (standart/uydu, açık/koyu, trafik, durak adları).
///
/// Dinamik özellikler:
/// • Animasyonlu araç hareketi (gerçek güncelleme aralığına göre süzülme)
/// • Nabız halkası (yakın zoom'da)
/// • Düz (2D) görünüm: kamera eğimi ve 3D bina kabartması kapalı
/// • Durak / araç dokunuşlarında canlı varış süreli alt sayfalar
///
/// Performans: yalnızca değişen marker'ları günceller, ikon bitmap'leri
/// (zoom aralığı + renk + durum anahtarıyla) önbelleklenir, controller tek
/// seferde oluşturulur.
class SehiriciLiveMap extends StatefulWidget {
  final List<SehiriciLine> lines;
  final List<SehiriciActiveTrip> activeTrips;
  final SehiriciCity center;
  final int zoomLevel;
  final String? selectedStopId;
  final bool interactive;
  final double height;

  /// Trafik katmanını göster/gizle (başlangıç değeri; kullanıcı katmanlar
  /// sayfasından değiştirebilir).
  final bool showTraffic;

  /// Canlı güncellemeleri etkinleştir
  final bool enableLiveUpdates;

  /// Live update aralığı (saniye)
  final int updateIntervalSeconds;

  /// Long press callback (konum düşürme)
  final ValueChanged<LatLng>? onLongPress;

  /// Hat yol rotasını (yol takip eden çizgi) göster/gizle.
  /// true ise: admin tarafından çizilmiş hat rotası (roadPolyline) çizilir.
  /// false ise: durak marker'ları yine görünür, hat çizgisi çizilmez.
  final bool showRoute;

  /// Vurgulanacak hat ID'si. null = tüm hatlar eşit görünür.
  /// Dolu ise: sadece bu hat tam opaklık + kalın + yön okları; diğerleri soluk
  /// ve ince. Bu hattın durakları öne çıkar, ilk/son durak işaretlenir.
  final String? highlightLineId;

  /// Şoförün o an geçtiği canlı yol polyline'ını göster/gizle.
  ///
  /// VARSAYILAN false — canlı iz haritada çizilmiyor. Nedeni ham GPS
  /// gürültüsü DEĞİL (o ayrıca [buildTripPathSegments] ile temizleniyor):
  /// konum ~10 sn'de bir yazıldığı için ardışık noktalar şehir içi hızda
  /// 130-300 m arayla düşüyor ve aralar DÜZ ÇİZGİYLE birleştiriliyor. Çizgi
  /// caddeleri takip etmiyor; blokların üzerinden kestirme geçiyor.
  /// İki örnek arasındaki yolun gerçek şekli veride yok; bunu ancak yol
  /// eşleme (OSRM `match`) üretebilir.
  ///
  /// true verilirse eski davranış (temizlenmiş, parçalara bölünmüş ham iz)
  /// geri gelir; altyapı yerinde duruyor.
  final bool showLiveTripPath;

  /// Aktif kuryeleri (role='courier', konum paylaşan) haritada motor ikonuyla
  /// göster. Şoförün kendi panelinde kapatılabilir.
  final bool showCouriers;

  /// Harita üstünde hat çipleri (dokununca hattı vurgular). Birden çok hat
  /// varken tam ekran haritada açılır.
  final bool showLineChips;

  /// Çipe dokunulunca vurgulanacak hat değişirse çağrılır (null = vurguyu
  /// kaldır). Verilmezse vurgu haritanın kendi içinde tutulur.
  final ValueChanged<String?>? onHighlightChanged;

  /// Üst/alt yüzen öğeleri güvenli alana (çentik, gezinme çubuğu) taşımak için.
  final EdgeInsets overlayPadding;

  /// Köşe yuvarlaklığı; tam ekranda 0 verilir.
  final double borderRadius;

  const SehiriciLiveMap({
    super.key,
    required this.lines,
    required this.activeTrips,
    required this.center,
    this.zoomLevel = 13,
    this.selectedStopId,
    this.interactive = true,
    this.height = 220,
    this.showTraffic = false,
    this.enableLiveUpdates = true,
    this.updateIntervalSeconds = 30,
    this.onLongPress,
    this.showRoute = true,
    this.highlightLineId,
    this.showLiveTripPath = false,
    this.showCouriers = true,
    this.showLineChips = false,
    this.onHighlightChanged,
    this.overlayPadding = EdgeInsets.zero,
    this.borderRadius = 18,
  });

  @override
  State<SehiriciLiveMap> createState() => _SehiriciLiveMapState();
}

/// Bir durağın harita üzerindeki çizim tanımı.
class _StopSpec {
  final String id;
  final String name;
  final LatLng position;
  final String? code;
  final String? address;

  /// Bu duraktan geçen hatlar (hiçbir hatta bağlı değilse boş).
  final List<SehiriciLine> lines;
  final MapStopState state;
  final bool isStart;
  final bool isEnd;
  final List<Color> colors;

  /// Vurgulu hat varken o hatta olmayan duraklar soluk çizilir.
  final bool dimmed;
  final bool onHighlightedLine;

  const _StopSpec({
    required this.id,
    required this.name,
    required this.position,
    required this.code,
    required this.address,
    required this.lines,
    required this.state,
    required this.isStart,
    required this.isEnd,
    required this.colors,
    required this.dimmed,
    required this.onHighlightedLine,
  });
}

class _SehiriciLiveMapState extends State<SehiriciLiveMap>
    with TickerProviderStateMixin {
  /// Araç marker'ını taşımak için gereken en küçük yer değiştirme (metre).
  /// Sabit araçta GPS zıplamasını süzecek kadar büyük, gerçek hareketi
  /// anında gösterecek kadar küçük.
  static const double _kMinMoveMeters = 5.0;

  /// Kurye marker rengi (turuncu) — hat renkli servis araçlarından ayrışır.
  static const Color _kCourierColor = Color(0xFFFB8C00);

  /// Yakınlık eşikleri: durak ayrıntısı, araç boyu, adlar ve oklar.
  static const double _kMidZoom = 14.2;
  static const double _kNearZoom = 15.6;
  static const double _kArrowZoom = 15.0;

  // Animasyon durumları
  final Map<String, LatLng> _previousPositions = {};
  final Map<String, LatLng> _targetPositions = {};
  final Map<String, AnimationController> _positionAnimControllers = {};
  final Map<String, Animation<LatLng>> _positionAnimations = {};

  // Pulse animasyonu: TÜM canlı araçlar için TEK shared controller (her araç
  // için ayrı controller + setState, N araçta saniyede ~60×N harita rebuild'i
  // üretiyordu). Araç yoksa animasyon durur.
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  final Map<String, Color> _pulseColors = {}; // tripId -> pulse rengi

  // Pulse setState'ini ~20fps'de tutmak için frame sayacı.
  int _pulseFrame = 0;

  // Timer durumları
  Timer? _liveUpdateTimer;
  Timer? _etaUpdateTimer;

  // Mevcut trip verileri (ETA hesaplaması için)
  final Map<String, SehiriciActiveTrip> _currentTripData = {};

  // Her aktif sefer için şoförün geçtiği gerçek yolun HAM GPS noktaları.
  // Haritaya doğrudan ÇİZİLMEZ: önce `buildTripPathSegments` ile temizlenip
  // parçalara bölünür.
  final Map<String, List<LatLng>> _tripPaths = {};
  final Set<String> _tripPathsLoading = {};
  final Map<String, String> _tripPathSignatures = {};

  final SehiriciTripService _tripService = SehiriciTripService();
  final SehiriciLineService _lineService = SehiriciLineService();
  final SehiriciIconCatalog _catalog = SehiriciIconCatalog.instance;

  // Şehirdeki TÜM duraklar (henüz hiçbir hatta bağlanmamış olanlar dahil).
  List<SehiriciStop> _standaloneStops = const [];

  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  Set<Circle> _circles = {}; // Pulse efektleri için
  bool _initialFit = true;
  bool _isMapReady = false;

  // ── Kamera / yakınlık ────────────────────────────────────────
  late double _zoom;
  late MapStopDetail _detail;
  late double _vehicleScale;
  late bool _labelsVisible;
  late bool _arrowsVisible;

  // ── İkon çözümleme (bitmap önbelleği) ────────────────────────
  final Map<String, SehiriciResolvedMarker> _resolved = {};
  final Map<String, Future<void>> _pendingIcons = {};
  int _iconGeneration = 0;
  bool _darkSurface = false;

  // ── Katmanlar ────────────────────────────────────────────────
  late final ValueNotifier<bool> _traffic;
  final ValueNotifier<bool> _stopLabels = ValueNotifier<bool>(true);

  /// Vurgu haritanın içinde tutuluyorsa (dışarıdan verilmemişse) hat kimliği.
  String? _localHighlightId;
  String? _selectedStopId;

  // Kullanıcının kendi konumu ve seçili sefer için canlı takip
  Position? _userPosition;
  LatLng? _draggedPosition;
  StreamSubscription<Position>? _userPositionSub;
  SehiriciLine? _selectedLine;
  String? _selectedLineId;
  String? _selectedTripId;

  // Cihazın konum servisi (GPS) kapalı mı?
  bool _locationServiceOff = false;

  // Her sefer için son konum güncellemesinin geldiği an. Marker animasyonu
  // sabit 800 ms yerine GERÇEK güncelleme aralığına göre sürer.
  final Map<String, DateTime> _lastPositionAt = {};

  // Marker'ın o an gösterdiği dönüş açısı (derece).
  final Map<String, double> _markerRotations = {};

  // Kuryeler: role='courier' + konum paylaşan kullanıcılar.
  Map<String, CourierInfo> _couriers = const {};
  void Function(Map<String, CourierInfo>)? _courierListener;

  // Kurye konum animasyonu: yeni snapshot geldiğinde marker eski konumdan
  // yenisine süzülür. Tüm kuryeler için TEK controller.
  late final AnimationController _courierMoveController;
  final Map<String, LatLng> _courierFrom = {};
  final Map<String, LatLng> _courierTo = {};
  int _courierMoveFrame = 0;

  // ─────────────────────────────────────────────
  // Yaşam döngüsü
  // ─────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _zoom = widget.zoomLevel.toDouble();
    _detail = _detailFor(_zoom);
    _vehicleScale = _scaleFor(_zoom);
    _labelsVisible = _zoom >= _kNearZoom;
    _arrowsVisible = _zoom >= _kArrowZoom;
    _traffic = ValueNotifier<bool>(widget.showTraffic);
    _traffic.addListener(_onLayerChanged);
    _stopLabels.addListener(_onLayerChanged);

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 2.4).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
    _pulseController.addListener(_onPulseTick);

    _courierMoveController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..addListener(_onCourierMoveTick);

    _catalog.addListener(_onCatalogChanged);
    _catalog.ensureLoaded();
    MapTypePreference.ensureLoaded();

    _initializeTripData();
    _rebuild();
    _initUserLocationOnEntry();
    _loadStandaloneStops();

    // Şoför konum güncellemelerini realtime dinle (yalnız canlı iz açıksa).
    if (widget.showLiveTripPath) {
      _tripService.watchTripPaths(onPoint: _onTripPathPoint);
    }

    if (widget.enableLiveUpdates) {
      _startLiveUpdates();
    }

    if (widget.showCouriers) {
      _startCourierTracking();
    }
  }

  @override
  void dispose() {
    _isMapReady = false;
    _iconGeneration++;

    _catalog.removeListener(_onCatalogChanged);
    _traffic.removeListener(_onLayerChanged);
    _stopLabels.removeListener(_onLayerChanged);
    _traffic.dispose();
    _stopLabels.dispose();

    // Realtime kanallarını kapat
    _tripService.stopWatching();
    final l = _courierListener;
    if (l != null) {
      CourierStreamService().unsubscribe(l);
      _courierListener = null;
    }

    _stopLiveUpdates();
    _stopUserLocationStream();

    for (final controller in _positionAnimControllers.values) {
      controller.dispose();
    }
    _positionAnimControllers.clear();
    _positionAnimations.clear();

    _pulseController.dispose();
    _courierMoveController.dispose();

    _mapController?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SehiriciLiveMap old) {
    super.didUpdateWidget(old);

    // Trip değişikliklerini kontrol et. Eklenen/çıkan seferleri işlemek YETMEZ —
    // realtime'dan gelen konum güncellemeleri de burada yansıtılmalı; aksi
    // hâlde araç yalnızca yedek timer'da (30 sn) hareket ederdi.
    if (!identical(old.activeTrips, widget.activeTrips)) {
      _handleTripChanges(old.activeTrips);
      // _refreshTripPositions setState çağırabilen yardımcılara giriyor;
      // didUpdateWidget build fazında çalıştığı için bir frame sonraya bırakılır.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _refreshTripPositions();
        _refreshIcons();
      });
    }

    if (old.enableLiveUpdates != widget.enableLiveUpdates) {
      if (widget.enableLiveUpdates) {
        _startLiveUpdates();
      } else {
        _stopLiveUpdates();
      }
    }

    if (old.showTraffic != widget.showTraffic) {
      _traffic.value = widget.showTraffic;
    }

    // Canlı yol polyline'ı değişikliği.
    if (old.showLiveTripPath != widget.showLiveTripPath) {
      if (!widget.showLiveTripPath) {
        _tripService.stopWatching();
        _tripPaths.clear();
        _tripPathSignatures.clear();
        setState(() {
          _polylines = _polylines
              .where((p) => !p.polylineId.value.startsWith('trip_path_'))
              .toSet();
        });
      } else {
        _tripService.watchTripPaths(onPoint: _onTripPathPoint);
      }
    }

    // Kurye gösterimi değişikliği.
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

    // Hat listesi değişince her şeyi (durak, rota, ikon) yeniden kur.
    if (old.lines != widget.lines) {
      _rebuild();
    }

    // Şehir değiştiyse hatta bağlı olmayan durakları yeniden yükle.
    if (old.center.id != widget.center.id) {
      _loadStandaloneStops();
    }

    // Vurgulu hat değiştiyse: durak durumları, rota kalınlığı ve oklar
    // yeniden çizilir; harita hattın duraklarına sığdırılır.
    if (old.highlightLineId != widget.highlightLineId) {
      _rebuild();
      if (widget.highlightLineId != null && _mapController != null) {
        _fitToHighlightedLine();
      }
    }
  }

  void _onCatalogChanged() {
    // Admin ikon kütüphanesini değiştirdi: eski bitmap anahtarları
    // (`imageCacheKey` sürümü içerir) zaten farklı; yalnız yeniden çöz.
    if (mounted) _refreshIcons();
  }

  void _onLayerChanged() {
    if (!mounted) return;
    setState(() {});
    _recompose();
  }

  // ─────────────────────────────────────────────
  // Yakınlık → ayrıntı düzeyi
  // ─────────────────────────────────────────────

  static MapStopDetail _detailFor(double zoom) => zoom < _kMidZoom
      ? MapStopDetail.far
      : (zoom < _kNearZoom ? MapStopDetail.mid : MapStopDetail.near);

  /// Uzaktan bakışta araçlar küçülür (ekrandaki boyutları sabit olduğu için
  /// şehir görünümünde birbirini örterler).
  static double _scaleFor(double zoom) {
    if (zoom < 13) return 0.66;
    if (zoom < 14.5) return 0.8;
    if (zoom < 15.5) return 0.92;
    return 1.0;
  }

  void _onCameraMove(CameraPosition position) {
    _zoom = position.zoom;
  }

  void _onCameraIdle() {
    final detail = _detailFor(_zoom);
    final scale = _scaleFor(_zoom);
    final labels = _zoom >= _kNearZoom;
    final arrows = _zoom >= _kArrowZoom;
    final iconsChanged = detail != _detail || scale != _vehicleScale;
    final overlaysChanged = labels != _labelsVisible || arrows != _arrowsVisible;
    if (!iconsChanged && !overlaysChanged) return;
    _detail = detail;
    _vehicleScale = scale;
    _labelsVisible = labels;
    _arrowsVisible = arrows;
    if (iconsChanged) {
      _refreshIcons();
    } else {
      _recompose();
    }
  }

  // ─────────────────────────────────────────────
  // Vurgu / seçim
  // ─────────────────────────────────────────────

  String? get _effectiveHighlightId =>
      widget.highlightLineId ?? _localHighlightId;

  SehiriciLine? get _effectiveHighlightLine {
    final id = _effectiveHighlightId;
    if (id == null) return null;
    for (final l in widget.lines) {
      if (l.id == id) return l;
    }
    return null;
  }

  String? get _effectiveSelectedStopId =>
      widget.selectedStopId ?? _selectedStopId;

  /// Takip edilen aracın sıradaki durağı (turuncu vurgulanır).
  String? get _trackedNextStopId {
    final id = _selectedTripId;
    if (id == null) return null;
    for (final t in widget.activeTrips) {
      if (t.tripId == id) return t.nextStopId;
    }
    return null;
  }

  void _onChipTap(String? lineId) {
    final next = lineId == _effectiveHighlightId ? null : lineId;
    final cb = widget.onHighlightChanged;
    if (cb != null) {
      cb(next);
      return;
    }
    setState(() => _localHighlightId = next);
    _rebuild();
    if (next != null) _fitToHighlightedLine();
  }

  // ─────────────────────────────────────────────
  // Durak verisi
  // ─────────────────────────────────────────────

  /// Şehirdeki tüm durakları (bir hatta bağlı olsun olmasın) yükler.
  /// widget.lines sadece hatta bağlı durakları taşıdığından, henüz hiçbir
  /// hatta eklenmemiş duraklar bu olmadan haritada hiç görünmezdi.
  Future<void> _loadStandaloneStops() async {
    final cityId = widget.center.id;
    if (cityId.isEmpty) return;
    try {
      final stops = await _lineService.getStopsByCity(cityId);
      if (!mounted || widget.center.id != cityId) return;
      _standaloneStops = stops;
      _refreshIcons();
    } catch (_) {
      // Sessizce geç — durak marker'ları olmadan da harita çalışır.
    }
  }

  /// Her durağın çizim tanımını hesaplar (hatlar, durum, renkler, soluklaştırma).
  List<_StopSpec> _computeStopSpecs() {
    final infoById = <String, SehiriciLineStop>{};
    final linesByStop = <String, List<SehiriciLine>>{};
    for (final line in widget.lines) {
      for (final stop in line.stops) {
        infoById.putIfAbsent(stop.stopId, () => stop);
        linesByStop.putIfAbsent(stop.stopId, () => []).add(line);
      }
    }

    final highlight = _effectiveHighlightLine;
    // İlk/son durak rozeti: vurgulu hat ya da haritada tek hat varsa.
    final terminalLine =
        highlight ?? (widget.lines.length == 1 ? widget.lines.first : null);
    final firstId = (terminalLine != null && terminalLine.stops.isNotEmpty)
        ? terminalLine.stops.first.stopId
        : null;
    final lastId = (terminalLine != null && terminalLine.stops.isNotEmpty)
        ? terminalLine.stops.last.stopId
        : null;
    final selectedId = _effectiveSelectedStopId;
    final nextId = _trackedNextStopId;

    _StopSpec make({
      required String id,
      required String name,
      required double lat,
      required double lng,
      String? code,
      String? address,
    }) {
      final lines = linesByStop[id] ?? const <SehiriciLine>[];
      final onHl = highlight != null && lines.any((l) => l.id == highlight.id);
      final isSelected = id == selectedId || id == nextId;
      final isStart = firstId != null && id == firstId;
      final isEnd = lastId != null && id == lastId && lastId != firstId;
      final state = isSelected
          ? MapStopState.selected
          : ((isStart || isEnd) ? MapStopState.terminal : MapStopState.normal);
      final colors = onHl
          ? [highlight.color]
          : lines.map((l) => l.color).take(3).toList();
      return _StopSpec(
        id: id,
        name: name,
        position: LatLng(lat, lng),
        code: code,
        address: address,
        lines: lines,
        state: state,
        isStart: isStart,
        isEnd: isEnd,
        colors: colors,
        dimmed: highlight != null && !onHl && !isSelected,
        onHighlightedLine: onHl,
      );
    }

    final specs = <_StopSpec>[];
    for (final stop in infoById.values) {
      specs.add(make(
        id: stop.stopId,
        name: stop.name,
        lat: stop.lat,
        lng: stop.lng,
        code: stop.code,
        address: stop.address,
      ));
    }
    for (final stop in _standaloneStops) {
      if (infoById.containsKey(stop.id)) continue;
      specs.add(make(
        id: stop.id,
        name: stop.name,
        lat: stop.lat,
        lng: stop.lng,
        code: stop.code,
        address: stop.address,
      ));
    }
    return specs;
  }

  // ─────────────────────────────────────────────
  // İkon çözümleme
  // ─────────────────────────────────────────────

  String _stopIconKey(_StopSpec s, SehiriciMarkerIcon icon) =>
      'stp|${icon.id}|${icon.imageCacheKey}|${_detail.name}|${s.state.name}|'
      '${s.isStart ? 1 : 0}${s.isEnd ? 1 : 0}|'
      '${s.colors.map((c) => c.toARGB32().toRadixString(16)).join('-')}';

  String _vehicleIconKey(SehiriciMarkerIcon icon, SehiriciLine line) =>
      'veh|${icon.id}|${icon.imageCacheKey}|${line.colorHex}|'
      '${_vehicleScale.toStringAsFixed(2)}';

  String _tripLabelKey(SehiriciActiveTrip trip, SehiriciLine line) =>
      'lbl|${trip.tripId}|${_tripLabelBadge(trip, line)}|${line.colorHex}|'
      '${_vehicleScale.toStringAsFixed(2)}';

  String _stopLabelKey(_StopSpec s, SehiriciResolvedMarker icon) =>
      'stl|${s.name}|${_labelDark ? 1 : 0}|'
      '${icon.halfWidth.toStringAsFixed(0)}|${icon.labelLift.toStringAsFixed(0)}';

  /// Etiket yazısının koyu haritada mı (koyu stil ya da uydu) çizileceği.
  bool get _labelDark => _darkSurface;

  /// Hattın kodu (etiketin sağ bölümü). Kod yoksa boş.
  String _tripLabelBadge(SehiriciActiveTrip trip, SehiriciLine line) =>
      (trip.lineCode.isNotEmpty ? trip.lineCode : line.code).trim();

  Future<void> _ensureIcon(
    String key,
    Future<SehiriciResolvedMarker> Function() make,
  ) {
    if (_resolved.containsKey(key)) return Future<void>.value();
    // DİKKAT: whenComplete geri çağrısı bir Future dönerse sonuç onu BEKLER.
    // `() => map.remove(key)` yazmak, kendi sonucu olan Future'ı döndürüp
    // sonsuza dek asılı kalırdı; bu yüzden süslü parantezli gövde şart.
    return _pendingIcons[key] ??= make().then((r) {
      _resolved[key] = r;
    }).catchError((Object e) {
      debugPrint('SehiriciLiveMap ikon çözülemedi ($key): $e');
    }).whenComplete(() {
      _pendingIcons.remove(key);
    });
  }

  /// Gerekli tüm bitmap'leri (durak, araç, etiket, ok, konum, kurye) çözer ve
  /// hazır olunca marker'ları BİR KEZ yeniden kurar. Üst üste çağrılırsa yalnız
  /// sonuncusu marker'ları kurar (eskiler bitmap'i önbelleğe koyup çıkar).
  Future<void> _refreshIcons() async {
    if (!mounted) return;
    final generation = ++_iconGeneration;
    final jobs = <Future<void>>[];

    final stopIcon = _catalog.stopIcon;
    for (final spec in _computeStopSpecs()) {
      jobs.add(_ensureIcon(
        _stopIconKey(spec, stopIcon),
        () => SehiriciMarkerBitmaps.stop(
          stopIcon,
          detail: _detail,
          state: spec.state,
          lineColors: spec.colors,
          isStart: spec.isStart,
          isEnd: spec.isEnd,
        ),
      ));
    }

    for (final trip in widget.activeTrips) {
      final line = _lineFor(trip);
      final vehicle = _catalog.resolveVehicle(line.vehicleKey);
      final vKey = _vehicleIconKey(vehicle, line);
      final lKey = _tripLabelKey(trip, line);
      jobs.add(() async {
        await _ensureIcon(
          vKey,
          () => SehiriciMarkerBitmaps.vehicle(
            vehicle,
            line.color,
            scale: _vehicleScale,
          ),
        );
        final v = _resolved[vKey];
        if (v == null) return;
        await _ensureIcon(lKey, () async {
          final badge = _tripLabelBadge(trip, line);
          final bitmap = await MapMarkerIcons.label(
            text: 'ŞEHİRİÇİ',
            badge: badge.isEmpty ? null : badge,
            background: line.color,
            gap: v.halfHeight,
          );
          return SehiriciResolvedMarker(
            bitmap: bitmap,
            anchor: const Offset(0.5, 1.0),
            halfHeight: 0,
          );
        });
      }());
    }

    final highlight = _effectiveHighlightLine ??
        (widget.lines.length == 1 ? widget.lines.first : null);
    if (highlight != null) {
      jobs.add(_ensureIcon('arw|${highlight.colorHex}', () async {
        return SehiriciResolvedMarker(
          bitmap: await MapMarkerIcons.routeArrow(highlight.color),
          anchor: const Offset(0.5, 0.5),
          halfHeight: 0,
        );
      }));
    }

    jobs.add(_ensureIcon('usr', () async {
      return SehiriciResolvedMarker(
        bitmap: await MapMarkerIcons.userLocation(),
        anchor: const Offset(0.5, 0.5),
        halfHeight: 0,
      );
    }));

    if (widget.showCouriers) {
      jobs.add(_ensureIcon('courier', () async {
        final bitmap = await MapMarkerIcons.vehicle(
          shape: MapVehicleShape.motorcycle,
          color: _kCourierColor,
        );
        return SehiriciResolvedMarker(
          bitmap: bitmap,
          anchor: const Offset(0.5, 0.5),
          halfHeight:
              MapMarkerIcons.labelGapFor(MapVehicleShape.motorcycle),
        );
      }));
      jobs.add(_ensureIcon('courier_label', () async {
        final bitmap = await MapMarkerIcons.label(
          text: 'KURYE',
          background: _kCourierColor,
          gap: MapMarkerIcons.labelGapFor(MapVehicleShape.motorcycle),
        );
        return SehiriciResolvedMarker(
          bitmap: bitmap,
          anchor: const Offset(0.5, 1.0),
          halfHeight: 0,
        );
      }));
    }

    await Future.wait(jobs);
    if (!mounted || generation != _iconGeneration) return;

    // Durak adı etiketleri, durak ikonunun ölçüsüne (yarı genişlik, yükseklik)
    // bağlıdır; bu yüzden ikonlar çözüldükten SONRA üretilir.
    if (_stopLabels.value && _labelsVisible) {
      final labelJobs = <Future<void>>[];
      for (final spec in _computeStopSpecs()) {
        if (!_wantsLabel(spec)) continue;
        final icon = _resolved[_stopIconKey(spec, stopIcon)];
        if (icon == null) continue;
        labelJobs.add(_ensureIcon(_stopLabelKey(spec, icon), () async {
          final bitmap = await MapMarkerIcons.stopLabel(
            text: spec.name,
            dark: _labelDark,
            leftGap: icon.halfWidth + 4,
            lift: icon.labelLift,
          );
          return SehiriciResolvedMarker(
            bitmap: bitmap,
            anchor: Offset(0, icon.labelLift > 0 ? 1.0 : 0.5),
            halfHeight: 0,
          );
        }));
      }
      await Future.wait(labelJobs);
      if (!mounted || generation != _iconGeneration) return;
    }

    setState(() => _recompose(notify: false));
  }

  /// Bu durağın adı haritada yazılsın mı? Seçili durak her zaman; ayrıca
  /// vurgulu hattın (ya da tek hatlı haritada o hattın) durakları.
  bool _wantsLabel(_StopSpec spec) {
    if (!_stopLabels.value || !_labelsVisible) return false;
    if (spec.state == MapStopState.selected) return true;
    if (_effectiveHighlightId != null) return spec.onHighlightedLine;
    return widget.lines.length == 1 && spec.lines.isNotEmpty;
  }

  // ─────────────────────────────────────────────
  // Marker / polyline kurulumu
  // ─────────────────────────────────────────────

  /// Bütün marker ve çizgileri yeniden kurar (hat, vurgu, yakınlık değişince).
  void _rebuild() {
    _recompose(notify: false);

    if (_mapController != null && _initialFit) {
      _fitBounds();
    }

    // Ağır async işler (bitmap üretimi + sefer yolu) ilk frame'i bloklamadan,
    // ilk çizim sonrasına bırakılır.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshIcons();
      _loadInitialTripPaths();
    });
  }

  /// Çözülmüş bitmap'lerle marker/polyline kümelerini kurar. [notify] true ise
  /// setState çağırır (build fazı dışında).
  void _recompose({bool notify = true}) {
    if (!mounted) return;
    final markers = <Marker>{
      // Kullanıcı konumu bu kümeden bağımsız yönetilir; yeniden kurmada
      // silinmesin.
      ..._markers.where((m) => m.markerId.value == 'user_location'),
      ..._buildStopMarkers(),
      ..._buildStopLabelMarkers(),
      ..._buildRouteArrowMarkers(),
      ..._buildTripMarkers(),
      ..._courierMarkers(),
    };
    for (final trip in widget.activeTrips) {
      if (trip.currentLat == null || trip.currentLng == null) continue;
      _startPulseAnimation(trip.tripId, _lineFor(trip).color);
    }
    final polylines = <Polyline>{
      ..._polylines.where((p) =>
          p.polylineId.value == 'user_connector' ||
          p.polylineId.value.startsWith('trip_path_')),
      ..._buildRoutePolylines(),
    };

    void apply() {
      _markers = markers;
      _polylines = polylines;
    }

    if (notify) {
      setState(apply);
    } else {
      apply();
    }
  }

  /// Durak marker'ları: katalogdaki durak ikonu, hat renk plakası, ilk/son durak
  /// rozeti, seçili durak vurgusu.
  Set<Marker> _buildStopMarkers() {
    final markers = <Marker>{};
    final icon = _catalog.stopIcon;
    for (final spec in _computeStopSpecs()) {
      final resolved = _resolved[_stopIconKey(spec, icon)];
      if (resolved == null) continue; // bitmap hazır olunca eklenir
      markers.add(Marker(
        markerId: MarkerId('stop_${spec.id}'),
        position: spec.position,
        icon: resolved.bitmap,
        anchor: resolved.anchor,
        alpha: spec.dimmed ? 0.38 : 1.0,
        zIndexInt: spec.state == MapStopState.selected
            ? 6
            : (spec.state == MapStopState.terminal ? 3 : 2),
        consumeTapEvents: true,
        onTap: () => _onStopTapped(spec),
      ));
    }
    return markers;
  }

  /// Durak adı etiketleri (yakın zoom'da, seçili ya da vurgulu hat için).
  Set<Marker> _buildStopLabelMarkers() {
    if (!_stopLabels.value || !_labelsVisible) return const {};
    final markers = <Marker>{};
    final icon = _catalog.stopIcon;
    for (final spec in _computeStopSpecs()) {
      if (!_wantsLabel(spec)) continue;
      final iconResolved = _resolved[_stopIconKey(spec, icon)];
      if (iconResolved == null) continue;
      final label = _resolved[_stopLabelKey(spec, iconResolved)];
      if (label == null) continue;
      markers.add(Marker(
        markerId: MarkerId('stoplbl_${spec.id}'),
        position: spec.position,
        icon: label.bitmap,
        anchor: label.anchor,
        alpha: spec.dimmed ? 0.5 : 1.0,
        zIndexInt: 1,
        consumeTapEvents: true,
        onTap: () => _onStopTapped(spec),
      ));
    }
    return markers;
  }

  /// Bir hattın admin tarafından çizilmiş rota noktalarını döner. Yalnızca
  /// [SehiriciLine.roadPolyline] (yol takip eden) noktalarını kullanır; kuş
  /// uçuşu yedek YOKTUR (admin rota çizmedikçe yol görünmez).
  List<LatLng> _adminLinePath(SehiriciLine line) {
    final road = line.roadPolyline;
    if (road == null || road.length < 2) return const [];
    return road.map((p) => LatLng(p[0], p[1])).toList();
  }

  /// Hat çizgileri: altta beyaz/koyu "kasing", üstte hat rengi. Vurgulu hatta
  /// kalın ve tam opak; diğerleri ince ve soluk.
  Set<Polyline> _buildRoutePolylines() {
    if (!widget.showRoute) return const {};
    final polylines = <Polyline>{};
    final highlightId = _effectiveHighlightId;
    final hasHighlight = highlightId != null;
    final casing = _darkSurface ? const Color(0xFF0E1116) : Colors.white;
    for (final line in widget.lines) {
      final path = _adminLinePath(line);
      if (path.length < 2) continue;
      final isHl = highlightId == line.id;
      final width = isHl ? 7 : (hasHighlight ? 3 : 5);
      final alpha = isHl ? 1.0 : (hasHighlight ? 0.38 : 0.94);
      polylines.add(Polyline(
        polylineId: PolylineId('route_casing_${line.id}'),
        points: path,
        color: casing.withValues(alpha: hasHighlight && !isHl ? 0.28 : 0.92),
        width: width + 4,
        zIndex: isHl ? 2 : 1,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        consumeTapEvents: false,
      ));
      polylines.add(Polyline(
        polylineId: PolylineId('admin_route_${line.id}'),
        points: path,
        color: line.color.withValues(alpha: alpha),
        width: width,
        zIndex: isHl ? 4 : 3,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        consumeTapEvents: false,
      ));
    }
    return polylines;
  }

  /// Vurgulu (ya da tek) hattın rotası boyunca gidiş yönünü gösteren oklar.
  Set<Marker> _buildRouteArrowMarkers() {
    if (!widget.showRoute || !_arrowsVisible) return const {};
    final line = _effectiveHighlightLine ??
        (widget.lines.length == 1 ? widget.lines.first : null);
    if (line == null) return const {};
    final arrow = _resolved['arw|${line.colorHex}'];
    if (arrow == null) return const {};
    final path = _adminLinePath(line);
    if (path.length < 2) return const {};

    final spacing = _zoom >= 16.5 ? 170.0 : 280.0;
    final out = <Marker>{};
    var travelled = 0.0;
    var nextAt = spacing / 2;
    var index = 0;
    for (var i = 0; i < path.length - 1 && out.length < 90; i++) {
      final a = path[i];
      final b = path[i + 1];
      final seg = distanceMeters(a, b);
      if (seg <= 0) continue;
      final bearing = bearingDegrees(a, b) ?? 0;
      while (nextAt <= travelled + seg && out.length < 90) {
        final t = (nextAt - travelled) / seg;
        out.add(Marker(
          markerId: MarkerId('arrow_${line.id}_${index++}'),
          position: LatLng(
            a.latitude + (b.latitude - a.latitude) * t,
            a.longitude + (b.longitude - a.longitude) * t,
          ),
          icon: arrow.bitmap,
          anchor: arrow.anchor,
          rotation: bearing,
          flat: true,
          zIndexInt: 1,
          consumeTapEvents: false,
        ));
        nextAt += spacing;
      }
      travelled += seg;
    }
    return out;
  }

  // ─────────────────────────────────────────────
  // Sefer marker'ları
  // ─────────────────────────────────────────────

  SehiriciLine _lineFor(SehiriciActiveTrip trip) => widget.lines.firstWhere(
        (l) => l.id == trip.lineId,
        orElse: () => SehiriciLine(
          id: trip.lineId,
          code: trip.lineCode,
          name: trip.lineName,
          colorHex: trip.lineColor,
        ),
      );

  /// Marker'ın bakacağı yön. GPS heading varsa o kullanılır; yoksa son iki
  /// konum arasındaki gidiş yönü (bearing) hesaplanır — araç haritada
  /// gerçekten gittiği yöne bakar, kuzeye kilitli kalmaz.
  double _rotationFor(String tripId, SehiriciActiveTrip trip) {
    final heading = trip.currentHeading;
    if (heading != null && heading > 0) {
      _markerRotations[tripId] = heading;
      return heading;
    }
    final from = _previousPositions[tripId];
    final to = _targetPositions[tripId];
    if (from != null && to != null && calculateDistance(from, to) > 4) {
      final bearing = bearingDegrees(from, to);
      if (bearing != null) {
        _markerRotations[tripId] = bearing;
        return bearing;
      }
    }
    return _markerRotations[tripId] ?? 0;
  }

  /// Aktif sefer marker'ları: gövde (yönle döner) + üstünde dönmeyen etiket.
  Set<Marker> _buildTripMarkers() {
    final out = <Marker>{};
    final highlightId = _effectiveHighlightId;
    for (final trip in widget.activeTrips) {
      if (trip.currentLat == null || trip.currentLng == null) continue;
      final line = _lineFor(trip);
      final vehicle = _catalog.resolveVehicle(line.vehicleKey);
      final resolved = _resolved[_vehicleIconKey(vehicle, line)];
      if (resolved == null) continue; // bitmap hazır olunca eklenir
      // Marker'ın O ANDAKİ (animasyonlu) konumu: marker'lar ETA yenileme veya
      // ikon yükleme gibi sebeplerle animasyon ortasında yeniden kurulabiliyor.
      final position = _positionAnimations[trip.tripId]?.value ??
          _targetPositions[trip.tripId] ??
          LatLng(trip.currentLat!, trip.currentLng!);
      final dimmed = highlightId != null && highlightId != line.id;

      out.add(Marker(
        markerId: MarkerId('trip_${trip.tripId}'),
        position: position,
        icon: resolved.bitmap,
        anchor: resolved.anchor,
        consumeTapEvents: true,
        onTap: () => _showTripSheet(trip),
        rotation: _rotationFor(trip.tripId, trip),
        flat: true,
        alpha: dimmed ? 0.45 : 1.0,
        zIndexInt: 8,
      ));

      // Etiket ayrı marker: flat=false olduğu için harita/araç dönse de yazı
      // hep düz durur.
      final label = _resolved[_tripLabelKey(trip, line)];
      if (label != null) {
        out.add(Marker(
          markerId: MarkerId('trip_${trip.tripId}_label'),
          position: position,
          icon: label.bitmap,
          anchor: label.anchor,
          alpha: dimmed ? 0.55 : 1.0,
          zIndexInt: 9,
          consumeTapEvents: true,
          onTap: () => _showTripSheet(trip),
        ));
      }
    }
    return out;
  }

  /// Sadece araç marker'larını yeniden oluşturup setState eder
  void _rebuildTripMarkersOnly() {
    final markers = {
      ..._markers.where((m) => !m.markerId.value.startsWith('trip_')),
      ..._buildTripMarkers(),
    };
    setState(() => _markers = markers);
  }

  void _initializeTripData() {
    for (final trip in widget.activeTrips) {
      if (trip.currentLat != null && trip.currentLng != null) {
        _currentTripData[trip.tripId] = trip;
        _previousPositions[trip.tripId] =
            LatLng(trip.currentLat!, trip.currentLng!);
        _targetPositions[trip.tripId] =
            LatLng(trip.currentLat!, trip.currentLng!);
      }
    }
  }

  void _startLiveUpdates() {
    _liveUpdateTimer = Timer.periodic(
      Duration(seconds: widget.updateIntervalSeconds),
      (_) => _refreshTripPositions(),
    );
    // ETA güncelleme timer (her 60 saniyede bir — yalnız marker metinleri)
    _etaUpdateTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refreshETAs(),
    );
  }

  void _stopLiveUpdates() {
    _liveUpdateTimer?.cancel();
    _etaUpdateTimer?.cancel();
    _liveUpdateTimer = null;
    _etaUpdateTimer = null;
  }

  void _refreshTripPositions() {
    if (!mounted || widget.activeTrips.isEmpty) return;

    bool needsRedraw = false;
    bool headingChanged = false;

    for (final trip in widget.activeTrips) {
      if (trip.currentLat == null || trip.currentLng == null) continue;

      final newPosition = LatLng(trip.currentLat!, trip.currentLng!);
      final tripId = trip.tripId;
      final currentTarget = _targetPositions[tripId];

      // GPS gürültüsünün üstünde her hareket anında yansıtılır.
      if (currentTarget == null ||
          calculateDistance(currentTarget, newPosition) > _kMinMoveMeters) {
        _previousPositions[tripId] = currentTarget ?? newPosition;
        _targetPositions[tripId] = newPosition;
        _animateVehicleToPosition(tripId, newPosition);
        needsRedraw = true;
      }

      // Araç yerinde dönüyor olabilir: marker rotasyonu da güncellenmeli.
      final previousHeading = _currentTripData[tripId]?.currentHeading;
      if (previousHeading != trip.currentHeading) headingChanged = true;

      _currentTripData[tripId] = trip;
    }

    // Konum animasyonu marker'ı zaten taşıyor; yalnızca yön/ETA değiştiyse
    // marker'ları bir kez yeniden kur.
    if (headingChanged && !needsRedraw) {
      _rebuildTripMarkersOnly();
    }

    // Eski trip'leri temizle
    final currentTripIds = widget.activeTrips.map((t) => t.tripId).toSet();
    _previousPositions.removeWhere((key, _) => !currentTripIds.contains(key));
    _targetPositions.removeWhere((key, _) => !currentTripIds.contains(key));
    _currentTripData.removeWhere((key, _) => !currentTripIds.contains(key));

    // Seçili sefer için kullanıcıya olan bağlantı çizgisini/ETA'yı güncelle
    if ((needsRedraw || _selectedLineId != null) && _userPosition != null) {
      _rebuildUserOverlay();
    }
  }

  void _refreshETAs() {
    if (!mounted) return;
    _rebuildTripMarkersOnly();
  }

  void _animateVehicleToPosition(String tripId, LatLng targetPosition) {
    final existingController = _positionAnimControllers[tripId];
    if (existingController != null && existingController.isAnimating) {
      final currentPosition =
          _positionAnimations[tripId]?.value ?? targetPosition;
      _previousPositions[tripId] = currentPosition;
      existingController.stop();
    }

    // Geçiş süresi GERÇEK güncelleme aralığından türetilir: konum ~10 sn'de
    // bir geliyorsa araç iki nokta arasını 4 sn'ye kadar süzülerek geçer.
    final now = DateTime.now();
    final previousAt = _lastPositionAt[tripId];
    _lastPositionAt[tripId] = now;
    final gapMs =
        previousAt == null ? 900 : now.difference(previousAt).inMilliseconds;
    final durationMs = (gapMs * 0.9).round().clamp(700, 4000);

    final controller = AnimationController(
      duration: Duration(milliseconds: durationMs),
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

    // Eski controller sızmasın.
    _positionAnimControllers[tripId]?.dispose();
    _positionAnimControllers[tripId] = controller;
    _positionAnimations[tripId] = animation;

    controller.forward();
  }

  /// Animasyonun her karesinde aracı ve üstündeki etiketi taşır; araç
  /// marker'ının yönünü de gidiş yönüne çevirir.
  void _updateVehicleMarkerPosition(String tripId, LatLng position) {
    final vehicleId = 'trip_$tripId';
    final labelId = 'trip_${tripId}_label';
    final trip = _currentTripData[tripId];
    final rotation = trip == null ? null : _rotationFor(tripId, trip);
    _markers = _markers.map((marker) {
      final id = marker.markerId.value;
      if (id == vehicleId) {
        return marker.copyWith(
          positionParam: position,
          rotationParam: rotation,
        );
      }
      if (id == labelId) {
        return marker.copyWith(positionParam: position);
      }
      return marker;
    }).toSet();
  }

  // ── Nabız halkası ────────────────────────────────────────────

  /// Bir aracı pulse kümesine ekler. İdempotent'tir.
  void _startPulseAnimation(String tripId, Color pulseColor) {
    _pulseColors[tripId] = pulseColor;
    if (!_pulseController.isAnimating) {
      _pulseController.repeat();
    }
  }

  /// Shared pulse controller'ın her frame'inde bir kez çağrılır; ~20fps
  /// (3 frame'de bir) günceller.
  void _onPulseTick() {
    if (!mounted || !_isMapReady || _pulseColors.isEmpty) return;
    if (++_pulseFrame % 3 != 0) return;
    setState(_rebuildPulseCircles);
  }

  void _rebuildPulseCircles() {
    final others =
        _circles.where((c) => !c.circleId.value.startsWith('pulse_')).toSet();
    // Uzak zoom'da halka görünmez (metre cinsinden) ve boşuna harita günceller.
    if (_zoom >= 14.5) {
      final scale = _pulseAnimation.value;
      final fade = (1 - (scale - 1) / 1.4).clamp(0.0, 1.0);
      for (final entry in _pulseColors.entries) {
        // Nabız halkası aracın GÖSTERİLEN konumunda durmalı.
        final pos = _positionAnimations[entry.key]?.value ??
            _targetPositions[entry.key];
        if (pos == null) continue;
        others.add(Circle(
          circleId: CircleId('pulse_${entry.key}'),
          center: pos,
          radius: 14 * scale,
          fillColor: entry.value.withValues(alpha: 0.20 * fade),
          strokeColor: entry.value.withValues(alpha: 0.5 * fade),
          strokeWidth: 2,
          consumeTapEvents: false,
        ));
      }
    }
    _circles = others;
  }

  void _stopPulseAnimation(String tripId) {
    _pulseColors.remove(tripId);
    _circles =
        _circles.where((c) => c.circleId.value != 'pulse_$tripId').toSet();
    if (_pulseColors.isEmpty && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  void _handleTripChanges(List<SehiriciActiveTrip> oldTrips) {
    final oldTripIds = oldTrips.map((t) => t.tripId).toSet();
    final newTripIds = widget.activeTrips.map((t) => t.tripId).toSet();

    for (final trip in widget.activeTrips) {
      if (!oldTripIds.contains(trip.tripId)) {
        if (trip.currentLat != null && trip.currentLng != null) {
          _currentTripData[trip.tripId] = trip;
          _previousPositions[trip.tripId] =
              LatLng(trip.currentLat!, trip.currentLng!);
          _targetPositions[trip.tripId] =
              LatLng(trip.currentLat!, trip.currentLng!);
          _startPulseAnimation(trip.tripId, _lineFor(trip).color);
        }
      }
    }

    for (final tripId in oldTripIds.difference(newTripIds)) {
      _stopPulseAnimation(tripId);
      _positionAnimControllers[tripId]?.dispose();
      _positionAnimControllers.remove(tripId);
      _positionAnimations.remove(tripId);
      _previousPositions.remove(tripId);
      _targetPositions.remove(tripId);
      _currentTripData.remove(tripId);
      _lastPositionAt.remove(tripId);
      _markerRotations.remove(tripId);
      _tripPaths.remove(tripId);
      _tripPathSignatures.remove(tripId);
      _polylines = _polylines
          .where((p) => !p.polylineId.value.startsWith('trip_path_$tripId'))
          .toSet();
      // Takip edilen sefer bittiyse takip kartını kapat.
      if (_selectedTripId == tripId) {
        _selectedTripId = null;
        _selectedLine = null;
        _selectedLineId = null;
        _stopUserLocationStream();
      }
    }
  }

  // ── Şoförün geçtiği yol (isteğe bağlı) ───────────────────────

  /// Realtime: bir sefere yeni konum noktası eklendi.
  void _onTripPathPoint(String tripId, double lat, double lng) {
    final newPoint = LatLng(lat, lng);
    if (!isValidCoordinate(newPoint)) return;
    final list = _tripPaths.putIfAbsent(tripId, () => <LatLng>[]);
    if (list.isNotEmpty) {
      final last = list.last;
      if ((last.latitude - lat).abs() < 0.00001 &&
          (last.longitude - lng).abs() < 0.00001) {
        return;
      }
    }
    list.add(newPoint);
    if (list.length > kMaxRawTripPoints) {
      list.removeRange(0, list.length - kMaxRawTripPoints);
    }
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

  /// Aktif seferlerin şoförünün geçtiği yol noktalarını (konum geçmişi)
  /// sunucudan yükler.
  Future<void> _loadInitialTripPaths() async {
    if (!widget.showLiveTripPath) return;
    for (final trip in widget.activeTrips) {
      if (_tripPaths.containsKey(trip.tripId)) continue;
      if (_tripPathsLoading.contains(trip.tripId)) continue;
      _tripPathsLoading.add(trip.tripId);
      try {
        final path = await _tripService.getTripPath(trip.tripId);
        if (!mounted) return;
        var points = path.map((p) => LatLng(p.lat, p.lng)).toList();
        if (points.length > kMaxRawTripPoints) {
          points = points.sublist(points.length - kMaxRawTripPoints);
        }
        _tripPaths[trip.tripId] = points;
        _rebuildTripPathPolyline(trip);
      } catch (e) {
        debugPrint('_loadInitialTripPaths hata: $e');
      } finally {
        _tripPathsLoading.remove(trip.tripId);
      }
    }
  }

  /// Belirli bir seferin canlı yol polyline'ını haritaya ekler. Ham GPS
  /// geçmişi doğrudan çizilmez: [buildTripPathSegments] önce duruş bulutlarını
  /// ve aykırı fixleri temizler, ardından izi kopukluk noktalarından parçalara
  /// böler.
  void _rebuildTripPathPolyline(SehiriciActiveTrip trip) {
    final line = _lineFor(trip);
    final tripId = trip.tripId;
    final segments = buildTripPathSegments(_tripPaths[tripId] ?? const []);

    final signature = segments.isEmpty
        ? 'empty'
        : '${segments.length}:'
            '${segments.fold<int>(0, (sum, s) => sum + s.length)}:'
            '${segments.last.last.latitude},${segments.last.last.longitude}';
    if (_tripPathSignatures[tripId] == signature) return;
    _tripPathSignatures[tripId] = signature;

    final rebuilt = _polylines
        .where((p) => !p.polylineId.value.startsWith('trip_path_$tripId'))
        .toSet();
    for (var i = 0; i < segments.length; i++) {
      rebuilt.add(Polyline(
        polylineId: PolylineId('trip_path_${tripId}_$i'),
        points: segments[i],
        color: line.color,
        width: 4,
        consumeTapEvents: false,
      ));
    }
    setState(() => _polylines = rebuilt);
  }

  // ─────────────────────────────────────────────
  // Dokunuşlar → alt sayfalar
  // ─────────────────────────────────────────────

  SehiriciProvider? _providerOrNull() {
    try {
      return context.read<SehiriciProvider>();
    } catch (_) {
      return null;
    }
  }

  /// Duruğa dokunulunca: durağı vurgula ve varış süreli alt sayfayı aç.
  Future<void> _onStopTapped(_StopSpec spec) async {
    if (!mounted) return;
    setState(() => _selectedStopId = spec.id);
    _refreshIcons();

    final provider = _providerOrNull();
    final directions = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${spec.position.latitude},${spec.position.longitude}'
      '&travelmode=walking',
    );

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        Widget sheet() => SehiriciStopSheet(
              stopId: spec.id,
              name: spec.name,
              code: spec.code,
              address: spec.address,
              lines: spec.lines,
              trips: provider?.activeTrips ?? widget.activeTrips,
              isFavorite: (provider != null &&
                      provider.settings.allowUserFavorites &&
                      spec.lines.isNotEmpty)
                  ? provider.favoriteStopIds.contains(spec.id)
                  : null,
              onToggleFavorite: provider == null
                  ? null
                  : () => provider.toggleFavorite(spec.id),
              onLineTap: (line) {
                Navigator.of(ctx).pop();
                _onChipTap(line.id == _effectiveHighlightId ? null : line.id);
              },
              onDirections: () async {
                try {
                  await launchUrl(directions,
                      mode: LaunchMode.externalApplication);
                } catch (_) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text('Harita uygulaması açılamadı.'),
                    ));
                  }
                }
              },
            );
        // Sayfa açıkken canlı varış ve favori durumu güncel kalsın.
        return provider == null
            ? sheet()
            : ListenableBuilder(listenable: provider, builder: (_, __) => sheet());
      },
    );

    if (!mounted) return;
    setState(() => _selectedStopId = null);
    _refreshIcons();
  }

  /// Araca dokunulunca bilgi sayfası; "Takip et" ile seferi kilitler.
  void _showTripSheet(SehiriciActiveTrip trip) {
    final line = _lineFor(trip);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SehiriciTripSheet(
        trip: trip,
        line: line,
        following: _selectedTripId == trip.tripId,
        onFollow: () {
          Navigator.of(ctx).pop();
          _onTripTapped(trip);
        },
        onShowLine: () {
          Navigator.of(ctx).pop();
          if (_effectiveHighlightId != line.id) _onChipTap(line.id);
        },
      ),
    );
  }

  /// Kullanıcı bir araç ikonuna dokunup "Takip et" dediğinde: seferi hedef
  /// olarak kilitler ve aracın kendisine hangi hızla, kaç dakikada yaklaştığını
  /// gösterir. Sıradaki durak turuncu vurgulanır.
  Future<void> _onTripTapped(SehiriciActiveTrip trip) async {
    final line = _lineFor(trip);
    setState(() {
      _selectedLine = line;
      _selectedLineId = line.id;
      _selectedTripId = trip.tripId;
    });
    _refreshIcons();

    final lat = trip.currentLat;
    final lng = trip.currentLng;
    if (lat != null && lng != null) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(lat, lng), math.max(_zoom, 16)),
      );
    }

    if (_userPosition == null) {
      final ok = await _ensureUserLocation(source: 'Aracı takip etmek');
      if (!ok) return;
    }

    _startUserLocationStream();
    _rebuildUserOverlay();
  }

  // ─────────────────────────────────────────────
  // Kullanıcı konumu
  // ─────────────────────────────────────────────

  /// Harita açılışında konum otomatik İSTENMEZ (sistem diyaloğu açılmaz).
  /// Ancak kullanıcı daha önce izin verdiyse, harita açılır açılmaz sessizce
  /// son bilinen konumu çekip mavi "konumum" marker'ını gösterir.
  Future<void> _initUserLocationOnEntry() async {
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) return;

      if (!await LocationDisclosureService.isReady(LocationPurpose.nearby)) {
        return;
      }

      Position? pos;
      try {
        pos = await Geolocator.getLastKnownPosition();
      } catch (_) {
        pos = null;
      }
      pos ??= await _tryGetCurrentFast();

      if (!mounted || pos == null) return;
      setState(() => _userPosition = pos);
      _rebuildUserOverlay();
    } catch (_) {
      // Herhangi bir hata — kullanıcıyı rahatsız etmeden sessizce geç.
    }
  }

  /// 6 saniyelik kısa zaman limitiyle mevcut konumu almaya çalışır.
  Future<Position?> _tryGetCurrentFast() async {
    try {
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

  /// Kullanıcı haritanın boş bir noktasına dokunduğunda çağrılır. Konum servisi
  /// kapalıysa uyarı bandını gösterir — otomatik değil, etkileşimden sonra.
  void _onMapTapped(LatLng _) {
    _checkLocationServiceAndShowBanner();
  }

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

  /// Kullanıcı bir aksiyonu (buton, araç takibi) sonucu konum istediğinde
  /// çağrılır. İzin verilmişse sessizce konum alır; verilmemişse sistem
  /// diyaloğunu açar. Sonuca göre uygun SnackBar/eylem gösterir.
  Future<bool> _ensureUserLocation({String source = 'konum'}) async {
    final result = await SehiriciUserLocation.requestCurrent(context);
    if (!mounted) return false;
    final newPos = result.position;

    switch (result.outcome) {
      case _LocationOutcome.granted:
        if (newPos != null) {
          setState(() => _userPosition = newPos);
        }
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
        if (!_locationServiceOff) {
          setState(() => _locationServiceOff = true);
        }
        return false;
    }
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

  /// Takibi bırakır: ETA kartını, kullanıcı bağlantı çizgisini ve turuncu
  /// "sıradaki durak" vurgusunu kaldırır.
  void _clearSelectedLine() {
    setState(() {
      _selectedLine = null;
      _selectedLineId = null;
      _selectedTripId = null;
      _draggedPosition = null;
      _markers =
          _markers.where((m) => m.markerId.value != 'user_location').toSet();
      _polylines = _polylines
          .where((p) => p.polylineId.value != 'user_connector')
          .toSet();
    });
    _stopUserLocationStream();
    _refreshIcons();
  }

  /// Seçili hattaki, kullanıcıya en yakın aktif seferi bulur.
  SehiriciActiveTrip? _nearestTripForLine(String lineId, LatLng userLatLng) {
    final trips = widget.activeTrips
        .where((t) =>
            t.lineId == lineId && t.currentLat != null && t.currentLng != null)
        .toList();
    if (trips.isEmpty) return null;
    trips.sort((a, b) {
      final da =
          calculateDistance(userLatLng, LatLng(a.currentLat!, a.currentLng!));
      final db =
          calculateDistance(userLatLng, LatLng(b.currentLat!, b.currentLng!));
      return da.compareTo(db);
    });
    return trips.first;
  }

  /// Bir araç takip ediliyorsa o sefere kilitlenir; yalnız hat seçiliyse
  /// kullanıcıya en yakın seferi bulur.
  SehiriciActiveTrip? _targetTripForSelection(LatLng userLatLng) {
    if (_selectedTripId != null) {
      final matches = widget.activeTrips.where((t) =>
          t.tripId == _selectedTripId &&
          t.currentLat != null &&
          t.currentLng != null);
      if (matches.isEmpty) return null;
      return matches.first;
    }
    if (_selectedLineId != null) {
      return _nearestTripForLine(_selectedLineId!, userLatLng);
    }
    return null;
  }

  /// Seçili sefer/hat için kullanıcıya olan mesafe, hız ve ETA bilgisi.
  /// Sürüklenen konum varsa onu, yoksa gerçek konumu kullanır.
  ({SehiriciActiveTrip trip, int distanceMeters, int etaMinutes, double? speedKmh})?
      _selectedLineEta() {
    if (_userPosition == null ||
        (_selectedLineId == null && _selectedTripId == null)) {
      return null;
    }
    final userLatLng = _draggedPosition ??
        LatLng(_userPosition!.latitude, _userPosition!.longitude);
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

  /// Kullanıcı konum marker'ını ve seçili sefere giden bağlantı çizgisini
  /// günceller. Marker sürüklenebilirdir (uzaktan "buradan binsem" senaryosu).
  void _rebuildUserOverlay() {
    if (_userPosition == null || !mounted) return;
    final userLatLng = _draggedPosition ??
        LatLng(_userPosition!.latitude, _userPosition!.longitude);

    final isDraggable = _selectedLineId != null || _selectedTripId != null;
    final userIcon = _resolved['usr']?.bitmap ??
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);

    final markers = {
      ..._markers.where((m) => m.markerId.value != 'user_location'),
      Marker(
        markerId: const MarkerId('user_location'),
        position: userLatLng,
        icon: userIcon,
        anchor: const Offset(0.5, 0.5),
        zIndexInt: 7,
        draggable: isDraggable,
        onDrag: (LatLng pos) {
          if (mounted) setState(() => _draggedPosition = pos);
        },
        onDragEnd: (LatLng newPos) {
          if (mounted) setState(() => _draggedPosition = newPos);
        },
        consumeTapEvents: !isDraggable,
        infoWindow: InfoWindow(
          title: isDraggable ? 'Konumum (sürükleyebilirsiniz)' : 'Konumum',
        ),
      ),
    };

    var polylines = _polylines
        .where((p) => p.polylineId.value != 'user_connector')
        .toSet();
    if (_selectedLineId != null || _selectedTripId != null) {
      final trip = _targetTripForSelection(userLatLng);
      if (trip != null) {
        polylines = {
          ...polylines,
          Polyline(
            polylineId: const PolylineId('user_connector'),
            points: [userLatLng, LatLng(trip.currentLat!, trip.currentLng!)],
            color: const Color(0xFF16A34A),
            width: 3,
            zIndex: 5,
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
  }

  // ─────────────────────────────────────────────
  // Kamera
  // ─────────────────────────────────────────────

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
      // engeller).
      await _mapController!.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: target,
            zoom: widget.zoomLevel.toDouble(),
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

  LatLngBounds _boundsFromLatLngList(List<LatLng> list) {
    double minLat = list.first.latitude, maxLat = list.first.latitude;
    double minLng = list.first.longitude, maxLng = list.first.longitude;
    for (final p in list) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  /// Verilen noktaları kapsayacak biçimde kamerayı animasyonla götürür. Tek
  /// nokta ya da sıfır alanlı sınırlarda (plugin hata verir) zoom'a düşer.
  Future<void> _animateToPoints(List<LatLng> points, {double padding = 70}) async {
    final ctl = _mapController;
    if (ctl == null || points.isEmpty) return;
    try {
      final bounds = _boundsFromLatLngList(points);
      final degenerate = bounds.southwest.latitude == bounds.northeast.latitude ||
          bounds.southwest.longitude == bounds.northeast.longitude;
      if (points.length == 1 || degenerate) {
        await ctl.animateCamera(CameraUpdate.newLatLngZoom(points.first, 17));
      } else {
        await ctl.animateCamera(CameraUpdate.newLatLngBounds(bounds, padding));
      }
    } catch (_) {
      // Harita henüz ölçülmediyse (ilk kare) kamera güncellemesi reddedilebilir.
    }
  }

  /// Vurgulanan hattın rotasına (yoksa duraklarına) haritayı sığdırır.
  Future<void> _fitToHighlightedLine() async {
    final line = _effectiveHighlightLine;
    if (line == null) return;
    final path = _adminLinePath(line);
    if (path.length >= 2) {
      await _animateToPoints(path, padding: 80);
    } else if (line.stops.isNotEmpty) {
      await _animateToPoints(
        line.stops.map((s) => LatLng(s.lat, s.lng)).toList(),
        padding: 80,
      );
    }
  }

  /// Şehri (durak + rota + sefer) tek bakışta gösterir.
  Future<void> _fitAll() async {
    final points = <LatLng>[
      for (final line in widget.lines) ...[
        for (final s in line.stops) LatLng(s.lat, s.lng),
        ..._adminLinePath(line),
      ],
      for (final s in _standaloneStops) LatLng(s.lat, s.lng),
      for (final t in widget.activeTrips)
        if (t.currentLat != null && t.currentLng != null)
          LatLng(t.currentLat!, t.currentLng!),
    ];
    if (points.isEmpty) {
      await _mapController?.animateCamera(CameraUpdate.newLatLngZoom(
        LatLng(widget.center.centerLat, widget.center.centerLng),
        widget.zoomLevel.toDouble(),
      ));
      return;
    }
    await _animateToPoints(points, padding: 60);
  }

  Future<void> _recenterToUser() async {
    if (_mapController == null) return;

    // Kullanıcı konum butonuna BASMIŞ olabilir — daha önce konum alınmadıysa
    // burada izin istenir (sistem diyaloğu açılır).
    if (_userPosition == null) {
      final ok = await _ensureUserLocation(source: 'Konumuma git');
      if (!ok) return;
      if (_userPosition == null) return;
      _rebuildUserOverlay();
    }

    final pos = _userPosition!;
    await _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 16),
    );
  }

  void _showLayersSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SehiriciMapLayersSheet(
        traffic: _traffic,
        stopLabels: _stopLabels,
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Kuryeler (role='courier') — seferden bağımsız canlı konum
  // ─────────────────────────────────────────────

  /// Kuryeleri CourierStreamService üzerinden dinler. Kurye sonradan gelirse
  /// marker eklenir ama kamera kaydırılmaz.
  Future<void> _startCourierTracking() async {
    void onChange(Map<String, CourierInfo> snap) {
      if (!mounted) return;
      _couriers = snap;
      _startCourierMoveAnimation(snap);
      _rebuildCourierMarkersOnly();
    }

    _courierListener = onChange;
    CourierStreamService().subscribe(onChange);
  }

  /// Kurye marker'larını cache'lenen `_couriers`'den üretir: kuşbakışı
  /// motosiklet gövdesi (yönle döner) + üstünde dönmeyen "KURYE" etiketi.
  Set<Marker> _courierMarkers() {
    if (!widget.showCouriers || _couriers.isEmpty) return const {};
    final icon = _resolved['courier'];
    final label = _resolved['courier_label'];
    if (icon == null) return const {};
    final out = <Marker>{};
    for (final c in _couriers.values) {
      final position = _courierDisplayPosition(c.id) ?? LatLng(c.lat, c.lng);
      out.add(Marker(
        markerId: MarkerId('courier_${c.id}'),
        position: position,
        icon: icon.bitmap,
        anchor: icon.anchor,
        rotation: c.heading ?? 0,
        flat: true,
        zIndexInt: 5,
        consumeTapEvents: true,
        onTap: () => _showCourierSheet(c),
      ));
      if (label != null) {
        out.add(Marker(
          markerId: MarkerId('courier_${c.id}_label'),
          position: position,
          icon: label.bitmap,
          anchor: label.anchor,
          zIndexInt: 6,
          consumeTapEvents: true,
          onTap: () => _showCourierSheet(c),
        ));
      }
    }
    return out;
  }

  void _rebuildCourierMarkersOnly() {
    final markers = {
      ..._markers.where((m) => !m.markerId.value.startsWith('courier_')),
      ..._courierMarkers(),
    };
    setState(() => _markers = markers);
  }

  /// Kurye snapshot'ı geldiğinde marker'ları eski konumdan yenisine süzer.
  void _startCourierMoveAnimation(Map<String, CourierInfo> next) {
    final from = <String, LatLng>{};
    final to = <String, LatLng>{};
    for (final c in next.values) {
      final target = LatLng(c.lat, c.lng);
      final shown = _courierDisplayPosition(c.id) ?? target;
      from[c.id] = shown;
      to[c.id] = target;
    }
    _courierFrom
      ..clear()
      ..addAll(from);
    _courierTo
      ..clear()
      ..addAll(to);
    if (_courierTo.isEmpty) {
      _courierMoveController.stop();
      return;
    }
    _courierMoveController.forward(from: 0);
  }

  /// Kuryenin o an haritada gösterilen (animasyonlu) konumu.
  LatLng? _courierDisplayPosition(String id) {
    final to = _courierTo[id];
    if (to == null) return null;
    final from = _courierFrom[id];
    if (from == null) return to;
    final t = _courierMoveController.value;
    if (t >= 1) return to;
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
  }

  /// Kurye hareket animasyonunun her karesi (~20 fps).
  void _onCourierMoveTick() {
    if (!mounted || !_isMapReady || _courierTo.isEmpty) return;
    if (++_courierMoveFrame % 3 != 0 && _courierMoveController.value < 1.0) {
      return;
    }
    _rebuildCourierMarkersOnly();
  }

  /// Kurye marker'ına dokunulduğunda bilgi kartı gösterir. Kullanıcı konumu
  /// biliniyorsa kuryeye olan mesafe ve tahmini varış da hesaplanır.
  void _showCourierSheet(CourierInfo courier) {
    final hasUserPos = _userPosition != null;
    int? distMeters;
    int? etaMinutes;
    if (hasUserPos) {
      final userLatLng = _draggedPosition ??
          LatLng(_userPosition!.latitude, _userPosition!.longitude);
      distMeters = calculateDistance(
        userLatLng,
        LatLng(courier.lat, courier.lng),
      ).round();
      // Kurye ortalaması kentsel motor: ~25 km/sa.
      etaMinutes = calculateETA(distMeters, speedKmh: 25.0);
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SehiriciSheetFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _kCourierColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.two_wheeler_rounded,
                      color: _kCourierColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        courier.name,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800),
                      ),
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
    final dt = time.toLocal();
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'az önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} sa önce';
    return '${diff.inDays} gün önce';
  }

  // ─────────────────────────────────────────────
  // Arayüz
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Harita görünümü tercihi (Otomatik/Açık/Koyu) ve harita türü (Standart/
    // Uydu) değişince anında yeniden çizilsin.
    return MapStyleBuilder(
      builder: (context, mapStyle) => ValueListenableBuilder<MapBaseType>(
        valueListenable: MapTypePreference.choice,
        builder: (context, baseType, _) =>
            _buildMapSurface(context, mapStyle, baseType),
      ),
    );
  }

  Widget _buildMapSurface(
    BuildContext context,
    String mapStyle,
    MapBaseType baseType,
  ) {
    final satellite = baseType == MapBaseType.satellite;
    final darkSurface = satellite || mapStyle == AppMapStyle.dark;
    if (darkSurface != _darkSurface) {
      // Kasing rengi ve durak adı yazısı zemine göre değişir.
      _darkSurface = darkSurface;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshIcons();
      });
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pad = widget.overlayPadding;

    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 330;
            return Stack(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: _traffic,
                  builder: (context, traffic, _) => GoogleMap(
                    // Uygulama geneli modern harita stili + kullanıcının
                    // görünüm tercihi (bkz. MapThemePreference).
                    style: mapStyle,
                    initialCameraPosition: CameraPosition(
                      target: LatLng(
                          widget.center.centerLat, widget.center.centerLng),
                      zoom: widget.zoomLevel.toDouble(),
                    ),
                    onMapCreated: (c) {
                      _mapController = c;
                      _isMapReady = true;
                      // İlk odaklamayı anında, animasyonsuz yap.
                      if (_markers.isNotEmpty && _initialFit) {
                        _fitBounds();
                      }
                    },
                    onCameraMove: _onCameraMove,
                    onCameraIdle: _onCameraIdle,
                    markers: _markers,
                    polylines: _polylines,
                    circles: _circles,
                    trafficEnabled: traffic,
                    zoomControlsEnabled: false,
                    myLocationButtonEnabled: false,
                    compassEnabled: false,
                    mapToolbarEnabled: false,
                    scrollGesturesEnabled: widget.interactive,
                    zoomGesturesEnabled: widget.interactive,
                    rotateGesturesEnabled: widget.interactive,
                    // Düz (2D) harita: eğim hareketi ve 3D bina kabartması kapalı.
                    tiltGesturesEnabled: false,
                    buildingsEnabled: false,
                    mapType: satellite ? MapType.hybrid : MapType.normal,
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
                    // Boş haritaya dokunulunca: konum servisi kapalıysa banner.
                    onTap: _onMapTapped,
                  ),
                ),
                // Üst: canlı durum hapı + hat çipleri (yalnız etkileşimli haritada)
                if (widget.interactive)
                  Positioned(
                    top: 10 + pad.top,
                    left: 10,
                    right: 62,
                    child: _buildTopOverlay(isDark, compact),
                  ),
                // Konum servisi kapalı uyarı banner'ı
                if (_locationServiceOff)
                  Positioned(
                    top: (widget.interactive ? 58 : 10) + pad.top,
                    left: 10,
                    right: 10,
                    child: _buildLocationServiceOffBanner(isDark),
                  ),
                // Yüzen modern kontroller
                if (widget.interactive)
                  Positioned(
                    right: 10,
                    top: 10 + pad.top,
                    child: _buildMapControls(compact),
                  ),
                if (_selectedLine != null)
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10 + pad.bottom,
                    child: _buildLineEtaCard(isDark),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Sol üst: "CANLI · N araç" hapı ve (isteğe bağlı) hat çipleri.
  Widget _buildTopOverlay(bool isDark, bool compact) {
    final count = widget.activeTrips.length;
    final live = count > 0;
    final showChips = widget.showLineChips && widget.lines.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MapGlassPanel(
          radius: 20,
          padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SehiriciLiveDot(
                color: live ? const Color(0xFF22C55E) : Colors.grey,
                pulsing: live,
              ),
              Text(
                live ? 'CANLI' : 'SEFER YOK',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                  color: live
                      ? const Color(0xFF16A34A)
                      : (isDark ? Colors.white70 : Colors.black54),
                ),
              ),
              if (live) ...[
                const SizedBox(width: 6),
                Text(
                  '$count araç',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1F2937),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (showChips && !compact) ...[
          const SizedBox(height: 8),
          _buildLineChips(isDark),
        ],
      ],
    );
  }

  /// Yatay kaydırmalı hat çipleri: hat rengi + kodu; dokununca hattı vurgular.
  Widget _buildLineChips(bool isDark) {
    final highlightId = _effectiveHighlightId;
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.lines.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, i) {
          final line = widget.lines[i];
          final selected = highlightId == line.id;
          final dimmed = highlightId != null && !selected;
          return GestureDetector(
            onTap: () => _onChipTap(line.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.fromLTRB(5, 4, 12, 4),
              decoration: BoxDecoration(
                color: selected
                    ? line.color
                    : (isDark ? const Color(0xFF12151A) : Colors.white)
                        .withValues(alpha: dimmed ? 0.6 : 0.92),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected
                      ? line.color
                      : (isDark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.10),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SehiriciLineBadge(
                    code: line.code,
                    color: selected ? Colors.white : line.color,
                    height: 26,
                    minWidth: 32,
                  ),
                  const SizedBox(width: 7),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: Text(
                      line.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? sehiriciOnColor(line.color)
                            : (isDark ? Colors.white : const Color(0xFF1F2937)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Yüzen cam kontroller: katmanlar, konumuma git, tümünü göster, zoom +/-.
  /// Küçük haritada (kompakt) zoom düğmeleri gizlenir — iki parmakla yakınlaşılır.
  Widget _buildMapControls(bool compact) {
    return MapGlassControls(
      children: [
        MapGlassButton(
          icon: Icons.layers_rounded,
          tooltip: 'Harita katmanları',
          onPressed: _showLayersSheet,
        ),
        MapGlassButton(
          icon: Icons.my_location,
          tooltip: 'Konumuma git',
          onPressed: _recenterToUser,
        ),
        MapGlassButton(
          icon: Icons.zoom_out_map_rounded,
          tooltip: 'Tümünü göster',
          onPressed: _fitAll,
        ),
        if (!compact) ...[
          MapGlassButton(
            icon: Icons.add,
            tooltip: 'Yakınlaştır',
            onPressed: () =>
                _mapController?.animateCamera(CameraUpdate.zoomIn()),
          ),
          MapGlassButton(
            icon: Icons.remove,
            tooltip: 'Uzaklaştır',
            onPressed: () =>
                _mapController?.animateCamera(CameraUpdate.zoomOut()),
          ),
        ],
      ],
    );
  }

  /// Cihazın konum servisi kapalıyken harita üstünde gösterilen uyarı
  /// banner'ı. "Aç" butonuyla kullanıcıyı doğrudan cihazın konum ayarlarına
  /// gönderebilir; kapat (×) yalnızca banner'ı gizler.
  Widget _buildLocationServiceOffBanner(bool isDark) {
    return Material(
      color: Colors.transparent,
      child: MapGlassPanel(
        radius: 14,
        opacity: 0.94,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.location_off, color: Color(0xFFF59E0B), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Konum servisi kapalı',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: isDark ? Colors.white : const Color(0xFF1F2937),
                ),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFD97706),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
              child: const Text('Aç',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            ),
            IconButton(
              icon: Icon(Icons.close,
                  size: 18, color: isDark ? Colors.white70 : Colors.black54),
              onPressed: () => setState(() => _locationServiceOff = false),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'Bildirimi kapat',
            ),
          ],
        ),
      ),
    );
  }

  /// Takip edilen sefer için canlı ETA/mesafe kartı (cam efektli).
  Widget _buildLineEtaCard(bool isDark) {
    final line = _selectedLine!;
    final eta = _selectedLineEta();
    final hasEta = eta != null;
    final ink = isDark ? Colors.white : const Color(0xFF1F2937);
    return MapGlassPanel(
      radius: 20,
      opacity: isDark ? 0.82 : 0.92,
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 52,
            decoration: BoxDecoration(
              color: line.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
            ),
            alignment: Alignment.center,
            child: SehiriciVehicleIcon.forLine(line, height: 44),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SehiriciStatusPill(
                      label: hasEta ? 'CANLI TAKİP' : 'BEKLENİYOR',
                      color: hasEta ? const Color(0xFF16A34A) : Colors.grey,
                      dense: true,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${line.code} — ${line.name}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: ink,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
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
                    color: hasEta ? const Color(0xFF16A34A) : Colors.grey,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 21, color: ink),
            onPressed: _clearSelectedLine,
            visualDensity: VisualDensity.compact,
            tooltip: 'Takibi bırak',
          ),
        ],
      ),
    );
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
  static Future<({Position? position, _LocationOutcome outcome})>
      requestCurrent(BuildContext context) async {
    try {
      // 1) Konum servisi açık mı?
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return (position: null, outcome: _LocationOutcome.serviceOff);
      }

      // 2) Prominent Disclosure ekranı + sistem izni. Bu metot sadece
      //    kullanıcının butona basmasıyla tetiklenir; harita açılışında
      //    çağrılmaz. Onay ve izin zaten varsa hiçbir ekran gösterilmez.
      if (!context.mounted) {
        return (position: null, outcome: _LocationOutcome.denied);
      }
      final allowed = await LocationDisclosureService.ensure(
        context,
        LocationPurpose.nearby,
      );
      if (!allowed) {
        return (position: null, outcome: _LocationOutcome.denied);
      }

      // 3) İzin verildi — konumu al
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
