import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/courier_stream_service.dart';
import '../screens/couriers_map_full_screen.dart';

class CouriersMapCard extends StatefulWidget {
  final double? pickupLat;
  final double? pickupLng;
  final double? deliveryLat;
  final double? deliveryLng;
  final List<LatLng> routePoints;

  const CouriersMapCard({
    super.key,
    this.pickupLat,
    this.pickupLng,
    this.deliveryLat,
    this.deliveryLng,
    this.routePoints = const [],
  });

  @override
  State<CouriersMapCard> createState() => _CouriersMapCardState();
}

class _CouriersMapCardState extends State<CouriersMapCard> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  int _courierCount = 0;
  bool _isLoading = true;
  Position? _userLocation;
  BitmapDescriptor? _courierIcon;

  // Tüm sorgu katmanları başarısız olursa hatayı burada tut; UI'da göster ki
  // "kurye yok" mu yoksa "sorgu patladı mı" ayırt edilebilsin.
  String? _loadError;

  // "Kurye yok" mesajı bir kez gösterilsin (overlay yerine SnackBar). Her
  // courier snapshot'ta tekrarlamaz.
  bool _shownNoCourierNotice = false;

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
      // "Kurye yok" mesajı yalnızca bir kez, SnackBar ile göster — overlay
      // haritayı kaplamasın, her snapshot'ta tekrarlanmasın.
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

  /// Yön oklu kırmızı disk + motor ikonu. rotation=0 → ok yukarı (kuzey).
  /// flat:true ile haritaya yapışır; marker rotation=heading ile döner.
  /// (şehiriçi `_createVehicleBitmap` deseniyle aynı.)
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

    // Motor ikonu
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
          // heading: 0 = kuzey yukarı. null/0 → rotation 0 (ok kuzeye).
          // flat: true → disk haritaya yapışır, harita döndükçe kuzey sabit.
          rotation: c.heading ?? 0,
          flat: true,
          anchor: const Offset(0.5, 0.5),
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
    // phone artık public CourierInfo'da bulunmuyor (PII sızıntısı
    // engellendi). Talep sonrası kurye atanırsa atanmış kuryenin telefonu
    // yalnız talep göndericisine ayrı bir RPC ile gösterilir.
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
              // Kurye telefonu artık public akışta ifşa edilmiyor (PII
              // sızıntısı engellendi). Atanmış kuryenin telefonu yalnız
              // aktif talep göndericisine ayrı bir RPC ile gösterilir;
              // buradaki kartta telefon alanı ve "Kuryeyi Ara" butonu
              // kaldırıldı.
              if (c.updatedAt != null) ...[
                const SizedBox(height: 8),
                _infoRow(Icons.update, 'Son konum: ${_formatUpdate(c.updatedAt)}'),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  LatLngBounds _getBounds() {
    final points = <LatLng>[];

    // Marker'lardan.
    for (final marker in _markers) {
      points.add(marker.position);
    }
    // Rota polyline noktalarından (varsa).
    for (final p in widget.routePoints) {
      points.add(p);
    }
    // En azından alım/teslim koordinatları.
    if (widget.pickupLat != null && widget.pickupLng != null) {
      points.add(LatLng(widget.pickupLat!, widget.pickupLng!));
    }
    if (widget.deliveryLat != null && widget.deliveryLng != null) {
      points.add(LatLng(widget.deliveryLat!, widget.deliveryLng!));
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
      southwest: LatLng(minLat - 0.005, minLng - 0.005),
      northeast: LatLng(maxLat + 0.005, maxLng + 0.005),
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

  void _zoomIn() {
    _mapController?.animateCamera(CameraUpdate.zoomBy(1));
  }

  void _zoomOut() {
    _mapController?.animateCamera(CameraUpdate.zoomBy(-1));
  }

  Future<void> _openFullScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CouriersMapFullScreen(
          pickupLat: widget.pickupLat,
          pickupLng: widget.pickupLng,
          deliveryLat: widget.deliveryLat,
          deliveryLng: widget.deliveryLng,
          routePoints: widget.routePoints,
        ),
      ),
    );
  }

  /// Yüzen modern kontrol butonu — beyaz arka plan, gölge, daire.
  Widget _floatingMapButton({
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
            width: 40,
            height: 40,
            child: Icon(icon, color: Colors.black87, size: 20),
          ),
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(CouriersMapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final routeChanged = oldWidget.routePoints != widget.routePoints;
    if (oldWidget.pickupLat != widget.pickupLat ||
        oldWidget.pickupLng != widget.pickupLng ||
        oldWidget.deliveryLat != widget.deliveryLat ||
        oldWidget.deliveryLng != widget.deliveryLng ||
        routeChanged) {
      // Sadece koordinatlar/rota değişti; kuryeleri tekrar sorgulama, marker'ları
      // cache'lenen veriden yeniden çiz.
      _buildMarkers();
      // Rota yeni geldiyse haritayı rota + marker'lara sığdır (bir sonraki
      // frame'de, polylines state'e işlenmiş haliyle).
      if (routeChanged && widget.routePoints.length >= 2) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark
        ? Theme.of(context).colorScheme.surfaceContainerHigh
        : Colors.white;

    return Card(
      elevation: 4,
      color: cardBg,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Başlık satırı: yumuşak arka plan, yuvarlatılmış üst köşeler
          Container(
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.two_wheeler, color: primary, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Yakın Kuryeler ($_courierCount)',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!_isLoading)
                  IconButton(
                    tooltip: 'Konumuma git',
                    icon: const Icon(Icons.my_location, size: 20),
                    onPressed: _recenterOnUser,
                    visualDensity: VisualDensity.compact,
                  ),
                if (!_isLoading && _markers.isNotEmpty)
                  IconButton(
                    tooltip: 'Tümünü göster',
                    icon: const Icon(Icons.zoom_out_map, size: 20),
                    onPressed: _fitBounds,
                    visualDensity: VisualDensity.compact,
                  ),
                IconButton(
                  tooltip: 'Tam ekran',
                  icon: const Icon(Icons.fullscreen, size: 20),
                  onPressed: _openFullScreen,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          // Harita alanı
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(16),
            ),
            child: SizedBox(
              height: 220,
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
                          polylines: _polylines,
                          // Parmakla kaydırma + iki parmakla yakınlaştırma aktif
                          scrollGesturesEnabled: true,
                          zoomGesturesEnabled: true,
                          tiltGesturesEnabled: true,
                          rotateGesturesEnabled: true,
                          zoomControlsEnabled: false,
                          mapToolbarEnabled: false,
                          myLocationButtonEnabled: false,
                          compassEnabled: false,
                        ),
                        // Zoom in / Zoom out — modern yüzen butonlar (sağ alt)
                        Positioned(
                          right: 10,
                          bottom: 36,
                          child: Column(
                            children: [
                              _floatingMapButton(
                                icon: Icons.add,
                                tooltip: 'Yakınlaştır',
                                onPressed: _zoomIn,
                              ),
                              const SizedBox(height: 8),
                              _floatingMapButton(
                                icon: Icons.remove,
                                tooltip: 'Uzaklaştır',
                                onPressed: _zoomOut,
                              ),
                            ],
                          ),
                        ),
                        // Alt ipucu şeridi
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            color: Colors.black.withValues(alpha: 0.42),
                            child: const Text(
                              '💡 Kaydırın · İki parmakla yakınlaştırın',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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
