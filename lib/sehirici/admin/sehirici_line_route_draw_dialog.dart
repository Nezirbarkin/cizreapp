// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../models/sehirici_models.dart';
import '../providers/sehirici_provider.dart';
import '../services/sehirici_line_service.dart';
import '../services/sehirici_road_snap_service.dart';
import '../utils/sehirici_route_geometry.dart';

/// Admin için harita üzerinde kalemle rota çizme dialog'u (modernize).
///
/// • Haritaya tıklayarak nokta eklenir; noktalar sürüklenebilir.
/// • "Çiz" modunda parmak basılı tutulup sürüklenerek serbest rota çizilir
///   (Douglas-Peucker ile 3m tolerance sadeleştirme uygulanır).
/// • Sağ panelde sıralı nokta listesi (sürükle-bırak ile yeniden sırala, sil).
/// • Üst segmentli toolbar: Geri Al · Temizle · Çiz · Odakla · Duraklardan Öner ·
///   Son Seferden Öner · Rotayı Sil · Kaydet.
/// • Alt bilgi barı: toplam km, tahmini süre, nokta sayısı.
/// • Çıkışta kaydedilmemiş değişiklik uyarısı.

/// Çizim modu: tıkla-tıkla mı, parmakla çiz mi.
enum MapDrawMode { click, draw }

/// Nokta listesindeki bir noktadan itibaren rota kırpma yönü.
enum _PointTrimAction { trimFromStart, trimToEnd }

class SehiriciLineRouteDrawDialog extends StatefulWidget {
  final SehiriciLine line;
  const SehiriciLineRouteDrawDialog({super.key, required this.line});

  @override
  State<SehiriciLineRouteDrawDialog> createState() =>
      _SehiriciLineRouteDrawDialogState();
}

class _SehiriciLineRouteDrawDialogState
    extends State<SehiriciLineRouteDrawDialog> {
  final SehiriciLineService _service = SehiriciLineService();
  final SehiriciRoadSnapService _roadSnapService = SehiriciRoadSnapService();
  final Completer<GoogleMapController> _mapCtl =
      Completer<GoogleMapController>();

  /// Kullanıcının çizdiği noktalar (polyline).
  final List<LatLng> _points = [];

  /// Hat için duraklar (referans pin).
  List<SehiriciLineStop> _lineStops = const [];

  bool _loading = true;
  bool _saving = false;
  bool _loadingProposal = false;
  bool _dirty = false;
  MapDrawMode _mode = MapDrawMode.click;
  bool _drawing = false;
  // Çiz sırasında ardışık çok yakın nokta eklemeyi önlemek için min mesafe.
  static const double _drawMinStepMeters = 2.0;
  // Çizim bittiğinde sadeleştirme toleransı.
  static const double _drawToleranceMeters = 3.0;

  LatLng _initialTarget = const LatLng(37.0, 41.0);
  double _initialZoom = 13;

  // Side panel genişliği (sabit).
  static const double _sidePanelWidth = 300;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _lineStops = await _service.getLineStops(widget.line.id);
    if (widget.line.roadPolyline != null &&
        widget.line.roadPolyline!.length >= 2) {
      _points
        ..clear()
        ..addAll(widget.line.roadPolyline!.map((p) => LatLng(p[0], p[1])));
    }

    if (_points.isNotEmpty) {
      _initialTarget = _centroid(_points);
    } else if (_lineStops.isNotEmpty) {
      _initialTarget = LatLng(_lineStops.first.lat, _lineStops.first.lng);
    } else {
      final p = context.read<SehiriciProvider>();
      if (p.selectedCityId != null) {
        final sel = p.cities.firstWhere(
          (c) => c.id == p.selectedCityId,
          orElse: () => p.cities.isNotEmpty
              ? p.cities.first
              : const SehiriciCity(
                  id: '',
                  name: '',
                  slug: '',
                  centerLat: 37.0,
                  centerLng: 41.0,
                  zoomLevel: 13,
                ),
        );
        _initialTarget = LatLng(sel.centerLat, sel.centerLng);
        _initialZoom = sel.zoomLevel.toDouble();
      }
    }
    if (mounted) setState(() => _loading = false);
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
    if (_mode == MapDrawMode.draw) {
      // Çiz modunda kısa tıklama da tek nokta ekler (hızlı düzeltme için).
      setState(() {
        _points.add(latLng);
        _dirty = true;
      });
      return;
    }
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

  // ─────────────────────────────────────────────
  // Öneriler
  // ─────────────────────────────────────────────

  /// Mevcut durakları sırayla gerçek sürüş yoluyla bağla.
  Future<void> _proposeFromStops() async {
    if (_lineStops.isEmpty) return;
    setState(() => _loadingProposal = true);
    final waypoints = _lineStops
        .map((stop) => LatLng(stop.lat, stop.lng))
        .toList(growable: false);
    final routed = await _roadSnapService.routeThroughWaypoints(waypoints);
    if (!mounted) return;
    setState(() => _loadingProposal = false);
    if (routed.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Duraklar arasında gerçek yol bulunamadı. Düz çizgi kaydedilmedi.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() {
      _points
        ..clear()
        ..addAll(routed);
      _dirty = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Duraklar gerçek yollardan bağlandı (${_points.length} nokta). '
          'Kontrol edip kaydedin.',
        ),
      ),
    );
    _fitToPoints();
  }

  /// Bu hattın en son tamamlanmış seferinin GPS noktalarını sadeleştirip yükle.
  Future<void> _proposeFromLastTrip() async {
    setState(() => _loadingProposal = true);
    try {
      final raw = await _service.getLatestCompletedTripPath(widget.line.id);
      if (!mounted) return;
      if (raw.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Bu hat için tamamlanmış bir sefer yolu bulunamadı. '
              'Önce şöför bir sefer tamamlamalı.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      final roadMatched = await _roadSnapService.matchDrivenPath(raw);
      if (!mounted) return;
      if (roadMatched.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sefer GPS izi gerçek yolla eşleştirilemedi. Düz çizgi kaydedilmedi.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      // Çok turlu bir vardiya izi eşlendiğinde on binlerce nokta çıkabilir;
      // sabit 1.5 m tolerans bunu ciddi biçimde azaltmaz. Nokta sayısını
      // tavanla sınırla — yol geometrisi görsel olarak korunur.
      final simplified = simplifyToMaxPoints(roadMatched, maxPoints: 1500);
      setState(() {
        _points
          ..clear()
          ..addAll(simplified);
        _dirty = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Son seferden ${simplified.length} nokta yüklendi '
            '(orijinal ${raw.length} GPS noktası yola eşlendi).',
          ),
          backgroundColor: Colors.teal,
        ),
      );
      _fitToPoints();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sefer yolu yüklenemedi: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
    final bounds = _boundsFromLatLngList(_points);
    await ctl.animateCamera(CameraUpdate.newLatLngBounds(bounds, 64));
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

  // ─────────────────────────────────────────────
  // Kaydet / Sil
  // ─────────────────────────────────────────────

  Future<void> _save() async {
    if (_points.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('En az 2 nokta gerekli'),
          backgroundColor: Colors.red,
        ),
      );
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
      if (ok) _dirty = false;
    });
    if (ok) {
      context.read<SehiriciProvider>().invalidateAllCaches();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_points.length} nokta kaydedildi'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Kaydedilemedi. Durak imzası uyuşmuyor olabilir (duraklar değişmiş).',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _clearOnServer() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Rotayı Sil'),
        content: const Text(
          'Bu hatta ait kayıtlı yol rotasını silmek istediğinize emin misiniz?\n\n'
          'Duraklar kalır, sadece harita üzerindeki çizgi kalkar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _saving = true);
    final ok = await _service.clearRoutePolyline(widget.line.id);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) {
        _points.clear();
        _dirty = false;
      }
    });
    if (ok) {
      context.read<SehiriciProvider>().invalidateAllCaches();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kayıtlı rota silindi'),
          backgroundColor: Colors.green,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Silinemedi'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _confirmDiscardAndExit() async {
    if (!_dirty) {
      Navigator.pop(context, false);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Kaydedilmemiş değişiklikler'),
        content: const Text(
          'Kaydetmeden çıkmak istediğinize emin misiniz? Çizdiğiniz noktalar kaybolacak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Çık'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context, false);
  }

  // ─────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    for (var i = 0; i < _lineStops.length; i++) {
      final s = _lineStops[i];
      markers.add(
        Marker(
          markerId: MarkerId('stop_${s.stopId}'),
          position: LatLng(s.lat, s.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: InfoWindow(
            title: '${i + 1}. ${s.name}',
            snippet: 'Durak (referans)',
          ),
        ),
      );
    }
    for (var i = 0; i < _points.length; i++) {
      final p = _points[i];
      markers.add(
        Marker(
          markerId: MarkerId('pt_$i'),
          position: p,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
          draggable: true,
          onDragEnd: (newPos) => _onMarkerDragEnd(i, newPos),
          infoWindow: InfoWindow(title: 'Nokta ${i + 1}'),
        ),
      );
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final totalMeters = pathLengthMeters(_points);
    final durationMin = estimateDurationMinutes(totalMeters);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final mediaWidth = MediaQuery.of(context).size.width;
    final mediaHeight = MediaQuery.of(context).size.height;
    final dialogWidth = mediaWidth < 720
        ? mediaWidth - 24
        : (mediaWidth > 1100 ? 960.0 : mediaWidth - 48);
    final dialogHeight = mediaHeight < 600
        ? mediaHeight - 24
        : (mediaHeight > 900 ? 720.0 : mediaHeight - 80);

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).colorScheme.surface,
        ),
        clipBehavior: Clip.antiAlias,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : mediaWidth < 720
            ? Column(
                children: [
                  _buildHeader(isDark),
                  _buildSegmentedToolbar(),
                  Expanded(flex: 3, child: _buildMap()),
                  SizedBox(
                    height: dialogHeight * 0.45,
                    child: _buildSidePanel(totalMeters, durationMin),
                  ),
                ],
              )
            : Column(
                children: [
                  _buildHeader(isDark),
                  _buildSegmentedToolbar(),
                  Expanded(
                    child: Row(
                      children: [
                        // Sol: harita
                        Expanded(child: _buildMap()),
                        // Sağ: yan panel
                        SizedBox(
                          width: _sidePanelWidth,
                          child: _buildSidePanel(totalMeters, durationMin),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: widget.line.color),
      child: Row(
        children: [
          Icon(widget.line.vehicleType.icon, color: Colors.white, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rota Çiz · ${widget.line.code} — ${widget.line.name}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Haritaya dokunarak nokta ekleyin veya sürükleyin',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: _confirmDiscardAndExit,
          ),
        ],
      ),
    );
  }

  /// Material 3 tarzı segmentli toolbar: 6 aksiyon tek satırda.
  Widget _buildSegmentedToolbar() {
    final style = FilledButton.styleFrom(
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    );
    return Container(
      color: Colors.grey.shade100,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _toolbarBtn(
              icon: Icons.undo,
              label: 'Geri Al',
              enabled: _points.isNotEmpty,
              onTap: _undo,
            ),
            _toolbarBtn(
              icon: Icons.layers_clear,
              label: 'Temizle',
              enabled: _points.isNotEmpty,
              onTap: _clearAll,
            ),
            _toolbarBtn(
              icon: Icons.brush,
              label: _mode == MapDrawMode.draw ? 'Tıklamaya Dön' : 'Çiz',
              enabled: true,
              onTap: _toggleDrawMode,
              highlighted: _mode == MapDrawMode.draw,
            ),
            const _VDivider(),
            _toolbarBtn(
              icon: Icons.center_focus_strong,
              label: 'Odakla',
              enabled: _points.length >= 2,
              onTap: _fitToPoints,
            ),
            const _VDivider(),
            _toolbarBtn(
              icon: Icons.place_outlined,
              label: 'Duraklardan',
              enabled: _lineStops.isNotEmpty,
              onTap: _proposeFromStops,
            ),
            _toolbarBtn(
              icon: Icons.route,
              label: _loadingProposal ? 'Yükleniyor…' : 'Son Seferden',
              enabled: !_loadingProposal,
              onTap: _proposeFromLastTrip,
            ),
            const _VDivider(),
            _toolbarBtn(
              icon: Icons.delete_outline,
              label: 'Rotayı Sil',
              enabled: widget.line.roadPolyline != null,
              destructive: true,
              onTap: _clearOnServer,
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: FilledButton.icon(
                onPressed: (_saving || _points.length < 2 || !_dirty)
                    ? null
                    : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save, size: 18),
                label: const Text('Kaydet'),
                style: style.copyWith(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.disabled)) {
                      return Colors.grey.shade400;
                    }
                    return widget.line.color;
                  }),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _toolbarBtn({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
    bool destructive = false,
    bool highlighted = false,
  }) {
    final color = destructive
        ? Colors.red
        : (enabled
              ? (highlighted ? Colors.white : Colors.black87)
              : Colors.grey);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextButton.icon(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, size: 18, color: color),
        label: Text(label, style: TextStyle(color: color)),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          backgroundColor: highlighted ? widget.line.color : null,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
    );
  }

  void _toggleDrawMode() {
    setState(() {
      if (_drawing) _onDrawEnd();
      _mode = _mode == MapDrawMode.draw ? MapDrawMode.click : MapDrawMode.draw;
    });
  }

  Widget _buildMap() {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _initialTarget,
            zoom: _initialZoom,
          ),
          onMapCreated: (c) {
            if (!_mapCtl.isCompleted) _mapCtl.complete(c);
          },
          onTap: _onMapTap,
          onLongPress: _onDrawStart,
          onCameraMove: _drawing ? (pos) => _onDrawAppend(pos.target) : null,
          onCameraIdle: _drawing ? () => _onDrawEnd() : null,
          markers: _buildMarkers(),
          polylines: _points.length < 2
              ? const {}
              : {
                  Polyline(
                    polylineId: const PolylineId('admin_route'),
                    points: _points,
                    color: widget.line.color,
                    width: 5,
                  ),
                },
          myLocationButtonEnabled: false,
          zoomControlsEnabled: true,
          mapToolbarEnabled: false,
        ),
        if (_mode == MapDrawMode.draw)
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Material(
              color: widget.line.color,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.brush, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Çizim modu: haritaya uzun basıp parmağınızı sürükleyin. Bırakınca otomatik sadeleştirilir.',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Material(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  const Icon(Icons.touch_app, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _mode == MapDrawMode.draw
                          ? 'Çizim modu aktif. Uzun basarak çizin veya tıkla-tıkla nokta ekleyin.'
                          : 'Nokta eklemek için haritaya dokunun. Noktaları sürükleyerek taşıyabilirsiniz.',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSidePanel(double totalMeters, int durationMin) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(left: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Özet barı
          Container(
            color: Colors.grey.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _summaryChip(
                  icon: Icons.scatter_plot,
                  label: '${_points.length} nokta',
                ),
                const SizedBox(width: 6),
                _summaryChip(
                  icon: Icons.straighten,
                  label: totalMeters < 1000
                      ? '${totalMeters.toStringAsFixed(0)} m'
                      : '${(totalMeters / 1000).toStringAsFixed(2)} km',
                ),
                const SizedBox(width: 6),
                _summaryChip(
                  icon: Icons.access_time,
                  label: '~$durationMin dk',
                ),
              ],
            ),
          ),
          // Nokta listesi
          Expanded(
            child: _points.isEmpty
                ? const _EmptyHint()
                : ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _points.length,
                    buildDefaultDragHandles: false,
                    onReorder: _reorderPoint,
                    itemBuilder: (ctx, i) {
                      final p = _points[i];
                      return ListTile(
                        key: ValueKey('pt_tile_$i'),
                        dense: true,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: widget.line.color,
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          '${p.latitude.toStringAsFixed(5)}, '
                          '${p.longitude.toStringAsFixed(5)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PopupMenuButton<_PointTrimAction>(
                              icon: const Icon(
                                Icons.content_cut,
                                color: Colors.deepPurple,
                                size: 18,
                              ),
                              tooltip: 'Buradan itibaren sil',
                              onSelected: (action) {
                                switch (action) {
                                  case _PointTrimAction.trimFromStart:
                                    _trimFromStart(i);
                                    break;
                                  case _PointTrimAction.trimToEnd:
                                    _trimToEnd(i);
                                    break;
                                }
                              },
                              itemBuilder: (c) => [
                                PopupMenuItem(
                                  enabled: i > 0,
                                  value: _PointTrimAction.trimFromStart,
                                  child: const Text('Baştan buraya kadar sil'),
                                ),
                                PopupMenuItem(
                                  enabled: i < _points.length - 1,
                                  value: _PointTrimAction.trimToEnd,
                                  child: const Text('Buradan sona kadar sil'),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                                size: 18,
                              ),
                              tooltip: 'Bu noktayı sil',
                              onPressed: () => _removePoint(i),
                            ),
                            ReorderableDragStartListener(
                              index: i,
                              child: const Icon(
                                Icons.drag_handle,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey.shade700),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

class _VDivider extends StatelessWidget {
  const _VDivider();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 24, color: Colors.grey.shade300);
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.touch_app, size: 32, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          const Text(
            'Henüz nokta yok',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            '• Haritaya dokunarak nokta ekleyin\n'
            '• "Duraklardan" ile hat duraklarını temel alın\n'
            '• "Son Seferden" ile son tamamlanan seferin GPS noktalarını sadeleştirip getirin',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
