import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PackageTrackingScreen extends StatefulWidget {
  final String packageId;
  final String? packageTitle;

  const PackageTrackingScreen({
    super.key,
    required this.packageId,
    this.packageTitle,
  });

  @override
  State<PackageTrackingScreen> createState() => _PackageTrackingScreenState();
}

class _PackageTrackingScreenState extends State<PackageTrackingScreen> {
  late GoogleMapController _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  bool _isLoading = true;

  Position? _userLocation;
  Map<String, dynamic>? _courierLocation;
  Map<String, dynamic>? _packageData;

  StreamSubscription? _courierLocationStream;
  StreamSubscription? _userLocationStream;
  Timer? _locationUpdateTimer;

  static const double _cizreLatitude = 37.3255;
  static const double _cizveLongitude = 42.1876;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Future.wait([
      _getUserLocation(),
      _loadPackageData(),
    ]);
    if (mounted) {
      setState(() => _isLoading = false);
      _startLocationTracking();
    }
  }

  Future<void> _getUserLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final result = await Geolocator.requestPermission();
        if (result == LocationPermission.denied) return;
      }

      if (!mounted) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
        ),
      );

      if (mounted) setState(() => _userLocation = position);
    } catch (e) {
      debugPrint('Konum alma hatası: $e');
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

  Future<void> _loadPackageData() async {
    try {
      final data = await Supabase.instance.client
          .from('courier_requests')
          .select()
          .eq('id', widget.packageId)
          .single();

      if (!mounted) return;
      setState(() => _packageData = data);

      // Kurye atamasını yükle
      final courierId = data['courier_id'] as String?;
      if (courierId != null && courierId.isNotEmpty) {
        _listenToCourierLocation(courierId);
      } else {
        debugPrint('Henüz kurye atanmamış');
      }
    } catch (e) {
      debugPrint('❌ Paket verisi yükleme hatası: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _listenToCourierLocation(String courierId) {
    _courierLocationStream = Supabase.instance.client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', courierId)
        .listen((data) {
          if (data.isNotEmpty) {
            final courier = data[0];
            if (mounted) {
              setState(() {
                _courierLocation = {
                  'id': courier['id'],
                  'full_name': courier['full_name'],
                  'lat': (courier['last_known_lat'] as num?)?.toDouble(),
                  'lng': (courier['last_known_lng'] as num?)?.toDouble(),
                };
              });
              _updateMarkers();
            }
          }
        });
  }

  void _startLocationTracking() {
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _updateUserLocation();
    });

    if (_packageData?['courier_id'] != null) {
      _loadPackageData();
    }
  }

  Future<void> _updateUserLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 5,
        ),
      );

      if (mounted) {
        setState(() => _userLocation = position);
        _updateMarkers();

        // Kullanıcının konumunu veritabanına kaydet
        await Supabase.instance.client
            .from('profiles')
            .update({
              'last_known_lat': position.latitude,
              'last_known_lng': position.longitude,
            })
            .eq('id', Supabase.instance.client.auth.currentUser?.id ?? '')
            .then((_) => debugPrint('Kullanıcı konumu güncellendi'));
      }
    } catch (e) {
      debugPrint('Konum güncelleme hatası: $e');
    }
  }

  void _updateMarkers() {
    final Set<Marker> newMarkers = {};
    final Set<Polyline> newPolylines = {};

    // Kullanıcı konumu - insan ikonu
    if (_userLocation != null) {
      newMarkers.add(
        Marker(
          markerId: const MarkerId('user_location'),
          position: LatLng(_userLocation!.latitude, _userLocation!.longitude),
          infoWindow: const InfoWindow(title: 'Benim Konumum'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueBlue,
          ),
        ),
      );
    }

    // Kurye konumu - motor ikonu
    if (_courierLocation != null) {
      final courierLat = _courierLocation!['lat'] as double?;
      final courierLng = _courierLocation!['lng'] as double?;

      if (courierLat != null && courierLng != null) {
        newMarkers.add(
          Marker(
            markerId: const MarkerId('courier_location'),
            position: LatLng(courierLat, courierLng),
            infoWindow: InfoWindow(
              title: _courierLocation!['full_name'] ?? 'Kurye',
              snippet: 'Motor Konumu',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
          ),
        );

        // Kullanıcı ve kurye arasında çizgi çek
        if (_userLocation != null) {
          newPolylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              color: Colors.blue,
              width: 3,
              points: [
                LatLng(_userLocation!.latitude, _userLocation!.longitude),
                LatLng(courierLat, courierLng),
              ],
            ),
          );
        }
      }
    }

    // Alım noktası
    if (_packageData != null) {
      final pickupLat = (_packageData!['pickup_lat'] as num?)?.toDouble();
      final pickupLng = (_packageData!['pickup_lng'] as num?)?.toDouble();

      if (pickupLat != null && pickupLng != null) {
        newMarkers.add(
          Marker(
            markerId: const MarkerId('pickup_location'),
            position: LatLng(pickupLat, pickupLng),
            infoWindow: const InfoWindow(
              title: 'Alım Noktası',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
          ),
        );
      }

      // Teslim noktası
      final deliveryLat = (_packageData!['delivery_lat'] as num?)?.toDouble();
      final deliveryLng = (_packageData!['delivery_lng'] as num?)?.toDouble();

      if (deliveryLat != null && deliveryLng != null) {
        newMarkers.add(
          Marker(
            markerId: const MarkerId('delivery_location'),
            position: LatLng(deliveryLat, deliveryLng),
            infoWindow: const InfoWindow(
              title: 'Teslim Noktası',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueOrange,
            ),
          ),
        );
      }
    }

    if (mounted) {
      setState(() {
        _markers.clear();
        _markers.addAll(newMarkers);
        _polylines.clear();
        _polylines.addAll(newPolylines);
      });
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

  String? _getDistance() {
    if (_userLocation == null || _courierLocation == null) return null;

    final userLat = _userLocation!.latitude;
    final userLng = _userLocation!.longitude;

    final courierLat = _courierLocation!['lat'] as double?;
    final courierLng = _courierLocation!['lng'] as double?;

    if (courierLat == null || courierLng == null) return null;

    final distance = Geolocator.distanceBetween(
      userLat,
      userLng,
      courierLat,
      courierLng,
    );

    if (distance < 1000) {
      return '${distance.toStringAsFixed(0)} m';
    }
    return '${(distance / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final distance = _getDistance();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.packageTitle ?? 'Paket Takibi'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        actions: [
          if (_markers.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.zoom_out_map),
              onPressed: _fitBounds,
            ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: primary),
            )
          : Stack(
              children: [
                GoogleMap(
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
                  polylines: _polylines,
                  zoomControlsEnabled: false,
                  myLocationButtonEnabled: false,
                  compassEnabled: false,
                ),
                // Durum kartı
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_packageData != null) ...[
                            Text(
                              'Alım: ${_packageData!['pickup_address'] ?? '-'}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Teslim: ${_packageData!['delivery_address'] ?? '-'}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (_courierLocation != null) ...[
                            Row(
                              children: [
                                Icon(Icons.two_wheeler, color: Colors.red, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _courierLocation!['full_name'] ?? 'Kurye',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      if (distance != null)
                                        Text(
                                          'Sizden uzaklığı: $distance',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ] else if (_packageData?['status'] == 'pending') ...[
                            Center(
                              child: Text(
                                'Kurye atanması bekleniyor...',
                                style: TextStyle(
                                  color: Colors.orange.shade700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _courierLocationStream?.cancel();
    _userLocationStream?.cancel();
    _locationUpdateTimer?.cancel();
    if (mounted) {
      try {
        _mapController.dispose();
      } catch (_) {}
    }
    super.dispose();
  }
}
