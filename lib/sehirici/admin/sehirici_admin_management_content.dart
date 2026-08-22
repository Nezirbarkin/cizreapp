// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';
import '../models/sehirici_models.dart';
import '../providers/sehirici_provider.dart';
import '../services/sehirici_city_service.dart';
import '../services/sehirici_line_service.dart';
import '../services/sehirici_driver_service.dart';
import '../utils/sehirici_route_geometry.dart';
import 'sehirici_route_viewer_dialog.dart';
import 'sehirici_line_stops_editor_dialog.dart';
import 'sehirici_line_route_draw_dialog.dart';
import 'sehirici_location_picker_dialog.dart';

/// Admin paneli: Şehiriçi Yönetimi içerik widget'ı.
/// Tabs: Şehirler, Hatlar, Duraklar, Şoförler, Ayarlar.
class SehiriciAdminManagementContent extends StatefulWidget {
  const SehiriciAdminManagementContent({super.key});

  @override
  State<SehiriciAdminManagementContent> createState() =>
      _SehiriciAdminManagementContentState();
}

class _SehiriciAdminManagementContentState
    extends State<SehiriciAdminManagementContent>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedCityId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    // Provider'daki şehri seç
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<SehiriciProvider>();
      setState(() {
        _selectedCityId = p.selectedCityId ??
            (p.cities.isNotEmpty ? p.cities.first.id : null);
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Üst bilgi
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Row(
            children: [
              Icon(Icons.directions_bus,
                  color: Theme.of(context).colorScheme.primary, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Şehiriçi Yönetimi',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                    Text(
                      'Şehirler, hatlar, duraklar, şoförler ve modül ayarları',
                      style: TextStyle(
                          color: Colors.grey.shade700, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Şehir seçici (tüm tabs için geçerli)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Text('Şehir:', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              Expanded(
                child: Consumer<SehiriciProvider>(
                  builder: (_, p, __) => DropdownButton<String>(
                    value: _selectedCityId,
                    isExpanded: true,
                    items: p.cities
                        .map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.name),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _selectedCityId = v);
                        p.selectCity(v);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.location_city, size: 18), text: 'Şehirler'),
            Tab(icon: Icon(Icons.alt_route, size: 18), text: 'Hatlar'),
            Tab(icon: Icon(Icons.location_on, size: 18), text: 'Duraklar'),
            Tab(icon: Icon(Icons.person, size: 18), text: 'Şoförler'),
            Tab(icon: Icon(Icons.settings, size: 18), text: 'Ayarlar'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _CitiesTab(),
              _LinesTab(cityId: _selectedCityId),
              _StopsTab(cityId: _selectedCityId),
              _DriversTab(cityId: _selectedCityId),
              _SettingsTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// ŞEHİRLER TAB
// ─────────────────────────────────────────────
class _CitiesTab extends StatefulWidget {
  @override
  State<_CitiesTab> createState() => _CitiesTabState();
}

class _CitiesTabState extends State<_CitiesTab> {
  final SehiriciCityService _service = SehiriciCityService();
  List<SehiriciCity> _cities = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _cities = await _service.getAllCitiesAdmin();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else
          ListView.builder(
            itemCount: _cities.length,
            itemBuilder: (ctx, i) {
              final c = _cities[i];
              return ListTile(
                leading: const Icon(Icons.location_city),
                title: Text(c.name),
                subtitle: Text(
                  '(${c.centerLat.toStringAsFixed(4)}, ${c.centerLng.toStringAsFixed(4)}) · zoom ${c.zoomLevel}',
                ),
                trailing: Switch(
                  value: c.isActive,
                  onChanged: (v) async {
                    await _service.upsertCity(SehiriciCity(
                      id: c.id,
                      name: c.name,
                      slug: c.slug,
                      centerLat: c.centerLat,
                      centerLng: c.centerLng,
                      zoomLevel: c.zoomLevel,
                      isActive: v,
                    ));
                    _load();
                  },
                ),
                onLongPress: () => _showCityDialog(city: c),
              );
            },
          ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.extended(
            heroTag: 'sehirici_add_city',
            onPressed: () => _showCityDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Yeni Şehir'),
          ),
        ),
      ],
    );
  }

  void _showCityDialog({SehiriciCity? city}) {
    final nameCtrl = TextEditingController(text: city?.name ?? '');
    final slugCtrl = TextEditingController(text: city?.slug ?? '');
    final latCtrl =
        TextEditingController(text: city?.centerLat.toString() ?? '');
    final lngCtrl =
        TextEditingController(text: city?.centerLng.toString() ?? '');
    final zoomCtrl = TextEditingController(text: '${city?.zoomLevel ?? 13}');
    bool isActive = city?.isActive ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        return AlertDialog(
          title: Text(city == null ? 'Yeni Şehir' : 'Şehir Düzenle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Ad'),
                ),
                TextField(
                  controller: slugCtrl,
                  decoration: const InputDecoration(labelText: 'Slug'),
                ),
                TextField(
                  controller: latCtrl,
                  decoration: const InputDecoration(labelText: 'Merkez Lat'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: lngCtrl,
                  decoration: const InputDecoration(labelText: 'Merkez Lng'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: zoomCtrl,
                  decoration: const InputDecoration(labelText: 'Zoom'),
                  keyboardType: TextInputType.number,
                ),
                SwitchListTile(
                  title: const Text('Aktif'),
                  value: isActive,
                  onChanged: (v) => setSt(() => isActive = v),
                ),
              ],
            ),
          ),
          actions: [
            if (city != null)
              TextButton.icon(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: ctx,
                    builder: (c) => AlertDialog(
                      title: const Text('Şehiri Sil'),
                      content: Text(
                        '${city.name} şehrini ve tüm verilerini silmek istediğinize emin misiniz?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('İptal'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Sil'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    final ok = await _service.deleteCity(city.id);
                    if (ok) {
                      Navigator.pop(ctx);
                      _load();
                      context.read<SehiriciProvider>().invalidateAllCaches();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Şehir silindi'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } else if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Şehir silinemedi'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.delete, color: Colors.red),
                label: const Text('Sil', style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () async {
                final ok = await _service.upsertCity(SehiriciCity(
                  id: city?.id ?? const Uuid().v4(),
                  name: nameCtrl.text.trim(),
                  slug: slugCtrl.text.trim(),
                  centerLat: double.tryParse(latCtrl.text) ?? 0,
                  centerLng: double.tryParse(lngCtrl.text) ?? 0,
                  zoomLevel: int.tryParse(zoomCtrl.text) ?? 13,
                  isActive: isActive,
                ));
                if (ok) {
                  Navigator.pop(ctx);
                  _load();
                  context.read<SehiriciProvider>().invalidateAllCaches();
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────
// HATLAR TAB
// ─────────────────────────────────────────────
class _LinesTab extends StatefulWidget {
  final String? cityId;
  const _LinesTab({this.cityId});
  @override
  State<_LinesTab> createState() => _LinesTabState();
}

class _LinesTabState extends State<_LinesTab> {
  final SehiriciLineService _service = SehiriciLineService();
  List<SehiriciLine> _lines = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.cityId == null) return;
    setState(() => _loading = true);
    _lines = await _service.getAllLinesAdmin(widget.cityId!);
    if (mounted) setState(() => _loading = false);
  }

  @override
  void didUpdateWidget(covariant _LinesTab old) {
    super.didUpdateWidget(old);
    if (old.cityId != widget.cityId) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_lines.isEmpty)
          const Center(child: Text('Bu şehir için hat yok'))
        else
          ListView.builder(
            itemCount: _lines.length,
            itemBuilder: (ctx, i) {
              final l = _lines[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: l.color,
                  child: Text(l.code,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
                ),
                title: Text(l.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          l.vehicleType.icon,
                          color: l.vehicleType.iconColor,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${l.vehicleType.label} · ${l.estimatedMinutes ?? '?'} dk · ₺${l.fareAmount.toStringAsFixed(2)}',
                            style:
                                TextStyle(color: Colors.grey.shade700, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${l.stops.length} durak',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_road),
                      tooltip: 'Durakları Düzenle',
                      onPressed: () => _openStopsEditor(l),
                    ),
                    _routeMenu(l),
                    Switch(
                      value: l.isActive,
                      onChanged: (v) async {
                        await _service.updateLineActive(l.id, v);
                        _load();
                      },
                    ),
                  ],
                ),
                onLongPress: () => _showLineDialog(line: l),
              );
            },
          ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.extended(
            heroTag: 'sehirici_add_line',
            onPressed: widget.cityId == null
                ? null
                : () => _showLineDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Yeni Hat'),
          ),
        ),
      ],
    );
  }

  /// Hat satırındaki rota kısayolları. Çizim dialogunu açmadan rotayı
  /// temizlemeyi/silmeyi sağlar; rota yoksa yalnızca "Çiz" etkin kalır.
  Widget _routeMenu(SehiriciLine line) {
    final hasRoute =
        line.roadPolyline != null && line.roadPolyline!.length >= 2;
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.route,
        color: hasRoute ? Theme.of(context).colorScheme.primary : Colors.grey,
      ),
      tooltip: hasRoute
          ? 'Rota (${line.roadPolyline!.length} nokta)'
          : 'Rota yok',
      onSelected: (value) => switch (value) {
        'draw' => _openRouteDraw(line),
        'sanitize' => _sanitizeLineRoute(line),
        'clear' => _clearLineRoute(line),
        _ => null,
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'draw',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.brush),
            title: Text('Rotayı Çiz'),
          ),
        ),
        PopupMenuItem(
          value: 'sanitize',
          enabled: hasRoute,
          child: const ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.cleaning_services_outlined),
            title: Text('Rotayı Ayıkla'),
            subtitle: Text('Gürültülü noktaları temizle'),
          ),
        ),
        PopupMenuItem(
          value: 'clear',
          enabled: hasRoute,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline,
                color: hasRoute ? Colors.red : Colors.grey),
            title: Text(
              'Rotayı Sil',
              style: TextStyle(color: hasRoute ? Colors.red : Colors.grey),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openRouteDraw(SehiriciLine line) async {
    await showDialog<void>(
      context: context,
      builder: (_) => SehiriciLineRouteDrawDialog(line: line),
    );
    if (mounted) _load();
  }

  Future<void> _sanitizeLineRoute(SehiriciLine line) async {
    final raw = line.roadPolyline;
    if (raw == null || raw.length < 2) return;
    final cleaned = sanitizeRoutePolyline(
      raw.map((p) => LatLng(p[0], p[1])).toList(),
    );

    if (!mounted) return;
    if (cleaned.length < 2) {
      _snack('Rota temizlenince 2 noktanın altına düştü; dokunulmadı.',
          Colors.orange);
      return;
    }
    if (cleaned.length == raw.length) {
      _snack('${line.code} rotası zaten temiz.', Colors.green);
      return;
    }

    final ok = await _service.cacheRoutePolyline(
      lineId: line.id,
      lineStopsInOrder: line.stops,
      points:
          cleaned.map((p) => <double>[p.latitude, p.longitude]).toList(),
      source: 'admin_sanitized',
    );
    if (!mounted) return;
    _snack(
      ok
          ? '${line.code}: ${raw.length} → ${cleaned.length} nokta '
              '(${raw.length - cleaned.length} gürültü atıldı).'
          : 'Rota kaydedilemedi.',
      ok ? Colors.green : Colors.red,
    );
    if (ok) _load();
  }

  Future<void> _clearLineRoute(SehiriciLine line) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${line.code} rotası silinsin mi?'),
        content: Text(
          '${line.roadPolyline?.length ?? 0} noktalı rota kalıcı olarak '
          'silinecek. Hat rotasız kalır ve haritada çizgi görünmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await _service.clearRoutePolyline(line.id);
    if (!mounted) return;
    _snack(
      ok ? '${line.code} rotası silindi.' : 'Rota silinemedi.',
      ok ? Colors.green : Colors.red,
    );
    if (ok) _load();
  }

  void _snack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  Future<void> _openStopsEditor(SehiriciLine line) async {
    if (widget.cityId == null) return;
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => SehiriciLineStopsEditorDialog(
        line: line,
        cityId: widget.cityId!,
      ),
    );
    if (changed == true) {
      _load();
      if (mounted) {
        context.read<SehiriciProvider>().invalidateAllCaches();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Duraklar güncellendi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _showLineDialog({SehiriciLine? line}) {
    final codeCtrl = TextEditingController(text: line?.code ?? '');
    final nameCtrl = TextEditingController(text: line?.name ?? '');
    final colorCtrl =
        TextEditingController(text: line?.colorHex ?? '#1976D2');
    final estCtrl =
        TextEditingController(text: '${line?.estimatedMinutes ?? ''}');
    final fareCtrl =
        TextEditingController(text: '${line?.fareAmount ?? 0}');
    SehiriciVehicleType vehicleType = line?.vehicleType ?? SehiriciVehicleType.bus;
    bool isActive = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        return AlertDialog(
          title: Text(line == null ? 'Yeni Hat' : 'Hat Düzenle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(labelText: 'Kod (1A)'),
                ),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Ad'),
                ),
                TextField(
                  controller: colorCtrl,
                  decoration: const InputDecoration(labelText: 'Renk (#1976D2)'),
                ),
                DropdownButtonFormField<SehiriciVehicleType>(
                  value: vehicleType,
                  decoration:
                      const InputDecoration(labelText: 'Araç Tipi'),
                  items: SehiriciVehicleType.values
                      .map((v) => DropdownMenuItem(
                          value: v, child: Text(v.label)))
                      .toList(),
                  onChanged: (v) =>
                      setSt(() => vehicleType = v ?? vehicleType),
                ),
                TextField(
                  controller: estCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Tahmini Dakika'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: fareCtrl,
                  decoration: const InputDecoration(labelText: 'Ücret (TL)'),
                  keyboardType: TextInputType.number,
                ),
                SwitchListTile(
                  title: const Text('Aktif'),
                  value: isActive,
                  onChanged: (v) => setSt(() => isActive = v),
                ),
              ],
            ),
          ),
          actions: [
            if (line != null) ...[
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openStopsEditor(line);
                },
                icon: const Icon(Icons.edit_road, color: Colors.teal),
                label: const Text('Duraklar', style: TextStyle(color: Colors.teal)),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  showDialog(
                    context: context,
                    builder: (_) => SehiriciRouteViewerDialog(line: line),
                  );
                },
                icon: const Icon(Icons.map, color: Colors.blue),
                label: const Text('Rotalar', style: TextStyle(color: Colors.blue)),
              ),
              TextButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final saved = await showDialog<bool>(
                    context: context,
                    builder: (_) => SehiriciLineRouteDrawDialog(line: line),
                  );
                  if (saved == true && mounted) {
                    _load();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Yol rotası güncellendi'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.draw, color: Colors.deepPurple),
                label: const Text('Rota Çiz',
                    style: TextStyle(color: Colors.deepPurple)),
              ),
              TextButton.icon(
                onPressed: () async {
                  final ok = await _service.deleteLine(line.id);
                  if (ok) {
                    Navigator.pop(ctx);
                    _load();
                    context.read<SehiriciProvider>().invalidateAllCaches();
                  }
                },
                icon: const Icon(Icons.delete, color: Colors.red),
                label: const Text('Sil', style: TextStyle(color: Colors.red)),
              ),
            ],
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () async {
                final ok = await _service.upsertLine(
                  id: line?.id,
                  cityId: widget.cityId!,
                  code: codeCtrl.text.trim(),
                  name: nameCtrl.text.trim(),
                  colorHex: colorCtrl.text.trim(),
                  vehicleType: vehicleType,
                  estimatedMinutes: int.tryParse(estCtrl.text),
                  fareAmount: double.tryParse(fareCtrl.text) ?? 0,
                  isActive: isActive,
                );
                if (ok) {
                  Navigator.pop(ctx);
                  _load();
                  context.read<SehiriciProvider>().invalidateAllCaches();
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────
// DURAKLAR TAB
// ─────────────────────────────────────────────
class _StopsTab extends StatefulWidget {
  final String? cityId;
  const _StopsTab({this.cityId});
  @override
  State<_StopsTab> createState() => _StopsTabState();
}

class _StopsTabState extends State<_StopsTab> {
  final SehiriciLineService _service = SehiriciLineService();
  List<SehiriciStop> _stops = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.cityId == null) return;
    setState(() => _loading = true);
    _stops = await _service.getStopsByCity(widget.cityId!);
    if (mounted) setState(() => _loading = false);
  }

  @override
  void didUpdateWidget(covariant _StopsTab old) {
    super.didUpdateWidget(old);
    if (old.cityId != widget.cityId) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_stops.isEmpty)
          const Center(child: Text('Bu şehir için durak yok'))
        else
          ListView.builder(
            itemCount: _stops.length,
            itemBuilder: (ctx, i) {
              final s = _stops[i];
              final isLast = i == _stops.length - 1;
              return Column(
                children: [
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(s.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '(${s.lat.toStringAsFixed(4)}, ${s.lng.toStringAsFixed(4)})',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                        if (s.code != null)
                          Text(
                            'Kod: ${s.code}',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                        if (s.address != null)
                          Text(
                            'Adres: ${s.address}',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                      ],
                    ),
                    trailing: Icon(Icons.location_on_sharp,
                        color: Theme.of(context).colorScheme.primary),
                    onLongPress: () => _showStopDialog(stop: s),
                  ),
                  if (!isLast)
                    Padding(
                      padding: const EdgeInsets.only(left: 40),
                      child: Container(
                        height: 20,
                        width: 2,
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                      ),
                    ),
                ],
              );
            },
          ),
        Positioned(
          bottom: 16,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.extended(
                heroTag: 'sehirici_add_stops_map',
                backgroundColor: Theme.of(context).colorScheme.secondary,
                foregroundColor: Theme.of(context).colorScheme.onSecondary,
                onPressed:
                    widget.cityId == null ? null : _showMultiStopPicker,
                icon: const Icon(Icons.add_location_alt),
                label: const Text('Haritadan Çoklu'),
              ),
              const SizedBox(height: 10),
              FloatingActionButton.extended(
                heroTag: 'sehirici_add_stop',
                onPressed: widget.cityId == null
                    ? null
                    : () => _showStopDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Yeni Durak'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Haritaya sırayla dokunarak birden çok durağı tek seferde oluşturur.
  /// Durakları tek tek form doldurarak girmek yerine güzergâh üzerinde
  /// dizmek için — hat kurulumundaki en yavaş adım buydu.
  Future<void> _showMultiStopPicker() async {
    final cityId = widget.cityId;
    if (cityId == null) return;

    SehiriciCity? city;
    for (final c in context.read<SehiriciProvider>().cities) {
      if (c.id == cityId) {
        city = c;
        break;
      }
    }
    // Şehir merkezi yoksa mevcut ilk durağa, o da yoksa güvenli varsayılana.
    final startLat = city?.centerLat ??
        (_stops.isNotEmpty ? _stops.first.lat : 41.0082);
    final startLng = city?.centerLng ??
        (_stops.isNotEmpty ? _stops.first.lng : 28.9784);

    final picked = await SehiriciLocationPickerDialog.pickMultiple(
      context,
      initialLat: startLat,
      initialLng: startLng,
      initialZoom: (city?.zoomLevel ?? 14).toDouble(),
      existingStops: _stops,
    );
    if (!mounted || picked == null || picked.isEmpty) return;

    setState(() => _loading = true);
    var saved = 0;
    final failed = <String>[];
    for (final stop in picked) {
      final ok = await _service.upsertStop(
        cityId: cityId,
        name: stop.name.trim(),
        lat: stop.position.latitude,
        lng: stop.position.longitude,
      );
      if (ok) {
        saved++;
      } else {
        failed.add(stop.name.trim());
      }
    }

    await _load();
    if (!mounted) return;
    context.read<SehiriciProvider>().invalidateAllCaches();

    // Kısmi başarı sessiz kalmasın: hangi durakların yazılamadığı söylenmeli,
    // yoksa admin listede eksik olanı fark etmeden hattı kurmaya geçer.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed.isEmpty
              ? '$saved durak eklendi'
              : '$saved durak eklendi, ${failed.length} tanesi '
                  'eklenemedi: ${failed.join(", ")}',
        ),
        backgroundColor: failed.isEmpty ? Colors.green : Colors.orange,
        duration: Duration(seconds: failed.isEmpty ? 3 : 6),
      ),
    );
  }

  void _showStopDialog({SehiriciStop? stop}) {
    final nameCtrl = TextEditingController(text: stop?.name ?? '');
    final codeCtrl = TextEditingController(text: stop?.code ?? '');
    final latCtrl = TextEditingController(text: stop?.lat.toString() ?? '');
    final lngCtrl = TextEditingController(text: stop?.lng.toString() ?? '');
    final addrCtrl = TextEditingController(text: stop?.address ?? '');
    bool locating = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(stop == null ? 'Yeni Durak' : 'Durak Düzenle'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Ad'),
                  ),
                  TextField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(labelText: 'Kod (ops.)'),
                  ),
                  TextField(
                    controller: latCtrl,
                    decoration: const InputDecoration(labelText: 'Lat'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true, signed: true),
                  ),
                  TextField(
                    controller: lngCtrl,
                    decoration: const InputDecoration(labelText: 'Lng'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true, signed: true),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: locating
                          ? null
                          : () async {
                              setDialogState(() => locating = true);
                              try {
                                final pos = await _getCurrentLocation(ctx);
                                if (pos != null) {
                                  latCtrl.text = pos.latitude.toString();
                                  lngCtrl.text = pos.longitude.toString();
                                }
                              } finally {
                                setDialogState(() => locating = false);
                              }
                            },
                      icon: locating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location),
                      label: const Text('Konumumu Al'),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        SehiriciCity? city;
                        for (final c in ctx.read<SehiriciProvider>().cities) {
                          if (c.id == widget.cityId) {
                            city = c;
                            break;
                          }
                        }
                        final startLat =
                            double.tryParse(latCtrl.text) ?? city?.centerLat ?? 41.0082;
                        final startLng =
                            double.tryParse(lngCtrl.text) ?? city?.centerLng ?? 28.9784;
                        final picked =
                            await SehiriciLocationPickerDialog.pickSingle(
                          ctx,
                          initialLat: startLat,
                          initialLng: startLng,
                          initialZoom: (city?.zoomLevel ?? 14).toDouble(),
                          existingStops: _stops,
                        );
                        if (picked != null) {
                          setDialogState(() {
                            latCtrl.text = picked.latitude.toString();
                            lngCtrl.text = picked.longitude.toString();
                          });
                        }
                      },
                      icon: const Icon(Icons.map),
                      label: const Text('Haritadan Seç'),
                    ),
                  ),
                  TextField(
                    controller: addrCtrl,
                    decoration: const InputDecoration(labelText: 'Adres'),
                  ),
                ],
              ),
            ),
            actions: [
              if (stop != null)
                TextButton.icon(
                  onPressed: () async {
                    final ok = await _service.deleteStop(stop.id);
                    if (ok) {
                      Navigator.pop(ctx);
                      _load();
                      context.read<SehiriciProvider>().invalidateAllCaches();
                    }
                  },
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text('Sil', style: TextStyle(color: Colors.red)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('İptal'),
              ),
              FilledButton(
                onPressed: () async {
                  final lat = double.tryParse(
                      latCtrl.text.trim().replaceAll(',', '.'));
                  final lng = double.tryParse(
                      lngCtrl.text.trim().replaceAll(',', '.'));
                  if (lat == null || lng == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Geçerli bir Lat/Lng değeri girin.'),
                      ),
                    );
                    return;
                  }
                  final ok = await _service.upsertStop(
                    id: stop?.id,
                    cityId: widget.cityId!,
                    name: nameCtrl.text.trim(),
                    code: codeCtrl.text.trim().isEmpty
                        ? null
                        : codeCtrl.text.trim(),
                    lat: lat,
                    lng: lng,
                    address: addrCtrl.text.trim().isEmpty
                        ? null
                        : addrCtrl.text.trim(),
                  );
                  if (ok) {
                    Navigator.pop(ctx);
                    _load();
                    context.read<SehiriciProvider>().invalidateAllCaches();
                  }
                },
                child: const Text('Kaydet'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<Position?> _getCurrentLocation(BuildContext dialogCtx) async {
    try {
      var serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Konum servisleri kapalı.')),
          );
        }
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Konum izni reddedildi.')),
            );
          }
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Konum izni kalıcı olarak reddedildi. Ayarlardan izin verin.'),
            ),
          );
        }
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Konum alınamadı: $e')),
        );
      }
      return null;
    }
  }
}

// ─────────────────────────────────────────────
// ŞOFÖRLER TAB
// ─────────────────────────────────────────────
class _DriversTab extends StatefulWidget {
  final String? cityId;
  const _DriversTab({this.cityId});
  @override
  State<_DriversTab> createState() => _DriversTabState();
}

class _DriversTabState extends State<_DriversTab> {
  final SehiriciDriverService _service = SehiriciDriverService();
  List<Map<String, dynamic>> _drivers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _drivers = await _service.getAllDriversAdmin();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_drivers.isEmpty)
          const Center(child: Text('Henüz şoför kaydı yok'))
        else
          ListView.builder(
            itemCount: _drivers.length,
            itemBuilder: (ctx, i) {
              final d = _drivers[i];
              final profile = d['profiles'] as Map?;
              final assignedLineId = d['assigned_line_id'] as String?;

              return ListTile(
                leading: CircleAvatar(
                  child: Text(
                    ((profile?['full_name'] as String?) ?? '?').isEmpty
                        ? '?'
                        : ((profile?['full_name'] as String?) ?? '?')[0],
                  ),
                ),
                title: Text(profile?['full_name'] ?? 'İsimsiz'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '@${profile?['username'] ?? ''}',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    ),
                    Text(
                      'Ehliyet: ${d['license_number'] ?? '-'}',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    ),
                    if (assignedLineId != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Hat atandı',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Hat atanmadı',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                trailing: PopupMenuButton(
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      child: const Text('Hat Ata'),
                      onTap: () {
                        Future.delayed(Duration.zero, () {
                          _showAssignLineDialog(d);
                        });
                      },
                    ),
                    PopupMenuItem(
                      child: const Text('Sil'),
                      onTap: () {
                        Future.delayed(Duration.zero, () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('Şoförü Sil'),
                              content: const Text(
                                  'Bu şoför kaydını silmek istediğinize emin misiniz?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c, false),
                                  child: const Text('İptal'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(c, true),
                                  child: const Text('Sil'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await _service.deleteDriver(d['id'] as String);
                            _load();
                          }
                        });
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.extended(
            heroTag: 'sehirici_add_driver',
            onPressed: _showAddDriverDialog,
            icon: const Icon(Icons.person_add),
            label: const Text('Şoför Ekle'),
          ),
        ),
      ],
    );
  }

  Future<void> _showAddDriverDialog() async {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> results = [];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        return AlertDialog(
          title: const Text('Şoför Ekle'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: searchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Kullanıcı ara (en az 2 karakter)',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) async {
                    if (v.length >= 2) {
                      results = await _service.searchProfiles(v);
                      setSt(() {});
                    } else {
                      results = [];
                      setSt(() {});
                    }
                  },
                ),
                const SizedBox(height: 8),
                if (results.isNotEmpty)
                  SizedBox(
                    height: 200,
                    child: ListView(
                      children: results.map((r) {
                        return ListTile(
                          leading: const Icon(Icons.person),
                          title: Text(r['full_name'] ?? r['username']),
                          subtitle: Text('@${r['username']}'),
                          trailing: FilledButton(
                            onPressed: () async {
                              final driverId = await _service.createDriver(
                                profileId: r['id'] as String,
                              );
                              if (driverId != null) {
                                Navigator.pop(ctx);
                                _load();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Şoför eklendi'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            },
                            child: const Text('Ekle'),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Kapat'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _showAssignLineDialog(Map<String, dynamic> driver) async {
    final lineService = SehiriciLineService();
    final driverService = SehiriciDriverService();
    List<SehiriciLine> lines = [];
    String? selectedLineId = driver['assigned_line_id'] as String?;
    bool isLoading = true;

    if (widget.cityId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Önce üstteki şehir seçiciden bir şehir seçin'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Seçili şehrin hatlarını yükle
    lines = await lineService.getLinesWithStops(widget.cityId!, forceRefresh: true);
    isLoading = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        return AlertDialog(
          title: const Text('Şöföre Hat Ata'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Şoför: ${(driver['profiles'] as Map?)?['full_name'] ?? 'İsimsiz'}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              if (isLoading)
                const CircularProgressIndicator()
              else if (lines.isEmpty)
                const Text('Hiçbir hat bulunamadı')
              else
                DropdownButton<String?>(
                  value: selectedLineId,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Hat Seçmeyin'),
                    ),
                    ...lines.map((line) {
                      // Başka şöför bu hata atanmış mı kontrol et
                      final otherDriverAssigned = _drivers.any((d) =>
                          d['id'] != driver['id'] &&
                          d['assigned_line_id'] == line.id);
                      return DropdownMenuItem(
                        value: line.id,
                        enabled: !otherDriverAssigned,
                        child: Text(
                          '${line.code} - ${line.name}${otherDriverAssigned ? ' (Atanmış)' : ''}',
                          style: TextStyle(
                            color: otherDriverAssigned ? Colors.grey : null,
                          ),
                        ),
                      );
                    }),
                  ],
                  onChanged: (newValue) {
                    setSt(() => selectedLineId = newValue);
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () async {
                // Seçilen hat başka şöföre atanmış mı final kontrol
                if (selectedLineId != null &&
                    _drivers.any((d) =>
                        d['id'] != driver['id'] &&
                        d['assigned_line_id'] == selectedLineId)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Bu hat zaten başka bir şöföre atanmış'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final ok = await driverService.assignLine(
                  driver['id'] as String,
                  selectedLineId,
                );
                if (ok) {
                  Navigator.pop(ctx);
                  _load();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Hat atandı'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Hat ataması başarısız'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────
// AYARLAR TAB
// ─────────────────────────────────────────────
class _SettingsTab extends StatefulWidget {
  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  final SehiriciCityService _service = SehiriciCityService();
  final SehiriciLineService _lineService = SehiriciLineService();
  SehiriciSettings? _settings;
  bool _loading = true;
  // Toplu rota bakımı sürerken kontrolleri kilitler (çift tetikleme koruması).
  bool _routeBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _settings = await _service.getSettings(forceRefresh: true);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _settings == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final s = _settings!;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SwitchListTile(
          title: const Text('Modül Aktif'),
          subtitle: const Text(
              'Tüm şehirlerde şehiriçi servis özelliğini aç/kapat'),
          value: s.moduleEnabled,
          onChanged: (v) => _updateSetting(
              'sehirici_module_enabled', v.toString(),
              invalidateCaches: true),
        ),
        SwitchListTile(
          title: const Text('Kullanıcı Favorileri'),
          subtitle: const Text('Kullanıcılar favori durak ekleyebilsin mi?'),
          value: s.allowUserFavorites,
          onChanged: (v) => _updateSetting(
              'sehirici_allow_user_favorites', v.toString(),
              invalidateCaches: true),
        ),
        const Divider(),
        ListTile(
          title: const Text('Konum Güncelleme Aralığı'),
          subtitle: Text('${s.locationUpdateIntervalSec} saniye'),
          trailing: const Icon(Icons.edit),
          onTap: () async {
            final v = await _askNumber(s.locationUpdateIntervalSec);
            if (v != null) {
              await _updateSetting(
                  'sehirici_location_update_interval_sec', v.toString());
            }
          },
        ),
        ListTile(
          title: const Text('ETA Yenileme'),
          subtitle: Text('${s.etaRefreshSeconds} saniye'),
          trailing: const Icon(Icons.edit),
          onTap: () async {
            final v = await _askNumber(s.etaRefreshSeconds);
            if (v != null) {
              await _updateSetting(
                  'sehirici_eta_refresh_seconds', v.toString());
            }
          },
        ),
        ListTile(
          title: const Text('Konum Geçmişi Saklama'),
          subtitle: Text('${s.maxHistoryMinutes} dakika'),
          trailing: const Icon(Icons.edit),
          onTap: () async {
            final v = await _askNumber(s.maxHistoryMinutes);
            if (v != null) {
              await _updateSetting(
                  'sehirici_max_history_minutes', v.toString());
            }
          },
        ),
        const Divider(),
        _buildRouteMaintenanceSection(s),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // Hat rotası bakımı
  // ─────────────────────────────────────────────

  /// Hat rotalarının kaynağını ve kalitesini yöneten bölüm.
  ///
  /// Kirli hat rotalarının kök nedeni, şoförün ham GPS izinden otomatik rota
  /// üretilmesidir: duruş bulutları ve hatalı fixler rotaya yazılıp haritada
  /// "her tarafa çizgi" görüntüsü oluşturur. Buradaki üç kontrol sırasıyla
  /// kaynağı keser, mevcut kiri ayıklar ve gerekirse hepsini sıfırlar.
  Widget _buildRouteMaintenanceSection(SehiriciSettings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'HAT ROTASI BAKIMI',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.auto_fix_high),
          title: const Text('Otomatik Rota Yazımı'),
          subtitle: const Text(
            'Şoförün sürüşünden hat rotası üretilsin mi? Kapalıyken rotalar '
            'yalnız admin tarafından elle çizilir — kirli rota oluşmaz.',
          ),
          value: s.autoRouteEnabled,
          onChanged: _routeBusy
              ? null
              : (v) => _updateSetting(
                    'sehirici_auto_route_enabled', v.toString(),
                    invalidateCaches: true,
                  ),
        ),
        ListTile(
          leading: _routeBusy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cleaning_services_outlined),
          title: const Text('Bozuk Rotaları Ayıkla'),
          subtitle: const Text(
            'Kayıtlı rotaları siler değil TEMİZLER: üst üste binen noktaları '
            've rotadan fırlayan hatalı fixleri atar.',
          ),
          enabled: !_routeBusy,
          onTap: _routeBusy ? null : _sanitizeRoutes,
        ),
        ListTile(
          leading: Icon(
            Icons.delete_sweep_outlined,
            color: _routeBusy ? Colors.grey : Colors.red,
          ),
          title: Text(
            'Tüm Rotaları Sil',
            style: TextStyle(color: _routeBusy ? Colors.grey : Colors.red),
          ),
          subtitle: const Text(
            'Bütün hatların kayıtlı rotasını kaldırır. Hatlar rotasız kalır, '
            'haritada çizgi görünmez; yeniden çizilmesi gerekir.',
          ),
          enabled: !_routeBusy,
          onTap: _routeBusy ? null : _clearAllRoutes,
        ),
      ],
    );
  }

  Future<void> _sanitizeRoutes() async {
    setState(() => _routeBusy = true);
    try {
      final report = await _lineService.sanitizeAllRoutePolylines();
      if (!mounted) return;
      if (report.isEmpty) {
        _showRouteResult('Kayıtlı rotası olan hat yok.', Colors.blueGrey);
        return;
      }
      final changed = report.where((r) => r.saved).toList();
      if (changed.isEmpty) {
        _showRouteResult(
          '${report.length} hat kontrol edildi, hepsi zaten temiz.',
          Colors.green,
        );
        return;
      }
      final removed =
          changed.fold<int>(0, (sum, r) => sum + (r.before - r.after));
      _showRouteResult(
        '${changed.length}/${report.length} hat temizlendi, '
        '$removed gürültülü nokta atıldı.',
        Colors.green,
        detail: changed
            .map((r) => '${r.code}: ${r.before} → ${r.after} nokta')
            .join('\n'),
      );
    } catch (e) {
      if (mounted) _showRouteResult('Ayıklama başarısız: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _routeBusy = false);
    }
  }

  Future<void> _clearAllRoutes() async {
    final lines = await _lineService.getLinesWithRoute();
    if (!mounted) return;
    if (lines.isEmpty) {
      _showRouteResult('Kayıtlı rotası olan hat yok.', Colors.blueGrey);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tüm rotalar silinsin mi?'),
        content: Text(
          '${lines.length} hattın kayıtlı rotası kalıcı olarak silinecek:\n\n'
          '${lines.map((l) => '• ${l.code} (${l.points.length} nokta)').join('\n')}\n\n'
          'Bu işlem geri alınamaz. Hatlar rotasız kalır ve haritada çizgi '
          'görünmez; her hattın rotası yeniden çizilmelidir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hepsini Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _routeBusy = true);
    try {
      final result = await _lineService.clearAllRoutePolylines();
      if (!mounted) return;
      _showRouteResult(
        result.failed == 0
            ? '${result.cleared} hattın rotası silindi.'
            : '${result.cleared} hat silindi, ${result.failed} hat başarısız.',
        result.failed == 0 ? Colors.green : Colors.orange,
      );
    } catch (e) {
      if (mounted) _showRouteResult('Silme başarısız: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _routeBusy = false);
    }
  }

  void _showRouteResult(String message, Color color, {String? detail}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 5),
        action: detail == null
            ? null
            : SnackBarAction(
                label: 'Detay',
                textColor: Colors.white,
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Rota temizleme raporu'),
                    content: SingleChildScrollView(child: Text(detail)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Kapat'),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _updateSetting(String key, String value,
      {bool invalidateCaches = false}) async {
    final ok = await _service.updateSetting(key, value);
    await _load();
    if (!mounted) return;
    if (ok) {
      if (invalidateCaches) {
        context.read<SehiriciProvider>().invalidateAllCaches();
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ayar güncellenemedi'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<int?> _askNumber(int current) async {
    final ctrl = TextEditingController(text: current.toString());
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Değer Girin'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(ctrl.text)),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }
}
