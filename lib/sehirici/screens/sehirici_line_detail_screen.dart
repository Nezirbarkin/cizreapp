// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/sehirici_models.dart';
import '../providers/sehirici_provider.dart';
import '../services/sehirici_line_service.dart';
import '../widgets/sehirici_live_map.dart';

/// Hat detayı: rota haritası + durak listesi + sıraları.
class SehiriciLineDetailScreen extends StatefulWidget {
  final SehiriciLine line;
  const SehiriciLineDetailScreen({super.key, required this.line});

  @override
  State<SehiriciLineDetailScreen> createState() =>
      _SehiriciLineDetailScreenState();
}

class _SehiriciLineDetailScreenState extends State<SehiriciLineDetailScreen> {
  final SehiriciLineService _lineService = SehiriciLineService();
  List<SehiriciActiveTrip> _tripsForStops = const [];
  bool _loading = false; // ignore: unused_field

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    setState(() => _loading = true);
    try {
      // Bu hattın duraklarından herhangi birinden geçen aktif seferleri getir
      final all = await _lineService.getActiveTrips();
      final lineTrips =
          all.where((t) => t.lineId == widget.line.id).toList();
      setState(() => _tripsForStops = lineTrips);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SehiriciProvider>();
    final city = provider.selectedCity;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.line.code} — ${widget.line.name}'),
        actions: [
          Icon(widget.line.vehicleType.icon, color: widget.line.color),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        children: [
          if (city != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SehiriciLiveMap(
                lines: [widget.line],
                activeTrips: _tripsForStops,
                center: city,
                zoomLevel: city.zoomLevel,
                height: 300,
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: _InfoChip(
                    icon: Icons.location_on,
                    label: '${widget.line.stops.length} durak',
                  ),
                ),
                if (widget.line.estimatedMinutes != null)
                  Expanded(
                    child: _InfoChip(
                      icon: Icons.access_time,
                      label: '~${widget.line.estimatedMinutes} dk',
                    ),
                  ),
                if (widget.line.fareAmount > 0)
                  Expanded(
                    child: _InfoChip(
                      icon: Icons.payments,
                      label:
                          '${widget.line.fareAmount.toStringAsFixed(0)} TL',
                    ),
                  ),
              ],
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Duraklar ve Tahmini Varış',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          ...widget.line.stops.asMap().entries.map((entry) {
            final idx = entry.key;
            final stop = entry.value;
            final isFavorite =
                provider.favoriteStopIds.contains(stop.stopId);
            return ListTile(
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: widget.line.color,
                child: Text(
                  '${idx + 1}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ),
              title: Text(stop.name),
              subtitle: Text(
                '+${stop.minutesFromStart} dk (başlangıçtan)'
                '${stop.distanceKm != null ? ' · ${stop.distanceKm!.toStringAsFixed(1)} km' : ''}',
              ),
              trailing: IconButton(
                icon: Icon(
                  isFavorite ? Icons.star : Icons.star_border,
                  color: isFavorite ? Colors.amber : null,
                ),
                onPressed: () =>
                    provider.toggleFavorite(stop.stopId),
              ),
            );
          }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
