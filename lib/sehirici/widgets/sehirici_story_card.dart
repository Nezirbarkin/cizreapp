import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sehirici_models.dart';
import '../providers/sehirici_provider.dart';
import '../utils/sehirici_arrivals.dart';
import 'sehirici_common_widgets.dart';
import 'sehirici_live_map.dart';

/// Hattın ilk aracı ikonu: hikaye halkasında ve kartlarda "Şehiriçi"nin
/// simgesi olarak kullanılır. Hat yoksa varsayılan araç ikonu.
Widget _serviceGlyph(SehiriciProvider provider,
    {required double height, double angle = 0.6}) {
  final line = provider.lines.isNotEmpty ? provider.lines.first : null;
  return Transform.rotate(
    angle: angle,
    child: SehiriciVehicleIcon(
      vehicleKey: line?.vehicleKey,
      color: line?.color ?? const Color(0xFF1976D2),
      height: height,
    ),
  );
}

/// Instagram hikayesi tarzında yuvarlak Şehiriçi Servisler kartı.
/// Hikayelerin yanında görünür ve tıklanınca tam ekran harita açar.
class SehiriciStoryCard extends StatefulWidget {
  const SehiriciStoryCard({super.key});

  @override
  State<SehiriciStoryCard> createState() => _SehiriciStoryCardState();
}

class _SehiriciStoryCardState extends State<SehiriciStoryCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeStartRealtime();
    });
  }

  void _maybeStartRealtime() {
    if (!mounted) return;
    final provider = context.read<SehiriciProvider>();
    provider.ensureFresh();
    if (!provider.moduleEnabled) return;
    provider.ensureRealtimeWatching();
  }

  void _openFullDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => const _SehiriciMapDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SehiriciProvider>();
    if (!provider.moduleEnabled) return const SizedBox.shrink();

    final trips = provider.activeTrips;
    final city = provider.selectedCity;
    if (city == null || city.id.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: () => _openFullDialog(context),
        child: SizedBox(
          width: 70,
          child: Column(
            children: [
              // Yuvarlak hikaye kartı
              Container(
                width: 70,
                height: 70,
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: trips.isEmpty
                        ? [Colors.grey.shade400, Colors.grey.shade600]
                        : [
                            Colors.blue.shade400,
                            Colors.cyan.shade400,
                            Colors.teal.shade400,
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                    color: const Color(0xFFEAF1FB),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      _serviceGlyph(provider, height: 40),
                      // Canlı sefer varsa animasyonlu nokta
                      if (trips.isNotEmpty)
                        const Positioned(
                          top: 2,
                          right: 2,
                          child: SehiriciLiveDot(size: 8),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const SizedBox(
                height: 14,
                child: Text(
                  'Şehiriçi',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full mode (açık) Şehiriçi hikaye kartı — harita önizlemesi ile.
class SehiriciFullStoryCard extends StatelessWidget {
  const SehiriciFullStoryCard({super.key});

  void _openFullDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => const _SehiriciMapDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SehiriciProvider>();
    if (!provider.moduleEnabled) return const SizedBox.shrink();

    final trips = provider.activeTrips;
    final lines = provider.lines;
    final city = provider.selectedCity;
    if (city == null || city.id.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => _openFullDialog(context),
      child: Container(
        height: 180,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Web'de liteMode yok: küçük kart için tam JS haritası açılır ve
              // Maps JavaScript API kapalıysa Google'ın "Hata! Bir sorun
              // oluştu" katmanı kartı örter. Web'de hat şeması çizilir.
              if (kIsWeb)
                _SehiriciRoutePreview(lines: lines, trips: trips)
              else
              // Harita önizlemesi (etkileşimsiz) — sefer olmasa da duraklar görünür
              IgnorePointer(
                child: SehiriciLiveMap(
                  lines: lines,
                  activeTrips: trips,
                  center: city,
                  zoomLevel: city.zoomLevel,
                  height: double.infinity,
                  interactive: false,
                  showCouriers: false,
                  borderRadius: 0,
                  // Ana sayfa önizlemesi: tam harita motoru yerine statik
                  // bitmap (bkz. SehiriciLiveMap.liteMode).
                  liteMode: true,
                ),
              ),
              // Gradient overlay (üstten)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 84,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.62),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                left: 10,
                right: 10,
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFEAF1FB),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: _serviceGlyph(provider, height: 24),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Şehiriçi Servisler',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              shadows: [
                                Shadow(
                                  color: Colors.black45,
                                  blurRadius: 3,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            trips.isEmpty
                                ? 'Şu an aktif sefer yok'
                                : '${trips.length} sefer aktif',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              shadows: [
                                Shadow(
                                  color: Colors.black45,
                                  blurRadius: 3,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Web ana sayfa önizlemesi: harita motoru olmadan hat rotaları, duraklar ve
/// aktif araçlar sade bir şema olarak çizilir.
class _SehiriciRoutePreview extends StatelessWidget {
  final List<SehiriciLine> lines;
  final List<SehiriciActiveTrip> trips;

  const _SehiriciRoutePreview({required this.lines, required this.trips});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RouteSchematicPainter(lines: lines, trips: trips),
      child: const SizedBox.expand(),
    );
  }
}

class _RouteSchematicPainter extends CustomPainter {
  final List<SehiriciLine> lines;
  final List<SehiriciActiveTrip> trips;

  _RouteSchematicPainter({required this.lines, required this.trips});

  // Koyu zemin: dar kartta başlık degradenin altına taşınca da beyaz yazı
  // okunur kalsın.
  static const _background = Color(0xFF2F4358);
  static const _street = Color(0xFF3B536B);

  List<List<double>> _pathOf(SehiriciLine line) => line.hasRoute
      ? line.roadPolyline!
      : [for (final s in line.stops) [s.lat, s.lng]];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _background);

    // Sokak dokusu: hafif eğik ızgara.
    final street = Paint()
      ..color = _street
      ..strokeWidth = 2;
    for (double x = -size.height; x < size.width; x += 26) {
      canvas.drawLine(
          Offset(x, size.height), Offset(x + size.height * 0.35, 0), street);
    }
    for (double y = 12; y < size.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 8), street);
    }

    final paths = [for (final l in lines) _pathOf(l)];
    final points = [
      for (final p in paths) ...p,
      for (final t in trips)
        if (t.currentLat != null && t.currentLng != null)
          [t.currentLat!, t.currentLng!],
    ];
    if (points.isEmpty) return;

    var minLat = points.first[0], maxLat = minLat;
    var minLng = points.first[1], maxLng = minLng;
    for (final p in points) {
      minLat = math.min(minLat, p[0]);
      maxLat = math.max(maxLat, p[0]);
      minLng = math.min(minLng, p[1]);
      maxLng = math.max(maxLng, p[1]);
    }
    // Üstteki başlık degradesinin altına sığdır; boylam enleme göre daraltılır.
    final area = Rect.fromLTRB(14, 64, size.width - 14, size.height - 14);
    final lngScale = math.cos((minLat + maxLat) / 2 * math.pi / 180);
    final spanX = math.max((maxLng - minLng) * lngScale, 1e-6);
    final spanY = math.max(maxLat - minLat, 1e-6);
    final scale = math.min(area.width / spanX, area.height / spanY);
    final dx = area.left + (area.width - spanX * scale) / 2;
    final dy = area.top + (area.height - spanY * scale) / 2;
    Offset project(double lat, double lng) => Offset(
          dx + (lng - minLng) * lngScale * scale,
          dy + (maxLat - lat) * scale,
        );

    for (var i = 0; i < lines.length; i++) {
      final pts = [for (final p in paths[i]) project(p[0], p[1])];
      if (pts.length >= 2) {
        final path = Path()..addPolygon(pts, false);
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
        canvas.drawPath(
          path,
          Paint()
            ..color = lines[i].color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
      for (final s in lines[i].stops) {
        final o = project(s.lat, s.lng);
        canvas.drawCircle(o, 2.8, Paint()..color = Colors.white);
        canvas.drawCircle(
          o,
          2.8,
          Paint()
            ..color = lines[i].color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
      }
    }

    for (final t in trips) {
      if (t.currentLat == null || t.currentLng == null) continue;
      final o = project(t.currentLat!, t.currentLng!);
      canvas.drawCircle(o, 5.5, Paint()..color = Colors.white);
      canvas.drawCircle(o, 4, Paint()..color = t.color);
    }
  }

  @override
  bool shouldRepaint(_RouteSchematicPainter old) =>
      old.lines != lines || old.trips != trips;
}

/// Tam ekran Şehiriçi harita dialog'u: başlık çubuğu + tam ekran harita +
/// aktif seferler tepsisi. Sefer olmasa da harita (durak + rota) görünür.
class _SehiriciMapDialog extends StatelessWidget {
  const _SehiriciMapDialog();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SehiriciProvider>();
    final trips = provider.activeTrips;
    final lines = provider.lines;
    final city = provider.selectedCity;
    final scheme = Theme.of(context).colorScheme;

    if (city == null) {
      return const SizedBox.shrink();
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Column(
          children: [
            // Başlık çubuğu
            Material(
              color: scheme.surface,
              elevation: 2,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 8, 10, 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Kapat',
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Şehiriçi Servisler',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Row(
                              children: [
                                SehiriciLiveDot(
                                  size: 6,
                                  color: trips.isEmpty
                                      ? Colors.grey
                                      : const Color(0xFF22C55E),
                                  pulsing: trips.isNotEmpty,
                                ),
                                Text(
                                  trips.isEmpty
                                      ? 'Şu an aktif sefer yok · ${lines.length} hat'
                                      : '${trips.length} sefer aktif · ${lines.length} hat',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.of(context).pushNamed('/sehirici-lines');
                        },
                        icon: const Icon(Icons.view_list_rounded, size: 18),
                        label: const Text('Tüm hatlar'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Harita — iki parmakla zoom aktif
            Expanded(
              child: SehiriciLiveMap(
                lines: lines,
                activeTrips: trips,
                center: city,
                zoomLevel: city.zoomLevel,
                height: double.infinity,
                interactive: true,
                highlightLineId: provider.highlightedLineId,
                showLineChips: true,
                onHighlightChanged: provider.highlightLine,
                borderRadius: 0,
              ),
            ),

            // Alt tepsi: aktif seferler
            if (trips.isNotEmpty)
              Material(
                color: scheme.surface,
                elevation: 8,
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    height: 92,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      itemCount: trips.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) =>
                          _TripInfoChip(trip: trips[i], lines: lines),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Alt tepsideki sefer kartı: araç ikonu + hat + sıradaki durak/varış.
class _TripInfoChip extends StatelessWidget {
  final SehiriciActiveTrip trip;
  final List<SehiriciLine> lines;

  const _TripInfoChip({required this.trip, required this.lines});

  @override
  Widget build(BuildContext context) {
    final line = lines.firstWhere(
      (l) => l.id == trip.lineId,
      orElse: () => SehiriciLine(
        id: trip.lineId,
        code: trip.lineCode,
        name: trip.lineName,
        colorHex: trip.lineColor,
      ),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.read<SehiriciProvider>().highlightLine(trip.lineId),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
        decoration: BoxDecoration(
          color: trip.color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: trip.color.withValues(alpha: 0.4), width: 1.3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SehiriciVehicleIcon.forLine(line, height: 54),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                SehiriciLineBadge(
                  code: trip.lineCode.isEmpty ? line.code : trip.lineCode,
                  color: trip.color,
                  height: 24,
                  minWidth: 38,
                ),
                const SizedBox(height: 5),
                Text(
                  trip.etaMinutes != null
                      ? '${trip.nextStopName ?? 'Sıradaki durak'} · '
                          '${formatArrivalMinutes(trip.etaMinutes!)}'
                      : (trip.nextStopName ?? 'Yolda'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
