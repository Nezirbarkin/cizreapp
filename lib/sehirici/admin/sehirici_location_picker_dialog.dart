// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/sehirici_models.dart';
import '../utils/sehirici_route_geometry.dart';

/// Çoklu seçim modunda haritadan toplanan tek bir durak adayı.
class SehiriciPickedStop {
  SehiriciPickedStop({required this.position, required this.name});

  LatLng position;
  String name;
}

/// Admin'in durak konumunu elle lat/lng yazmak yerine haritaya dokunarak
/// (veya pini sürükleyerek) seçmesini sağlayan dialog.
///
/// İki modda çalışır:
///  • **Tek seçim** ([SehiriciLocationPickerDialog.pickSingle]) — tek bir pin,
///    "Bu Konumu Kullan" ile [LatLng] döner. Durak formundaki "Haritadan Seç"
///    bunu kullanır.
///  • **Çoklu seçim** ([SehiriciLocationPickerDialog.pickMultiple]) — haritaya
///    her dokunuşta sıralı bir durak pini eklenir, adları satır içinde
///    düzenlenebilir, hepsi tek seferde kaydedilir. Bir hattın duraklarını
///    tek tek form doldurarak girmek yerine güzergâh üzerinde tıklayarak
///    dizmek için.
///
/// [existingStops] verilirse şehirdeki mevcut duraklar haritada gri pinlerle
/// referans olarak gösterilir; yeni pin bunlardan birine çok yakın düşerse
/// uyarı verilir (yanlışlıkla kopya durak oluşturmayı engeller).
class SehiriciLocationPickerDialog extends StatefulWidget {
  final double initialLat;
  final double initialLng;
  final double initialZoom;
  final bool multiSelect;
  final List<SehiriciStop> existingStops;

  const SehiriciLocationPickerDialog({
    super.key,
    required this.initialLat,
    required this.initialLng,
    this.initialZoom = 15,
    this.multiSelect = false,
    this.existingStops = const [],
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
  }) {
    return showDialog<List<SehiriciPickedStop>>(
      context: context,
      builder: (_) => SehiriciLocationPickerDialog(
        initialLat: initialLat,
        initialLng: initialLng,
        initialZoom: initialZoom,
        multiSelect: true,
        existingStops: existingStops,
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

  @override
  void initState() {
    super.initState();
    if (!widget.multiSelect) {
      _picked.add(SehiriciPickedStop(
        position: LatLng(widget.initialLat, widget.initialLng),
        name: '',
      ));
      _nameCtrls.add(TextEditingController());
    }
  }

  @override
  void dispose() {
    for (final c in _nameCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isMulti => widget.multiSelect;

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.orange),
    );
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

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};

    // Mevcut duraklar — referans, sürüklenemez.
    for (final s in widget.existingStops) {
      markers.add(Marker(
        markerId: MarkerId('existing_${s.id}'),
        position: LatLng(s.lat, s.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueAzure,
        ),
        alpha: 0.6,
        consumeTapEvents: true,
        infoWindow: InfoWindow(title: s.name, snippet: 'Mevcut durak'),
        onTap: () {},
      ));
    }

    for (var i = 0; i < _picked.length; i++) {
      final p = _picked[i];
      markers.add(Marker(
        markerId: MarkerId('picked_$i'),
        position: p.position,
        draggable: true,
        onDragEnd: (pos) => _onPinDragged(i, pos),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueRed,
        ),
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
        polylineId: const PolylineId('picked_order'),
        points: _picked.map((p) => p.position).toList(),
        color: Colors.red.withValues(alpha: 0.55),
        width: 3,
        consumeTapEvents: false,
      ),
    };
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

  @override
  Widget build(BuildContext context) {
    final mediaWidth = MediaQuery.of(context).size.width;
    final mediaHeight = MediaQuery.of(context).size.height;
    final dialogWidth = mediaWidth < 720 ? mediaWidth - 24 : 640.0;
    final dialogHeight = mediaHeight < 600 ? mediaHeight - 24 : 620.0;

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).colorScheme.surface,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _header(context),
            Expanded(child: _map()),
            if (_isMulti) _pickedList(),
            _footer(context),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Theme.of(context).colorScheme.primary,
      child: Row(
        children: [
          const Icon(Icons.location_on, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _isMulti ? 'Haritadan Çoklu Durak' : 'Haritadan Konum Seç',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (_isMulti && _picked.isNotEmpty)
            IconButton(
              tooltip: 'Son durağı geri al',
              icon: const Icon(Icons.undo, color: Colors.white),
              onPressed: () => _removeAt(_picked.length - 1),
            ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _map() {
    return Stack(
      children: [
        GoogleMap(
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
          zoomControlsEnabled: true,
          mapToolbarEnabled: false,
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Material(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  const Icon(Icons.touch_app, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isMulti
                          ? 'Güzergâh üzerinde durak sırasıyla haritaya '
                              'dokunun. Pinleri sürükleyerek düzeltebilirsiniz.'
                          : 'Durağın olacağı noktaya dokunun veya pini '
                              'sürükleyin.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Çoklu modda seçilen durakların düzenlenebilir listesi.
  Widget _pickedList() {
    if (_picked.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          'Henüz durak eklenmedi — haritaya dokunarak başlayın.',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
      );
    }
    return SizedBox(
      height: 132,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _picked.length,
        itemBuilder: (ctx, i) {
          final p = _picked[i];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _nameCtrls[i],
                    onChanged: (v) => p.name = v,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Durak adı',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                IconButton(
                  tooltip: 'Kaldır',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => _removeAt(i),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final canSubmit = _picked.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _isMulti
                  ? '${_picked.length} durak seçildi'
                  : '${_picked.first.position.latitude.toStringAsFixed(6)}, '
                      '${_picked.first.position.longitude.toStringAsFixed(6)}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('İptal'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: canSubmit ? _submit : null,
            icon: const Icon(Icons.check, size: 18),
            label: Text(
              _isMulti
                  ? '${_picked.length} Durağı Kaydet'
                  : 'Bu Konumu Kullan',
            ),
          ),
        ],
      ),
    );
  }
}
