// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/theme/app_map_style.dart';
import '../../core/utils/map_marker_icons.dart';
import '../../core/widgets/map_controls.dart';
import '../../features/admin/widgets/admin_ui.dart';
import '../models/sehirici_models.dart';
import '../utils/sehirici_route_geometry.dart';

/// Çoklu seçim modunda haritadan toplanan tek bir durak adayı.
class SehiriciPickedStop {
  SehiriciPickedStop({required this.position, required this.name});

  LatLng position;
  String name;
}

/// Admin'in konumu elle lat/lng yazmak yerine haritaya dokunarak (veya pini
/// sürükleyerek) seçmesini sağlayan ekran.
///
/// İki modda çalışır:
///  • **Tek seçim** ([SehiriciLocationPickerDialog.pickSingle]) — tek bir pin,
///    "Bu konumu kullan" ile [LatLng] döner. Durak ve şehir formundaki
///    "Haritadan seç" bunu kullanır.
///  • **Çoklu seçim** ([SehiriciLocationPickerDialog.pickMultiple]) — haritaya
///    her dokunuşta sıralı, NUMARALI bir durak pini eklenir; adları alttaki
///    listeden düzenlenir, hepsi tek seferde döner. Bir hattın duraklarını
///    tek tek form doldurarak girmek yerine güzergâh üzerinde dokunarak
///    dizmek için.
///
/// [existingStops] verilirse şehirdeki mevcut duraklar küçük gri noktalarla
/// referans olarak gösterilir; yeni pin bunlardan birine çok yakın düşerse
/// uyarı verilir (yanlışlıkla kopya durak oluşturmayı engeller).
class SehiriciLocationPickerDialog extends StatefulWidget {
  final double initialLat;
  final double initialLng;
  final double initialZoom;
  final bool multiSelect;
  final List<SehiriciStop> existingStops;

  /// Yeni pinlerin rengi (hat rengi). Verilmezse admin marka rengi.
  final Color? lineColor;

  const SehiriciLocationPickerDialog({
    super.key,
    required this.initialLat,
    required this.initialLng,
    this.initialZoom = 15,
    this.multiSelect = false,
    this.existingStops = const [],
    this.lineColor,
  });

  /// Tek konum seçtirir. İptal edilirse null döner.
  static Future<LatLng?> pickSingle(
    BuildContext context, {
    required double initialLat,
    required double initialLng,
    double initialZoom = 15,
    List<SehiriciStop> existingStops = const [],
  }) async {
    final result = await showDialog<List<SehiriciPickedStop>>(
      context: context,
      builder: (_) => SehiriciLocationPickerDialog(
        initialLat: initialLat,
        initialLng: initialLng,
        initialZoom: initialZoom,
        existingStops: existingStops,
      ),
    );
    if (result == null || result.isEmpty) return null;
    return result.first.position;
  }

  /// Sırayla birden çok durak seçtirir. İptal edilirse null döner.
  static Future<List<SehiriciPickedStop>?> pickMultiple(
    BuildContext context, {
    required double initialLat,
    required double initialLng,
    double initialZoom = 15,
    List<SehiriciStop> existingStops = const [],
    Color? lineColor,
  }) {
    return showDialog<List<SehiriciPickedStop>>(
      context: context,
      builder: (_) => SehiriciLocationPickerDialog(
        initialLat: initialLat,
        initialLng: initialLng,
        initialZoom: initialZoom,
        multiSelect: true,
        existingStops: existingStops,
        lineColor: lineColor,
      ),
    );
  }

  @override
  State<SehiriciLocationPickerDialog> createState() =>
      _SehiriciLocationPickerDialogState();
}

class _SehiriciLocationPickerDialogState
    extends State<SehiriciLocationPickerDialog> {
  /// Yeni bir pin, mevcut bir durağa veya başka bir yeni pine bu mesafeden
  /// yakın düşerse kopya sayılır.
  static const double _kDuplicateRadiusMeters = 25;

  final Completer<GoogleMapController> _mapCtl =
      Completer<GoogleMapController>();

  /// Tek seçim modunda daima tek eleman taşır.
  final List<SehiriciPickedStop> _picked = [];

  /// [_picked] ile aynı sırada ad düzenleme controller'ları.
  ///
  /// `TextFormField.initialValue` yalnız ilk build'de uygulanır; ListView
  /// State'i yeniden kullandığı için, bir durak silinip kalanlar yeniden
  /// numaralandığında alanlarda eski metin kalırdı. Controller ile metni
  /// açıkça güncelliyoruz.
  final List<TextEditingController> _nameCtrls = [];

  /// Mevcut duraklar için küçük gri nokta ve numaralı pinler (async üretilir).
  BitmapDescriptor? _dot;
  final Map<int, BitmapDescriptor> _pins = {};

  /// Ekranın üstünde kısa süre görünen uyarı (SnackBar diyaloğun ARKASINDA
  /// kalırdı).
  String? _notice;
  Timer? _noticeTimer;

  Color get _pinColor => widget.lineColor ?? AdminUi.brand;
  bool get _isMulti => widget.multiSelect;

  @override
  void initState() {
    super.initState();
    if (!_isMulti) {
      _picked.add(SehiriciPickedStop(
        position: LatLng(widget.initialLat, widget.initialLng),
        name: '',
      ));
      _nameCtrls.add(TextEditingController());
    }
    _loadIcons();
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    for (final c in _nameCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadIcons() async {
    final dot = await MapMarkerIcons.stop(
      style: MapStopStyle.dot,
      detail: MapStopDetail.mid,
      lineColors: const [Color(0xFF64748B)],
    );
    if (!mounted) return;
    setState(() => _dot = dot);
    await _ensurePins();
  }

  /// Şu an gereken numaralı pinleri üretir (yoksa).
  Future<void> _ensurePins() async {
    final wanted = _isMulti
        ? [for (var i = 1; i <= _picked.length; i++) i]
        : const [0];
    var changed = false;
    for (final n in wanted) {
      if (_pins.containsKey(n)) continue;
      _pins[n] = await MapMarkerIcons.numberedPin(
        number: _isMulti ? n : null,
        color: _pinColor,
        large: !_isMulti,
      );
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  // ── Düzenleme ────────────────────────────────────────────────

  void _onMapTap(LatLng target) {
    if (!_isMulti) {
      setState(() => _picked.first.position = target);
      return;
    }
    final clash = _nearbyLabel(target);
    if (clash != null) {
      _warn('Buraya çok yakın bir durak zaten var: $clash');
      return;
    }
    setState(() {
      final name = 'Durak ${_picked.length + 1}';
      _picked.add(SehiriciPickedStop(position: target, name: name));
      _nameCtrls.add(TextEditingController(text: name));
    });
    _ensurePins();
  }

  /// [target]'a [_kDuplicateRadiusMeters] içindeki mevcut/yeni durağın adı;
  /// yoksa null.
  String? _nearbyLabel(LatLng target, {int? ignoreIndex}) {
    for (final s in widget.existingStops) {
      if (distanceMeters(target, LatLng(s.lat, s.lng)) <
          _kDuplicateRadiusMeters) {
        return s.name;
      }
    }
    for (var i = 0; i < _picked.length; i++) {
      if (i == ignoreIndex) continue;
      if (distanceMeters(target, _picked[i].position) <
          _kDuplicateRadiusMeters) {
        return _picked[i].name;
      }
    }
    return null;
  }

  void _warn(String message) {
    _noticeTimer?.cancel();
    setState(() => _notice = message);
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  void _onPinDragged(int index, LatLng target) {
    if (_isMulti) {
      final clash = _nearbyLabel(target, ignoreIndex: index);
      if (clash != null) {
        _warn('Buraya çok yakın bir durak zaten var: $clash');
        // Pin'i geri çekmek için setState yeterli: marker konumu
        // _picked'ten türetiliyor, sürükleme kalıcı olmuyor.
        setState(() {});
        return;
      }
    }
    setState(() => _picked[index].position = target);
  }

  static final RegExp _autoNamePattern = RegExp(r'^Durak \d+$');

  void _removeAt(int index) {
    setState(() {
      _picked.removeAt(index);
      _nameCtrls.removeAt(index).dispose();
      // Otomatik adları ("Durak N") yeniden numaralandır; kullanıcının elle
      // yazdığı adlara dokunma.
      for (var i = 0; i < _picked.length; i++) {
        if (_autoNamePattern.hasMatch(_picked[i].name)) {
          final renamed = 'Durak ${i + 1}';
          _picked[i].name = renamed;
          _nameCtrls[i].text = renamed;
        }
      }
    });
  }

  void _submit() {
    if (_picked.isEmpty) return;
    if (_isMulti) {
      final unnamed = _picked.where((p) => p.name.trim().isEmpty).toList();
      if (unnamed.isNotEmpty) {
        _warn('Adı boş durak var. Tüm duraklara ad verin.');
        return;
      }
    }
    Navigator.of(context).pop(_picked);
  }

  // ── Harita ───────────────────────────────────────────────────

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};

    // Mevcut duraklar — referans, sürüklenemez.
    for (final s in widget.existingStops) {
      markers.add(Marker(
        markerId: MarkerId('existing_${s.id}'),
        position: LatLng(s.lat, s.lng),
        icon: _dot ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        anchor: const Offset(0.5, 0.5),
        alpha: 0.9,
        zIndexInt: 1,
        consumeTapEvents: true,
        infoWindow: InfoWindow(title: s.name, snippet: 'Mevcut durak'),
        onTap: () {},
      ));
    }

    for (var i = 0; i < _picked.length; i++) {
      final p = _picked[i];
      final icon = _pins[_isMulti ? i + 1 : 0];
      markers.add(Marker(
        markerId: MarkerId('picked_$i'),
        position: p.position,
        draggable: true,
        onDragEnd: (pos) => _onPinDragged(i, pos),
        icon: icon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        anchor: const Offset(0.5, 1),
        zIndexInt: 5,
        infoWindow: _isMulti
            ? InfoWindow(title: '${i + 1}. ${p.name}')
            : InfoWindow.noText,
      ));
    }
    return markers;
  }

  /// Çoklu modda seçilen durakları sırayla bağlayan yardımcı çizgi.
  Set<Polyline> _buildPolylines() {
    if (!_isMulti || _picked.length < 2) return const {};
    return {
      Polyline(
        polylineId: const PolylineId('picked_order_casing'),
        points: _picked.map((p) => p.position).toList(),
        color: Colors.white.withValues(alpha: 0.9),
        width: 7,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
      Polyline(
        polylineId: const PolylineId('picked_order'),
        points: _picked.map((p) => p.position).toList(),
        color: _pinColor.withValues(alpha: 0.9),
        width: 4,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
    };
  }

  /// Cam zoom butonları için ortak kamera hareketi.
  Future<void> _zoomBy(double delta) async {
    final c = await _mapCtl.future;
    await c.animateCamera(CameraUpdate.zoomBy(delta));
  }

  Widget _map() {
    // Harita görünümü (Otomatik/Açık/Koyu) harita üstündeki düğmeyle
    // değiştirilir; MapStyleBuilder tercihi anında uygular.
    return MapStyleBuilder(
      builder: (context, mapStyle) => _mapSurface(mapStyle),
    );
  }

  Widget _mapSurface(String mapStyle) {
    return Stack(
      children: [
        GoogleMap(
          style: mapStyle,
          initialCameraPosition: CameraPosition(
            target: LatLng(widget.initialLat, widget.initialLng),
            zoom: widget.initialZoom,
          ),
          onMapCreated: (c) {
            if (!_mapCtl.isCompleted) _mapCtl.complete(c);
          },
          onTap: _onMapTap,
          markers: _buildMarkers(),
          polylines: _buildPolylines(),
          myLocationButtonEnabled: false,
          // Gömülü gri zoom kutuları yerine cam kontroller.
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          // Düz (2D) harita: eğim hareketi ve 3D bina kabartması kapalı.
          tiltGesturesEnabled: false,
          buildingsEnabled: false,
          mapType: MapType.normal,
        ),
        Positioned(
          right: 12,
          bottom: 64,
          child: MapZoomControls(
            onZoomIn: () => _zoomBy(1),
            onZoomOut: () => _zoomBy(-1),
            showThemeToggle: true,
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: MapHintBar(
            text: _notice ??
                (_isMulti
                    ? 'Güzergâh üzerinde durak sırasıyla haritaya dokunun. '
                        'Pinleri sürükleyerek düzeltebilirsiniz.'
                    : 'Konumun olacağı noktaya dokunun veya pini sürükleyin.'),
            icon: _notice == null ? Icons.touch_app : Icons.info_outline_rounded,
            accentColor: _notice == null ? null : const Color(0xFFD97706),
          ),
        ),
      ],
    );
  }

  // ── Arayüz ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final narrow = size.width < 720;
    final content = Column(
      children: [
        _header(),
        Expanded(child: _map()),
        if (_isMulti) _pickedList(),
        _footer(),
      ],
    );
    if (narrow) {
      // Telefonda tam ekran: haritaya en çok yer.
      return Dialog.fullscreen(
        backgroundColor: AdminUi.page,
        child: SafeArea(child: content),
      );
    }
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: AdminUi.page,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 680,
        height: size.height < 700 ? size.height - 48 : 660,
        child: content,
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AdminUi.brand, const Color(0xFF3F1D7A)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              _isMulti ? Icons.pin_drop_rounded : Icons.location_on_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isMulti ? 'Haritadan Çoklu Durak' : 'Haritadan Konum Seç',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  _isMulti
                      ? '${_picked.length} durak · dokunarak ekleyin'
                      : 'Dokunun ya da pini sürükleyin',
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ],
            ),
          ),
          if (_isMulti && _picked.isNotEmpty)
            IconButton(
              tooltip: 'Son durağı geri al',
              icon: const Icon(Icons.undo_rounded, color: Colors.white),
              onPressed: () => _removeAt(_picked.length - 1),
            ),
          IconButton(
            tooltip: 'Kapat',
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// Çoklu modda seçilen durakların düzenlenebilir listesi.
  Widget _pickedList() {
    if (_picked.isEmpty) {
      return Container(
        width: double.infinity,
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: const Row(
          children: [
            Icon(Icons.touch_app_rounded, color: AdminUi.muted, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Henüz durak eklenmedi — haritaya dokunarak başlayın.',
                style: TextStyle(color: AdminUi.muted, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      color: Colors.white,
      constraints: const BoxConstraints(maxHeight: 176),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        itemCount: _picked.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (ctx, i) {
          final p = _picked[i];
          return Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: _pinColor, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _nameCtrls[i],
                  onChanged: (v) => p.name = v,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Durak adı',
                    filled: true,
                    fillColor: AdminUi.page,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Kaldır',
                icon: const Icon(Icons.close_rounded, size: 20),
                color: AdminUi.muted,
                onPressed: () => _removeAt(i),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _footer() {
    final canSubmit = _picked.isNotEmpty;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AdminUi.line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          if (!_isMulti)
            Expanded(
              child: Text(
                '${_picked.first.position.latitude.toStringAsFixed(6)}, '
                '${_picked.first.position.longitude.toStringAsFixed(6)}',
                style: const TextStyle(
                  color: AdminUi.muted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Vazgeç'),
          ),
          const SizedBox(width: 8),
          if (_isMulti)
            Expanded(child: _submitButton(canSubmit))
          else
            _submitButton(canSubmit),
        ],
      ),
    );
  }
  Widget _submitButton(bool canSubmit) {
    return FilledButton.icon(
      onPressed: canSubmit ? _submit : null,
      icon: const Icon(Icons.check_rounded, size: 20),
      label: Text(
        _isMulti
            ? (_picked.isEmpty ? 'Ekle' : '${_picked.length} durağı ekle')
            : 'Bu konumu kullan',
      ),
      style: FilledButton.styleFrom(
        backgroundColor: AdminUi.brand,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
