// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/sehirici_models.dart';
import '../providers/sehirici_provider.dart';
import 'sehirici_live_map.dart';

/// Instagram hikayesi tarzında yuvarlak Şehiriçi Servisler kartı
/// Hikayelerin yanında görünür ve tıklanınca tam ekran harita açar
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
    final provider = context.read<SehiriciProvider>();
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => _SehiriciMapDialog(provider: provider),
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
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: trips.isEmpty
                            ? [
                                Colors.grey.shade400,
                                Colors.grey.shade600,
                              ]
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
                        color: Theme.of(context).colorScheme.primaryContainer,
                      ),
                      child: Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Icons.directions_bus,
                              size: 28,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            // Canlı sefer varsa animasyonlu nokta
                            if (trips.isNotEmpty)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.green.shade400,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.green.shade400.withOpacity(0.6),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Başlık
              SizedBox(
                height: 14,
                child: Text(
                  'Şehiriçi',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
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

/// Full mode (açık) Şehiriçi hikaye kartı - harita önizlemesi ile
class SehiriciFullStoryCard extends StatelessWidget {
  const SehiriciFullStoryCard({super.key});

  void _openFullDialog(BuildContext context) {
    final provider = context.read<SehiriciProvider>();
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => _SehiriciMapDialog(provider: provider),
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
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Harita önizlemesi veya placeholder
              trips.isEmpty
                  ? Container(
                      color: Colors.grey.shade800,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.directions_bus_outlined,
                            size: 48,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Aktif Sefer Yok',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : IgnorePointer(
                      child: SehiriciLiveMap(
                        lines: lines,
                        activeTrips: trips,
                        center: city,
                        zoomLevel: city.zoomLevel,
                        height: double.infinity,
                        interactive: false,
                      ),
                    ),
              
              // Gradient overlay (üstten)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.6),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              
              // Başlık ve bilgi
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context).colorScheme.primaryContainer,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Icon(
                        Icons.directions_bus,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Şehiriçi Servisler',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(
                                  color: Colors.black45,
                                  blurRadius: 3,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            trips.isEmpty
                                ? 'Aktif sefer yok'
                                : '${trips.length} sefer aktif',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
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

/// Tam ekran Şehiriçi harita dialog'u
class _SehiriciMapDialog extends StatefulWidget {
  final SehiriciProvider provider;

  const _SehiriciMapDialog({required this.provider});

  @override
  State<_SehiriciMapDialog> createState() => _SehiriciMapDialogState();
}

class _SehiriciMapDialogState extends State<_SehiriciMapDialog> {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SehiriciProvider>();
    final trips = provider.activeTrips;
    final lines = provider.lines;
    final city = provider.selectedCity;

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
            // Header
            SafeArea(
              bottom: false,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      tooltip: 'Kapat',
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Şehiriçi Servisler',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            trips.isEmpty
                                ? 'Şu an aktif sefer yok'
                                : '${trips.length} sefer aktif · ${lines.length} hat',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Tüm hatlar butonu
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.of(context).pushNamed('/sehirici-lines');
                      },
                      icon: const Icon(Icons.list, size: 18),
                      label: const Text('Tüm Hatlar'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Harita - İKİ PARMAKLA ZOOM AKTİF
            Expanded(
              child: trips.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.directions_bus_outlined,
                            size: 80,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Şu an aktif sefer yok',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Servisler başladığında burada göreceksiniz',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : SehiriciLiveMap(
                      lines: lines,
                      activeTrips: trips,
                      center: city,
                      zoomLevel: city.zoomLevel,
                      height: double.infinity,
                      interactive: true, // Zoom ve kaydırma aktif
                    ),
            ),

            // Alt bilgi çubuğu - Aktif seferler
            if (trips.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 16,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Aktif Seferler',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 70,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          itemCount: trips.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 8),
                          itemBuilder: (_, i) => _TripInfoChip(trip: trips[i]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Sefer bilgi chip'i
class _TripInfoChip extends StatelessWidget {
  final SehiriciActiveTrip trip;

  const _TripInfoChip({required this.trip});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: trip.color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: trip.color.withOpacity(0.4), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_bus, color: trip.color, size: 24),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                trip.lineCode,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: trip.color,
                ),
              ),
              const SizedBox(height: 2),
              if (trip.etaMinutes != null)
                Text(
                  'Tahmini: ${trip.etaMinutes} dk',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
