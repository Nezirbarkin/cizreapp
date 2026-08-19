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
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  bool _isLoading = true;
  bool _loadFailed = false;

  Position? _userLocation;
  Map<String, dynamic>? _courierLocation;
  Map<String, dynamic>? _packageData;

  StreamSubscription<List<Map<String, dynamic>>>? _requestStatusStream;
  Timer? _courierPollTimer;
  Timer? _locationUpdateTimer;

  static const double _cizreLatitude = 37.3255;
  static const double _cizveLongitude = 42.1876;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Future.wait([_getUserLocation(), _loadPackageData()]);
    if (mounted) {
      setState(() => _isLoading = false);
      // Veriler yüklendiğinde marker'ları hemen çiz ki harita açılışta boş kalmasın.
      _updateMarkers();
      _startCourierLocationPolling();
      _listenToRequestStatus();
      _startUserLocationTimer();
    }
  }

  Future<void> _getUserLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final result = await Geolocator.requestPermission();
        if (result == LocationPermission.denied ||
            result == LocationPermission.deniedForever) {
          // İzin yoksa da harita boş kalmasın: Cizre merkezini kullan.
          _applyFallbackLocation();
          return;
        }
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
      _applyFallbackLocation();
    }
  }

  void _applyFallbackLocation() {
    if (!mounted) return;
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

  Future<void> _loadPackageData() async {
    try {
      final data = await Supabase.instance.client
          .from('courier_requests')
          .select()
          .eq('id', widget.packageId)
          .single();

      if (!mounted) return;
      setState(() {
        _packageData = data;
        _loadFailed = false;
      });
    } catch (e) {
      debugPrint('❌ Paket verisi yükleme hatası: $e');
      if (mounted) {
        setState(() {
          _loadFailed = true;
          _isLoading = false;
        });
      }
    }
  }

  /// 2026-08-09: Kurye canlı konumunu RLS-güvenli RPC ile periyodik çeker.
  ///
  /// profiles.last_known_* istemciye grant edilmediği için eski kodun
  /// `profiles.stream(eq id courierId)` çağrısı RLS altında sessizce boş
  /// dönüyordu — kurye marker'ı hiç çıkmıyordu. get_assigned_courier_location
  /// RPC (SECURITY DEFINER) yalnız gönderici/atanmış kurye/admin'e ~1m
  /// yuvarlanmış koordinatı döner; gizlilik (ghost/offline/private) altında
  /// NULL döner. Aynı RPC request status'u da döndürdüğü için teslim
  /// durumunu buradan yansıtırız.
  void _startCourierLocationPolling() {
    _pollCourierLocation(); // açılışta hemen ilk değer
    _courierPollTimer?.cancel();
    _courierPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pollCourierLocation();
    });
  }

  Future<void> _pollCourierLocation() async {
    try {
      final res = await Supabase.instance.client.rpc<List<dynamic>>(
        'get_assigned_courier_location',
        params: {'p_request_id': widget.packageId},
      );
      // RPC tek satır döner (kurye yoksa NULL'lu satır); boş listeye karşı koru.
      final Map<String, dynamic>? row =
          res.isNotEmpty ? res.first as Map<String, dynamic> : null;
      if (row == null || !mounted) return;

      final status = row['r_request_status'] as String?;
      final courierId = row['r_courier_id'] as String?;

      setState(() {
        // Status'u RPC'den yansı: kurye teslim onayı istediğinde anlık görünsün.
        if (status != null && _packageData != null) {
          _packageData = {..._packageData!, 'status': status};
        }
        if (courierId != null) {
          _courierLocation = {
            'id': courierId,
            'full_name': row['r_full_name'],
            'lat': (row['r_lat'] as num?)?.toDouble(),
            'lng': (row['r_lng'] as num?)?.toDouble(),
          };
        } else {
          _courierLocation = null;
        }
      });
      _updateMarkers();
    } catch (e) {
      debugPrint('Kurye konum RPC hatası: $e');
    }
  }

  /// Göndericinin KENDİ courier_requests satırı (RLS: sender_id=auth.uid())
  /// üzerinden realtime — güvenli. Kurye durumu değiştirince (accepted →
  /// delivery_pending_confirmation → delivered) anında kurye konum RPC'sini
  /// yeniden çeker; polling'i beklemeden UI güncellenir. Kuryenin profiles
  /// satırı grant dışı olduğu için konum realtime'i RPC üzerinden olmaz; bu
  /// abonelik yalnızca "değişiklik oldu, yeniden çek" sinyali verir.
  void _listenToRequestStatus() {
    _requestStatusStream = Supabase.instance.client
        .from('courier_requests')
        .stream(primaryKey: ['id'])
        .eq('id', widget.packageId)
        .listen((rows) {
          if (rows.isNotEmpty) {
            _pollCourierLocation();
          }
        });
  }

  void _startUserLocationTimer() {
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _updateUserLocation();
    });
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
        // Not: Gönderen (müşteri) konumunu profiles'a yazmıyoruz — bu ekran
        // kuryenin konumunu takip eder; müşterinin last_known_lat/lng'sini
        // 10 sn'de bir üzerine yazmak kurye takip pinini bozabilir ve anlamsız
        // DB trafiği yaratır. Kullanıcı konumu yalnızca yerel marker içindir.
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
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
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
            infoWindow: const InfoWindow(title: 'Alım Noktası'),
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
            infoWindow: const InfoWindow(title: 'Teslim Noktası'),
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
      minLat = minLat > marker.position.latitude
          ? marker.position.latitude
          : minLat;
      maxLat = maxLat < marker.position.latitude
          ? marker.position.latitude
          : maxLat;
      minLng = minLng > marker.position.longitude
          ? marker.position.longitude
          : minLng;
      maxLng = maxLng < marker.position.longitude
          ? marker.position.longitude
          : maxLng;
    }

    return LatLngBounds(
      southwest: LatLng(minLat - 0.01, minLng - 0.01),
      northeast: LatLng(maxLat + 0.01, maxLng + 0.01),
    );
  }

  void _fitBounds() {
    final controller = _mapController;
    if (controller == null || _markers.isEmpty) return;
    controller.animateCamera(CameraUpdate.newLatLngBounds(_getBounds(), 100));
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

  /// Kuryenin kullanıcıya tahmini varış dakikası. Kuş uçuşu mesafeyi
  /// kentsel motor ortalaması (~25 km/h) ve yol faktörü (1.3) ile tahmin eder.
  int? _getEtaMinutes() {
    if (_userLocation == null || _courierLocation == null) return null;

    final courierLat = _courierLocation!['lat'] as double?;
    final courierLng = _courierLocation!['lng'] as double?;
    if (courierLat == null || courierLng == null) return null;

    final distance = Geolocator.distanceBetween(
      _userLocation!.latitude,
      _userLocation!.longitude,
      courierLat,
      courierLng,
    );
    if (distance <= 0) return 0;
    const double avgSpeedMPerMin = (25 * 1000) / 60;
    final minutes = (distance * 1.3) / avgSpeedMPerMin;
    return minutes < 1 ? 1 : minutes.ceil();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final distance = _getDistance();
    final eta = _getEtaMinutes();

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
          ? Center(child: CircularProgressIndicator(color: primary))
          : _loadFailed
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Paket bilgileri yüklenemedi.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Paket bulunamadı veya yetki sorunu olabilir.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
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
                      Future.delayed(
                        const Duration(milliseconds: 500),
                        _fitBounds,
                      );
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
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Teslim: ${_packageData!['delivery_address'] ?? '-'}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (_courierLocation != null) ...[
                            Row(
                              children: [
                                Icon(
                                  Icons.two_wheeler,
                                  color: Colors.red,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _courierLocation!['full_name'] ??
                                            'Kurye',
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
                                      if (eta != null)
                                        Text(
                                          'Tahmini varış: ~$eta dk',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.green.shade700,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ] else if (_packageData?['status'] == 'accepted') ...[
                            Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.two_wheeler,
                                    color: Colors.blue.shade700,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Kurye yola çıktı, paketinizi alıyor...',
                                    style: TextStyle(
                                      color: Colors.blue.shade700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else if (_packageData?['status'] == 'delivered') ...[
                            Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    color: Colors.green.shade700,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Paketiniz teslim edildi',
                                    style: TextStyle(
                                      color: Colors.green.shade700,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
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
    _courierPollTimer?.cancel();
    _locationUpdateTimer?.cancel();
    _requestStatusStream?.cancel();
    // mounted, dispose sırasında her zaman false olurdu; bu yüzden eski kod
    // map controller'ı hiç dispose etmiyordu. nullable + try/catch ile güvenli dispose.
    try {
      _mapController?.dispose();
    } catch (_) {}
    super.dispose();
  }
}
