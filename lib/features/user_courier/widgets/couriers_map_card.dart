import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/courier_stream_service.dart';

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
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  int _courierCount = 0;
  bool _isLoading = true;
  Position? _userLocation;
  BitmapDescriptor? _courierIcon;

  // Tüm sorgu katmanları başarısız olursa hatayı burada tut; UI'da göster ki
  // "kurye yok" mu yoksa "sorgu patladı mı" ayırt edilebilsin.
  String? _loadError;

  // Tanılama: konumlu kurye 0 geldiğinde, sistemde hiç 'courier' rolünde
  // kullanıcı olup olmadığını sayar (rol uyuşmazlığını ayırt etmek için).
  int _diagTotalCouriers = -1; // -1 = henük bakılmadı

  // Ortak CourierStreamService'ten gelen güncel kurye cache'i. Realtime
  // akışı bu widget'ta değişmez; yalnızca dinler. Kurye konum paylaşmaya
  // başladığında marker otomatik belirir, paylaşımı kapattığında kaybolur.
  Map<String, CourierInfo> _couriers = const {};

  // Cizre varsayılan koordinatları
  static const double _cizreLatitude = 37.3255;
  static const double _cizveLongitude = 42.1876;

  // CourierStreamService listener referansı (unsubscribe için).
  void Function(Map<String, CourierInfo>)? _courierListener;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    await _getUserLocation();
    // İkonu hazırla; ardından CourierStreamService'e bağlan. Servis ilk
    // abone geldiğinde `profiles` tablosunu realtime dinlemeye başlar, son
    // abone ayrılınca kapatır — birden fazla harita varsa tek kanal yeter.
    await _ensureCourierIcon();

    void onChange(Map<String, CourierInfo> snap) {
      if (!mounted) return;
      setState(() {
        _couriers = snap;
        _loadError = CourierStreamService().lastError;
      });
      _buildMarkers();
    }

    _courierListener = onChange;
    CourierStreamService().subscribe(onChange);
    // İlk snapshot subscribe içinde zaten emit ediliyor; burada sadece
    // _isLoading'i kapatıyoruz (kurye verisi gelmese bile UI hazır).
    if (mounted) setState(() => _isLoading = false);
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

  Future<void> _ensureCourierIcon() async {
    if (_courierIcon != null) return;
    _courierIcon = await _createMotorcycleBitmap();
  }

  /// Rengi daire + alt üçgenden oluşan, motor ikonlu bir pin marker üretir.
  Future<BitmapDescriptor> _createMotorcycleBitmap() async {
    const double size = 90;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    final center = Offset(size / 2, size * 0.38);
    final radius = size * 0.38;
    const fill = Color(0xFFE53935); // kırmızı

    // Pin gövdesi (daire)
    canvas.drawCircle(center, radius, Paint()..color = fill);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );

    // Alt üçgen (konumu işaret eden uç)
    final triangle = Path()
      ..moveTo(center.dx - radius * 0.55, center.dy + radius * 0.78)
      ..lineTo(center.dx + radius * 0.55, center.dy + radius * 0.78)
      ..lineTo(center.dx, size * 0.92)
      ..close();
    canvas.drawPath(triangle, Paint()..color = fill);
    canvas.drawPath(
      triangle,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );

    // Motor ikonu
    final iconPainter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(Icons.two_wheeler.codePoint),
        style: TextStyle(
          fontSize: radius,
          fontFamily: Icons.two_wheeler.fontFamily,
          package: Icons.two_wheeler.fontPackage,
          color: Colors.white,
        ),
      )
      ..layout();
    iconPainter.paint(
      canvas,
      Offset(
        center.dx - iconPainter.width / 2,
        center.dy - iconPainter.height / 2,
      ),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      // Bellek baskısı altında null dönebilir; varsayılan markera düş.
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    }
    return BitmapDescriptor.bytes(bytes.buffer.asUint8List());
  }

  /// Marker'ları yerel state'ten çiz (kullanıcı konumu + CourierStreamService
  /// snapshot'ı + widget'ın alım/teslim koordinatları). DB sorgusu yapmaz.
  void _buildMarkers() {
    final markers = <Marker>{};

    // Kullanıcı konumu (mavi)
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

    int count = 0;
    for (final c in _couriers.values) {
      markers.add(
        Marker(
          markerId: MarkerId('courier_${c.id}'),
          position: LatLng(c.lat, c.lng),
          infoWindow: InfoWindow(
            title: c.name,
            snippet: '🏍️ Detaylar için dokunun',
          ),
          onTap: () => _showCourierInfo(c),
          icon: _courierIcon ??
              BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueRed,
              ),
        ),
      );
      count++;
    }

    // Alım noktası (widget koordinatlarından)
    if (widget.pickupLat != null && widget.pickupLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup_location'),
          position: LatLng(widget.pickupLat!, widget.pickupLng!),
          infoWindow: const InfoWindow(title: 'Alım Noktası'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      );
    }

    // Teslim noktası (widget koordinatlarından)
    if (widget.deliveryLat != null && widget.deliveryLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('delivery_location'),
          position: LatLng(widget.deliveryLat!, widget.deliveryLng!),
          infoWindow: const InfoWindow(title: 'Teslim Noktası'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        ),
      );
    }

    if (mounted) {
      setState(() {
        _markers
          ..clear()
          ..addAll(markers);
        _courierCount = count;
        _isLoading = false;
      });
    }
  }

  /// Düz çizgi (kuş uçuşu) mesafeyi tahmini varış dakikasına çevirir.
  /// Kentsel motor ortalaması ~25 km/h ve yol faktörü 1.3 (gerçek rota düz
  /// çizgiden uzundur) ile hesaplanır; en az 1 dk döner.
  int _estimateEtaMinutes(double straightDistanceMeters) {
    if (straightDistanceMeters <= 0) return 0;
    const double avgSpeedMPerMin = (25 * 1000) / 60; // ~416.7 m/dk
    final routeDistance = straightDistanceMeters * 1.3;
    final minutes = routeDistance / avgSpeedMPerMin;
    return minutes < 1 ? 1 : minutes.ceil();
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  /// last_location_update (ISO) değerini göreli süre metnine çevirir.
  String _formatUpdate(DateTime? dt) {
    if (dt == null) return '-';
    final diff = DateTime.now().difference(dt);
    if (diff.isNegative) return 'az önce';
    if (diff.inMinutes < 1) return 'az önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} sa önce';
    return '${diff.inDays} gün önce';
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Arama başlatılamadı')),
      );
    }
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
        ),
      ],
    );
  }

  /// Kurye marker'ına dokunulduğunda isim, telefon, teslimat sayısı ve
  /// kullanıcıya tahmini varış süresini gösteren alt sayfa açar.
  void _showCourierInfo(CourierInfo c) {
    if (_userLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konumunuz alınamadı')),
      );
      return;
    }

    final distance = Geolocator.distanceBetween(
      _userLocation!.latitude,
      _userLocation!.longitude,
      c.lat,
      c.lng,
    );
    final eta = _estimateEtaMinutes(distance);
    final distanceText = _formatDistance(distance);
    final phone = c.phone;
    final avatarUrl = c.avatarUrl;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.red.shade100,
                    backgroundImage:
                        avatarUrl != null ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl == null
                        ? Icon(Icons.two_wheeler,
                            color: Colors.red.shade700, size: 28)
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.two_wheeler,
                                size: 14, color: Colors.red.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'Moto Kurye',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Tahmini varış kartı
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule, color: Colors.green.shade800),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tahmini varış: ~$eta dk',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Mesafeniz: $distanceText',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (c.deliveredCount > 0)
                _infoRow(Icons.check_circle_outline,
                    '${c.deliveredCount} teslimat tamamladı'),
              if (phone != null && phone.isNotEmpty) ...[
                const SizedBox(height: 8),
                _infoRow(Icons.phone_outlined, phone),
              ],
              if (c.updatedAt != null) ...[
                const SizedBox(height: 8),
                _infoRow(Icons.update, 'Son konum: ${_formatUpdate(c.updatedAt)}'),
              ],
              const SizedBox(height: 16),
              if (phone != null && phone.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _callPhone(phone),
                    icon: const Icon(Icons.phone),
                    label: const Text('Kuryeyi Ara'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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
    final controller = _mapController;
    if (controller == null || _markers.isEmpty) return;
    controller.animateCamera(
      CameraUpdate.newLatLngBounds(_getBounds(), 100),
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

  @override
  void didUpdateWidget(CouriersMapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pickupLat != widget.pickupLat ||
        oldWidget.pickupLng != widget.pickupLng ||
        oldWidget.deliveryLat != widget.deliveryLat ||
        oldWidget.deliveryLng != widget.deliveryLng) {
      // Sadece koordinatlar değişti; kuryeleri tekrar sorgulama, marker'ları
      // cache'lenen veriden yeniden çiz.
      _buildMarkers();
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
                Icon(Icons.two_wheeler, color: primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Yakın Kuryeler ($_courierCount)',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (!_isLoading)
                  IconButton(
                    tooltip: 'Konumuma git',
                    icon: const Icon(Icons.my_location, size: 18),
                    onPressed: _recenterOnUser,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                if (!_isLoading && _markers.isNotEmpty)
                  IconButton(
                    tooltip: 'Tümünü göster',
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
            child: _isLoading || _userLocation == null
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
                        },
                        markers: _markers,
                        // Parmakla kaydırma + iki parmakla yakınlaştırma
                        scrollGesturesEnabled: true,
                        zoomGesturesEnabled: true,
                        tiltGesturesEnabled: true,
                        rotateGesturesEnabled: true,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                        myLocationButtonEnabled: false,
                        compassEnabled: false,
                      ),
                      // Hiç konum paylaşan kurye yoksa teşhis amaçlı ipucu
                      // göster — "ikon bozuk" mu yoksa "veri yok" mu belli olsun.
                      // Sorgu patladıysa hatanın kendisini göster.
                      if (_courierCount == 0)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _loadError != null
                                      ? 'Kurye sorgusu hatası:\n$_loadError'
                                      : _diagTotalCouriers == 0
                                          ? 'Sistemde kurye kullanıcısı yok '
                                              '(role=courier bulunamadı)'
                                          : _diagTotalCouriers > 0
                                              ? 'Sistemde $_diagTotalCouriers kurye var '
                                                  'ama henüz konum paylaşan yok'
                                              : 'Henüz konum paylaşan kurye yok',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
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
}
