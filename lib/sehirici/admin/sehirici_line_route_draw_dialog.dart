// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_map_style.dart';
import '../../core/utils/map_marker_icons.dart';
import '../../core/widgets/map_controls.dart';
import '../../features/admin/widgets/admin_ui.dart';
import '../models/sehirici_models.dart';
import '../providers/sehirici_provider.dart';
import '../services/sehirici_errors.dart';
import '../services/sehirici_line_service.dart';
import '../services/sehirici_road_snap_service.dart';
import '../utils/sehirici_route_geometry.dart';
import '../widgets/sehirici_common_widgets.dart';
import 'sehirici_admin_controller.dart';
import 'sehirici_admin_kit.dart';

/// Admin için harita üzerinde hat rotası çizme ekranı.
///
/// • Haritaya dokunarak nokta eklenir; noktalar sürüklenebilir.
/// • "Çiz" modunda uzun basılıp sürüklenerek serbest rota çizilir
///   (Douglas-Peucker ile 3 m toleranslı sadeleştirme uygulanır).
/// • Yan panelde sıralı nokta listesi (sürükle-bırak ile yeniden sırala, sil,
///   buradan sona/baştan buraya kırp).
/// • Araç çubuğu: Geri al · Temizle · Çiz · Odakla · Duraklardan · Son
///   seferden · Rotayı sil.
/// • Alt özet: nokta sayısı, toplam km, tahmini süre ve Kaydet.
/// • Çıkışta kaydedilmemiş değişiklik uyarısı.
///
/// Diyalog, rota kaydedildiyse/silindiyse `true` döner.

/// Çizim modu: tıkla-tıkla mı, parmakla çiz mi.
enum MapDrawMode { click, draw }

/// Nokta listesindeki bir noktadan itibaren rota kırpma yönü.
enum _PointTrimAction { trimFromStart, trimToEnd }

class SehiriciLineRouteDrawDialog extends StatefulWidget {
  final SehiriciLine line;

  /// Verilirse servisler paylaşılır (testlerde sahte servis vermek için).
  final SehiriciAdminController? controller;

  const SehiriciLineRouteDrawDialog({
    super.key,
    required this.line,
    this.controller,
  });

  @override
  State<SehiriciLineRouteDrawDialog> createState() =>
      _SehiriciLineRouteDrawDialogState();
}

class _SehiriciLineRouteDrawDialogState
    extends State<SehiriciLineRouteDrawDialog> {
  /// Haritada aynı anda gösterilecek en çok nokta işaretçisi. Bir yol rotası
  /// yüzlerce/binlerce nokta içerebilir; her biri için ayrı bir işaretçi
  /// çizmek haritayı boğuyor ve donduruyordu. Fazlası seyreltilir (çizgi yine
  /// tüm noktalardan geçer).
  static const int _maxPointMarkers = 160;

  late final SehiriciLineService _service =
      widget.controller?.lineService ?? SehiriciLineService();
  late final SehiriciRoadSnapService _roadSnapService =
      widget.controller?.roadSnapService ?? SehiriciRoadSnapService();
  final Completer<GoogleMapController> _mapCtl =
      Completer<GoogleMapController>();

  /// Kullanıcının çizdiği noktalar (polyline).
  final List<LatLng> _points = [];

  /// Hat durakları (referans).
  List<SehiriciLineStop> _lineStops = const [];

  bool _loading = true;
  bool _saving = false;
  bool _loadingProposal = false;
  bool _dirty = false;

  /// Kaydedildi ya da sunucudan silindi: kapanırken `true` döner.
  bool _changed = false;

  /// Sunucuda kayıtlı bir rota var mı ("Kayıtlı rotayı sil" için).
  late bool _hasSavedRoute = widget.line.hasRoute;
  MapDrawMode _mode = MapDrawMode.click;
  bool _drawing = false;

  // Çiz sırasında ardışık çok yakın nokta eklemeyi önlemek için min mesafe.
  static const double _drawMinStepMeters = 2.0;
  // Çizim bittiğinde sadeleştirme toleransı.
  static const double _drawToleranceMeters = 3.0;

  LatLng _initialTarget = const LatLng(37.0, 41.0);
  double _initialZoom = 13;

  // Yan panel genişliği (geniş ekranda).
  static const double _sidePanelWidth = 320;

  // İşaretçi bitmap'leri (async üretilir).
  BitmapDescriptor? _midDot;
  BitmapDescriptor? _startDot;
  BitmapDescriptor? _endDot;
  final Map<int, BitmapDescriptor> _stopPins = {};

  /// Harita üstünde kısa süre görünen bildirim (SnackBar diyaloğun ARKASINDA
  /// kalırdı).
  String? _notice;
  bool _noticeIsError = false;
  Timer? _noticeTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _loadIcons();
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    super.dispose();
  }

  void _say(String message, {bool error = false}) {
    _noticeTimer?.cancel();
    setState(() {
      _notice = message;
      _noticeIsError = error;
    });
    _noticeTimer = Timer(Duration(seconds: error ? 6 : 4), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  Future<void> _loadIcons() async {
    final color = widget.line.color;
    final mid = await MapMarkerIcons.routePoint(color: color, size: 13);
    final start = await MapMarkerIcons.routePoint(
        color: const Color(0xFF16A34A), size: 19, filled: true);
    final end = await MapMarkerIcons.routePoint(
        color: const Color(0xFFDC2626), size: 19, filled: true);
    if (!mounted) return;
    setState(() {
      _midDot = mid;
      _startDot = start;
      _endDot = end;
    });
    await _ensureStopPins();
  }

  Future<void> _ensureStopPins() async {
    var changed = false;
    for (var n = 1; n <= _lineStops.length; n++) {
      if (_stopPins.containsKey(n)) continue;
      _stopPins[n] =
          await MapMarkerIcons.numberedPin(number: n, color: widget.line.color);
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Hattın yüklü durakları varsa onlar kullanılır (ağ isteği yok); yoksa
    // sunucudan okunur.
    _lineStops = widget.line.stops.isNotEmpty
        ? widget.line.stops
        : await _service.getLineStops(widget.line.id);
    if (widget.line.hasRoute) {
      _points
        ..clear()
        ..addAll(widget.line.roadPolyline!.map((p) => LatLng(p[0], p[1])));
    }

    if (_points.isNotEmpty) {
      _initialTarget = _centroid(_points);
    } else if (_lineStops.isNotEmpty) {
      _initialTarget = LatLng(_lineStops.first.lat, _lineStops.first.lng);
      _initialZoom = 15;
    } else {
      final city = widget.controller?.city ?? _cityFromProvider();
      if (city != null) {
        _initialTarget = LatLng(city.centerLat, city.centerLng);
        _initialZoom = city.zoomLevel.toDouble();
      }
    }
    if (mounted) setState(() => _loading = false);
    _ensureStopPins();
  }

  SehiriciCity? _cityFromProvider() {
    try {
      final p = context.read<SehiriciProvider>();
      return p.selectedCity ?? (p.cities.isNotEmpty ? p.cities.first : null);
    } catch (_) {
      return null;
    }
  }

  LatLng _centroid(List<LatLng> pts) {
    double lat = 0, lng = 0;
    for (final p in pts) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / pts.length, lng / pts.length);
  }

  // ─────────────────────────────────────────────
  // Düzenleme
  // ─────────────────────────────────────────────

  void _onMapTap(LatLng latLng) {
    if (_saving || _loadingProposal) return;
    setState(() {
      _points.add(latLng);
      _dirty = true;
    });
  }

  /// Çiz modu: parmak basılı tutulduğunda başlar.
  void _onDrawStart(LatLng latLng) {
    if (_saving || _loadingProposal) return;
    if (_mode != MapDrawMode.draw) return;
    setState(() {
      _drawing = true;
      _points.add(latLng);
      _dirty = true;
    });
  }

  /// Çiz sırasında her kamera hareketinde çağrılır; merkez LatLng'si
  /// kullanıcının parmağının o anki konumudur. Çok yakın noktaları atla.
  void _onDrawAppend(LatLng latLng) {
    if (!_drawing) return;
    if (_points.isEmpty) {
      setState(() => _points.add(latLng));
      return;
    }
    final last = _points.last;
    final dist = pathLengthMeters([last, latLng]);
    if (dist < _drawMinStepMeters) return;
    setState(() {
      _points.add(latLng);
      _dirty = true;
    });
  }

  /// Çiz bitti: Douglas-Peucker ile sadeleştir, draw modundan çık.
  void _onDrawEnd() {
    if (!_drawing) return;
    final simplified = simplifyPath(
      List<LatLng>.of(_points),
      toleranceMeters: _drawToleranceMeters,
    );
    setState(() {
      _drawing = false;
      if (simplified.length != _points.length) {
        _points
          ..clear()
          ..addAll(simplified);
      }
    });
  }

  void _onMarkerDragEnd(int index, LatLng newPos) {
    setState(() {
      _points[index] = newPos;
      _dirty = true;
    });
  }

  void _reorderPoint(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _points.removeAt(oldIndex);
      _points.insert(newIndex, item);
      _dirty = true;
    });
  }

  void _removePoint(int index) {
    setState(() {
      _points.removeAt(index);
      _dirty = true;
    });
  }

  /// Baştan bu noktaya kadar (bu nokta dahil) olan kısmı siler — rotanın
  /// başlangıcını bu noktaya taşır.
  void _trimFromStart(int index) {
    setState(() {
      _points.removeRange(0, index + 1);
      _dirty = true;
    });
  }

  /// Bu noktadan sona kadar (bu nokta dahil) olan kısmı siler — rotanın
  /// bitişini bu noktadan öncesine taşır.
  void _trimToEnd(int index) {
    setState(() {
      _points.removeRange(index, _points.length);
      _dirty = true;
    });
  }

  void _undo() {
    if (_points.isEmpty) return;
    setState(() {
      _points.removeLast();
      _dirty = true;
    });
  }

  void _clearAll() {
    if (_points.isEmpty) return;
    setState(() {
      _points.clear();
      _dirty = true;
    });
  }

  void _toggleDrawMode() {
    setState(() {
      if (_drawing) _onDrawEnd();
      _mode = _mode == MapDrawMode.draw ? MapDrawMode.click : MapDrawMode.draw;
    });
  }

  // ─────────────────────────────────────────────
  // Öneriler
  // ─────────────────────────────────────────────

  /// Mevcut durakları sırayla gerçek sürüş yoluyla bağla.
  Future<void> _proposeFromStops() async {
    if (_lineStops.length < 2) {
      _say('Rota için hatta en az 2 durak olmalı.', error: true);
      return;
    }
    setState(() => _loadingProposal = true);
    final waypoints = _lineStops
        .map((stop) => LatLng(stop.lat, stop.lng))
        .toList(growable: false);
    final routed = await _roadSnapService.routeThroughWaypoints(waypoints);
    if (!mounted) return;
    setState(() => _loadingProposal = false);
    if (routed.length < 2) {
      _say('Duraklar arasında gerçek yol bulunamadı. Düz çizgi kaydedilmedi.',
          error: true);
      return;
    }
    final simplified = simplifyToMaxPoints(routed, maxPoints: 1500);
    setState(() {
      _points
        ..clear()
        ..addAll(simplified);
      _dirty = true;
    });
    _say('Duraklar gerçek yollardan bağlandı (${_points.length} nokta). '
        'Kontrol edip kaydedin.');
    _fitToPoints();
  }

  /// Bu hattın en son tamamlanmış seferinin GPS noktalarını sadeleştirip yükle.
  Future<void> _proposeFromLastTrip() async {
    setState(() => _loadingProposal = true);
    try {
      final raw = await _service.getLatestCompletedTripPath(widget.line.id);
      if (!mounted) return;
      if (raw.length < 2) {
        _say('Bu hat için tamamlanmış bir sefer yolu bulunamadı. '
            'Önce şoför bir sefer tamamlamalı.', error: true);
        return;
      }
      final roadMatched = await _roadSnapService.matchDrivenPath(raw);
      if (!mounted) return;
      if (roadMatched.length < 2) {
        _say('Sefer GPS izi gerçek yolla eşleştirilemedi. Düz çizgi '
            'kaydedilmedi.', error: true);
        return;
      }
      // Çok turlu bir vardiya izi eşlendiğinde on binlerce nokta çıkabilir;
      // nokta sayısını tavanla sınırla — yol geometrisi görsel olarak korunur.
      final simplified = simplifyToMaxPoints(roadMatched, maxPoints: 1500);
      setState(() {
        _points
          ..clear()
          ..addAll(simplified);
        _dirty = true;
      });
      _say('Son seferden ${simplified.length} nokta yüklendi '
          '(orijinal ${raw.length} GPS noktası yola eşlendi).');
      _fitToPoints();
    } catch (e) {
      if (mounted) _say('Sefer yolu yüklenemedi: ${sehiriciErrorMessage(e)}', error: true);
    } finally {
      if (mounted) setState(() => _loadingProposal = false);
    }
  }

  // ─────────────────────────────────────────────
  // Harita kamera
  // ─────────────────────────────────────────────

  Future<void> _fitToPoints() async {
    if (_points.isEmpty) return;
    final ctl = await _mapCtl.future;
    if (_points.length == 1) {
      await ctl.animateCamera(CameraUpdate.newLatLngZoom(_points.first, 16));
      return;
    }
    await ctl.animateCamera(CameraUpdate.newLatLngBounds(_bounds(_points), 64));
  }

  Future<void> _focusPoint(int index) async {
    if (index < 0 || index >= _points.length) return;
    final ctl = await _mapCtl.future;
    await ctl.animateCamera(CameraUpdate.newLatLngZoom(_points[index], 18));
  }

  LatLngBounds _bounds(List<LatLng> list) {
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

  /// Cam zoom butonları için ortak kamera hareketi.
  Future<void> _zoomBy(double delta) async {
    final c = await _mapCtl.future;
    await c.animateCamera(CameraUpdate.zoomBy(delta));
  }

  // ─────────────────────────────────────────────
  // Kaydet / Sil / Kapat
  // ─────────────────────────────────────────────

  Future<void> _save() async {
    if (_points.length < 2) {
      _say('En az 2 nokta gerekli.', error: true);
      return;
    }
    setState(() => _saving = true);
    final polyline = _points
        .map((p) => <double>[p.latitude, p.longitude])
        .toList(growable: false);

    final ok = await _service.cacheRoutePolyline(
      lineId: widget.line.id,
      lineStopsInOrder: _lineStops,
      points: polyline,
      source: 'manual',
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) {
        _dirty = false;
        _changed = true;
      }
    });
    if (ok) {
      _refreshUserSide();
      Navigator.of(context).pop(true);
    } else {
      _say('Kaydedilemedi. Durak imzası uyuşmuyor olabilir (duraklar '
          'değişmiş); hat duraklarını kaydedip yeniden deneyin.', error: true);
    }
  }

  Future<void> _clearOnServer() async {
    final confirm = await sehiriciConfirm(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'Rota silinsin mi?',
      message: 'Bu hatta ait kayıtlı yol rotası silinir. Duraklar kalır, '
          'yalnız haritadaki çizgi kalkar.',
      confirmLabel: 'Rotayı Sil',
      destructive: true,
    );
    if (!confirm || !mounted) return;
    setState(() => _saving = true);
    final ok = await _service.clearRoutePolyline(widget.line.id);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) {
        _points.clear();
        _dirty = false;
        _changed = true;
        _hasSavedRoute = false;
      }
    });
    if (ok) {
      _refreshUserSide();
      _say('Kayıtlı rota silindi.');
    } else {
      _say('Rota silinemedi.', error: true);
    }
  }

  void _refreshUserSide() {
    try {
      context.read<SehiriciProvider>().invalidateAllCaches();
    } catch (_) {}
  }

  Future<void> _requestClose() async {
    if (_saving) return;
    if (!_dirty) {
      Navigator.of(context).pop(_changed);
      return;
    }
    final discard = await sehiriciConfirm(
      context,
      icon: Icons.edit_off_rounded,
      title: 'Değişiklikler atılsın mı?',
      message: 'Kaydetmeden çıkarsanız çizdiğiniz noktalar kaybolur.',
      confirmLabel: 'Atıp Çık',
      destructive: true,
    );
    if (discard && mounted) Navigator.of(context).pop(_changed);
  }

  // ─────────────────────────────────────────────
  // Harita bileşenleri
  // ─────────────────────────────────────────────

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};

    // Duraklar: numaralı iğneler (referans, sürüklenemez).
    for (var i = 0; i < _lineStops.length; i++) {
      final s = _lineStops[i];
      final pin = _stopPins[i + 1];
      markers.add(Marker(
        markerId: MarkerId('stop_${s.stopId}'),
        position: LatLng(s.lat, s.lng),
        icon: pin ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        anchor: const Offset(0.5, 1),
        zIndexInt: 3,
        infoWindow: InfoWindow(title: '${i + 1}. ${s.name}', snippet: 'Durak'),
      ));
    }

    // Rota noktaları: küçük noktalar. Çok fazlaysa seyreltilir.
    final n = _points.length;
    if (n > 0) {
      final step = n <= _maxPointMarkers ? 1 : (n / _maxPointMarkers).ceil();
      for (var i = 0; i < n; i++) {
        final isEnd = i == 0 || i == n - 1;
        if (!isEnd && i % step != 0) continue;
        markers.add(Marker(
          markerId: MarkerId('pt_$i'),
          position: _points[i],
          icon: (i == 0 ? _startDot : (i == n - 1 ? _endDot : _midDot)) ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          anchor: const Offset(0.5, 0.5),
          draggable: true,
          zIndexInt: isEnd ? 5 : 4,
          onDragEnd: (newPos) => _onMarkerDragEnd(i, newPos),
          infoWindow: InfoWindow(
            title: i == 0
                ? 'Başlangıç'
                : (i == n - 1 ? 'Bitiş' : 'Nokta ${i + 1}'),
          ),
        ));
      }
    }
    return markers;
  }

  Set<Polyline> _buildPolylines() {
    if (_points.length < 2) return const {};
    final color = widget.line.color;
    return {
      Polyline(
        polylineId: const PolylineId('admin_route_casing'),
        points: _points,
        color: Colors.white.withValues(alpha: 0.9),
        width: 9,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        zIndex: 1,
      ),
      Polyline(
        polylineId: const PolylineId('admin_route'),
        points: _points,
        color: color,
        width: 5,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        zIndex: 2,
      ),
    };
  }

  /// Açılış kamerası: rota (yoksa duraklar) ekrana sığacak yakınlıkta. Web
  /// Mercator ile hesaplanır — `newLatLngBounds` düzen tamamlanmadan çağrılırsa
  /// bazı cihazlarda hata verdiği için başlangıç konumu baştan doğru verilir.
  CameraPosition _initialCamera(Size size) {
    final pts = _points.length >= 2
        ? _points
        : [for (final s in _lineStops) LatLng(s.lat, s.lng)];
    if (pts.length < 2) {
      return CameraPosition(target: _initialTarget, zoom: _initialZoom);
    }
    final b = _bounds(pts);
    final sw = b.southwest, ne = b.northeast;
    double lat2y(double lat) {
      final s = math.sin(lat * math.pi / 180);
      return 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi);
    }

    final lngSpan = (ne.longitude - sw.longitude).abs() / 360;
    final latSpan = (lat2y(sw.latitude) - lat2y(ne.latitude)).abs();
    final availW = math.max(size.width - 96, 80.0);
    final availH = math.max(size.height - 96, 80.0);
    final zoomX = lngSpan <= 0 ? 18.0 : math.log(availW / (256 * lngSpan)) / math.ln2;
    final zoomY = latSpan <= 0 ? 18.0 : math.log(availH / (256 * latSpan)) / math.ln2;
    return CameraPosition(
      target: LatLng(
        (sw.latitude + ne.latitude) / 2,
        (sw.longitude + ne.longitude) / 2,
      ),
      zoom: math.min(math.min(zoomX, zoomY), 18.0).clamp(3.0, 18.0),
    );
  }

  Widget _buildMap() {
    // Harita görünümü (Otomatik/Açık/Koyu) admin tarafından harita üstündeki
    // düğmeyle değiştirilir; MapStyleBuilder tercihi anında uygular.
    return MapStyleBuilder(
      builder: (context, mapStyle) => LayoutBuilder(
        builder: (context, box) => _mapSurface(mapStyle, box.biggest),
      ),
    );
  }

  Widget _mapSurface(String mapStyle, Size size) {
    final drawing = _mode == MapDrawMode.draw;
    return Stack(
      children: [
        GoogleMap(
          style: mapStyle,
          initialCameraPosition: _initialCamera(size),
          onMapCreated: (c) {
            if (!_mapCtl.isCompleted) _mapCtl.complete(c);
          },
          onTap: _onMapTap,
          onLongPress: _onDrawStart,
          onCameraMove: _drawing ? (pos) => _onDrawAppend(pos.target) : null,
          onCameraIdle: _drawing ? () => _onDrawEnd() : null,
          markers: _buildMarkers(),
          polylines: _buildPolylines(),
          myLocationButtonEnabled: false,
          // Gömülü gri zoom kutuları yerine cam kontroller.
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          // Düz (2D) harita: eğim hareketi ve 3D bina kabartması kapalı.
          tiltGesturesEnabled: false,
          buildingsEnabled: false,
          mapType: MapType.normal,
        ),
        Positioned(
          right: 12,
          bottom: 64,
          child: MapZoomControls(
            onZoomIn: () => _zoomBy(1),
            onZoomOut: () => _zoomBy(-1),
            showThemeToggle: true,
          ),
        ),
        if (_notice != null)
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: MapHintBar(
              icon: _noticeIsError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              accentColor:
                  _noticeIsError ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
              text: _notice!,
              onDismiss: () => setState(() => _notice = null),
            ),
          )
        else if (drawing)
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: MapHintBar(
              icon: Icons.brush_rounded,
              accentColor: widget.line.color,
              text: 'Çizim modu: haritaya uzun basıp parmağınızı sürükleyin. '
                  'Bırakınca otomatik sadeleştirilir.',
            ),
          ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: MapHintBar(
            text: drawing
                ? 'Çizim modu aktif. Uzun basarak çizin veya tıkla-tıkla '
                    'nokta ekleyin.'
                : 'Nokta eklemek için haritaya dokunun. Noktaları '
                    'sürükleyerek taşıyabilirsiniz.',
          ),
        ),
        if (_loadingProposal)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.18),
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // Arayüz
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 900;
    final totalMeters = pathLengthMeters(_points);
    final durationMin = estimateDurationMinutes(totalMeters);

    final Widget body = _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              _buildHeader(),
              _buildToolbar(),
              Expanded(
                child: wide
                    ? Row(
                        children: [
                          Expanded(child: _buildMap()),
                          SizedBox(
                            width: _sidePanelWidth,
                            child: _buildSidePanel(totalMeters, durationMin),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(flex: 5, child: _buildMap()),
                          Expanded(
                            flex: 4,
                            child: _buildSidePanel(totalMeters, durationMin),
                          ),
                        ],
                      ),
              ),
            ],
          );

    final guarded = PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose();
      },
      child: body,
    );

    if (size.width < 720) {
      return Dialog.fullscreen(
        backgroundColor: AdminUi.page,
        child: SafeArea(child: guarded),
      );
    }
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: AdminUi.page,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: wide ? 1040 : size.width - 40,
        height: size.height < 720 ? size.height - 40 : 700,
        child: guarded,
      ),
    );
  }

  Widget _buildHeader() {
    final base = widget.line.color;
    final hsl = HSLColor.fromColor(base);
    final dark = hsl.withLightness((hsl.lightness * 0.62).clamp(0.12, 0.6)).toColor();
    final fg = sehiriciOnColor(base);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, dark],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: SehiriciVehicleIcon.forLine(widget.line, height: 40),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rota çiz',
                  style: TextStyle(
                    color: fg,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${widget.line.code} — ${widget.line.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg.withValues(alpha: 0.88), fontSize: 12.5),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, color: fg),
            tooltip: 'Kapat',
            onPressed: _requestClose,
          ),
        ],
      ),
    );
  }

  /// Kaydırmalı çip araç çubuğu.
  Widget _buildToolbar() {
    final drawing = _mode == MapDrawMode.draw;
    Widget divider() => Container(
          width: 1,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: AdminUi.line,
        );
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            _ToolChip(
              icon: Icons.undo_rounded,
              label: 'Geri al',
              onTap: _points.isNotEmpty ? _undo : null,
            ),
            _ToolChip(
              icon: Icons.layers_clear_rounded,
              label: 'Temizle',
              onTap: _points.isNotEmpty ? _clearAll : null,
            ),
            _ToolChip(
              icon: Icons.brush_rounded,
              label: drawing ? 'Tıklamaya dön' : 'Çiz',
              onTap: _toggleDrawMode,
              highlighted: drawing,
              color: widget.line.color,
            ),
            _ToolChip(
              icon: Icons.center_focus_strong_rounded,
              label: 'Odakla',
              onTap: _points.length >= 2 ? _fitToPoints : null,
            ),
            divider(),
            _ToolChip(
              icon: Icons.auto_fix_high_rounded,
              label: 'Duraklardan',
              onTap: (_lineStops.length >= 2 && !_loadingProposal)
                  ? _proposeFromStops
                  : null,
            ),
            _ToolChip(
              icon: Icons.history_rounded,
              label: 'Son seferden',
              onTap: _loadingProposal ? null : _proposeFromLastTrip,
            ),
            divider(),
            _ToolChip(
              icon: Icons.delete_outline_rounded,
              label: 'Kayıtlı rotayı sil',
              destructive: true,
              onTap: (_hasSavedRoute && !_saving) ? _clearOnServer : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidePanel(double totalMeters, int durationMin) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: AdminUi.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Özet
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                SehiriciMetaChip(
                  icon: Icons.scatter_plot_rounded,
                  label: '${_points.length} nokta',
                ),
                SehiriciMetaChip(
                  icon: Icons.straighten_rounded,
                  label: totalMeters < 1000
                      ? '${totalMeters.toStringAsFixed(0)} m'
                      : '${(totalMeters / 1000).toStringAsFixed(2)} km',
                ),
                SehiriciMetaChip(
                  icon: Icons.schedule_rounded,
                  label: '~$durationMin dk',
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AdminUi.line),
          Expanded(
            child: _points.isEmpty
                ? const _EmptyHint()
                : ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _points.length,
                    buildDefaultDragHandles: false,
                    onReorder: _reorderPoint,
                    itemBuilder: (ctx, i) => _pointTile(i),
                  ),
          ),
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AdminUi.line)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      (_saving || _points.length < 2 || !_dirty) ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(_dirty ? 'Rotayı kaydet' : 'Değişiklik yok'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AdminUi.brand,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pointTile(int i) {
    final p = _points[i];
    final n = _points.length;
    final isEnd = i == 0 || i == n - 1;
    final color = i == 0
        ? const Color(0xFF16A34A)
        : (i == n - 1 ? const Color(0xFFDC2626) : widget.line.color);
    return ListTile(
      key: ValueKey('pt_tile_$i'),
      dense: true,
      onTap: () => _focusPoint(i),
      leading: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: isEnd ? color : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
        ),
        alignment: Alignment.center,
        child: Text(
          '${i + 1}',
          style: TextStyle(
            color: isEnd ? Colors.white : color,
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      title: Text(
        '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}',
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      subtitle: i == 0
          ? const Text('Başlangıç', style: TextStyle(fontSize: 11))
          : (i == n - 1 ? const Text('Bitiş', style: TextStyle(fontSize: 11)) : null),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<_PointTrimAction>(
            icon: Icon(Icons.content_cut_rounded, color: AdminUi.brand, size: 18),
            tooltip: 'Buradan itibaren sil',
            onSelected: (action) {
              switch (action) {
                case _PointTrimAction.trimFromStart:
                  _trimFromStart(i);
                case _PointTrimAction.trimToEnd:
                  _trimToEnd(i);
              }
            },
            itemBuilder: (c) => [
              PopupMenuItem(
                enabled: i > 0,
                value: _PointTrimAction.trimFromStart,
                child: const Text('Baştan buraya kadar sil'),
              ),
              PopupMenuItem(
                enabled: i < n - 1,
                value: _PointTrimAction.trimToEnd,
                child: const Text('Buradan sona kadar sil'),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            color: const Color(0xFFDC2626),
            tooltip: 'Bu noktayı sil',
            visualDensity: VisualDensity.compact,
            onPressed: () => _removePoint(i),
          ),
          ReorderableDragStartListener(
            index: i,
            child: const Icon(Icons.drag_indicator_rounded, color: AdminUi.muted),
          ),
        ],
      ),
    );
  }
}

/// Araç çubuğundaki çip düğme.
class _ToolChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool highlighted;
  final bool destructive;
  final Color? color;

  const _ToolChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
    this.destructive = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final accent = destructive ? const Color(0xFFDC2626) : (color ?? AdminUi.brand);
    final fg = !enabled
        ? Colors.grey.shade400
        : (highlighted ? sehiriciOnColor(accent) : (destructive ? accent : AdminUi.ink));
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: highlighted ? accent : AdminUi.page,
        shape: StadiumBorder(
          side: BorderSide(
            color: highlighted
                ? accent
                : (destructive && enabled ? accent.withValues(alpha: 0.4) : AdminUi.line),
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.touch_app_rounded, size: 32, color: AdminUi.muted),
          SizedBox(height: 8),
          Text(
            'Henüz nokta yok',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
          ),
          SizedBox(height: 6),
          Text(
            '• Haritaya dokunarak nokta ekleyin\n'
            '• "Duraklardan" ile hat duraklarını gerçek yolla bağlayın\n'
            '• "Son seferden" ile son tamamlanan seferin GPS izini getirin',
            style: TextStyle(color: AdminUi.muted, fontSize: 12.5, height: 1.45),
          ),
        ],
      ),
    );
  }
}
