import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/chat_location_service.dart';

/// Sohbette konum gönderme (Görev 3.1).
///
/// Harita anlık konumda açılır (izin akışı [ChatLocationService] üzerinden,
/// önce uygulama içi açıklama). Ortadaki iğne gönderilecek noktadır;
/// kullanıcı haritayı kaydırarak başka bir nokta seçebilir. İğnenin adresi
/// kamera durunca bulunur. "Bu Konumu Gönder" seçimi [ChatLocationPick]
/// olarak döndürür; vazgeçilirse null.
class ChatLocationPickerScreen extends StatefulWidget {
  const ChatLocationPickerScreen({super.key, this.service});

  final ChatLocationService? service;

  @override
  State<ChatLocationPickerScreen> createState() => _ChatLocationPickerScreenState();
}

class _ChatLocationPickerScreenState extends State<ChatLocationPickerScreen> {
  late final ChatLocationService _service = widget.service ?? ChatLocationService();

  GoogleMapController? _map;
  LatLng _center = const LatLng(
    ChatLocationService.defaultLatitude,
    ChatLocationService.defaultLongitude,
  );

  bool _locating = true;
  bool _hasFix = false;
  bool _moving = false;

  String? _label;
  bool _labelLoading = false;
  int _labelSeq = 0;
  Timer? _labelDebounce;

  @override
  void initState() {
    super.initState();
    // Açıklama diyaloğu için bağlam hazır olsun.
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  @override
  void dispose() {
    _labelDebounce?.cancel();
    _map?.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    if (!mounted) return;
    setState(() => _locating = true);
    final fix = await _service.currentLocation(context);
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (fix != null) {
        _hasFix = true;
        _center = LatLng(fix.latitude, fix.longitude);
      }
    });
    if (fix != null) {
      await _map?.animateCamera(CameraUpdate.newLatLngZoom(_center, 17));
    }
    _lookUpLabel();
  }

  void _onCameraMove(CameraPosition position) {
    _center = position.target;
    if (!_moving) setState(() => _moving = true);
  }

  void _onCameraIdle() {
    if (_moving) setState(() => _moving = false);
    _lookUpLabel();
  }

  /// İğnenin adresi; art arda kaydırmalarda yalnız sonuncusu sorulur.
  void _lookUpLabel() {
    _labelDebounce?.cancel();
    final seq = ++_labelSeq;
    setState(() => _labelLoading = true);
    _labelDebounce = Timer(const Duration(milliseconds: 450), () async {
      final target = _center;
      final label = await _service.reverseGeocode(target.latitude, target.longitude);
      if (!mounted || seq != _labelSeq) return;
      setState(() {
        _label = label;
        _labelLoading = false;
      });
    });
  }

  void _send() {
    Navigator.of(context).pop(
      ChatLocationPick(
        latitude: _center.latitude,
        longitude: _center.longitude,
        // Kaydırma sürerken bulunan adres iğnenin yeni yerine ait olmayabilir.
        label: _labelLoading || _moving ? null : _label,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showFixWarning = !_locating && !_hasFix;

    return Scaffold(
      appBar: AppBar(title: const Text('Konum Gönder')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(target: _center, zoom: 15),
                  onMapCreated: (controller) {
                    _map = controller;
                    // Konum harita oluşmadan bulunduysa kamera oraya taşınır;
                    // yoksa iğne ve koordinat konumu, harita varsayılanı
                    // gösterirdi.
                    if (_hasFix) {
                      controller.moveCamera(CameraUpdate.newLatLngZoom(_center, 17));
                    }
                  },
                  onCameraMove: _onCameraMove,
                  onCameraIdle: _onCameraIdle,
                  myLocationEnabled: _hasFix,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  compassEnabled: false,
                ),
                // Ortadaki iğne: ucu tam merkeze gelsin diye yarı boyu kadar yukarıda.
                IgnorePointer(
                  child: Center(
                    child: Transform.translate(
                      offset: const Offset(0, -22),
                      child: AnimatedScale(
                        scale: _moving ? 1.12 : 1,
                        duration: const Duration(milliseconds: 150),
                        child: const Icon(
                          Icons.location_on,
                          size: 46,
                          color: Color(0xFFE53935),
                          shadows: [Shadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 3))],
                        ),
                      ),
                    ),
                  ),
                ),
                if (showFixWarning)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: Material(
                      color: const Color(0xFFFFF4E0),
                      borderRadius: BorderRadius.circular(12),
                      elevation: 2,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.location_off_outlined, color: Color(0xFFB26A00)),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Konumun alınamadı. Haritayı kaydırıp iğneyi göndermek '
                                'istediğin yere getirebilirsin.',
                                style: TextStyle(fontSize: 13, color: Color(0xFF6B4A00)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: FloatingActionButton.small(
                    heroTag: null,
                    tooltip: 'Konumuma git',
                    backgroundColor: Colors.white,
                    foregroundColor: theme.colorScheme.primary,
                    onPressed: _locating ? null : _locate,
                    child: _locating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),
          Material(
            elevation: 8,
            color: Colors.white,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                          child: Icon(Icons.place, color: theme.colorScheme.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _locating
                                    ? 'Konumun bulunuyor…'
                                    : (_labelLoading || _moving)
                                        ? 'Adres aranıyor…'
                                        : (_label ?? 'Seçilen konum'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                ChatLocationService.formatCoordinates(
                                  _center.latitude,
                                  _center.longitude,
                                ),
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _locating ? null : _send,
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('Bu Konumu Gönder'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
