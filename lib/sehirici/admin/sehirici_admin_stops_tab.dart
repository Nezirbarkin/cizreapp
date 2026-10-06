import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/map_vehicle_painters.dart';
import '../../features/admin/widgets/admin_ui.dart';
import '../models/sehirici_models.dart';
import '../providers/sehirici_provider.dart';
import '../services/sehirici_errors.dart';
import '../widgets/sehirici_common_widgets.dart';
import 'sehirici_admin_controller.dart';
import 'sehirici_admin_kit.dart';
import 'sehirici_location_picker_dialog.dart';
import 'sehirici_stop_editor_sheet.dart';

enum _StopFilter { all, linked, unlinked, inactive }

/// Admin > Şehiriçi > Duraklar: arama, filtre, hangi hatlarda kullanıldığı,
/// tek tek veya haritadan çoklu ekleme, seçip toplu silme (Görev 3.10).
class SehiriciAdminStopsTab extends StatefulWidget {
  final SehiriciAdminController controller;
  const SehiriciAdminStopsTab({super.key, required this.controller});

  @override
  State<SehiriciAdminStopsTab> createState() => _SehiriciAdminStopsTabState();
}

class _SehiriciAdminStopsTabState extends State<SehiriciAdminStopsTab> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  _StopFilter _filter = _StopFilter.all;
  bool _bulkSaving = false;

  // Toplu seçim (Görev 3.10): uzun basış ya da "Seç" ile açılır.
  bool _selecting = false;
  final Set<String> _selected = <String>{};
  bool _deleting = false;

  SehiriciAdminController get c => widget.controller;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<SehiriciStop> get _visible {
    final usage = c.linesByStop;
    final q = sehiriciFold(_query.trim());
    final list = c.stops.where((s) {
      final linked = (usage[s.id] ?? const []).isNotEmpty;
      switch (_filter) {
        case _StopFilter.linked:
          if (!linked) return false;
        case _StopFilter.unlinked:
          if (linked) return false;
        case _StopFilter.inactive:
          if (s.isActive) return false;
        case _StopFilter.all:
          break;
      }
      if (q.isEmpty) return true;
      return sehiriciFold(s.name).contains(q) ||
          sehiriciFold(s.code ?? '').contains(q) ||
          sehiriciFold(s.address ?? '').contains(q);
    }).toList()
      ..sort((a, b) => sehiriciFold(a.name).compareTo(sehiriciFold(b.name)));
    return list;
  }

  void _refreshUserSide() {
    try {
      context.read<SehiriciProvider>().invalidateAllCaches();
    } catch (_) {}
  }

  Future<void> _edit([SehiriciStop? stop]) async {
    final changed = await showSehiriciStopEditor(context, controller: c, stop: stop);
    if (changed && mounted) {
      sehiriciSnack(context, stop == null ? 'Durak eklendi.' : 'Durak güncellendi.');
    }
  }

  /// Haritaya sırayla dokunarak birden çok durak oluşturur (bir hattın
  /// duraklarını tek tek form doldurmadan dizmek için).
  Future<void> _addFromMap() async {
    final city = c.city;
    final cityId = c.cityId;
    if (city == null || cityId == null) return;
    final picked = await SehiriciLocationPickerDialog.pickMultiple(
      context,
      initialLat: city.centerLat,
      initialLng: city.centerLng,
      initialZoom: city.zoomLevel.toDouble(),
      existingStops: c.stops,
    );
    if (!mounted || picked == null || picked.isEmpty) return;

    setState(() => _bulkSaving = true);
    var saved = 0;
    final failed = <String>[];
    for (final stop in picked) {
      try {
        await c.lineService.saveStop(
          cityId: cityId,
          name: stop.name.trim(),
          lat: stop.position.latitude,
          lng: stop.position.longitude,
        );
        saved++;
      } catch (e) {
        failed.add('${stop.name.trim()} (${sehiriciErrorMessage(e)})');
      }
    }
    await c.reloadCityData();
    _refreshUserSide();
    if (!mounted) return;
    setState(() => _bulkSaving = false);
    // Kısmi başarı sessiz kalmasın: hangi durakların yazılamadığı söylenir.
    sehiriciSnack(
      context,
      failed.isEmpty
          ? '$saved durak eklendi.'
          : '$saved durak eklendi, ${failed.length} tanesi eklenemedi: ${failed.join(', ')}',
      error: failed.isNotEmpty,
    );
  }

  void _startSelection([String? stopId]) {
    setState(() {
      _selecting = true;
      if (stopId != null) _selected.add(stopId);
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggle(String stopId) {
    setState(() {
      if (!_selected.remove(stopId)) _selected.add(stopId);
    });
  }

  /// Seçilen durakları siler; hatta kullanılanlar için etkilenen hatları söyler.
  Future<void> _deleteSelected() async {
    // Görünmeyen (silinmiş/süzülmüş) seçimleri at.
    final existing = c.stops.map((s) => s.id).toSet();
    final ids = _selected.where(existing.contains).toList();
    if (ids.isEmpty) return;
    final usage = c.linesByStop;
    final affected = <String, SehiriciLine>{};
    for (final id in ids) {
      for (final line in usage[id] ?? const <SehiriciLine>[]) {
        affected[line.id] = line;
      }
    }
    final codes = affected.values.map((l) => l.code.isEmpty ? l.name : l.code).join(', ');
    final ok = await sehiriciConfirm(
      context,
      icon: Icons.delete_sweep_rounded,
      title: '${ids.length} durak silinsin mi?',
      message: affected.isEmpty
          ? 'Seçilen duraklar hiçbir hatta bağlı değil; kalıcı olarak silinir.'
          : 'Seçilen duraklar ${affected.length} hatta kullanılıyor ($codes). Silinince bu '
              'hatların durak listesinden çıkar ve sıraları yeniden düzenlenir; '
              'rotalarını yeniden çizmeniz gerekebilir.',
      confirmLabel: '${ids.length} Durağı Sil',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _deleting = true);
    try {
      final result = await c.lineService.deleteStopsOrThrow(ids);
      await c.reloadCityData();
      _refreshUserSide();
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _selecting = false;
        _selected.clear();
      });
      sehiriciSnack(
        context,
        result.affectedLines.isEmpty
            ? '${result.deleted} durak silindi.'
            : '${result.deleted} durak silindi; ${result.affectedLines.length} hattın durak sırası güncellendi.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      sehiriciSnack(context, sehiriciErrorMessage(e), error: true);
    }
  }

  Widget _selectionBar(List<SehiriciStop> visible) {
    final allVisible = visible.isNotEmpty && visible.every((s) => _selected.contains(s.id));
    return Row(
      children: [
        IconButton(
          tooltip: 'Seçimi kapat',
          onPressed: _deleting ? null : _exitSelection,
          icon: const Icon(Icons.close_rounded),
        ),
        Expanded(
          child: Text(
            '${_selected.length} durak seçili',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ),
        TextButton(
          onPressed: visible.isEmpty || _deleting
              ? null
              : () => setState(() {
                    final ids = visible.map((s) => s.id);
                    if (allVisible) {
                      _selected.removeAll(ids);
                    } else {
                      _selected.addAll(ids);
                    }
                  }),
          child: Text(allVisible ? 'Seçimi kaldır' : 'Tümünü seç'),
        ),
        const SizedBox(width: 4),
        FilledButton.icon(
          onPressed: _selected.isEmpty || _deleting ? null : _deleteSelected,
          icon: _deleting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.delete_outline_rounded, size: 18),
          label: const Text('Sil'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
            minimumSize: const Size(0, 44),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        if (c.city == null && !c.loadingCities) {
          return const AdminEmpty(
            icon: Icons.location_city_rounded,
            title: 'Önce bir şehir ekleyin',
            subtitle: 'Duraklar bir şehre bağlıdır.',
          );
        }
        return SehiriciAsyncBody(
          loading: c.loadingCity && c.stops.isEmpty,
          error: c.cityError,
          onRetry: c.reloadCityData,
          child: _buildContent(context),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context) {
    final visible = _visible;
    final usage = c.linesByStop;
    final unlinked = c.unlinkedStops.length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            children: [
              SehiriciSearchField(
                controller: _search,
                hint: 'Durak adı, kod veya adres ara',
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 10),
              if (_selecting)
                _selectionBar(visible)
              else
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _edit(),
                      icon: const Icon(Icons.add_location_alt_rounded, size: 20),
                      label: const Text('Yeni Durak'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AdminUi.brand,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _bulkSaving ? null : _addFromMap,
                      icon: _bulkSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.touch_app_rounded, size: 20),
                      label: const Text('Haritadan çoklu'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AdminUi.brand,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: AdminChipBar<_StopFilter>(
            selected: _filter,
            onSelected: (f) => setState(() => _filter = f),
            items: [
              (value: _StopFilter.all, label: 'Tümü', icon: null, count: c.stops.length),
              (
                value: _StopFilter.linked,
                label: 'Hatta bağlı',
                icon: null,
                count: c.stops.length - unlinked
              ),
              (
                value: _StopFilter.unlinked,
                label: 'Bağsız',
                icon: Icons.link_off_rounded,
                count: unlinked
              ),
              (
                value: _StopFilter.inactive,
                label: 'Pasif',
                icon: null,
                count: c.stops.where((s) => !s.isActive).length
              ),
            ],
          ),
              ),
              if (!_selecting && c.stops.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _startSelection(),
                  icon: const Icon(Icons.checklist_rounded, size: 18),
                  label: const Text('Seç'),
                ),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? AdminEmpty(
                  icon: Icons.signpost_outlined,
                  title: c.stops.isEmpty ? 'Henüz durak yok' : 'Sonuç bulunamadı',
                  subtitle: c.stops.isEmpty
                      ? 'Durakları tek tek ekleyin ya da haritaya dokunarak '
                          'güzergâh üzerinde dizin.'
                      : 'Arama veya filtreyi değiştirin.',
                )
              : RefreshIndicator(
                  onRefresh: c.reloadCityData,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final stop = visible[i];
                      final lines = usage[stop.id] ?? const <SehiriciLine>[];
                      return _StopCard(
                        stop: stop,
                        lines: lines,
                        selecting: _selecting,
                        selected: _selected.contains(stop.id),
                        onTap: _selecting ? () => _toggle(stop.id) : () => _edit(stop),
                        onLongPress: _selecting ? null : () => _startSelection(stop.id),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _StopCard extends StatelessWidget {
  final SehiriciStop stop;
  final List<SehiriciLine> lines;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selecting;
  final bool selected;

  const _StopCard({
    required this.stop,
    required this.lines,
    required this.onTap,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final unlinked = lines.isEmpty;
    final sub = [
      if ((stop.code ?? '').isNotEmpty) 'Kod ${stop.code}',
      if ((stop.address ?? '').isNotEmpty) stop.address!,
    ].join(' · ');

    return Opacity(
      opacity: stop.isActive ? 1 : 0.6,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: AdminCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 68,
              decoration: BoxDecoration(
                color: const Color(0xFFF2F1ED),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: SehiriciStopIcon(
                height: 54,
                state: MapStopState.normal,
                lineColors: lines.map((l) => l.color).take(3).toList(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          stop.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (!stop.isActive) ...[
                        const SizedBox(width: 6),
                        const AdminBadge(label: 'Pasif', color: Colors.grey),
                      ],
                    ],
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5, color: AdminUi.muted)),
                  ],
                  const SizedBox(height: 7),
                  if (unlinked)
                    const SehiriciMetaChip(
                      icon: Icons.link_off_rounded,
                      label: 'Hiçbir hatta bağlı değil',
                      color: Color(0xFFD97706),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final l in lines.take(4))
                          SehiriciLineBadge.forLine(l, height: 22, minWidth: 34),
                        if (lines.length > 4)
                          Text('+${lines.length - 4}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AdminUi.muted)),
                      ],
                    ),
                ],
              ),
            ),
            if (selecting)
              Checkbox(
                value: selected,
                onChanged: (_) => onTap(),
                activeColor: const Color(0xFFDC2626),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.chevron_right_rounded, color: AdminUi.muted),
              ),
          ],
        ),
      ),
      ),
    );
  }
}
