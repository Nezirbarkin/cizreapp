// ignore_for_file: use_build_context_synchronously

import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../models/sehirici_models.dart';
import '../services/sehirici_line_service.dart';

/// Bir hatta durak ekleme/çıkarma/sıralama ekranı.
/// Basit mantık: solda "Hatta eklenen duraklar" (sıralı, sürükle-bırak),
/// altta "+ Durak Ekle" ile şehirdeki mevcut duraklardan seçim.
class SehiriciLineStopsEditorDialog extends StatefulWidget {
  final SehiriciLine line;
  final String cityId;

  const SehiriciLineStopsEditorDialog({
    super.key,
    required this.line,
    required this.cityId,
  });

  @override
  State<SehiriciLineStopsEditorDialog> createState() =>
      _SehiriciLineStopsEditorDialogState();
}

class _SehiriciLineStopsEditorDialogState
    extends State<SehiriciLineStopsEditorDialog> {
  final SehiriciLineService _service = SehiriciLineService();

  bool _loading = true;
  bool _saving = false;
  bool _autoSaving = false;

  /// Hatta eklenmiş duraklar, sırayla.
  List<SehiriciStop> _selected = [];
  /// Şehirdeki tüm duraklar (seçim havuzu).
  List<SehiriciStop> _allStops = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _service.getStopsByCity(widget.cityId),
      _service.getLineStops(widget.line.id),
    ]);
    _allStops = results[0] as List<SehiriciStop>;
    final lineStops = results[1] as List<SehiriciLineStop>;
    final byId = {for (final s in _allStops) s.id: s};
    _selected = lineStops
        .map((ls) => byId[ls.stopId] ?? ls.asStop)
        .toList();
    if (mounted) setState(() => _loading = false);
  }

  List<SehiriciStop> get _availableToAdd {
    final selectedIds = _selected.map((s) => s.id).toSet();
    return _allStops.where((s) => !selectedIds.contains(s.id)).toList();
  }

  double _distanceKm(SehiriciStop a, SehiriciStop b) {
    const r = 6371.0;
    final dLat = (b.lat - a.lat) * math.pi / 180;
    final dLng = (b.lng - a.lng) * math.pi / 180;
    final lat1 = a.lat * math.pi / 180;
    final lat2 = b.lat * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  /// Sürükle-bırak sonrası otomatik kaydet (küçük snackbar ile)
  Future<void> _autoSave() async {
    if (_saving || _autoSaving) return;
    setState(() => _autoSaving = true);
    
    double cumulativeKm = 0;
    final rows = <Map<String, dynamic>>[];
    for (int i = 0; i < _selected.length; i++) {
      if (i > 0) {
        final segmentKm = _distanceKm(_selected[i - 1], _selected[i]);
        cumulativeKm += segmentKm;
      }
      final totalKm = double.parse(cumulativeKm.toStringAsFixed(3));
      final minutes = ((totalKm / 25.0) * 60).round();
      rows.add({
        'stop_id': _selected[i].id,
        'stop_order': i,
        'minutes_from_start': minutes,
        'distance_km': totalKm,
      });
    }

    final ok = await _service.setLineStops(widget.line.id, rows);
    if (!mounted) return;
    setState(() => _autoSaving = false);
    
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Sıralama ve mesafeler güncellendi'),
          duration: Duration(seconds: 1),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// Manuel kaydet (Kaydet butonu ile)
  Future<void> _save() async {
    setState(() => _saving = true);
    
    double cumulativeKm = 0;
    final rows = <Map<String, dynamic>>[];
    for (int i = 0; i < _selected.length; i++) {
      if (i > 0) {
        final segmentKm = _distanceKm(_selected[i - 1], _selected[i]);
        cumulativeKm += segmentKm;
      }
      final totalKm = double.parse(cumulativeKm.toStringAsFixed(3));
      final minutes = ((totalKm / 25.0) * 60).round();
      rows.add({
        'stop_id': _selected[i].id,
        'stop_order': i,
        'minutes_from_start': minutes,
        'distance_km': totalKm,
      });
    }

    final ok = await _service.setLineStops(widget.line.id, rows);
    if (!mounted) return;
    setState(() => _saving = false);
    
    if (ok) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Duraklar kaydedilemedi'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _addStop(SehiriciStop stop) {
    setState(() => _selected.add(stop));
  }

  void _removeStop(int index) {
    setState(() => _selected.removeAt(index));
  }

  void _showAddStopPicker() {
    final available = _availableToAdd;
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Eklenecek başka durak yok — önce Duraklar sekmesinden yeni durak oluşturun')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: 400,
          child: ListView.builder(
            itemCount: available.length,
            itemBuilder: (c, i) {
              final s = available[i];
              return ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text(s.name),
                subtitle: s.address != null ? Text(s.address!) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _addStop(s);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: widget.line.color,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.line.code} - ${widget.line.name}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const Text(
                          'Durakları sürükleyerek sırala, sil, ya da yeni ekle',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _selected.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Bu hatta henüz durak eklenmedi.\nAşağıdaki "Durak Ekle" butonuyla başlayın.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _selected.length,
                          onReorder: (oldIndex, newIndex) {
                            setState(() {
                              if (newIndex > oldIndex) newIndex -= 1;
                              final item = _selected.removeAt(oldIndex);
                              _selected.insert(newIndex, item);
                            });
                            // Sürükle-bırak sonrası otomatik kaydet ve bildirim göster
                            _autoSave();
                          },
                          itemBuilder: (ctx, i) {
                            final s = _selected[i];
                            // Hesaplanan tahmini değerler (sadece görüntüleme için)
                            double? km;
                            int? minutes;
                            if (_selected.isNotEmpty) {
                              double cumKm = 0;
                              for (int j = 0; j <= i; j++) {
                                if (j > 0) {
                                  cumKm += _distanceKm(_selected[j - 1], _selected[j]);
                                }
                              }
                              km = double.parse(cumKm.toStringAsFixed(2));
                              minutes = ((km / 25.0) * 60).round();
                            }
                            return ListTile(
                              key: ValueKey(s.id),
                              leading: CircleAvatar(
                                backgroundColor: widget.line.color,
                                child: Text(
                                  '${i + 1}',
                                  style: const TextStyle(
                                      color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(s.name),
                              subtitle: Text(
                                '${km?.toStringAsFixed(1) ?? '0'} km · ~${minutes ?? 0} dk'
                                '${s.address != null ? ' · ${s.address}' : ''}',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    tooltip: 'Duraktan çıkar',
                                    onPressed: () => _removeStop(i),
                                  ),
                                  const Icon(Icons.drag_handle, color: Colors.grey),
                                ],
                              ),
                            );
                          },
                        ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Mevcut duraklar için güncelleme butonu
                  if (_selected.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: (_saving || _autoSaving) ? null : () async {
                            // Sadece tahmini değerleri güncelle (sıralama değişmez)
                            setState(() => _saving = true);
                            double cumulativeKm = 0;
                            final rows = <Map<String, dynamic>>[];
                            for (int i = 0; i < _selected.length; i++) {
                              if (i > 0) {
                                final segmentKm = _distanceKm(_selected[i - 1], _selected[i]);
                                cumulativeKm += segmentKm;
                              }
                              final totalKm = double.parse(cumulativeKm.toStringAsFixed(3));
                              final minutes = ((totalKm / 25.0) * 60).round();
                              rows.add({
                                'stop_id': _selected[i].id,
                                'stop_order': i,
                                'minutes_from_start': minutes,
                                'distance_km': totalKm,
                              });
                            }
                            final ok = await _service.setLineStops(widget.line.id, rows);
                            if (!mounted) return;
                            setState(() => _saving = false);
                            if (ok) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('✓ Mesafe ve süreler güncellendi'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Mesafeleri Güncelle'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blue.shade700,
                          ),
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _showAddStopPicker,
                          icon: const Icon(Icons.add_location_alt_outlined),
                          label: const Text('Durak Ekle'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: (_saving || _autoSaving) ? null : _save,
                          icon: (_saving || _autoSaving)
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.check),
                          label: const Text('Kaydet'),
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
    );
  }
}
