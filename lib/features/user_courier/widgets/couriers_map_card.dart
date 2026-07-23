import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CouriersMapCard extends StatefulWidget {
  final double? pickupLat;
  final double? pickupLng;
  final double? deliveryLat;
  final double? deliveryLng;

  const CouriersMapCard({
    super.key,
    this.pickupLat,
    this.pickupLng,
    this.deliveryLat,
    this.deliveryLng,
  });

  @override
  State<CouriersMapCard> createState() => _CouriersMapCardState();
}

class _CouriersMapCardState extends State<CouriersMapCard> {
  late GoogleMapController _mapController;
  final Set<Marker> _markers = {};
  bool _isLoading = true;
  Position? _userLocation;

  // Cizre varsayılan koordinatları
  static const double _cizreLatitude = 37.3255;
  static const double _cizveLongitude = 42.1876;

  @override
  void initState() {
    super.initState();
    _getUserLocation();
    _loadCouriers();
  }

  Future<void> _getUserLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
        ),
      );

      if (mounted) {
        setState(() => _userLocation = position);
      }
    } catch (e) {
      debugPrint('Konum alma hatası: $e');
      // Konum alınamadığında Cizre konumunu varsayılan olarak kullan
      if (mounted) {
        setState(() {
          _userLocation = Position(
            latitude: _cizreLatitude,
            longitude: _cizveLongitude,
            timestamp: DateTime.now(),
            accuracy: 0,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
          );
        });
      }
    }
  }

  Future<void> _loadCouriers() async {
    try {
      final couriers = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name, last_known_lat, last_known_lng')
          .eq('role', 'courier')
          .not('last_known_lat', 'is', null)
          .not('last_known_lng', 'is', null)
          .order('created_at', ascending: false);

      debugPrint('📍 Kuryeler yüklendi: ${couriers.length} adet');

      final Set<Marker> markers = {};

      // Kullanıcı konumunu ekle
      if (_userLocation != null) {
        markers.add(
          Marker(
            markerId: const MarkerId('user_location'),
            position: LatLng(_userLocation!.latitude, _userLocation!.longitude),
            infoWindow: const InfoWindow(title: 'Benim Konumum'),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueBlue,
            ),
          ),
        );
        debugPrint('👤 Kullanıcı konumu: ${_userLocation!.latitude}, ${_userLocation!.longitude}');
      }

      // Kuryeler marker'larını ekle
      for (final courier in List<Map<String, dynamic>>.from(couriers)) {
        final lat = (courier['last_known_lat'] as num?)?.toDouble();
        final lng = (courier['last_known_lng'] as num?)?.toDouble();
        final name = courier['full_name'] as String?;
        final id = courier['id'] as String?;

        if (lat != null && lng != null && id != null) {
          markers.add(
            Marker(
              markerId: MarkerId(id),
              position: LatLng(lat, lng),
              infoWindow: InfoWindow(
                title: name ?? 'Kurye',
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueRed,
              ),
            ),
          );
          debugPrint('🚗 Kurye: $name - $lat, $lng');
        }
      }

      if (mounted) {
        setState(() {
          _markers.clear();
          _markers.addAll(markers);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Kuryeler yükleme hatası: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  LatLngBounds _getBounds() {
    if (_markers.isEmpty) {
      return LatLngBounds(
        southwest: const LatLng(37.0, 42.0),
        northeast: const LatLng(38.0, 43.0),
      );
    }

    double minLat = _markers.first.position.latitude;
    double maxLat = _markers.first.position.latitude;
    double minLng = _markers.first.position.longitude;
    double maxLng = _markers.first.position.longitude;

    for (final marker in _markers) {
      minLat = minLat > marker.position.latitude ? marker.position.latitude : minLat;
      maxLat = maxLat < marker.position.latitude ? marker.position.latitude : maxLat;
      minLng = minLng > marker.position.longitude ? marker.position.longitude : minLng;
      maxLng = maxLng < marker.position.longitude ? marker.position.longitude : maxLng;
    }

    return LatLngBounds(
      southwest: LatLng(minLat - 0.01, minLng - 0.01),
      northeast: LatLng(maxLat + 0.01, maxLng + 0.01),
    );
  }

  void _fitBounds() {
    if (_markers.isNotEmpty) {
      _mapController.animateCamera(
        CameraUpdate.newLatLngBounds(_getBounds(), 100),
      );
    }
  }

  @override
  void didUpdateWidget(CouriersMapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pickupLat != widget.pickupLat ||
        oldWidget.pickupLng != widget.pickupLng ||
        oldWidget.deliveryLat != widget.deliveryLat ||
        oldWidget.deliveryLng != widget.deliveryLng) {
      _loadCouriers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.location_on_outlined, color: primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Yakın Kuryeler (${_markers.length})',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (!_isLoading && _markers.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.zoom_out_map, size: 18),
                    onPressed: _fitBounds,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 200,
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: primary),
                  )
                : GoogleMap(
                    initialCameraPosition: const CameraPosition(
                      target: LatLng(_cizreLatitude, _cizveLongitude),
                      zoom: 13,
                    ),
                    onMapCreated: (controller) {
                      _mapController = controller;
                      if (_markers.isNotEmpty) {
                        Future.delayed(const Duration(milliseconds: 500), _fitBounds);
                      }
                    },
                    markers: _markers,
                    zoomControlsEnabled: false,
                    myLocationButtonEnabled: false,
                    compassEnabled: false,
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }
}
