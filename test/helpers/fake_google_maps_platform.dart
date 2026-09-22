// ignore_for_file: unnecessary_import, depend_on_referenced_packages

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformViewCreatedCallback;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

/// Widget testleri için sahte Google Maps platformu.
///
/// Gerçek harita bir platform görünümüdür ve `flutter test` altında
/// çizilemez. Bu sahte platform:
///  • marker / polyline / circle güncellemelerini KAYDEDER (testler
///    `markers`, `polylines` üzerinden doğrular),
///  • marker dokunuşlarını simüle eder ([tapMarker]),
///  • marker'ları, çizgileri ve halkaları gerçek Web Mercator izdüşümüyle
///    sahte bir şehir dokusunun üstüne KENDİSİ çizer — bitmap boyutu, çapa
///    noktası ve dönüş doğru mu, gözle (PNG) kontrol edilebilir.
class FakeGoogleMapsPlatform extends GoogleMapsFlutterPlatform {
  final Map<MarkerId, Marker> markers = {};
  final Map<PolylineId, Polyline> polylines = {};
  final Map<CircleId, Circle> circles = {};
  final ChangeNotifier _repaint = _Notifier();

  CameraPosition camera = const CameraPosition(target: LatLng(0, 0), zoom: 10);
  String? style;
  MapType mapType = MapType.normal;
  bool trafficEnabled = false;
  /// Etkin (en son oluşturulan) haritanın kimliği. Aynı anda birden çok harita
  /// açık olabilir (ör. yönetim panelinde altta canlı harita, üstte konum
  /// seçici diyaloğu); testler her zaman en yeni olanı inceler, eskilerin
  /// güncellemeleri yok sayılır.
  int mapId = 1;
  final Set<int> _seenCreationIds = {};

  final StreamController<MapEvent<Object?>> _events =
      StreamController<MapEvent<Object?>>.broadcast();

  /// Görünümü elle güncellemek için (ör. kamera hareketi sonrası).
  void notify() => (_repaint as _Notifier).ping();

  /// Bir marker'a dokunulmuş gibi olay üretir.
  void tapMarker(String id) =>
      _events.add(MarkerTapEvent(mapId, MarkerId(id)));

  /// Haritanın boş bir noktasına dokunulmuş gibi olay üretir.
  void tapMap(LatLng position) => _events.add(MapTapEvent(mapId, position));

  /// Bir marker sürüklenip [position]'a bırakılmış gibi olay üretir.
  void dragMarkerEnd(String id, LatLng position) =>
      _events.add(MarkerDragEndEvent(mapId, position, MarkerId(id)));

  /// Kamera boşta olayı (yakınlık eşiklerini tetiklemek için).
  void cameraIdle() => _events.add(CameraIdleEvent(mapId));

  /// Kamerayı [zoom]'a taşır ve hareket + boşta olaylarını gönderir.
  void zoomTo(double zoom) {
    camera = CameraPosition(target: camera.target, zoom: zoom);
    _events.add(CameraMoveEvent(mapId, camera));
    _events.add(CameraIdleEvent(mapId));
    notify();
  }

  Stream<T> _of<T extends MapEvent<Object?>>() =>
      _events.stream.where((e) => e is T).cast<T>();

  // ── Yaşam döngüsü ───────────────────────────────────────────

  @override
  Future<void> init(int mapId) async {}

  @override
  void dispose({required int mapId}) {}

  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) {
    // Gerçek platform görünümü her harita için YALNIZ BİR KEZ oluşturulur;
    // GoogleMap widget'ı yeniden çizildikçe bu metot tekrar çağrılır ama
    // görünüm/controller aynı kalır. İlk çağrıdan sonra durumu (kamera,
    // marker'lar) SIFIRLAMAYIZ — sonraki değişiklikler update* çağrılarıyla
    // gelir. Yeni bir harita oluşunca o "etkin" olur ve durum ona geçer.
    if (_seenCreationIds.add(creationId)) {
      mapId = creationId;
      markers.clear();
      polylines.clear();
      circles.clear();
      camera = widgetConfiguration.initialCameraPosition;
      style = mapConfiguration.style;
      mapType = mapConfiguration.mapType ?? MapType.normal;
      for (final m in mapObjects.markers) {
        markers[m.markerId] = m;
      }
      for (final p in mapObjects.polylines) {
        polylines[p.polylineId] = p;
      }
      for (final c in mapObjects.circles) {
        circles[c.circleId] = c;
      }
      scheduleMicrotask(() => onPlatformViewCreated(creationId));
    }
    return FakeMapView(platform: this);
  }

  // ── Güncellemeler ───────────────────────────────────────────

  @override
  Future<void> updateMapConfiguration(MapConfiguration configuration,
      {required int mapId}) async {
    if (mapId != this.mapId) return;
    style = configuration.style ?? style;
    mapType = configuration.mapType ?? mapType;
    trafficEnabled = configuration.trafficEnabled ?? trafficEnabled;
    notify();
  }

  @override
  Future<void> updateMarkers(MarkerUpdates markerUpdates,
      {required int mapId}) async {
    if (mapId != this.mapId) return;
    for (final m in markerUpdates.markersToAdd) {
      markers[m.markerId] = m;
    }
    for (final m in markerUpdates.markersToChange) {
      markers[m.markerId] = m;
    }
    for (final id in markerUpdates.markerIdsToRemove) {
      markers.remove(id);
    }
    notify();
  }

  @override
  Future<void> updatePolylines(PolylineUpdates polylineUpdates,
      {required int mapId}) async {
    if (mapId != this.mapId) return;
    for (final p in polylineUpdates.polylinesToAdd) {
      polylines[p.polylineId] = p;
    }
    for (final p in polylineUpdates.polylinesToChange) {
      polylines[p.polylineId] = p;
    }
    for (final id in polylineUpdates.polylineIdsToRemove) {
      polylines.remove(id);
    }
    notify();
  }

  @override
  Future<void> updateCircles(CircleUpdates circleUpdates,
      {required int mapId}) async {
    if (mapId != this.mapId) return;
    for (final c in circleUpdates.circlesToAdd) {
      circles[c.circleId] = c;
    }
    for (final c in circleUpdates.circlesToChange) {
      circles[c.circleId] = c;
    }
    for (final id in circleUpdates.circleIdsToRemove) {
      circles.remove(id);
    }
    notify();
  }

  @override
  Future<void> updatePolygons(PolygonUpdates polygonUpdates,
      {required int mapId}) async {}

  @override
  Future<void> updateTileOverlays(
      {required Set<TileOverlay> newTileOverlays, required int mapId}) async {}

  @override
  Future<void> updateClusterManagers(ClusterManagerUpdates clusterManagerUpdates,
      {required int mapId}) async {}

  @override
  Future<void> updateHeatmaps(HeatmapUpdates heatmapUpdates,
      {required int mapId}) async {}

  @override
  Future<void> updateGroundOverlays(GroundOverlayUpdates groundOverlayUpdates,
      {required int mapId}) async {}

  @override
  Future<void> setMapStyle(String? mapStyle, {required int mapId}) async {
    if (mapId != this.mapId) return;
    style = mapStyle;
    notify();
  }

  @override
  Future<String?> getStyleError({required int mapId}) async => null;

  // ── Kamera ──────────────────────────────────────────────────

  @override
  Future<void> moveCamera(CameraUpdate cameraUpdate, {required int mapId}) async {
    if (mapId != this.mapId) return;
    _apply(cameraUpdate);
  }

  @override
  Future<void> animateCamera(CameraUpdate cameraUpdate,
      {required int mapId}) async {
    if (mapId != this.mapId) return;
    _apply(cameraUpdate);
  }

  @override
  Future<double> getZoomLevel({required int mapId}) async => camera.zoom;

  void _apply(CameraUpdate update) {
    final json = update.toJson() as List<dynamic>;
    final type = json.first as String;
    switch (type) {
      case 'newCameraPosition':
        final m = json[1] as Map<dynamic, dynamic>;
        final t = (m['target'] as List).cast<num>();
        camera = CameraPosition(
          target: LatLng(t[0].toDouble(), t[1].toDouble()),
          zoom: (m['zoom'] as num).toDouble(),
        );
      case 'newLatLng':
        final t = (json[1] as List).cast<num>();
        camera = CameraPosition(
            target: LatLng(t[0].toDouble(), t[1].toDouble()), zoom: camera.zoom);
      case 'newLatLngZoom':
        final t = (json[1] as List).cast<num>();
        camera = CameraPosition(
          target: LatLng(t[0].toDouble(), t[1].toDouble()),
          zoom: (json[2] as num).toDouble(),
        );
      case 'newLatLngBounds':
        final b = (json[1] as List);
        final sw = (b[0] as List).cast<num>();
        final ne = (b[1] as List).cast<num>();
        final lat = (sw[0] + ne[0]) / 2;
        final lng = (sw[1] + ne[1]) / 2;
        final span = math.max((ne[0] - sw[0]).abs(), (ne[1] - sw[1]).abs());
        final zoom = span <= 0 ? 16.0 : (math.log(360 / span) / math.ln2) - 0.6;
        camera = CameraPosition(
          target: LatLng(lat.toDouble(), lng.toDouble()),
          zoom: zoom.clamp(3, 19).toDouble(),
        );
      case 'zoomIn':
        camera = CameraPosition(target: camera.target, zoom: camera.zoom + 1);
      case 'zoomOut':
        camera = CameraPosition(target: camera.target, zoom: camera.zoom - 1);
      case 'zoomBy':
        camera = CameraPosition(
            target: camera.target, zoom: camera.zoom + (json[1] as num));
      case 'zoomTo':
        camera =
            CameraPosition(target: camera.target, zoom: (json[1] as num).toDouble());
      default:
        break;
    }
    notify();
  }

  // ── Olay akışları ───────────────────────────────────────────

  @override
  Stream<CameraMoveStartedEvent> onCameraMoveStarted({required int mapId}) =>
      _of<CameraMoveStartedEvent>();
  @override
  Stream<CameraMoveEvent> onCameraMove({required int mapId}) =>
      _of<CameraMoveEvent>();
  @override
  Stream<CameraIdleEvent> onCameraIdle({required int mapId}) =>
      _of<CameraIdleEvent>();
  @override
  Stream<MarkerTapEvent> onMarkerTap({required int mapId}) =>
      _of<MarkerTapEvent>();
  @override
  Stream<InfoWindowTapEvent> onInfoWindowTap({required int mapId}) =>
      _of<InfoWindowTapEvent>();
  @override
  Stream<MarkerDragStartEvent> onMarkerDragStart({required int mapId}) =>
      _of<MarkerDragStartEvent>();
  @override
  Stream<MarkerDragEvent> onMarkerDrag({required int mapId}) =>
      _of<MarkerDragEvent>();
  @override
  Stream<MarkerDragEndEvent> onMarkerDragEnd({required int mapId}) =>
      _of<MarkerDragEndEvent>();
  @override
  Stream<PolylineTapEvent> onPolylineTap({required int mapId}) =>
      _of<PolylineTapEvent>();
  @override
  Stream<PolygonTapEvent> onPolygonTap({required int mapId}) =>
      _of<PolygonTapEvent>();
  @override
  Stream<CircleTapEvent> onCircleTap({required int mapId}) =>
      _of<CircleTapEvent>();
  @override
  Stream<MapTapEvent> onTap({required int mapId}) => _of<MapTapEvent>();
  @override
  Stream<MapLongPressEvent> onLongPress({required int mapId}) =>
      _of<MapLongPressEvent>();
  @override
  Stream<ClusterTapEvent> onClusterTap({required int mapId}) =>
      _of<ClusterTapEvent>();
  @override
  Stream<GroundOverlayTapEvent> onGroundOverlayTap({required int mapId}) =>
      _of<GroundOverlayTapEvent>();
}

class _Notifier extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// Sahte haritanın çizimi: şehir dokusu + çizgiler + marker'lar.
class FakeMapView extends StatelessWidget {
  final FakeGoogleMapsPlatform platform;
  const FakeMapView({super.key, required this.platform});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: platform._repaint,
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final size = Size(
            box.maxWidth.isFinite ? box.maxWidth : 360,
            box.maxHeight.isFinite ? box.maxHeight : 260,
          );
          final proj = _Projection(platform.camera.target, platform.camera.zoom, size);
          final dark = platform.style != null && platform.style!.contains('#1a1d23');
          final satellite = platform.mapType == MapType.hybrid;

          final markers = platform.markers.values.toList()
            ..sort((a, b) => a.zIndexInt.compareTo(b.zIndexInt));

          return ClipRect(
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _CityPainter(proj, dark: dark, satellite: satellite),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ObjectsPainter(
                      proj,
                      platform.polylines.values.toList(),
                      platform.circles.values.toList(),
                    ),
                  ),
                ),
                for (final m in markers) _markerWidget(proj, m),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _markerWidget(_Projection proj, Marker m) {
    final bmp = m.icon;
    Size size = const Size(28, 28);
    Widget image = const Icon(Icons.location_on, color: Colors.red, size: 28);
    if (bmp is BytesMapBitmap) {
      size = Size(bmp.width ?? 30, bmp.height ?? 30);
      image = Image.memory(
        bmp.byteData,
        width: size.width,
        height: size.height,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
      );
    }
    final p = proj.project(m.position);
    final left = p.dx - m.anchor.dx * size.width;
    final top = p.dy - m.anchor.dy * size.height;
    Widget child = image;
    if (m.rotation != 0) {
      child = Transform.rotate(
        angle: m.rotation * math.pi / 180,
        alignment: Alignment(m.anchor.dx * 2 - 1, m.anchor.dy * 2 - 1),
        child: child,
      );
    }
    if (m.alpha < 1) child = Opacity(opacity: m.alpha, child: child);
    return Positioned(
      left: left,
      top: top,
      width: size.width,
      height: size.height,
      child: child,
    );
  }
}

/// Web Mercator izdüşümü (dp cinsinden; sıfırıncı zoom'da dünya 256 dp).
class _Projection {
  final LatLng center;
  final double zoom;
  final Size size;
  const _Projection(this.center, this.zoom, this.size);

  double get _scale => 256 * math.pow(2, zoom).toDouble();

  double _x(double lon) => (lon + 180) / 360 * _scale;
  double _y(double lat) {
    final s = math.sin(lat * math.pi / 180);
    return (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * _scale;
  }

  Offset project(LatLng p) {
    final cx = _x(center.longitude);
    final cy = _y(center.latitude);
    return Offset(
      size.width / 2 + (_x(p.longitude) - cx),
      size.height / 2 + (_y(p.latitude) - cy),
    );
  }

  /// Metreyi dp'ye çevirir (enleme göre).
  double metersToDp(double meters) {
    final metersPerDp =
        156543.03392 * math.cos(center.latitude * math.pi / 180) / math.pow(2, zoom);
    return meters / metersPerDp;
  }
}

class _CityPainter extends CustomPainter {
  final _Projection proj;
  final bool dark;
  final bool satellite;
  const _CityPainter(this.proj, {required this.dark, required this.satellite});

  @override
  void paint(Canvas canvas, Size size) {
    final land = satellite
        ? const Color(0xFF3B4636)
        : (dark ? const Color(0xFF1A1D23) : const Color(0xFFF2F1ED));
    final block = satellite
        ? const Color(0xFF5B5C55)
        : (dark ? const Color(0xFF22262D) : const Color(0xFFE7E5DD));
    final road = satellite
        ? const Color(0xFF8A8B84)
        : (dark ? const Color(0xFF2F343D) : Colors.white);
    canvas.drawRect(Offset.zero & size, Paint()..color = land);

    // ~110 m'lik kare blokları, aralarında sokak.
    const step = 0.001;
    final c = proj.center;
    final baseLat = (c.latitude / step).floor() * step;
    final baseLng = (c.longitude / step).floor() * step;
    final spanDp = proj.metersToDp(111000 * step);
    final n = (math.max(size.width, size.height) / math.max(spanDp, 1)).ceil() + 3;
    final roadW = math.max(3.0, proj.metersToDp(9));
    for (var i = -n; i <= n; i++) {
      for (var j = -n; j <= n; j++) {
        final a = proj.project(LatLng(baseLat + i * step, baseLng + j * step));
        final b = proj.project(LatLng(baseLat + (i + 1) * step, baseLng + (j + 1) * step));
        final rect = Rect.fromPoints(a, b).deflate(roadW / 2 + 1);
        if (rect.width <= 0 || rect.height <= 0) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          Paint()..color = block,
        );
      }
    }
    // Ana caddeler (her 3 blokta bir daha kalın).
    final wide = Paint()
      ..color = road
      ..strokeWidth = roadW * 1.5;
    for (var i = -n; i <= n; i += 3) {
      final a = proj.project(LatLng(baseLat + i * step, baseLng - n * step));
      final b = proj.project(LatLng(baseLat + i * step, baseLng + n * step));
      canvas.drawLine(a, b, wide);
      final a2 = proj.project(LatLng(baseLat - n * step, baseLng + i * step));
      final b2 = proj.project(LatLng(baseLat + n * step, baseLng + i * step));
      canvas.drawLine(a2, b2, wide);
    }
  }

  @override
  bool shouldRepaint(covariant _CityPainter old) => true;
}

class _ObjectsPainter extends CustomPainter {
  final _Projection proj;
  final List<Polyline> polylines;
  final List<Circle> circles;
  const _ObjectsPainter(this.proj, this.polylines, this.circles);

  @override
  void paint(Canvas canvas, Size size) {
    for (final c in circles) {
      final center = proj.project(c.center);
      final r = proj.metersToDp(c.radius);
      canvas.drawCircle(center, r, Paint()..color = c.fillColor);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = c.strokeWidth.toDouble()
          ..color = c.strokeColor,
      );
    }
    final sorted = [...polylines]..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    for (final line in sorted) {
      if (line.points.length < 2) continue;
      final path = Path();
      for (var i = 0; i < line.points.length; i++) {
        final p = proj.project(line.points[i]);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = line.width.toDouble()
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = line.color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ObjectsPainter old) => true;
}
