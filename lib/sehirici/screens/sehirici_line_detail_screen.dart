import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/map_vehicle_painters.dart';
import '../models/sehirici_models.dart';
import '../providers/sehirici_provider.dart';
import '../utils/sehirici_arrivals.dart';
import '../widgets/sehirici_common_widgets.dart';
import '../widgets/sehirici_live_map.dart';

/// Hat detayı: renkli başlık + canlı harita + zaman çizelgesi biçiminde
/// duraklar (her durakta canlı varış süresi).
class SehiriciLineDetailScreen extends StatefulWidget {
  final SehiriciLine line;
  const SehiriciLineDetailScreen({super.key, required this.line});

  @override
  State<SehiriciLineDetailScreen> createState() =>
      _SehiriciLineDetailScreenState();
}

class _SehiriciLineDetailScreenState extends State<SehiriciLineDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Canlı konumlar gerçek zamanlı gelsin (liste ekranı açılmadan da).
      context.read<SehiriciProvider>().ensureRealtimeWatching();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SehiriciProvider>();
    final city = provider.selectedCity;
    // Sağlayıcıdaki güncel hat (durak/rota değişmiş olabilir); yoksa gelen hat.
    final line = provider.lines.firstWhere(
      (l) => l.id == widget.line.id,
      orElse: () => widget.line,
    );
    final trips =
        provider.activeTrips.where((t) => t.lineId == line.id).toList();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 170,
            backgroundColor: line.color,
            foregroundColor: sehiriciOnColor(line.color),
            surfaceTintColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: _Hero(line: line, liveCount: trips.length),
            ),
            title: Text(
              '${line.code} — ${line.name}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          if (city != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
                child: SehiriciLiveMap(
                  lines: [line],
                  activeTrips: trips,
                  center: city,
                  zoomLevel: city.zoomLevel,
                  height: 320,
                  showCouriers: false,
                  borderRadius: 22,
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: SehiriciStatTile(
                      icon: Icons.signpost_rounded,
                      value: '${line.stops.length}',
                      label: 'Durak',
                      color: const Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SehiriciStatTile(
                      icon: Icons.schedule_rounded,
                      value: line.estimatedMinutes != null
                          ? '~${line.estimatedMinutes}'
                          : '—',
                      label: 'Dakika',
                      color: const Color(0xFF1976D2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SehiriciStatTile(
                      icon: Icons.payments_rounded,
                      value: line.fareAmount > 0
                          ? '${line.fareAmount.toStringAsFixed(0)} ₺'
                          : 'Ücretsiz',
                      label: 'Ücret',
                      color: const Color(0xFF16A34A),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // DİKKAT: CustomScrollView.slivers'taki her öğe bir Sliver ÜRETMELİ.
          // SehiriciSectionHeader sıradan bir kutu widget'ı (Padding/Row) —
          // sarmalanmadan buraya konursa derleme zamanında yakalanmaz
          // (slivers salt List<Widget>'tır) ama çalışma zamanında "RenderViewport
          // expected a child of type RenderSliver but received a child of type
          // RenderErrorBox" ile çöker.
          // DİKKAT: CustomScrollView.slivers'taki her öğe bir Sliver ÜRETMELİ.
          // SehiriciSectionHeader sıradan bir kutu widget'ı (Padding/Row) —
          // sarmalanmadan buraya konursa derleme zamanında yakalanmaz
          // (slivers salt List<Widget>'tır) ama çalışma zamanında "RenderViewport
          // expected a child of type RenderSliver but received a child of type
          // RenderErrorBox" ile çöker.
          SliverToBoxAdapter(
            child: SehiriciSectionHeader(
              title: 'Duraklar ve Tahmini Varış',
              trailing: '${line.stops.length} durak',
            ),
          ),
          if (line.stops.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  'Bu hatta henüz durak eklenmemiş.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.55)),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final stop = line.stops[i];
                  final arrivals = arrivalsForStop(
                    stopId: stop.stopId,
                    lines: [line],
                    trips: trips,
                  );
                  SehiriciStopArrival? best;
                  for (final a in arrivals) {
                    if (!a.passed && a.minutes != null && !a.onBreak) {
                      best = a;
                      break;
                    }
                  }
                  return _StopTimelineTile(
                    line: line,
                    stop: stop,
                    index: i,
                    isFirst: i == 0,
                    isLast: i == line.stops.length - 1,
                    arrival: best,
                    passed: best == null && arrivals.any((a) => a.passed),
                    isFavorite: provider.favoriteStopIds.contains(stop.stopId),
                    showFavorite: provider.settings.allowUserFavorites,
                    onToggleFavorite: () => provider.toggleFavorite(stop.stopId),
                  );
                },
                childCount: line.stops.length,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

/// Renkli başlık: büyük araç ikonu + kod rozeti + canlı sayaç.
class _Hero extends StatelessWidget {
  final SehiriciLine line;
  final int liveCount;
  const _Hero({required this.line, required this.liveCount});

  @override
  Widget build(BuildContext context) {
    final fg = sehiriciOnColor(line.color);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            line.color,
            Color.lerp(line.color, Colors.black, 0.28)!,
          ],
        ),
      ),
      child: Stack(
        children: [
          // Dekoratif büyük araç (yarı saydam, sağda).
          Positioned(
            right: -6,
            bottom: -18,
            child: Opacity(
              opacity: 0.22,
              child: Transform.rotate(
                angle: 0.5,
                child: SehiriciVehicleIcon.forLine(line, height: 190),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: fg.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      line.code,
                      style: TextStyle(
                        color: fg,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    line.name,
                    style: TextStyle(
                      color: fg,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const SehiriciLiveDot(size: 7),
                      Text(
                        liveCount > 0
                            ? '$liveCount araç yolda'
                            : 'Şu an sefer yok',
                        style: TextStyle(
                          color: fg.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Zaman çizelgesindeki bir durak satırı.
class _StopTimelineTile extends StatelessWidget {
  final SehiriciLine line;
  final SehiriciLineStop stop;
  final int index;
  final bool isFirst;
  final bool isLast;
  final SehiriciStopArrival? arrival;
  final bool passed;
  final bool isFavorite;
  final bool showFavorite;
  final VoidCallback onToggleFavorite;

  const _StopTimelineTile({
    required this.line,
    required this.stop,
    required this.index,
    required this.isFirst,
    required this.isLast,
    required this.arrival,
    required this.passed,
    required this.isFavorite,
    required this.showFavorite,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final terminalColor = isFirst
        ? kStopStart
        : (isLast ? kStopEnd : null);
    final soon = arrival != null && arrival!.minutes! <= 2;

    return Opacity(
      opacity: passed ? 0.55 : 1,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 52,
              child: Column(
                children: [
                  Expanded(
                    flex: 1,
                    child: Container(
                      width: 5,
                      color: isFirst ? Colors.transparent : line.color,
                    ),
                  ),
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: terminalColor ?? scheme.surface,
                      border: Border.all(
                        color: terminalColor ?? line.color,
                        width: 4,
                      ),
                    ),
                    child: terminalColor == null
                        ? null
                        : const Icon(Icons.circle, size: 7, color: Colors.white),
                  ),
                  Expanded(
                    flex: 1,
                    child: Container(
                      width: 5,
                      color: isLast ? Colors.transparent : line.color,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      stop.name,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight:
                            (isFirst || isLast) ? FontWeight.w900 : FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isFirst
                          ? 'Başlangıç durağı'
                          : '+${stop.minutesFromStart} dk'
                              '${stop.distanceKm != null && stop.distanceKm! > 0 ? ' · ${stop.distanceKm!.toStringAsFixed(1)} km' : ''}'
                              '${isLast ? ' · Son durak' : ''}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (arrival != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: (soon ? const Color(0xFF16A34A) : line.color)
                          .withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      formatArrivalMinutes(arrival!.minutes!),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                        color: soon ? const Color(0xFF16A34A) : line.color,
                      ),
                    ),
                  ),
                ),
              )
            else if (passed)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Center(
                  child: Text('geçti',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      )),
                ),
              ),
            if (showFavorite)
              IconButton(
                onPressed: onToggleFavorite,
                tooltip: isFavorite ? 'Favoriden çıkar' : 'Favorilere ekle',
                icon: Icon(
                  isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: isFavorite ? Colors.amber.shade600 : null,
                ),
              )
            else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}
