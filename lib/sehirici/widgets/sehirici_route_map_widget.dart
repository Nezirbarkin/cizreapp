import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../models/sehirici_models.dart';
import '../models/sehirici_route_model.dart';
import '../providers/sehirici_location_provider.dart';
import '../services/sehirici_line_service.dart';

/// Hat rotasını harita üzerinde gösteren widget
class SehiriciRouteMapWidget extends StatefulWidget {
  final SehiriciLine line;
  final SehiriciRoute? route;
  final double? height;

  const SehiriciRouteMapWidget({
    super.key,
    required this.line,
    this.route,
    this.height,
  });

  @override
  State<SehiriciRouteMapWidget> createState() =>
      _SehiriciRouteMapWidgetState();
}

class _SehiriciRouteMapWidgetState extends State<SehiriciRouteMapWidget> {
  final SehiriciLineService _lineService = SehiriciLineService();
  late GoogleMapController _mapController;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _initializeMap();
    _loadRoadRoute();
  }

  void _initializeMap() {
    if (widget.line.stops.isEmpty) return;

    // Anında görünüm için durakları düz çizgiyle birleştir; yol takip eden
    // gerçek rota geldiğinde (_loadRoadRoute) bu çizgi onunla değiştirilir.
    final polylinePoints = widget.line.stops
        .map((stop) => LatLng(stop.lat, stop.lng))
        .toList();

    setState(() {
      _polylines = {
        Polyline(
          polylineId: PolylineId('route_${widget.line.id}'),
          points: polylinePoints,
          color: widget.line.color,
          width: 4,
          geodesic: true,
        ),
      };

      _updateMarkers();
    });
  }

  Future<void> _loadRoadRoute() async {
    if (widget.line.stops.length < 2) return;
    final points = await _lineService.getRoadRoute(widget.line);
    if (!mounted || points.length < 2) return;
    setState(() {
      _polylines = {
        Polyline(
          polylineId: PolylineId('route_${widget.line.id}'),
          points: points.map((p) => LatLng(p[0], p[1])).toList(),
          color: widget.line.color,
          width: 4,
          geodesic: false,
        ),
      };
    });
  }

  void _updateMarkers() {
    final markers = <Marker>{};

    // Durak markers
    for (int i = 0; i < widget.line.stops.length; i++) {
      markers.add(
        Marker(
          markerId: MarkerId('stop_$i'),
          position: LatLng(
              widget.line.stops[i].lat, widget.line.stops[i].lng),
          infoWindow: InfoWindow(
            title: widget.line.stops[i].name,
            snippet: '${i + 1}. Durak',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            i == 0
                ? BitmapDescriptor.hueGreen
                : i == widget.line.stops.length - 1
                    ? BitmapDescriptor.hueRed
                    : BitmapDescriptor.hueBlue,
          ),
        ),
      );
    }

    // Şoför konum marker (realtime)
    final locationProvider =
        context.watch<SehiriciLocationProvider>();
    if (locationProvider.currentPosition != null &&
        locationProvider.isTracking) {
      final pos = locationProvider.currentPosition!;
      markers.add(
        Marker(
          markerId: const MarkerId('driver_location'),
          position: LatLng(pos.latitude, pos.longitude),
          infoWindow: const InfoWindow(
            title: 'Şoför Konumu',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueCyan),
        ),
      );
    }

    setState(() => _markers = markers);
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.line.stops.isEmpty) {
      return Center(
        child: Text('${widget.line.name} için durak bulunamadı'),
      );
    }

    // Harita bounds
    final bounds = _calculateBounds();

    return GoogleMap(
      onMapCreated: (controller) {
        _mapController = controller;
        _mapController.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 100),
        );
      },
      initialCameraPosition: CameraPosition(
        target: LatLng(
          widget.line.stops[0].lat,
          widget.line.stops[0].lng,
        ),
        zoom: 13,
      ),
      polylines: _polylines,
      markers: _markers,
      myLocationEnabled: false,
      zoomControlsEnabled: true,
      trafficEnabled: false,
      buildingsEnabled: true,
      mapType: Theme.of(context).brightness == Brightness.dark
          ? MapType.normal
          : MapType.normal,
    );
  }

  LatLngBounds _calculateBounds() {
    double minLat = widget.line.stops[0].lat;
    double maxLat = widget.line.stops[0].lat;
    double minLng = widget.line.stops[0].lng;
    double maxLng = widget.line.stops[0].lng;

    for (final stop in widget.line.stops) {
      if (stop.lat < minLat) minLat = stop.lat;
      if (stop.lat > maxLat) maxLat = stop.lat;
      if (stop.lng < minLng) minLng = stop.lng;
      if (stop.lng > maxLng) maxLng = stop.lng;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }
}

/// Animasyonlu hat kartı (hikaye kartı tarzı)
class SehiriciLineStoryCard extends StatefulWidget {
  final SehiriciLine line;
  final SehiriciRoute? activeRoute;
  final VoidCallback? onTap;

  const SehiriciLineStoryCard({
    super.key,
    required this.line,
    this.activeRoute,
    this.onTap,
  });

  @override
  State<SehiriciLineStoryCard> createState() =>
      _SehiriciLineStoryCardState();
}

class _SehiriciLineStoryCardState extends State<SehiriciLineStoryCard>
    with SingleTickerProviderStateMixin {
  late ScrollController _scrollController;
  double _scrollProgress = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    // Scroll progress: 0 = top (hikaye view), 1 = bottom (harita view)
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    final progress =
        maxScroll > 0 ? (currentScroll / maxScroll).clamp(0.0, 1.0) : 0.0;

    setState(() => _scrollProgress = progress);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Dinamik yükseklik: scroll progress'e göre kartı büyüt
    final minHeight = 300.0;
    final maxHeight = MediaQuery.of(context).size.height - 60;
    final currentHeight = minHeight + (maxHeight - minHeight) * _scrollProgress;

    // Border radius: scroll progress'e göre yuvarlaklaş
    final borderRadius =
        BorderRadius.circular((20 * (1 - _scrollProgress)).toDouble());

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        height: currentHeight,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // Header (hikaye kartı tarzı)
            SliverAppBar(
              expandedHeight: 150,
              pinned: true,
              backgroundColor: widget.line.color,
              shape: RoundedRectangleBorder(
                borderRadius: borderRadius,
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Background gradient
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            widget.line.color,
                            widget.line.color.withValues(alpha: 0.8),
                          ],
                        ),
                      ),
                    ),
                    // Hat bilgisi
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: Colors.white.withValues(alpha: 0.3),
                                child: Icon(
                                  widget.line.vehicleType.icon,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${widget.line.code} - ${widget.line.name}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '${widget.line.stops.length} durak · ₺${widget.line.fareAmount.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (widget.activeRoute?.status ==
                                  RouteStatus.active)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    '🔴 Yolda',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Duraklar listesi
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final stop = widget.line.stops[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: widget.line.color,
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    title: Text(stop.name),
                    subtitle: Text(
                      '${stop.lat.toStringAsFixed(4)}, ${stop.lng.toStringAsFixed(4)}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: index == widget.line.stops.length - 1
                        ? const Icon(Icons.flag, color: Colors.red)
                        : null,
                  );
                },
                childCount: widget.line.stops.length,
              ),
            ),
            // Harita
            SliverToBoxAdapter(
              child: Container(
                height: 300,
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SehiriciRouteMapWidget(
                    line: widget.line,
                    route: widget.activeRoute,
                  ),
                ),
              ),
            ),
            // Padding bottom
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.of(context).padding.bottom + 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
