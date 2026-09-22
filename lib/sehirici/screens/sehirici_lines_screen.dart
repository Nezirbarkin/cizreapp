import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sehirici_models.dart';
import '../providers/sehirici_provider.dart';
import '../services/sehirici_trip_service.dart';
import '../utils/sehirici_arrivals.dart';
import '../widgets/sehirici_common_widgets.dart';
import '../widgets/sehirici_live_map.dart';
import 'sehirici_line_detail_screen.dart';

/// Kullanıcı: canlı harita + aktif seferler + hat listesi.
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
      if (!mounted) return;
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
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Şehiriçi Servisler',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.star_outline_rounded),
            onPressed: () =>
                Navigator.of(context).pushNamed('/sehirici-favorites'),
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
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      if (provider.cities.length > 1)
                        SliverToBoxAdapter(child: _CityChips(provider: provider)),
                      // Harita
                      if (provider.selectedCity != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                            child: SehiriciLiveMap(
                              lines: provider.lines,
                              activeTrips: provider.activeTrips,
                              center: provider.selectedCity!,
                              zoomLevel: provider.selectedCity!.zoomLevel,
                              height: 340,
                              highlightLineId: provider.highlightedLineId,
                              showLineChips: true,
                              onHighlightChanged: provider.highlightLine,
                              borderRadius: 22,
                            ),
                          ),
                        ),
                      // Özet
                      SliverToBoxAdapter(child: _SummaryRow(provider: provider)),
                      // Aktif seferler
                      SliverToBoxAdapter(
                        child: SehiriciSectionHeader(
                          title: 'Aktif Seferler',
                          trailing: '${provider.activeTrips.length}',
                        ),
                      ),
                      if (provider.activeTrips.isEmpty)
                        const SliverToBoxAdapter(child: _NoTripsCard())
                      else
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: 118,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              itemCount: provider.activeTrips.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (ctx, i) => _TripCard(
                                trip: provider.activeTrips[i],
                                line: _lineOf(provider, provider.activeTrips[i]),
                                onTap: () => provider
                                    .highlightLine(provider.activeTrips[i].lineId),
                              ),
                            ),
                          ),
                        ),
                      // Hat listesi
                      SliverToBoxAdapter(
                        child: SehiriciSectionHeader(
                          title: 'Hatlar',
                          trailing: '${provider.lines.length}',
                        ),
                      ),
                      if (provider.lines.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Text(
                              'Bu şehir için henüz hat tanımlanmamış.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: scheme.onSurface.withValues(alpha: 0.55),
                              ),
                            ),
                          ),
                        )
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) => _LineCard(
                              line: provider.lines[i],
                              liveCount: provider.activeTrips
                                  .where((t) => t.lineId == provider.lines[i].id)
                                  .length,
                              highlighted: provider.highlightedLineId ==
                                  provider.lines[i].id,
                            ),
                            childCount: provider.lines.length,
                          ),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 28)),
                    ],
                  ),
      ),
    );
  }

  SehiriciLine _lineOf(SehiriciProvider provider, SehiriciActiveTrip trip) {
    for (final l in provider.lines) {
      if (l.id == trip.lineId) return l;
    }
    return SehiriciLine(
      id: trip.lineId,
      code: trip.lineCode,
      name: trip.lineName,
      colorHex: trip.lineColor,
    );
  }
}

class _CityChips extends StatelessWidget {
  final SehiriciProvider provider;
  const _CityChips({required this.provider});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        itemCount: provider.cities.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = provider.cities[i];
          return ChoiceChip(
            label: Text(c.name),
            selected: c.id == provider.selectedCityId,
            onSelected: (_) => provider.selectCity(c.id),
            avatar: const Icon(Icons.location_city_rounded, size: 16),
          );
        },
      ),
    );
  }
}

/// Üç özet kutusu: aktif sefer, hat, durak.
class _SummaryRow extends StatelessWidget {
  final SehiriciProvider provider;
  const _SummaryRow({required this.provider});

  @override
  Widget build(BuildContext context) {
    final stopIds = <String>{
      for (final l in provider.lines)
        for (final s in l.stops) s.stopId,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: SehiriciStatTile(
              icon: Icons.sensors_rounded,
              value: '${provider.activeTrips.length}',
              label: 'Yolda',
              color: const Color(0xFF16A34A),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SehiriciStatTile(
              icon: Icons.alt_route_rounded,
              value: '${provider.lines.length}',
              label: 'Hat',
              color: const Color(0xFF1976D2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SehiriciStatTile(
              icon: Icons.signpost_rounded,
              value: '${stopIds.length}',
              label: 'Durak',
              color: const Color(0xFFF59E0B),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoTripsCard extends StatelessWidget {
  const _NoTripsCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(Icons.bedtime_outlined,
              size: 30, color: scheme.onSurface.withValues(alpha: 0.45)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Şu an yolda araç yok. Servisler başladığında burada canlı '
              'olarak göreceksiniz.',
              style: TextStyle(
                height: 1.35,
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Yatay kaydırılan aktif sefer kartı.
class _TripCard extends StatelessWidget {
  final SehiriciActiveTrip trip;
  final SehiriciLine line;
  final VoidCallback onTap;

  const _TripCard({
    required this.trip,
    required this.line,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onBreak = trip.status == SehiriciTripStatus.paused;
    return SizedBox(
      width: 250,
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: line.color.withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(
                  color: line.color.withValues(alpha: 0.10),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: line.color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: SehiriciVehicleIcon.forLine(line, height: 62),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          SehiriciLineBadge(
                            code: trip.lineCode.isEmpty ? line.code : trip.lineCode,
                            color: line.color,
                            height: 24,
                            minWidth: 38,
                          ),
                          const SizedBox(width: 6),
                          SehiriciStatusPill(
                            label: onBreak ? 'Mola' : 'Yolda',
                            color: onBreak
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFF16A34A),
                            dense: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        trip.nextStopName == null
                            ? (trip.lineName.isEmpty ? line.name : trip.lineName)
                            : 'Sıradaki: ${trip.nextStopName}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          height: 1.2,
                        ),
                      ),
                      if (trip.etaMinutes != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          formatArrivalMinutes(trip.etaMinutes!),
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: line.color,
                          ),
                        ),
                      ],
                    ],
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

/// Hat kartı: rozet + ad + araç ikonu + bilgi çipleri; dokununca hat detayı.
class _LineCard extends StatelessWidget {
  final SehiriciLine line;
  final int liveCount;
  final bool highlighted;

  const _LineCard({
    required this.line,
    required this.liveCount,
    required this.highlighted,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SehiriciLineDetailScreen(line: line),
          )),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: highlighted
                    ? line.color
                    : scheme.onSurface.withValues(alpha: 0.08),
                width: highlighted ? 1.8 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 66,
                  decoration: BoxDecoration(
                    color: line.color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: SehiriciVehicleIcon.forLine(line, height: 54),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SehiriciLineBadge.forLine(line, height: 26, minWidth: 42),
                          const SizedBox(width: 8),
                          if (liveCount > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SehiriciLiveDot(size: 7),
                                Text(
                                  '$liveCount araç yolda',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF16A34A),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        line.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 5,
                        children: [
                          SehiriciMetaChip(
                            icon: Icons.signpost_outlined,
                            label: '${line.stops.length} durak',
                          ),
                          if (line.estimatedMinutes != null)
                            SehiriciMetaChip(
                              icon: Icons.schedule_rounded,
                              label: '~${line.estimatedMinutes} dk',
                            ),
                          if (line.fareAmount > 0)
                            SehiriciMetaChip(
                              icon: Icons.payments_outlined,
                              label: '${line.fareAmount.toStringAsFixed(0)} ₺',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip:
                          highlighted ? 'Vurguyu kaldır' : 'Haritada göster',
                      onPressed: () =>
                          context.read<SehiriciProvider>().highlightLine(line.id),
                      icon: Icon(
                        highlighted
                            ? Icons.visibility_rounded
                            : Icons.visibility_outlined,
                        color: highlighted ? line.color : null,
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: scheme.onSurface.withValues(alpha: 0.4)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DisabledState extends StatelessWidget {
  const _DisabledState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.6,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.directions_bus_outlined,
                    size: 64, color: scheme.onSurface.withValues(alpha: 0.3)),
                const SizedBox(height: 12),
                const Text(
                  'Bu özellik şu anda kapalı',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Şehiriçi servisler modülü yönetici tarafından kapatıldı.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
