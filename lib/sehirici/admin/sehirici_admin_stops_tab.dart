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
/// tek tek veya haritadan çoklu ekleme.
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
                        onTap: () => _edit(stop),
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

  const _StopCard({
    required this.stop,
    required this.lines,
    required this.onTap,
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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.chevron_right_rounded, color: AdminUi.muted),
            ),
          ],
        ),
      ),
    );
  }
}
