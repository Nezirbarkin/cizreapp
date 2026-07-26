// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/sehirici_models.dart';
import '../providers/sehirici_provider.dart';
import '../services/sehirici_line_service.dart';
import '../services/sehirici_trip_service.dart';
import '../widgets/sehirici_live_map.dart';
import 'sehirici_line_detail_screen.dart';

/// Kullanıcı: Hat listesi + harita + duraklar.
class SehiriciLinesScreen extends StatefulWidget {
  const SehiriciLinesScreen({super.key});

  @override
  State<SehiriciLinesScreen> createState() => _SehiriciLinesScreenState();
}

class _SehiriciLinesScreenState extends State<SehiriciLinesScreen> {
  final SehiriciTripService _tripService = SehiriciTripService();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<SehiriciProvider>();
      p.initialize();
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) p.refreshActiveTrips();
      });
      _tripService.watchActiveTrips(
        cityId: p.selectedCityId,
        onTripUpdate: p.onTripRealtimeUpdate,
        onTripDelete: p.onTripRealtimeDelete,
      );
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tripService.stopWatching();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SehiriciProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Şehiriçi Servisler'),
        actions: [
          IconButton(
            icon: const Icon(Icons.star_outline),
            onPressed: () => Navigator.of(context).pushNamed('/sehirici-favorites'),
            tooltip: 'Favori Duraklarım',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            provider.loadLinesAndTrips(provider.selectedCityId ?? ''),
        child: provider.isLoading && provider.lines.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : provider.moduleEnabled == false
                ? const _DisabledState()
                : CustomScrollView(
                    slivers: [
                      // Şehir seçici
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: DropdownButtonFormField<String>(
                            value: provider.selectedCityId,
                            decoration: const InputDecoration(
                              labelText: 'Şehir',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                            ),
                            items: provider.cities
                                .map((c) => DropdownMenuItem(
                                      value: c.id,
                                      child: Text(c.name),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) provider.selectCity(v);
                            },
                          ),
                        ),
                      ),
                      // Harita
                      if (provider.selectedCity != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: SehiriciLiveMap(
                              lines: provider.lines,
                              activeTrips: provider.activeTrips,
                              center: provider.selectedCity!,
                              zoomLevel: provider.selectedCity!.zoomLevel,
                              height: 260,
                            ),
                          ),
                        ),
                      // Aktif sefer özetleri
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                          child: Text(
                            'Aktif Seferler (${provider.activeTrips.length})',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      if (provider.activeTrips.isEmpty)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(
                              child: Text(
                                  'Şu an aktif sefer yok. Lütfen daha sonra tekrar deneyin.'),
                            ),
                          ),
                        )
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) => _ActiveTripTile(
                                trip: provider.activeTrips[i]),
                            childCount: provider.activeTrips.length,
                          ),
                        ),
                      // Hat listesi
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
                          child: Text(
                            'Hatlar (${provider.lines.length})',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => _LineTile(line: provider.lines[i]),
                          childCount: provider.lines.length,
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ),
      ),
    );
  }
}

class _ActiveTripTile extends StatelessWidget {
  final SehiriciActiveTrip trip;
  const _ActiveTripTile({required this.trip});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: trip.color.withOpacity(0.15),
          child: Icon(Icons.directions_bus, color: trip.color),
        ),
        title: Text('${trip.lineCode} — ${trip.lineName}'),
        subtitle: trip.nextStopName == null
            ? const Text('Yolda')
            : Text('Sonraki: ${trip.nextStopName}'
                '${trip.etaMinutes != null ? ' · ${trip.etaMinutes} dk' : ''}'),
        trailing: trip.etaMinutes != null
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: trip.color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${trip.etaMinutes} dk',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700),
                ),
              )
            : null,
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  final SehiriciLine line;
  const _LineTile({required this.line});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: line.color.withOpacity(0.15),
          child: Icon(line.vehicleType.icon, color: line.color),
        ),
        title: Text('${line.code} — ${line.name}'),
        subtitle: Text(
          '${line.stops.length} durak'
          '${line.estimatedMinutes != null ? ' · ~${line.estimatedMinutes} dk' : ''}'
          '${line.fareAmount > 0 ? ' · ${line.fareAmount.toStringAsFixed(0)} TL' : ''}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SehiriciLineDetailScreen(line: line),
          ));
        },
      ),
    );
  }
}

class _DisabledState extends StatelessWidget {
  const _DisabledState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_bus_outlined,
              size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text('Bu özellik şu anda kapalı',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            'Şehiriçi servisler modülü yönetici tarafından kapatıldı.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
