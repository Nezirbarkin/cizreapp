// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import '../models/sehirici_models.dart';
import '../models/sehirici_route_model.dart';
import '../services/sehirici_route_service.dart';

/// Rota görüntüleme dialog'u (admin için)
class SehiriciRouteViewerDialog extends StatefulWidget {
  final SehiriciLine line;

  const SehiriciRouteViewerDialog({
    super.key,
    required this.line,
  });

  @override
  State<SehiriciRouteViewerDialog> createState() =>
      _SehiriciRouteViewerDialogState();
}

class _SehiriciRouteViewerDialogState extends State<SehiriciRouteViewerDialog> {
  final SehiriciRouteService _routeService = SehiriciRouteService();
  List<SehiriciRoute> _routes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    setState(() => _loading = true);
    _routes = await _routeService.getLineRoutes(widget.line.id);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _createRoute() async {
    final buildContext = context;
    final route = await _routeService.createLineRoute(widget.line.id);
    if (!mounted) return;
    if (route != null) {
      await _loadRoutes();
      if (mounted) {
        ScaffoldMessenger.of(buildContext).showSnackBar(
          const SnackBar(
            content: Text('Rota oluşturuldu'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(buildContext).showSnackBar(
        const SnackBar(
          content: Text('Rota oluşturulamadı'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 800),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: widget.line.color,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.line.vehicleType.icon,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.line.code} - ${widget.line.name}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${widget.line.stops.length} durak',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Yeni rota oluştur
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: widget.line.stops.isEmpty ? null : _createRoute,
                  icon: const Icon(Icons.add_road),
                  label: Text(
                    widget.line.stops.isEmpty
                        ? 'Rota oluşturmak için hatta durak ekleyin'
                        : 'Yeni Rota Oluştur',
                  ),
                ),
              ),
            ),
            // Content
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _routes.isEmpty
                      ? const Center(child: Text('Rota bulunamadı'))
                      : ListView.builder(
                          itemCount: _routes.length,
                          itemBuilder: (ctx, i) {
                            final route = _routes[i];
                            return _RouteListItem(
                              route: route,
                              line: widget.line,
                              onDelete: () async {
                                final buildContext = context;
                                final confirm = await showDialog<bool>(
                                  context: buildContext,
                                  builder: (c) => AlertDialog(
                                    title: const Text('Rotayı Sil'),
                                    content: const Text(
                                        'Bu rotayı silmek istediğinize emin misiniz?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(c, false),
                                        child: const Text('İptal'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(c, true),
                                        child: const Text('Sil'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true && mounted) {
                                  await _routeService.deleteRoute(route.id);
                                  _loadRoutes();
                                  if (mounted) {
                                    ScaffoldMessenger.of(buildContext).showSnackBar(
                                      const SnackBar(
                                        content: Text('Rota silindi'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                }
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rota liste öğesi
class _RouteListItem extends StatelessWidget {
  final SehiriciRoute route;
  final SehiriciLine line;
  final VoidCallback onDelete;

  const _RouteListItem({
    required this.route,
    required this.line,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColor(),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                route.status.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                route.startedAt != null
                    ? 'Başlatıldı: ${route.startedAt!.toLocal().hour}:${route.startedAt!.toLocal().minute.toString().padLeft(2, '0')}'
                    : 'Taslak Rota',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${route.points.length} nokta',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRoutePoints(),
                const SizedBox(height: 12),
                if (route.status == RouteStatus.draft)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete),
                        label: const Text('Sil'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutePoints() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Rota Noktaları:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        ...route.points.take(5).map((point) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: line.color,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${point.order + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${point.lat.toStringAsFixed(4)}, ${point.lng.toStringAsFixed(4)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          );
        }),
        if (route.points.length > 5)
          Text(
            '+${route.points.length - 5} daha',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
      ],
    );
  }

  Color _statusColor() {
    switch (route.status) {
      case RouteStatus.draft:
        return Colors.orange;
      case RouteStatus.active:
        return Colors.green;
      case RouteStatus.completed:
        return Colors.blue;
      case RouteStatus.cancelled:
        return Colors.red;
    }
  }
}
