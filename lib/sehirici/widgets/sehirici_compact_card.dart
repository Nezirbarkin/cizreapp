import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sehirici_models.dart';
import '../providers/sehirici_provider.dart';
import '../utils/sehirici_arrivals.dart';
import 'sehirici_common_widgets.dart';
import 'sehirici_live_map.dart';

/// Anasayfa (market_screen) Hikaye bölümünün altındaki açılır/kapanır canlı
/// servis harita kartı.
class SehiriciCompactCard extends StatefulWidget {
  final double height;
  const SehiriciCompactCard({super.key, this.height = 240});

  @override
  State<SehiriciCompactCard> createState() => _SehiriciCompactCardState();
}

class _SehiriciCompactCardState extends State<SehiriciCompactCard> {
  bool _expanded = false;

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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SehiriciProvider>();
    if (!provider.moduleEnabled) return const SizedBox.shrink();

    final trips = provider.activeTrips;
    final lines = provider.lines;
    final city = provider.selectedCity;
    if (city == null || city.id.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final live = trips.isNotEmpty;
    final firstLine = lines.isNotEmpty ? lines.first : null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: live
              ? const Color(0xFF22C55E).withValues(alpha: 0.35)
              : scheme.onSurface.withValues(alpha: 0.07),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Başlık
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: (firstLine?.color ?? scheme.primary)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Transform.rotate(
                      angle: 0.6,
                      child: SehiriciVehicleIcon(
                        vehicleKey: firstLine?.vehicleKey,
                        color: firstLine?.color ?? scheme.primary,
                        height: 34,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Şehiriçi Servisler',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            SehiriciLiveDot(
                              size: 6,
                              color: live
                                  ? const Color(0xFF22C55E)
                                  : Colors.grey,
                              pulsing: live,
                            ),
                            Flexible(
                              child: Text(
                                live
                                    ? '${trips.length} sefer aktif · ${lines.length} hat'
                                    : 'Şu an aktif sefer yok',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        size: 26),
                  ),
                ],
              ),
            ),
          ),

          // İçerik (harita + kısa özet)
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Şehir seçici (kompakt)
                        if (provider.cities.length > 1) ...[
                          SizedBox(
                            height: 34,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: provider.cities.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 6),
                              itemBuilder: (_, i) {
                                final c = provider.cities[i];
                                return ChoiceChip(
                                  label: Text(c.name),
                                  selected: c.id == provider.selectedCityId,
                                  onSelected: (_) => provider.selectCity(c.id),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        // Harita
                        SehiriciLiveMap(
                          lines: lines,
                          activeTrips: trips,
                          center: city,
                          zoomLevel: city.zoomLevel,
                          height: widget.height,
                          interactive: true,
                          borderRadius: 16,
                        ),
                        const SizedBox(height: 10),
                        // Kısa özet
                        if (trips.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(6),
                            child: Text(
                              'Şu an aktif sefer yok. Duraklar ve hat '
                              'güzergâhları haritada görünür; servisler '
                              'başlayınca canlı olarak takip edebilirsiniz.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: scheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          )
                        else
                          SizedBox(
                            height: 66,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: trips.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (_, i) => _TripMiniChip(
                                trip: trips[i],
                                line: lines.firstWhere(
                                  (l) => l.id == trips[i].lineId,
                                  orElse: () => SehiriciLine(
                                    id: trips[i].lineId,
                                    code: trips[i].lineCode,
                                    name: trips[i].lineName,
                                    colorHex: trips[i].lineColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        // "Tüm hatlar" linki
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () {
                              Navigator.of(context).pushNamed('/sehirici-lines');
                            },
                            icon: const Icon(Icons.arrow_forward_rounded,
                                size: 16),
                            label: const Text('Tüm hatlar'),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _TripMiniChip extends StatelessWidget {
  final SehiriciActiveTrip trip;
  final SehiriciLine line;
  const _TripMiniChip({required this.trip, required this.line});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
      decoration: BoxDecoration(
        color: trip.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: trip.color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SehiriciVehicleIcon.forLine(line, height: 46),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              SehiriciLineBadge(
                code: trip.lineCode.isEmpty ? line.code : trip.lineCode,
                color: trip.color,
                height: 22,
                minWidth: 34,
              ),
              const SizedBox(height: 4),
              Text(
                trip.etaMinutes != null
                    ? formatArrivalMinutes(trip.etaMinutes!)
                    : 'Yolda',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
