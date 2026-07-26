// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/sehirici_models.dart';
import '../providers/sehirici_provider.dart';
import '../services/sehirici_trip_service.dart';
import 'sehirici_live_map.dart';

/// Anasayfa (market_screen) Hikaye bölümünün altına eklenecek
/// açılır/kapanır canlı servis harita kartı.
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
    if (!provider.moduleEnabled) return;
    final cityId = provider.selectedCityId;
    SehiriciTripService().watchActiveTrips(
      cityId: cityId,
      onTripUpdate: provider.onTripRealtimeUpdate,
      onTripDelete: provider.onTripRealtimeDelete,
    );
  }

  @override
  void dispose() {
    // Realtime'i kapatmıyoruz — provider singleton, başka ekranlar da kullanabilir
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SehiriciProvider>();
    if (!provider.moduleEnabled) return const SizedBox.shrink();

    final trips = provider.activeTrips;
    final lines = provider.lines;
    final city = provider.selectedCity;
    if (city == null || city.id.isEmpty) return const SizedBox.shrink();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.directions_bus,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Şehiriçi Servisler',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          trips.isEmpty
                              ? 'Şu an aktif sefer yok'
                              : '${trips.length} sefer aktif · ${lines.length} hat',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down, size: 22),
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
                        SizedBox(
                          height: 32,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: provider.cities.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 6),
                            itemBuilder: (_, i) {
                              final c = provider.cities[i];
                              final selected = c.id == provider.selectedCityId;
                              return ChoiceChip(
                                label: Text(c.name),
                                selected: selected,
                                onSelected: (_) =>
                                    provider.selectCity(c.id),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Harita
                        SehiriciLiveMap(
                          lines: lines,
                          activeTrips: trips,
                          center: city,
                          zoomLevel: city.zoomLevel,
                          height: widget.height,
                          interactive: true,
                        ),
                        const SizedBox(height: 8),
                        // Kısa özet
                        if (trips.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              'Şu an aktif sefer yok. Detayları görmek için '
                              'haritaya tıklayın.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          )
                        else
                          SizedBox(
                            height: 64,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: trips.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 6),
                              itemBuilder: (_, i) =>
                                  _TripMiniChip(trip: trips[i]),
                            ),
                          ),
                        // "Tüm hatlar" linki
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () {
                              Navigator.of(context).pushNamed(
                                '/sehirici-lines',
                              );
                            },
                            icon: const Icon(Icons.arrow_forward, size: 14),
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
  const _TripMiniChip({required this.trip});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: trip.color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: trip.color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_bus, color: trip.color, size: 14),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                trip.lineCode,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 12),
              ),
              if (trip.etaMinutes != null)
                Text(
                  '${trip.etaMinutes} dk',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
