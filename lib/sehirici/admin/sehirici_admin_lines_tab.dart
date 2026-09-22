import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:provider/provider.dart';

import '../../features/admin/widgets/admin_ui.dart';
import '../models/sehirici_models.dart';
import '../providers/sehirici_provider.dart';
import '../services/sehirici_errors.dart';
import '../utils/sehirici_route_geometry.dart';
import '../widgets/sehirici_common_widgets.dart';
import 'sehirici_admin_controller.dart';
import 'sehirici_admin_kit.dart';
import 'sehirici_line_editor_sheet.dart';
import 'sehirici_line_route_draw_dialog.dart';
import 'sehirici_line_stops_editor_dialog.dart';

enum _LineFilter { all, active, inactive, needsRoute }

/// Admin > Şehiriçi > Hatlar: arama, filtre, sıralama, hat kartları ve
/// rota/durak işlemleri.
class SehiriciAdminLinesTab extends StatefulWidget {
  final SehiriciAdminController controller;
  const SehiriciAdminLinesTab({super.key, required this.controller});

  @override
  State<SehiriciAdminLinesTab> createState() => _SehiriciAdminLinesTabState();
}

class _SehiriciAdminLinesTabState extends State<SehiriciAdminLinesTab> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  _LineFilter _filter = _LineFilter.all;
  bool _reorderMode = false;
  final Set<String> _busy = {};

  SehiriciAdminController get c => widget.controller;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _needsRoute(SehiriciLine l) =>
      c.routeStateOf(l) != SehiriciRouteState.current;

  List<SehiriciLine> get _visible {
    final q = sehiriciFold(_query.trim());
    return c.lines.where((l) {
      switch (_filter) {
        case _LineFilter.active:
          if (!l.isActive) return false;
        case _LineFilter.inactive:
          if (l.isActive) return false;
        case _LineFilter.needsRoute:
          if (!_needsRoute(l)) return false;
        case _LineFilter.all:
          break;
      }
      if (q.isEmpty) return true;
      return sehiriciFold(l.code).contains(q) || sehiriciFold(l.name).contains(q);
    }).toList();
  }

  // ── İşlemler ─────────────────────────────────────────────────

  void _refreshUserSide() {
    try {
      context.read<SehiriciProvider>().invalidateAllCaches();
    } catch (_) {}
  }

  Future<void> _guard(String lineId, Future<void> Function() action) async {
    if (_busy.contains(lineId)) return;
    setState(() => _busy.add(lineId));
    try {
      await action();
    } catch (e) {
      if (mounted) sehiriciSnack(context, sehiriciErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(lineId));
    }
  }

  Future<void> _toggleActive(SehiriciLine line, bool value) => _guard(line.id, () async {
        final ok = await c.lineService.updateLineActive(line.id, value);
        if (!ok) {
          throw const SehiriciAdminException('Hat durumu değiştirilemedi.');
        }
        await c.reloadCityData();
        _refreshUserSide();
      });

  Future<void> _editLine([SehiriciLine? line]) async {
    final changed = await showSehiriciLineEditor(context, controller: c, line: line);
    if (changed && mounted) {
      sehiriciSnack(context, line == null ? 'Hat oluşturuldu.' : 'Hat güncellendi.');
    }
  }

  Future<void> _editStops(SehiriciLine line) async {
    final cityId = c.cityId;
    if (cityId == null) return;
    final changed = await showSehiriciLineStopsEditor(
      context,
      line: line,
      cityId: cityId,
      controller: c,
    );
    if (changed) {
      await c.reloadCityData();
      _refreshUserSide();
      if (mounted) sehiriciSnack(context, 'Duraklar güncellendi.');
    }
  }

  Future<void> _createRoute(SehiriciLine line) => _guard(line.id, () async {
        if (line.hasRoute) {
          final ok = await sehiriciConfirm(
            context,
            icon: Icons.alt_route_rounded,
            title: 'Rota yeniden oluşturulsun mu?',
            message: '${line.code} hattının kayıtlı rotası, duraklardan geçen '
                'yeni bir yol rotasıyla DEĞİŞTİRİLECEK. Elle çizdiğiniz '
                'düzeltmeler kaybolur.',
            confirmLabel: 'Yeniden Oluştur',
          );
          if (!ok) return;
        }
        final points = await c.createRouteFromStops(line);
        _refreshUserSide();
        if (mounted) {
          sehiriciSnack(context,
              '${line.code} için $points noktalık yol rotası oluşturuldu.');
        }
      });

  Future<void> _drawRoute(SehiriciLine line) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => SehiriciLineRouteDrawDialog(line: line, controller: c),
    );
    if (changed == true) {
      await c.reloadCityData();
      _refreshUserSide();
      if (mounted) sehiriciSnack(context, '${line.code} rotası güncellendi.');
    }
  }

  Future<void> _sanitizeRoute(SehiriciLine line) => _guard(line.id, () async {
        final raw = line.roadPolyline;
        if (raw == null || raw.length < 2) return;
        final cleaned =
            sanitizeRoutePolyline(raw.map((p) => LatLng(p[0], p[1])).toList());
        if (cleaned.length < 2) {
          throw const SehiriciAdminException(
              'Rota temizlenince 2 noktanın altına düştü; dokunulmadı.');
        }
        if (cleaned.length == raw.length) {
          if (mounted) sehiriciSnack(context, '${line.code} rotası zaten temiz.');
          return;
        }
        final ok = await c.lineService.cacheRoutePolyline(
          lineId: line.id,
          lineStopsInOrder: line.stops,
          points: cleaned.map((p) => <double>[p.latitude, p.longitude]).toList(),
          source: 'admin_sanitized',
        );
        if (!ok) throw const SehiriciAdminException('Rota kaydedilemedi.');
        await c.reloadCityData();
        _refreshUserSide();
        if (mounted) {
          sehiriciSnack(
              context,
              '${line.code}: ${raw.length} → ${cleaned.length} nokta '
              '(${raw.length - cleaned.length} gürültü atıldı).');
        }
      });

  Future<void> _clearRoute(SehiriciLine line) => _guard(line.id, () async {
        final ok = await sehiriciConfirm(
          context,
          icon: Icons.delete_outline_rounded,
          title: '${line.code} rotası silinsin mi?',
          message: '${line.roadPolyline?.length ?? 0} noktalı rota kalıcı '
              'olarak silinir. Hat rotasız kalır ve haritada çizgi görünmez.',
          confirmLabel: 'Rotayı Sil',
          destructive: true,
        );
        if (!ok) return;
        final done = await c.lineService.clearRoutePolyline(line.id);
        if (!done) throw const SehiriciAdminException('Rota silinemedi.');
        await c.reloadCityData();
        _refreshUserSide();
        if (mounted) sehiriciSnack(context, '${line.code} rotası silindi.');
      });

  Future<void> _onReorder(List<SehiriciLine> ordered, int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final next = [...ordered];
    final moved = next.removeAt(oldIndex);
    next.insert(newIndex, moved);
    final cityId = c.cityId;
    if (cityId == null) return;
    try {
      await c.lineService.reorderLines(cityId, next.map((l) => l.id).toList());
      await c.reloadCityData();
      _refreshUserSide();
    } catch (e) {
      if (mounted) sehiriciSnack(context, sehiriciErrorMessage(e), error: true);
    }
  }

  // ── Arayüz ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        if (c.city == null && !c.loadingCities) {
          return const AdminEmpty(
            icon: Icons.location_city_rounded,
            title: 'Önce bir şehir ekleyin',
            subtitle: 'Hatlar bir şehre bağlıdır. "Şehirler" sekmesinden '
                'şehir oluşturun.',
          );
        }
        return SehiriciAsyncBody(
          loading: c.loadingCity && c.lines.isEmpty,
          error: c.cityError,
          onRetry: c.reloadCityData,
          child: _buildContent(context),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context) {
    final visible = _visible;
    final canReorder = _filter == _LineFilter.all && _query.trim().isEmpty;
    final counts = {
      _LineFilter.all: c.lines.length,
      _LineFilter.active: c.lines.where((l) => l.isActive).length,
      _LineFilter.inactive: c.lines.where((l) => !l.isActive).length,
      _LineFilter.needsRoute: c.lines.where(_needsRoute).length,
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: SehiriciSearchField(
                  controller: _search,
                  hint: 'Hat ara',
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: () => _editLine(),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Yeni Hat'),
                style: FilledButton.styleFrom(
                  backgroundColor: AdminUi.brand,
                  minimumSize: const Size(0, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 6, bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: AdminChipBar<_LineFilter>(
                  selected: _filter,
                  onSelected: (f) => setState(() => _filter = f),
                  items: [
                    (value: _LineFilter.all, label: 'Tümü', icon: null, count: counts[_LineFilter.all]),
                    (value: _LineFilter.active, label: 'Aktif', icon: null, count: counts[_LineFilter.active]),
                    (value: _LineFilter.inactive, label: 'Pasif', icon: null, count: counts[_LineFilter.inactive]),
                    (
                      value: _LineFilter.needsRoute,
                      label: 'Rota eksik',
                      icon: Icons.warning_amber_rounded,
                      count: counts[_LineFilter.needsRoute]
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _reorderMode ? 'Sıralamayı bitir' : 'Sırala',
                onPressed: c.lines.length < 2
                    ? null
                    : () => setState(() => _reorderMode = !_reorderMode),
                icon: Icon(
                  _reorderMode ? Icons.check_circle_rounded : Icons.swap_vert_rounded,
                  color: _reorderMode ? AdminUi.brand : AdminUi.muted,
                ),
              ),
            ],
          ),
        ),
        if (_reorderMode)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AdminUi.brandSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: AdminUi.brand),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    canReorder
                        ? 'Hatları sürükleyerek sıralayın. Kullanıcı listesinde bu sırayla görünür.'
                        : 'Sıralamak için arama ve filtreyi temizleyin.',
                    style: TextStyle(color: AdminUi.brand, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: visible.isEmpty
              ? AdminEmpty(
                  icon: Icons.alt_route_rounded,
                  title: c.lines.isEmpty ? 'Henüz hat yok' : 'Sonuç bulunamadı',
                  subtitle: c.lines.isEmpty
                      ? 'İlk hattı oluşturup duraklarını ve rotasını ekleyin.'
                      : 'Arama veya filtreyi değiştirin.',
                  action: c.lines.isEmpty
                      ? FilledButton.icon(
                          onPressed: () => _editLine(),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('İlk hattı oluştur'),
                          style: FilledButton.styleFrom(
                              backgroundColor: AdminUi.brand),
                        )
                      : null,
                )
              : (_reorderMode && canReorder)
                  ? ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      buildDefaultDragHandles: false,
                      itemCount: visible.length,
                      onReorder: (o, n) => _onReorder(visible, o, n),
                      itemBuilder: (context, i) => _ReorderTile(
                        key: ValueKey(visible[i].id),
                        index: i,
                        line: visible[i],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: c.reloadCityData,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) => _LineCard(
                          line: visible[i],
                          routeState: c.routeStateOf(visible[i]),
                          driver: c.driverOfLine(visible[i].id),
                          busy: _busy.contains(visible[i].id),
                          onToggle: (v) => _toggleActive(visible[i], v),
                          onEdit: () => _editLine(visible[i]),
                          onStops: () => _editStops(visible[i]),
                          onRouteAction: (a) {
                            switch (a) {
                              case 'auto':
                                _createRoute(visible[i]);
                              case 'draw':
                                _drawRoute(visible[i]);
                              case 'sanitize':
                                _sanitizeRoute(visible[i]);
                              case 'clear':
                                _clearRoute(visible[i]);
                            }
                          },
                        ),
                      ),
                    ),
        ),
      ],
    );
  }
}

class _ReorderTile extends StatelessWidget {
  final int index;
  final SehiriciLine line;
  const _ReorderTile({super.key, required this.index, required this.line});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AdminCard(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text('${index + 1}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, color: AdminUi.muted)),
            ),
            SehiriciLineBadge.forLine(line, height: 28, minWidth: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Text(line.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.drag_indicator_rounded, color: AdminUi.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  final SehiriciLine line;
  final SehiriciRouteState routeState;
  final SehiriciDriver? driver;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onStops;
  final ValueChanged<String> onRouteAction;

  const _LineCard({
    required this.line,
    required this.routeState,
    required this.driver,
    required this.busy,
    required this.onToggle,
    required this.onEdit,
    required this.onStops,
    required this.onRouteAction,
  });

  @override
  Widget build(BuildContext context) {
    final inactive = !line.isActive;
    final incomplete = line.code.trim().isEmpty || line.name.trim().isEmpty;
    final (routeLabel, routeColor, routeIcon) = switch (routeState) {
      SehiriciRouteState.current => (
          'Rota güncel · ${line.roadPolyline?.length ?? 0} nokta',
          const Color(0xFF16A34A),
          Icons.check_circle_outline_rounded
        ),
      SehiriciRouteState.stale => (
          'Rota eski — duraklar değişti',
          const Color(0xFFD97706),
          Icons.sync_problem_rounded
        ),
      SehiriciRouteState.missing => (
          'Rota yok',
          const Color(0xFFDC2626),
          Icons.route_rounded
        ),
    };

    return Opacity(
      opacity: inactive ? 0.72 : 1,
      child: AdminCard(
        padding: EdgeInsets.zero,
        child: Column(
          // Durum rozetleri ortalanmasın: sola yaslı akış.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 58,
                    height: 82,
                    decoration: BoxDecoration(
                      color: line.color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: SehiriciVehicleIcon.forLine(line, height: 64),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SehiriciLineBadge(
                              code: line.code,
                              color: line.color,
                              height: 26,
                              minWidth: 42,
                            ),
                            const Spacer(),
                            if (busy)
                              const Padding(
                                padding: EdgeInsets.only(right: 12),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            else
                              Transform.scale(
                                scale: 0.85,
                                child: Switch(
                                  value: line.isActive,
                                  onChanged: onToggle,
                                  activeTrackColor: AdminUi.brand,
                                  activeThumbColor: Colors.white,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          incomplete
                              ? 'Adsız hat — düzenleyin'
                              : line.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: incomplete
                                ? const Color(0xFFDC2626)
                                : AdminUi.ink,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            SehiriciMetaChip(
                              icon: Icons.signpost_outlined,
                              label: '${line.stops.length} durak',
                              color: line.stops.isEmpty
                                  ? const Color(0xFFDC2626)
                                  : null,
                            ),
                            if (line.estimatedMinutes != null)
                              SehiriciMetaChip(
                                icon: Icons.schedule_rounded,
                                label: '~${line.estimatedMinutes} dk',
                              ),
                            if (line.fareAmount > 0)
                              SehiriciMetaChip(
                                icon: Icons.payments_outlined,
                                label: '${line.fareAmount.toStringAsFixed(0)} ₺',
                              ),
                            if (inactive)
                              const SehiriciMetaChip(
                                icon: Icons.visibility_off_outlined,
                                label: 'Pasif',
                                color: Color(0xFF6B7280),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _StatusPill(
                    icon: routeIcon,
                    label: routeLabel,
                    color: routeColor,
                    onTap: routeState == SehiriciRouteState.current
                        ? null
                        : () => onRouteAction('auto'),
                    hint: routeState == SehiriciRouteState.current
                        ? null
                        : 'Oluştur',
                  ),
                  _StatusPill(
                    icon: driver == null
                        ? Icons.person_off_outlined
                        : Icons.person_outline_rounded,
                    label: driver == null
                        ? 'Şoför atanmamış'
                        : driver!.displayName,
                    color: driver == null
                        ? const Color(0xFFD97706)
                        : const Color(0xFF475569),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AdminUi.line),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  SehiriciCardAction(
                    icon: Icons.signpost_rounded,
                    label: 'Duraklar',
                    onTap: onStops,
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Rota işlemleri',
                    onSelected: onRouteAction,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    itemBuilder: (_) => [
                      _menuItem('auto', Icons.auto_fix_high_rounded,
                          'Duraklardan otomatik oluştur',
                          enabled: line.stops.length >= 2),
                      _menuItem('draw', Icons.draw_rounded, 'Haritada elle çiz'),
                      _menuItem('sanitize', Icons.cleaning_services_outlined,
                          'Rotayı ayıkla (gürültüyü temizle)',
                          enabled: line.hasRoute),
                      _menuItem('clear', Icons.delete_outline_rounded, 'Rotayı sil',
                          enabled: line.hasRoute, destructive: true),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.route_rounded,
                              size: 18, color: AdminUi.brand),
                          const SizedBox(width: 6),
                          Text('Rota',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AdminUi.brand)),
                          Icon(Icons.arrow_drop_down_rounded,
                              size: 20, color: AdminUi.brand),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  SehiriciCardAction(
                    icon: Icons.edit_rounded,
                    label: 'Düzenle',
                    onTap: onEdit,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String text,
      {bool enabled = true, bool destructive = false}) {
    final color = !enabled
        ? Colors.grey
        : (destructive ? const Color(0xFFDC2626) : AdminUi.ink);
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// Kart içi durum hapı (rota durumu, şoför). [onTap] varsa "Oluştur" gibi bir
/// eylem ipucu gösterir.
class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final String? hint;

  const _StatusPill({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ),
          if (hint != null) ...[
            const SizedBox(width: 8),
            Text('· $hint',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w900, color: color)),
          ],
        ],
      ),
    );
    if (onTap == null) return child;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: child,
    );
  }
}
