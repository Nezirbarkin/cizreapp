import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/services/courier_stream_service.dart';
import '../../../core/services/location_disclosure_service.dart';

/// CouriersMapCard için tam ekran mod.
///
/// Aynı realtime akışına (`CourierStreamService`) bağlanır; küçük kart
/// widget'ı açıkken de bu sayfa açıkken de aynı veriyi paylaşır. Kurye
/// konum güncellemeleri burada da anlık yansır.
class CouriersMapFullScreen extends StatefulWidget {
  final double? pickupLat;
  final double? pickupLng;
  final double? deliveryLat;
  final double? deliveryLng;
  final List<LatLng> routePoints;

  const CouriersMapFullScreen({
    super.key,
    this.pickupLat,
    this.pickupLng,
    this.deliveryLat,
    this.deliveryLng,
    this.routePoints = const [],
  });

  @override
  State<CouriersMapFullScreen> createState() => _CouriersMapFullScreenState();
}

class _CouriersMapFullScreenState extends State<CouriersMapFullScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  bool _isLoading = true;
  Position? _userLocation;
  BitmapDescriptor? _courierIcon;

  String? _loadError;
  Map<String, CourierInfo> _couriers = const {};

  // "Kurye yok" mesajı bir kez gösterilsin (overlay yerine SnackBar).
  bool _shownNoCourierNotice = false;

  // Cizre varsayılan koordinatları
  static const double _cizreLatitude = 37.3255;
  static const double _cizreLongitude = 42.1876;

  void Function(Map<String, CourierInfo>)? _courierListener;

  @override
  void initState() {
    super.initState();
    // Polyline courier akışından bağımsız (routePoints widget parametresi),
    // bu yüzden ilk frame'de çiz — courier verisi gelmesini beklemeden.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _buildMarkers();
    });
    _initData();
  }

  Future<void> _initData() async {
    await _getUserLocation();
    await _ensureCourierIcon();

    void onChange(Map<String, CourierInfo> snap) {
      if (!mounted) return;
      setState(() {
        _couriers = snap;
        _loadError = CourierStreamService().lastError;
      });
      _buildMarkers();
      // "Kurye yok" mesajı yalnızca bir kez, SnackBar ile göster.
      if (snap.isEmpty && !_shownNoCourierNotice) {
        _shownNoCourierNotice = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_loadError ?? 'Henüz konum paylaşan kurye yok'),
              duration: const Duration(seconds: 4),
            ),
          );
        });
      }
    }

    _courierListener = onChange;
    CourierStreamService().subscribe(onChange);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _getUserLocation() async {
    try {
      // Ekran açılışında çalışır; burada izin İSTENMEZ. Kullanıcı konumunu
      // daha önce (Prominent Disclosure ekranını görüp kabul ederek)
      // paylaşmayı seçtiyse harita ona göre ortalanır, aksi halde aşağıdaki
      // catch dalındaki Cizre merkezi kullanılır. İzin talebi kullanıcının
      // açık bir eylemine bağlıdır — açılışta dialog patlatılmaz.
      if (!await LocationDisclosureService.isReady(LocationPurpose.nearby)) {
        throw StateError('konum izni yok');
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
      if (mounted) {
        setState(() {
          _userLocation = Position(
            latitude: _cizreLatitude,
            longitude: _cizreLongitude,
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

  Future<void> _ensureCourierIcon() async {
    if (_courierIcon != null) return;
    _courierIcon = await _createMotorcycleBitmap();
  }

  /// Yön oklu kırmızı disk + motor ikonu. rotation=0 → ok yukarı (kuzey).
  /// flat:true ile haritaya yapışır; marker rotation=heading ile döner.
  /// (CouriersMapCard ile aynı bitmap.)
  Future<BitmapDescriptor> _createMotorcycleBitmap() async {
    const double size = 56;
    const center = Offset(size / 2, size / 2);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    // Yumuşak gölge
    canvas.drawCircle(
      center + const Offset(0, 3),
      size / 2 - 5,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    // Beyaz kart zemin
    canvas.drawCircle(center, size / 2 - 3, Paint()..color = Colors.white);
    // Kırmızı disk
    const fill = Color(0xFFE53935);
    canvas.drawCircle(center, size / 2 - 7, Paint()..color = fill);

    // Yön oku: diskin üstü, dışa bakan üçgen (rotation=0 → kuzey).
    final arrowPath = Path()
      ..moveTo(center.dx, center.dy - (size / 2 - 5))
      ..lineTo(center.dx - 5, center.dy - (size / 2 - 12))
      ..lineTo(center.dx + 5, center.dy - (size / 2 - 12))
      ..close();
    canvas.drawPath(arrowPath, Paint()..color = Colors.white);
    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    final iconPainter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(Icons.two_wheeler.codePoint),
        style: TextStyle(
          fontSize: size * 0.36,
          fontFamily: Icons.two_wheeler.fontFamily,
          package: Icons.two_wheeler.fontPackage,
          color: Colors.white,
        ),
      )
      ..layout();
    iconPainter.paint(
      canvas,
      center - Offset(iconPainter.width / 2, iconPainter.height / 2 + 1),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    }
    return BitmapDescriptor.bytes(bytes.buffer.asUint8List());
  }

  void _buildMarkers() {
    final markers = <Marker>{};

    if (_userLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('user_location'),
          position: LatLng(_userLocation!.latitude, _userLocation!.longitude),
          infoWindow: const InfoWindow(
            title: 'Benim Konumum',
            snippet: '👤 Kullanıcı',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueBlue,
          ),
        ),
      );
    }

    for (final c in _couriers.values) {
      markers.add(
        Marker(
          markerId: MarkerId('courier_${c.id}'),
          position: LatLng(c.lat, c.lng),
          infoWindow: InfoWindow(
            title: c.name,
            snippet: '🏍️ Moto Kurye',
          ),
          icon: _courierIcon ??
              BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueRed),
          // heading: 0 = kuzey yukarı. null/0 → rotation 0 (ok kuzeye).
          // flat: true → disk haritaya yapışır, harita döndükçe kuzey sabit.
          rotation: c.heading ?? 0,
          flat: true,
          anchor: const Offset(0.5, 0.5),
        ),
      );
    }

    if (widget.pickupLat != null && widget.pickupLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup_location'),
          position: LatLng(widget.pickupLat!, widget.pickupLng!),
          infoWindow: const InfoWindow(title: 'Alım Noktası'),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      );
    }
    if (widget.deliveryLat != null && widget.deliveryLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('delivery_location'),
          position: LatLng(widget.deliveryLat!, widget.deliveryLng!),
          infoWindow: const InfoWindow(title: 'Teslim Noktası'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueOrange),
        ),
      );
    }

    // Rota polyline'ı (CouriersMapCard ile aynı görünüm).
    final polylines = <Polyline>{};
    if (widget.routePoints.length >= 2) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: widget.routePoints,
          color: const Color(0xFF1976D2),
          width: 6,
          jointType: JointType.round,
          endCap: Cap.roundCap,
          startCap: Cap.roundCap,
        ),
      );
    }

    if (mounted) {
      setState(() {
        _markers
          ..clear()
          ..addAll(markers);
        _polylines
          ..clear()
          ..addAll(polylines);
        _isLoading = false;
      });
    }
  }

  LatLngBounds _getBounds() {
    final points = <LatLng>[];
    for (final marker in _markers) {
      points.add(marker.position);
    }
    // Rota polyline noktaları — fitBounds rotayı da kapsasın.
    for (final p in widget.routePoints) {
      points.add(p);
    }
    if (points.isEmpty) {
      return LatLngBounds(
        southwest: const LatLng(37.0, 42.0),
        northeast: const LatLng(38.0, 43.0),
      );
    }
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat - 0.01, minLng - 0.01),
      northeast: LatLng(maxLat + 0.01, maxLng + 0.01),
    );
  }

  void _fitBounds() {
    final controller = _mapController;
    if (controller == null || _markers.isEmpty) return;
    controller.animateCamera(
      CameraUpdate.newLatLngBounds(_getBounds(), 64),
    );
  }

  void _recenterOnUser() {
    final controller = _mapController;
    final loc = _userLocation;
    if (controller == null || loc == null) return;
    controller.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(loc.latitude, loc.longitude),
        14.5,
      ),
    );
  }

  void _zoomIn() {
    _mapController?.animateCamera(CameraUpdate.zoomBy(1));
  }

  void _zoomOut() {
    _mapController?.animateCamera(CameraUpdate.zoomBy(-1));
  }

  Widget _mapControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: Colors.black26,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: Colors.black87, size: 22),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    final l = _courierListener;
    if (l != null) {
      CourierStreamService().unsubscribe(l);
      _courierListener = null;
    }
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        title: const Text('Harita — Yakın Kuryeler'),
        actions: [
          if (_markers.isNotEmpty)
            IconButton(
              tooltip: 'Tümünü göster',
              icon: const Icon(Icons.zoom_out_map),
              onPressed: _fitBounds,
            ),
          IconButton(
            tooltip: 'Konumuma dön',
            icon: const Icon(Icons.my_location),
            onPressed: _recenterOnUser,
          ),
        ],
      ),
      body: _isLoading || _userLocation == null
          ? Center(
              child: CircularProgressIndicator(color: primary),
            )
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(
                      _userLocation!.latitude,
                      _userLocation!.longitude,
                    ),
                    zoom: 14.5,
                  ),
                  onMapCreated: (controller) {
                    _mapController = controller;
                    if (_markers.isNotEmpty) {
                      // Marker'lar hazırsa ilk frame'de tümünü göster.
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _fitBounds();
                      });
                    } else if (widget.routePoints.length >= 2) {
                      // Marker yok ama rota var — rotaya sığdır.
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _fitBounds();
                      });
                    }
                  },
                  markers: _markers,
                  polylines: _polylines,
                  scrollGesturesEnabled: true,
                  zoomGesturesEnabled: true,
                  tiltGesturesEnabled: true,
                  rotateGesturesEnabled: true,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  myLocationButtonEnabled: false,
                  compassEnabled: true,
                ),
                // Sağ alt köşede zoom in/out butonları
                Positioned(
                  right: 12,
                  bottom: 24,
                  child: Column(
                    children: [
                      _mapControlButton(
                        icon: Icons.add,
                        tooltip: 'Yakınlaştır',
                        onPressed: _zoomIn,
                      ),
                      const SizedBox(height: 10),
                      _mapControlButton(
                        icon: Icons.remove,
                        tooltip: 'Uzaklaştır',
                        onPressed: _zoomOut,
                      ),
                    ],
                  ),
                ),
                // Boş/hata durumunda ipucu — bir kez SnackBar ile verildi
                // (yukarıda), overlay haritayı kaplamaz.

                // Alt ipucu şeridi
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    color: Colors.black.withValues(alpha: 0.45),
                    child: const Text(
                      '💡 Haritayı parmağınızla kaydırın, iki parmakla yakınlaştırın',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
