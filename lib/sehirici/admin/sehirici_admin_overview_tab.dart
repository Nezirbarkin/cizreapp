import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/admin/widgets/admin_ui.dart';
import '../models/sehirici_models.dart';
import '../providers/sehirici_provider.dart';
import '../utils/sehirici_arrivals.dart';
import '../widgets/sehirici_common_widgets.dart';
import '../widgets/sehirici_live_map.dart';
import 'sehirici_admin_controller.dart';
import 'sehirici_admin_kit.dart';

/// Sekme numaraları (kabuktaki sıra ile aynı).
class SehiriciAdminTabs {
  const SehiriciAdminTabs._();
  static const int overview = 0;
  static const int lines = 1;
  static const int stops = 2;
  static const int icons = 3;
  static const int drivers = 4;
  static const int cities = 5;
  static const int settings = 6;
}

/// Admin > Şehiriçi > Genel Bakış: özet sayılar, dikkat isteyen durumlar ve
/// canlı harita + yolda olan araçlar.
class SehiriciAdminOverviewTab extends StatefulWidget {
  final SehiriciAdminController controller;
  final ValueChanged<int> onGoToTab;

  const SehiriciAdminOverviewTab({
    super.key,
    required this.controller,
    required this.onGoToTab,
  });

  @override
  State<SehiriciAdminOverviewTab> createState() =>
      _SehiriciAdminOverviewTabState();
}

class _SehiriciAdminOverviewTabState extends State<SehiriciAdminOverviewTab> {
  bool _creatingRoutes = false;
  String? _highlightLineId;

  SehiriciAdminController get c => widget.controller;

  Future<void> _createRoutes() async {
    final targets = c.linesNeedingRoute;
    if (targets.isEmpty) return;
    final ok = await sehiriciConfirm(
      context,
      icon: Icons.auto_fix_high_rounded,
      title: '${targets.length} hat için rota oluşturulsun mu?',
      message: 'Duraklardan geçen gerçek yol rotaları otomatik hesaplanır:\n\n'
          '${targets.map((l) => '• ${l.code} — ${l.name}').join('\n')}',
      confirmLabel: 'Oluştur',
    );
    if (!ok || !mounted) return;
    setState(() => _creatingRoutes = true);
    final result = await c.createMissingRoutes();
    try {
      if (mounted) context.read<SehiriciProvider>().invalidateAllCaches();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _creatingRoutes = false);
    sehiriciSnack(
      context,
      result.failed.isEmpty
          ? '${result.done} hattın rotası oluşturuldu.'
          : '${result.done} hat tamamlandı, ${result.failed.length} hat başarısız: '
              '${result.failed.join('; ')}',
      error: result.failed.isNotEmpty,
    );
  }

  List<_Alert> _alerts() {
    final alerts = <_Alert>[];
    final s = c.settings;
    if (s != null && !s.moduleEnabled) {
      alerts.add(_Alert(
        severity: _Severity.critical,
        icon: Icons.power_settings_new_rounded,
        title: 'Şehiriçi modülü kapalı',
        detail: 'Kullanıcılar bu özelliği uygulamada göremiyor.',
        actionLabel: 'Ayarlar',
        onAction: () => widget.onGoToTab(SehiriciAdminTabs.settings),
      ));
    }
    final blank =
        c.lines.where((l) => l.code.trim().isEmpty || l.name.trim().isEmpty).toList();
    if (blank.isNotEmpty) {
      alerts.add(_Alert(
        severity: _Severity.critical,
        icon: Icons.error_outline_rounded,
        title: '${blank.length} hat kod veya ad içermiyor',
        detail: 'Kullanıcı listesinde boş satır olarak görünür; düzenleyin ya da silin.',
        actionLabel: 'Hatlar',
        onAction: () => widget.onGoToTab(SehiriciAdminTabs.lines),
      ));
    }
    final noStops = c.lines.where((l) => l.isActive && l.stops.isEmpty).toList();
    if (noStops.isNotEmpty) {
      alerts.add(_Alert(
        severity: _Severity.warning,
        icon: Icons.signpost_outlined,
        title: '${noStops.length} aktif hatta durak yok',
        detail: noStops.map((l) => l.code.isEmpty ? '(kodsuz)' : l.code).join(', '),
        actionLabel: 'Hatlar',
        onAction: () => widget.onGoToTab(SehiriciAdminTabs.lines),
      ));
    }
    final needRoute = c.linesNeedingRoute;
    if (needRoute.isNotEmpty) {
      final stale = needRoute
          .where((l) => c.routeStateOf(l) == SehiriciRouteState.stale)
          .length;
      alerts.add(_Alert(
        severity: _Severity.warning,
        icon: Icons.route_rounded,
        title: '${needRoute.length} hattın yol rotası '
            '${stale == needRoute.length ? 'eski' : 'eksik'}',
        detail: 'Rotası olmayan hatlar haritada çizgisiz görünür. '
            '${needRoute.map((l) => l.code).join(', ')}',
        actionLabel: _creatingRoutes ? 'Oluşturuluyor…' : 'Otomatik oluştur',
        onAction: _creatingRoutes ? null : _createRoutes,
      ));
    }
    final unlinked = c.unlinkedStops.length;
    if (unlinked > 0) {
      alerts.add(_Alert(
        severity: _Severity.info,
        icon: Icons.link_off_rounded,
        title: '$unlinked durak hiçbir hatta bağlı değil',
        detail: 'Haritada görünür ama hiçbir hattın parçası değil.',
        actionLabel: 'Duraklar',
        onAction: () => widget.onGoToTab(SehiriciAdminTabs.stops),
      ));
    }
    final unassigned = c.drivers.where((d) => d.assignedLineId == null).length;
    if (unassigned > 0) {
      alerts.add(_Alert(
        severity: _Severity.info,
        icon: Icons.person_off_outlined,
        title: '$unassigned şoföre hat atanmamış',
        detail: 'Hat atanmayan şoför sefer başlatamaz.',
        actionLabel: 'Şoförler',
        onAction: () => widget.onGoToTab(SehiriciAdminTabs.drivers),
      ));
    }
    return alerts;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SehiriciProvider>();
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final city = c.city;
        if (city == null && !c.loadingCities) {
          return AdminEmpty(
            icon: Icons.location_city_rounded,
            title: 'Şehiriçi servisleri kurmaya başlayın',
            subtitle: 'İlk adım: bir şehir ekleyin. Sonra hat, durak ve şoför '
                'tanımlayabilirsiniz.',
            action: FilledButton.icon(
              onPressed: () => widget.onGoToTab(SehiriciAdminTabs.cities),
              icon: const Icon(Icons.add_location_alt_rounded),
              label: const Text('Şehir ekle'),
              style: FilledButton.styleFrom(backgroundColor: AdminUi.brand),
            ),
          );
        }
        final trips = provider.selectedCityId == c.cityId
            ? provider.activeTrips
            : const <SehiriciActiveTrip>[];
        final activeLines = c.lines.where((l) => l.isActive).toList();
        final alerts = _alerts();
        final stopCount = c.stops.length;
        final onDuty = c.drivers.where((d) => d.isOnDuty).length;

        return RefreshIndicator(
          onRefresh: () async {
            await c.reloadCityData();
            await c.reloadDrivers();
            await provider.refreshActiveTrips();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.3,
                children: [
                  AdminStatTile(
                    icon: Icons.sensors_rounded,
                    label: 'Şu an yolda',
                    value: '${trips.length}',
                    color: const Color(0xFF16A34A),
                  ),
                  AdminStatTile(
                    icon: Icons.alt_route_rounded,
                    label: 'Aktif hat / toplam',
                    value: '${activeLines.length}/${c.lines.length}',
                    color: const Color(0xFF1976D2),
                    onTap: () => widget.onGoToTab(SehiriciAdminTabs.lines),
                  ),
                  AdminStatTile(
                    icon: Icons.signpost_rounded,
                    label: 'Durak',
                    value: '$stopCount',
                    color: const Color(0xFFF59E0B),
                    onTap: () => widget.onGoToTab(SehiriciAdminTabs.stops),
                  ),
                  AdminStatTile(
                    icon: Icons.badge_rounded,
                    label: 'Şoför (görevde)',
                    value: '${c.drivers.length} ($onDuty)',
                    color: AdminUi.brand,
                    onTap: () => widget.onGoToTab(SehiriciAdminTabs.drivers),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // ── Dikkat gerektirenler ──
              _SectionTitle(
                title: 'Durum',
                trailing: alerts.isEmpty ? null : '${alerts.length} uyarı',
              ),
              if (alerts.isEmpty)
                AdminCard(
                  color: const Color(0xFFF0FDF4),
                  borderColor: const Color(0xFFBBF7D0),
                  child: Row(
                    children: const [
                      Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Her şey yolunda. Hatlar, duraklar ve rotalar eksiksiz.',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: Color(0xFF166534)),
                        ),
                      ),
                    ],
                  ),
                )
              else
                for (final a in alerts) ...[
                  _AlertCard(alert: a),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 10),
              // ── Canlı harita ──
              _SectionTitle(
                title: 'Canlı harita',
                trailing: city?.name,
              ),
              if (city != null)
                AdminCard(
                  padding: EdgeInsets.zero,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SehiriciLiveMap(
                      lines: activeLines,
                      activeTrips: trips,
                      center: city,
                      zoomLevel: city.zoomLevel,
                      height: 340,
                      showCouriers: false,
                      showLineChips: true,
                      highlightLineId: _highlightLineId,
                      onHighlightChanged: (id) =>
                          setState(() => _highlightLineId = id),
                      borderRadius: 16,
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              // ── Yolda olan araçlar ──
              _SectionTitle(title: 'Yolda olan araçlar', trailing: '${trips.length}'),
              if (trips.isEmpty)
                const AdminCard(
                  child: Row(
                    children: [
                      Icon(Icons.bedtime_outlined, color: AdminUi.muted),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Şu an sefer yapan araç yok. Şoförler sefer başlattığında '
                          'burada canlı olarak görünür.',
                          style: TextStyle(color: AdminUi.muted, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                )
              else
                for (final t in trips) ...[
                  _TripRow(
                    trip: t,
                    line: c.lineById(t.lineId),
                    onTap: () => setState(() => _highlightLineId = t.lineId),
                  ),
                  const SizedBox(height: 8),
                ],
            ],
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? trailing;
  const _SectionTitle({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                sehiriciUpper(title),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: AdminUi.muted,
                ),
              ),
            ),
            if (trailing != null)
              Text(trailing!,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AdminUi.muted)),
          ],
        ),
      );
}

enum _Severity { critical, warning, info }

class _Alert {
  final _Severity severity;
  final IconData icon;
  final String title;
  final String detail;
  final String actionLabel;
  final VoidCallback? onAction;

  const _Alert({
    required this.severity,
    required this.icon,
    required this.title,
    required this.detail,
    required this.actionLabel,
    required this.onAction,
  });
}

class _AlertCard extends StatelessWidget {
  final _Alert alert;
  const _AlertCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final (color, bg) = switch (alert.severity) {
      _Severity.critical => (const Color(0xFFDC2626), const Color(0xFFFEF2F2)),
      _Severity.warning => (const Color(0xFFD97706), const Color(0xFFFFFBEB)),
      _Severity.info => (const Color(0xFF2563EB), const Color(0xFFEFF6FF)),
    };
    return AdminCard(
      color: bg,
      borderColor: color.withValues(alpha: 0.25),
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(alert.icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(alert.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14, color: AdminUi.ink)),
                const SizedBox(height: 2),
                Text(alert.detail,
                    style: const TextStyle(
                        fontSize: 12.5, color: AdminUi.muted, height: 1.3)),
              ],
            ),
          ),
          TextButton(
            onPressed: alert.onAction,
            style: TextButton.styleFrom(foregroundColor: color),
            child: Text(alert.actionLabel,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

class _TripRow extends StatelessWidget {
  final SehiriciActiveTrip trip;
  final SehiriciLine? line;
  final VoidCallback onTap;

  const _TripRow({required this.trip, required this.line, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = line ??
        SehiriciLine(
          id: trip.lineId,
          code: trip.lineCode,
          name: trip.lineName,
          colorHex: trip.lineColor,
        );
    final onBreak = trip.status == SehiriciTripStatus.paused;
    final speed = trip.currentSpeed;
    return AdminCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 60,
            decoration: BoxDecoration(
              color: l.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(13),
            ),
            alignment: Alignment.center,
            child: SehiriciVehicleIcon.forLine(l, height: 50),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SehiriciLineBadge.forLine(l, height: 22, minWidth: 34),
                    const SizedBox(width: 8),
                    SehiriciStatusPill(
                      label: onBreak ? 'Mola' : 'Yolda',
                      color: onBreak ? const Color(0xFFF59E0B) : const Color(0xFF16A34A),
                      dense: true,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  trip.driverName ?? 'Şoför',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  [
                    if (trip.nextStopName != null) 'Sıradaki: ${trip.nextStopName}',
                    if (speed != null && speed > 0.5) '${speed.toStringAsFixed(0)} km/sa',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AdminUi.muted),
                ),
              ],
            ),
          ),
          if (trip.etaMinutes != null)
            Text(
              formatArrivalMinutes(trip.etaMinutes!),
              style: TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 15, color: l.color),
            ),
        ],
      ),
    );
  }
}
