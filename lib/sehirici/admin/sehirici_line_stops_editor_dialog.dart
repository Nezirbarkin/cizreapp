import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/map_vehicle_painters.dart' show MapStopState;
import '../../features/admin/widgets/admin_ui.dart';
import '../models/sehirici_models.dart';
import '../providers/sehirici_provider.dart';
import '../services/sehirici_errors.dart';
import '../services/sehirici_line_service.dart';
import '../widgets/sehirici_common_widgets.dart';
import 'sehirici_admin_controller.dart';
import 'sehirici_admin_kit.dart';
import 'sehirici_location_picker_dialog.dart';

/// Bir hattın duraklarını düzenleyen alt sayfayı açar. Kaydedildiyse true döner.
///
/// [controller] verilirse: şehir durakları ondan okunur (ağ isteği yok) ve
/// kaydederken hattın yol rotası da yenilenebilir.
Future<bool> showSehiriciLineStopsEditor(
  BuildContext context, {
  required SehiriciLine line,
  required String cityId,
  SehiriciAdminController? controller,
}) async {
  final saved = await showSehiriciSheet<bool>(
    context,
    heightFactor: 0.96,
    // Sürükleyerek kapatma kapalı: yarım kalmış düzenleme yanlışlıkla gitmesin.
    enableDrag: false,
    builder: (_) => SehiriciLineStopsEditorDialog(
      line: line,
      cityId: cityId,
      controller: controller,
    ),
  );
  return saved == true;
}

/// Bir hatta durak ekleme / çıkarma / sıralama ekranı.
///
/// Değişiklikler ANINDA kaydedilmez: liste bellekte düzenlenir, "Kaydet" ile
/// tek işlemde (atomik) yazılır. Eskiden her sürükleme/ekleme kendi isteğini
/// atıyor, bir istek başarısız olursa ekran ile veritabanı ayrışıyordu.
/// Haritadan oluşturulan yeni duraklar da kaydedilene kadar şehre eklenmez;
/// vazgeçilirse ortada yetim durak kalmaz.
class SehiriciLineStopsEditorDialog extends StatefulWidget {
  final SehiriciLine line;
  final String cityId;

  /// Opsiyonel: şehir durakları ve rota yenileme için.
  final SehiriciAdminController? controller;

  const SehiriciLineStopsEditorDialog({
    super.key,
    required this.line,
    required this.cityId,
    this.controller,
  });

  @override
  State<SehiriciLineStopsEditorDialog> createState() =>
      _SehiriciLineStopsEditorDialogState();
}

/// Listedeki bir durak; [isNew] ise henüz sunucuda yok (kaydedilirken oluşur).
class _Entry {
  final SehiriciStop stop;
  final bool isNew;
  const _Entry(this.stop, {this.isNew = false});
}

class _SehiriciLineStopsEditorDialogState
    extends State<SehiriciLineStopsEditorDialog> {
  /// Otobüs/minibüs için ortalama şehir içi hız (km/sa): duraklar arası süre
  /// tahmini bundan hesaplanır.
  static const double _avgSpeedKmh = 25;

  late final SehiriciLineService _service =
      widget.controller?.lineService ?? SehiriciLineService();

  late List<_Entry> _entries;
  late final List<String> _initialIds;

  /// Şehirdeki tüm duraklar (seçim havuzu).
  List<SehiriciStop> _pool = const [];
  bool _poolLoading = true;

  bool _saving = false;
  bool _refreshRoute = true;
  String? _error;

  /// Duraklar kaydedildi ama rota yenilenemedi: sayfa açık kalır, uyarır.
  String? _routeWarning;

  @override
  void initState() {
    super.initState();
    // Başlangıç listesi hattın zaten yüklü duraklarından gelir: yeniden ağdan
    // okumak sessizce başarısız olup listeyi BOŞ gösterebilir, admin de o
    // boş listeyi kaydederek hattın tüm duraklarını silebilirdi.
    _entries = [for (final s in widget.line.stops) _Entry(s.asStop)];
    _initialIds = _entries.map((e) => e.stop.id).toList();
    _loadPool();
  }

  Future<void> _loadPool() async {
    final fromController = widget.controller?.stops;
    if (fromController != null && fromController.isNotEmpty) {
      setState(() {
        _pool = fromController;
        _poolLoading = false;
      });
      return;
    }
    final loaded = await _service.getStopsByCity(widget.cityId);
    if (!mounted) return;
    setState(() {
      _pool = loaded;
      _poolLoading = false;
    });
  }

  // ── Türetilmiş değerler ──────────────────────────────────────

  bool get _dirty {
    final ids = _entries.map((e) => e.stop.id).toList();
    if (ids.length != _initialIds.length) return true;
    for (var i = 0; i < ids.length; i++) {
      if (ids[i] != _initialIds[i]) return true;
    }
    return false;
  }

  /// Havuzdan henüz hatta eklenmemiş duraklar.
  List<SehiriciStop> get _available {
    final used = _entries.map((e) => e.stop.id).toSet();
    return _pool.where((s) => s.isActive && !used.contains(s.id)).toList();
  }

  static double _distanceKm(SehiriciStop a, SehiriciStop b) {
    const r = 6371.0;
    final dLat = (b.lat - a.lat) * math.pi / 180;
    final dLng = (b.lng - a.lng) * math.pi / 180;
    final lat1 = a.lat * math.pi / 180;
    final lat2 = b.lat * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  /// Her durağın hat başından itibaren kümülatif mesafesi (km).
  List<double> get _cumulativeKm {
    final out = <double>[];
    var total = 0.0;
    for (var i = 0; i < _entries.length; i++) {
      if (i > 0) total += _distanceKm(_entries[i - 1].stop, _entries[i].stop);
      out.add(double.parse(total.toStringAsFixed(3)));
    }
    return out;
  }

  static int _minutesFor(double km) => ((km / _avgSpeedKmh) * 60).round();

  /// Sunucuya gidecek satırlar (sıra, mesafe, süre hesaplanmış).
  List<Map<String, dynamic>> _rows() {
    final km = _cumulativeKm;
    return [
      for (var i = 0; i < _entries.length; i++)
        {
          'stop_id': _entries[i].stop.id,
          'stop_order': i,
          'minutes_from_start': _minutesFor(km[i]),
          'distance_km': km[i],
        },
    ];
  }

  /// Şu anki listenin [SehiriciLineStop] karşılığı (imza ve rota için).
  List<SehiriciLineStop> get _lineStops {
    final km = _cumulativeKm;
    return [
      for (var i = 0; i < _entries.length; i++)
        SehiriciLineStop(
          stopId: _entries[i].stop.id,
          stopOrder: i,
          minutesFromStart: _minutesFor(km[i]),
          distanceKm: km[i],
          name: _entries[i].stop.name,
          lat: _entries[i].stop.lat,
          lng: _entries[i].stop.lng,
          code: _entries[i].stop.code,
          address: _entries[i].stop.address,
        ),
    ];
  }

  /// Kayıtlı rota var ve bu durak sırasıyla uyuşmuyor (ya da düzenleme sonrası
  /// uyuşmayacak).
  bool get _routeWouldBeStale {
    if (!widget.line.hasRoute) return false;
    final saved = widget.line.routeSignature;
    if (saved == null) return _dirty;
    return saved != SehiriciLineService.computeStopsSignature(_lineStops);
  }

  // ── Düzenleme ────────────────────────────────────────────────

  void _remove(int index) {
    setState(() {
      _entries = [..._entries]..removeAt(index);
      _error = null;
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final next = [..._entries];
      next.insert(newIndex, next.removeAt(oldIndex));
      _entries = next;
      _error = null;
    });
  }

  void _reverse() {
    setState(() {
      _entries = _entries.reversed.toList();
      _error = null;
    });
  }

  Future<void> _addFromList() async {
    final available = _available;
    final picked = await showSehiriciSheet<List<SehiriciStop>>(
      context,
      heightFactor: 0.88,
      builder: (_) => _StopPickerSheet(
        stops: available,
        linesByStop: widget.controller?.linesByStop ?? const {},
        currentLineId: widget.line.id,
        loading: _poolLoading,
        onCreateOnMap: () {
          Navigator.of(context).pop(null);
          _createOnMap();
        },
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      _entries = [..._entries, for (final s in picked) _Entry(s)];
      _error = null;
    });
  }

  /// Haritada güzergâh boyunca dokunarak yeni duraklar oluşturur; sırasıyla
  /// listeye eklenir (kaydedilene kadar sunucuya yazılmaz).
  Future<void> _createOnMap() async {
    if (_saving) return;
    SehiriciCity? city = widget.controller?.city;
    if (city == null) {
      try {
        for (final c in context.read<SehiriciProvider>().cities) {
          if (c.id == widget.cityId) city = c;
        }
      } catch (_) {}
    }
    final startLat = _entries.isNotEmpty
        ? _entries.last.stop.lat
        : (city?.centerLat ?? (_pool.isNotEmpty ? _pool.first.lat : 37.0));
    final startLng = _entries.isNotEmpty
        ? _entries.last.stop.lng
        : (city?.centerLng ?? (_pool.isNotEmpty ? _pool.first.lng : 41.0));

    final picked = await SehiriciLocationPickerDialog.pickMultiple(
      context,
      initialLat: startLat,
      initialLng: startLng,
      initialZoom: (city?.zoomLevel ?? 14).toDouble(),
      existingStops: [..._pool, for (final e in _entries) e.stop],
      lineColor: widget.line.color,
    );
    if (!mounted || picked == null || picked.isEmpty) return;
    setState(() {
      _entries = [
        ..._entries,
        for (final p in picked)
          _Entry(
            SehiriciStop(
              id: const Uuid().v4(),
              name: p.name.trim(),
              lat: p.position.latitude,
              lng: p.position.longitude,
            ),
            isNew: true,
          ),
      ];
      _error = null;
    });
  }

  // ── Kaydet / kapat ───────────────────────────────────────────

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // 1) Yeni duraklar (kimlikleri sabit: yeniden denemek yinelenen üretmez).
      for (final e in _entries.where((e) => e.isNew)) {
        await _service.saveStop(
          id: e.stop.id,
          cityId: widget.cityId,
          name: e.stop.name,
          lat: e.stop.lat,
          lng: e.stop.lng,
        );
      }
      // 2) Hat-durak bağı: tek işlemde (hata olursa eski duraklar korunur).
      final lineStops = _lineStops;
      await _service.setLineStopsOrThrow(widget.line.id, _rows());
      _refreshUserSide();

      // 3) Rota (isteğe bağlı).
      final controller = widget.controller;
      if (controller != null &&
          _refreshRoute &&
          _routeWouldBeStale &&
          lineStops.length >= 2) {
        try {
          await controller.createRouteFromStops(
            widget.line.copyWith(stops: lineStops),
          );
          _refreshUserSide();
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _saving = false;
            _routeWarning = 'Duraklar kaydedildi ama rota yenilenemedi: '
                '${sehiriciErrorMessage(e)} Hatlar sekmesinden rotayı elle '
                'oluşturabilirsiniz.';
          });
          return;
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = sehiriciErrorMessage(e);
        });
      }
    }
  }

  void _refreshUserSide() {
    try {
      context.read<SehiriciProvider>().invalidateAllCaches();
    } catch (_) {}
  }

  Future<void> _requestClose() async {
    if (_saving) return;
    if (!_dirty || _routeWarning != null) {
      Navigator.of(context).pop(_routeWarning != null);
      return;
    }
    final discard = await sehiriciConfirm(
      context,
      icon: Icons.edit_off_rounded,
      title: 'Değişiklikler atılsın mı?',
      message: 'Kaydetmeden çıkarsanız duraklarda yaptığınız düzenlemeler '
          'kaybolur${_entries.any((e) => e.isNew) ? '; haritadan eklediğiniz '
              'yeni duraklar da oluşturulmaz' : ''}.',
      confirmLabel: 'Atıp Çık',
      destructive: true,
    );
    if (discard && mounted) Navigator.of(context).pop(false);
  }

  // ── Arayüz ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final km = _cumulativeKm;
    final totalKm = km.isEmpty ? 0.0 : km.last;
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose();
      },
      child: Column(
        children: [
          _Header(
            line: widget.line,
            stopCount: _entries.length,
            totalKm: totalKm,
            onClose: _requestClose,
          ),
          Expanded(
            child: Column(
              children: [
                _ActionBar(
                  onAdd: _saving ? null : _addFromList,
                  onMap: _saving ? null : _createOnMap,
                  onReverse: (_saving || _entries.length < 2) ? null : _reverse,
                ),
                if (_routeWarning != null)
                  _Banner(
                    color: const Color(0xFFD97706),
                    icon: Icons.warning_amber_rounded,
                    text: _routeWarning!,
                  )
                else if (_routeWouldBeStale)
                  _StaleRouteBanner(
                    canRefresh: widget.controller != null && _entries.length >= 2,
                    refresh: _refreshRoute,
                    onChanged: (v) => setState(() => _refreshRoute = v),
                  ),
                Expanded(
                  child: _entries.isEmpty
                      ? _EmptyState(
                          onAdd: _addFromList,
                          onMap: _createOnMap,
                        )
                      : _StopList(
                          entries: _entries,
                          km: km,
                          color: widget.line.color,
                          minutesFor: _minutesFor,
                          enabled: !_saving,
                          onReorder: _reorder,
                          onRemove: _remove,
                        ),
                ),
              ],
            ),
          ),
          _BottomBar(
            saving: _saving,
            dirty: _dirty,
            stopCount: _entries.length,
            newCount: _entries.where((e) => e.isNew).length,
            error: _error,
            closeOnly: _routeWarning != null,
            onCancel: _requestClose,
            onSave: _save,
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// Parçalar
// ═════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  final SehiriciLine line;
  final int stopCount;
  final double totalKm;
  final VoidCallback onClose;

  const _Header({
    required this.line,
    required this.stopCount,
    required this.totalKm,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final base = line.color;
    final dark = HSLColor.fromColor(base)
        .withLightness(
            (HSLColor.fromColor(base).lightness * 0.62).clamp(0.12, 0.6))
        .toColor();
    final fg = sehiriciOnColor(base);
    final subtle = fg.withValues(alpha: 0.85);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, dark],
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4.5,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Row(
            children: [
              Container(
                width: 46,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: SehiriciVehicleIcon.forLine(line, height: 46),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.code.isEmpty ? 'Hat durakları' : '${line.code} · Duraklar',
                      style: TextStyle(
                        color: fg,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      line.name.isEmpty ? 'Adsız hat' : line.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: subtle, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      stopCount == 0
                          ? 'Henüz durak yok'
                          : '$stopCount durak · ${totalKm.toStringAsFixed(1)} km · '
                              '~${((totalKm / _SehiriciLineStopsEditorDialogState._avgSpeedKmh) * 60).round()} dk',
                      style: TextStyle(
                        color: fg,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: fg),
                tooltip: 'Kapat',
                onPressed: onClose,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final VoidCallback? onAdd;
  final VoidCallback? onMap;
  final VoidCallback? onReverse;

  const _ActionBar({
    required this.onAdd,
    required this.onMap,
    required this.onReverse,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_location_alt_rounded, size: 20),
              label: const Text('Durak ekle'),
              style: FilledButton.styleFrom(
                backgroundColor: AdminUi.brand,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onMap,
              icon: const Icon(Icons.pin_drop_rounded, size: 20),
              label: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Haritadan yeni', maxLines: 1, softWrap: false),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AdminUi.brand,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                side: BorderSide(color: AdminUi.brand.withValues(alpha: 0.5)),
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: onReverse,
            tooltip: 'Sırayı ters çevir',
            icon: const Icon(Icons.swap_vert_rounded),
            color: AdminUi.brand,
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;

  const _Banner({required this.color, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, height: 1.35)),
          ),
        ],
      ),
    );
  }
}

/// "Rota eski kalacak" uyarısı + kaydederken rotayı yenileme anahtarı.
class _StaleRouteBanner extends StatelessWidget {
  final bool canRefresh;
  final bool refresh;
  final ValueChanged<bool> onChanged;

  const _StaleRouteBanner({
    required this.canRefresh,
    required this.refresh,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFD97706);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.route_rounded, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: canRefresh
                ? const Text(
                    'Duraklar değişiyor. Kaydederken hat rotasını da '
                    'yeniden oluştur',
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.w700, height: 1.3),
                  )
                : const Text(
                    'Duraklar değişince kayıtlı rota eski kalır; Hatlar '
                    'sekmesinden yeniden oluşturun.',
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.w700, height: 1.3),
                  ),
          ),
          if (canRefresh)
            Switch(
              value: refresh,
              onChanged: onChanged,
              activeTrackColor: color,
              activeThumbColor: Colors.white,
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  final VoidCallback onMap;

  const _EmptyState({required this.onAdd, required this.onMap});

  @override
  Widget build(BuildContext context) {
    return AdminEmpty(
      icon: Icons.signpost_outlined,
      title: 'Bu hatta henüz durak yok',
      subtitle: 'Şehirdeki hazır duraklardan seçin ya da haritada güzergâh '
          'boyunca dokunarak yeni duraklar oluşturun.',
      action: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_location_alt_rounded),
            label: const Text('Durak ekle'),
            style: FilledButton.styleFrom(backgroundColor: AdminUi.brand),
          ),
          OutlinedButton.icon(
            onPressed: onMap,
            icon: const Icon(Icons.pin_drop_rounded),
            label: const Text('Haritadan yeni'),
          ),
        ],
      ),
    );
  }
}

/// Sıralı durak listesi: soldaki zaman çizgisi + sürüklenebilir kartlar.
class _StopList extends StatelessWidget {
  final List<_Entry> entries;
  final List<double> km;
  final Color color;
  final int Function(double km) minutesFor;
  final bool enabled;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<int> onRemove;

  const _StopList({
    required this.entries,
    required this.km,
    required this.color,
    required this.minutesFor,
    required this.enabled,
    required this.onReorder,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      itemCount: entries.length,
      buildDefaultDragHandles: false,
      onReorder: enabled ? onReorder : (_, __) {},
      proxyDecorator: (child, index, animation) => Material(
        color: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black38,
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
      itemBuilder: (context, i) {
        final e = entries[i];
        final first = i == 0;
        final last = i == entries.length - 1;
        final seg = i == 0 ? 0.0 : km[i] - km[i - 1];
        return IntrinsicHeight(
          key: ValueKey('stop-${e.stop.id}'),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Zaman çizgisi
              SizedBox(
                width: 38,
                child: Column(
                  children: [
                    Container(
                      width: 4,
                      height: 16,
                      color: first ? Colors.transparent : color.withValues(alpha: 0.4),
                    ),
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: sehiriciOnColor(color),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        width: 4,
                        color: last ? Colors.transparent : color.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: e.isNew
                            ? AdminUi.brand.withValues(alpha: 0.5)
                            : AdminUi.line,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      e.stop.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  if (e.isNew) ...[
                                    const SizedBox(width: 6),
                                    AdminBadge(label: 'Yeni', color: AdminUi.brand),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                [
                                  if (first)
                                    'Başlangıç'
                                  else ...[
                                    '+${seg.toStringAsFixed(1)} km',
                                    'toplam ${km[i].toStringAsFixed(1)} km',
                                    '~${minutesFor(km[i])} dk',
                                  ],
                                  if ((e.stop.address ?? '').isNotEmpty)
                                    e.stop.address!,
                                ].join('  ·  '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12, color: AdminUi.muted),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Duraktan çıkar',
                          visualDensity: VisualDensity.compact,
                          onPressed: enabled ? () => onRemove(i) : null,
                          icon: const Icon(Icons.remove_circle_outline_rounded),
                          color: const Color(0xFFDC2626),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          enabled: enabled,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                            child: Icon(Icons.drag_indicator_rounded,
                                color: AdminUi.muted),
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
      },
    );
  }
}

class _BottomBar extends StatelessWidget {
  final bool saving;
  final bool dirty;
  final int stopCount;
  final int newCount;
  final String? error;
  final bool closeOnly;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const _BottomBar({
    required this.saving,
    required this.dirty,
    required this.stopCount,
    required this.newCount,
    required this.error,
    required this.closeOnly,
    required this.onCancel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AdminUi.line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: Color(0xFFB91C1C), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(error!,
                          style: const TextStyle(
                              color: Color(0xFF991B1B),
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            if (closeOnly)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Kapat'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AdminUi.brand,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              )
            else
              Row(
                children: [
                  TextButton(
                    onPressed: saving ? null : onCancel,
                    child: const Text('Vazgeç'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (saving || !dirty) ? null : onSave,
                      icon: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(
                        dirty ? 'Kaydet · $stopCount durak' : 'Değişiklik yok',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AdminUi.brand,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// Hazır duraklardan seçim
// ═════════════════════════════════════════════════════════════════

/// Şehirdeki hatta henüz eklenmemiş duraklar: arama + çoklu seçim. Seçim
/// SIRASI listeye ekleme sırasıdır (hat güzergâhı sırasıyla dokunulur).
class _StopPickerSheet extends StatefulWidget {
  final List<SehiriciStop> stops;
  final Map<String, List<SehiriciLine>> linesByStop;
  final String currentLineId;
  final bool loading;
  final VoidCallback onCreateOnMap;

  const _StopPickerSheet({
    required this.stops,
    required this.linesByStop,
    required this.currentLineId,
    required this.loading,
    required this.onCreateOnMap,
  });

  @override
  State<_StopPickerSheet> createState() => _StopPickerSheetState();
}

class _StopPickerSheetState extends State<_StopPickerSheet> {
  final TextEditingController _search = TextEditingController();
  final List<String> _picked = [];
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<SehiriciStop> get _visible {
    final q = sehiriciFold(_query.trim());
    final list = widget.stops.where((s) {
      if (q.isEmpty) return true;
      return sehiriciFold(s.name).contains(q) ||
          sehiriciFold(s.code ?? '').contains(q) ||
          sehiriciFold(s.address ?? '').contains(q);
    }).toList()
      ..sort((a, b) => sehiriciFold(a.name).compareTo(sehiriciFold(b.name)));
    return list;
  }

  void _toggle(String id) {
    setState(() {
      if (!_picked.remove(id)) _picked.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final byId = {for (final s in widget.stops) s.id: s};
    return SehiriciSheetScaffold(
      title: 'Hazır duraklardan ekle',
      subtitle: _picked.isEmpty
          ? 'Hat güzergâhı sırasıyla dokunun'
          : '${_picked.length} durak seçildi',
      bottomBar: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _picked.isEmpty
              ? null
              : () => Navigator.of(context)
                  .pop([for (final id in _picked) byId[id]!]),
          icon: const Icon(Icons.add_rounded),
          label: Text(_picked.isEmpty ? 'Ekle' : '${_picked.length} durağı ekle'),
          style: FilledButton.styleFrom(
            backgroundColor: AdminUi.brand,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SehiriciSearchField(
              controller: _search,
              hint: 'Durak adı, kod veya adres ara',
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: widget.loading
                ? const Center(child: CircularProgressIndicator())
                : widget.stops.isEmpty
                    ? AdminEmpty(
                        icon: Icons.signpost_outlined,
                        title: 'Eklenecek hazır durak yok',
                        subtitle: 'Şehirdeki tüm duraklar bu hatta zaten var '
                            'ya da henüz durak oluşturulmamış.',
                        action: FilledButton.icon(
                          onPressed: widget.onCreateOnMap,
                          icon: const Icon(Icons.pin_drop_rounded),
                          label: const Text('Haritadan yeni oluştur'),
                          style: FilledButton.styleFrom(
                              backgroundColor: AdminUi.brand),
                        ),
                      )
                    : visible.isEmpty
                        ? const AdminEmpty(
                            icon: Icons.search_off_rounded,
                            title: 'Eşleşen durak yok',
                            subtitle: 'Aramayı değiştirin.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                            itemCount: visible.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final s = visible[i];
                              final order = _picked.indexOf(s.id);
                              final others = (widget.linesByStop[s.id] ?? const [])
                                  .where((l) => l.id != widget.currentLineId)
                                  .toList();
                              return _PickRow(
                                stop: s,
                                order: order < 0 ? null : order + 1,
                                otherLines: others,
                                onTap: () => _toggle(s.id),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  final SehiriciStop stop;
  final int? order;
  final List<SehiriciLine> otherLines;
  final VoidCallback onTap;

  const _PickRow({
    required this.stop,
    required this.order,
    required this.otherLines,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = order != null;
    final sub = [
      if ((stop.code ?? '').isNotEmpty) 'Kod ${stop.code}',
      if ((stop.address ?? '').isNotEmpty) stop.address!,
    ].join(' · ');
    return AdminCard(
      onTap: onTap,
      borderColor: selected ? AdminUi.brand : null,
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 54,
            decoration: BoxDecoration(
              color: const Color(0xFFF2F1ED),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: SehiriciStopIcon(
              height: 42,
              state: MapStopState.normal,
              lineColors: otherLines.map((l) => l.color).take(3).toList(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stop.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w800)),
                if (sub.isNotEmpty)
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AdminUi.muted)),
                if (otherLines.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final l in otherLines.take(4))
                        SehiriciLineBadge.forLine(l, height: 18, minWidth: 28),
                      if (otherLines.length > 4)
                        Text('+${otherLines.length - 4}',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AdminUi.muted)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: selected ? AdminUi.brand : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AdminUi.brand : AdminUi.line,
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: selected
                ? Text('$order',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900))
                : null,
          ),
        ],
      ),
    );
  }
}
