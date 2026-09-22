import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/admin/widgets/admin_ui.dart';
import '../providers/sehirici_provider.dart';
import '../services/sehirici_errors.dart';
import 'sehirici_admin_cities_tab.dart';
import 'sehirici_admin_controller.dart';
import 'sehirici_admin_drivers_tab.dart';
import 'sehirici_admin_icons_tab.dart';
import 'sehirici_admin_kit.dart';
import 'sehirici_admin_lines_tab.dart';
import 'sehirici_admin_overview_tab.dart';
import 'sehirici_admin_settings_tab.dart';
import 'sehirici_admin_stops_tab.dart';

/// Admin paneli: Şehiriçi Yönetimi.
///
/// Yapı: üstte modül durumu + şehir seçici olan başlık, altında kaydırmalı
/// sekme çipleri (Genel Bakış · Hatlar · Duraklar · İkonlar · Şoförler ·
/// Şehirler · Ayarlar) ve seçili sekmenin içeriği. Sekmeler ilk açıldığında
/// kurulur, sonra durumlarını (arama, kaydırma) korur.
class SehiriciAdminManagementContent extends StatefulWidget {
  /// Testlerde sahte servisli denetleyici vermek için.
  final SehiriciAdminController? controller;

  const SehiriciAdminManagementContent({super.key, this.controller});

  @override
  State<SehiriciAdminManagementContent> createState() =>
      _SehiriciAdminManagementContentState();
}

class _SehiriciAdminManagementContentState
    extends State<SehiriciAdminManagementContent> {
  late final SehiriciAdminController _controller =
      widget.controller ?? SehiriciAdminController();
  late final bool _ownsController = widget.controller == null;

  int _index = SehiriciAdminTabs.overview;
  final Set<int> _visited = {SehiriciAdminTabs.overview};
  bool _moduleBusy = false;

  @override
  void initState() {
    super.initState();
    String? preferred;
    try {
      preferred = context.read<SehiriciProvider>().selectedCityId;
    } catch (_) {}
    _controller.loadAll(preferredCityId: preferred);
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    setState(() {
      _index = index;
      _visited.add(index);
    });
  }

  Future<void> _selectCity(String id) async {
    await _controller.selectCity(id);
    try {
      // Kullanıcı tarafı (canlı seferler, harita) da aynı şehri izlesin.
      if (mounted) await context.read<SehiriciProvider>().selectCity(id);
    } catch (_) {}
  }

  Future<void> _toggleModule(bool value) async {
    setState(() => _moduleBusy = true);
    try {
      await _controller.updateSetting('sehirici_module_enabled', value.toString());
      try {
        if (mounted) context.read<SehiriciProvider>().invalidateAllCaches();
      } catch (_) {}
    } catch (e) {
      if (mounted) sehiriciSnack(context, sehiriciErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _moduleBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AdminUi.page,
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Column(
          children: [
            _Header(
              controller: _controller,
              moduleBusy: _moduleBusy,
              onToggleModule: _toggleModule,
              onSelectCity: _selectCity,
              onAddCity: () => _goTo(SehiriciAdminTabs.cities),
            ),
            _NavBar(
              controller: _controller,
              index: _index,
              onSelected: _goTo,
            ),
            Expanded(
              child: IndexedStack(
                index: _index,
                children: [
                  for (var i = 0; i < 7; i++)
                    _visited.contains(i) ? _tab(i) : const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab(int i) {
    switch (i) {
      case SehiriciAdminTabs.overview:
        return SehiriciAdminOverviewTab(controller: _controller, onGoToTab: _goTo);
      case SehiriciAdminTabs.lines:
        return SehiriciAdminLinesTab(controller: _controller);
      case SehiriciAdminTabs.stops:
        return SehiriciAdminStopsTab(controller: _controller);
      case SehiriciAdminTabs.icons:
        return SehiriciAdminIconsTab(controller: _controller);
      case SehiriciAdminTabs.drivers:
        return SehiriciAdminDriversTab(controller: _controller);
      case SehiriciAdminTabs.cities:
        return SehiriciAdminCitiesTab(controller: _controller);
      default:
        return SehiriciAdminSettingsTab(controller: _controller);
    }
  }
}

/// Üst başlık: gradyanlı zemin, başlık, modül anahtarı ve şehir seçici.
class _Header extends StatelessWidget {
  final SehiriciAdminController controller;
  final bool moduleBusy;
  final ValueChanged<bool> onToggleModule;
  final ValueChanged<String> onSelectCity;
  final VoidCallback onAddCity;

  const _Header({
    required this.controller,
    required this.moduleBusy,
    required this.onToggleModule,
    required this.onSelectCity,
    required this.onAddCity,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = controller.settings?.moduleEnabled ?? true;
    final city = controller.city;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AdminUi.brand, const Color(0xFF3F1D7A)],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: AdminUi.brand.withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.directions_bus_rounded,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Şehiriçi Yönetimi',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      'Hat, durak, ikon ve şoförler',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Modül anahtarı
              Container(
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      enabled ? 'Açık' : 'Kapalı',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5),
                    ),
                    Transform.scale(
                      scale: 0.82,
                      child: moduleBusy
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              ),
                            )
                          : Switch(
                              value: enabled,
                              onChanged:
                                  controller.settings == null ? null : onToggleModule,
                              activeTrackColor: const Color(0xFF22C55E),
                              activeThumbColor: Colors.white,
                              inactiveTrackColor: Colors.white24,
                              inactiveThumbColor: Colors.white70,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Şehir seçici
          Row(
            children: [
              Expanded(
                child: PopupMenuButton<String>(
                  tooltip: 'Şehir değiştir',
                  enabled: controller.cities.isNotEmpty,
                  onSelected: onSelectCity,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  itemBuilder: (_) => [
                    for (final c in controller.cities)
                      PopupMenuItem<String>(
                        value: c.id,
                        child: Row(
                          children: [
                            Icon(
                              c.id == controller.cityId
                                  ? Icons.check_circle_rounded
                                  : Icons.location_city_outlined,
                              size: 20,
                              color: c.id == controller.cityId
                                  ? AdminUi.brand
                                  : AdminUi.muted,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(c.name,
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            if (!c.isActive)
                              const AdminBadge(label: 'Pasif', color: Colors.grey),
                          ],
                        ),
                      ),
                  ],
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_city_rounded,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            city?.name ??
                                (controller.loadingCities
                                    ? 'Yükleniyor…'
                                    : 'Şehir yok'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 15),
                          ),
                        ),
                        if (controller.loadingCity)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            ),
                          ),
                        const Icon(Icons.expand_more_rounded,
                            color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: onAddCity,
                tooltip: 'Şehirleri yönet',
                icon: const Icon(Icons.add_location_alt_rounded, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.16),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(46, 46),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Kaydırmalı sekme çipleri (sayaç rozetli). Seçili çip ekran dışındaysa
/// (ör. Genel Bakış'taki bir uyarıdan "Ayarlar"a geçilince) görünür kaydırılır.
class _NavBar extends StatefulWidget {
  final SehiriciAdminController controller;
  final int index;
  final ValueChanged<int> onSelected;

  const _NavBar({
    required this.controller,
    required this.index,
    required this.onSelected,
  });

  @override
  State<_NavBar> createState() => _NavBarState();
}

class _NavBarState extends State<_NavBar> {
  final List<GlobalKey> _keys = List.generate(7, (_) => GlobalKey());

  @override
  void didUpdateWidget(covariant _NavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _keys[widget.index].currentContext;
        if (ctx == null || !ctx.mounted) return;
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final items = <({int tab, String label, IconData icon, int? count})>[
      (tab: SehiriciAdminTabs.overview, label: 'Genel Bakış', icon: Icons.dashboard_rounded, count: null),
      (tab: SehiriciAdminTabs.lines, label: 'Hatlar', icon: Icons.alt_route_rounded, count: c.lines.length),
      (tab: SehiriciAdminTabs.stops, label: 'Duraklar', icon: Icons.signpost_rounded, count: c.stops.length),
      (tab: SehiriciAdminTabs.icons, label: 'İkonlar', icon: Icons.category_rounded, count: c.icons.length),
      (tab: SehiriciAdminTabs.drivers, label: 'Şoförler', icon: Icons.badge_rounded, count: c.drivers.length),
      (tab: SehiriciAdminTabs.cities, label: 'Şehirler', icon: Icons.location_city_rounded, count: c.cities.length),
      (tab: SehiriciAdminTabs.settings, label: 'Ayarlar', icon: Icons.tune_rounded, count: null),
    ];
    return SizedBox(
      height: 62,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            for (final item in items) ...[
              _NavChip(
                key: _keys[item.tab],
                tab: item.tab,
                label: item.label,
                icon: item.icon,
                count: item.count,
                selected: item.tab == widget.index,
                onTap: () => widget.onSelected(item.tab),
              ),
              if (item.tab != SehiriciAdminTabs.settings) const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _NavChip extends StatelessWidget {
  final int tab;
  final String label;
  final IconData icon;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  const _NavChip({
    super.key,
    required this.tab,
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        key: ValueKey('sehirici-nav-$tab'),
        color: selected ? AdminUi.brand : Colors.white,
        elevation: selected ? 3 : 0,
        shadowColor: AdminUi.brand.withValues(alpha: 0.45),
        shape: StadiumBorder(
          side: BorderSide(color: selected ? AdminUi.brand : AdminUi.line),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 18, color: selected ? Colors.white : AdminUi.muted),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: selected ? Colors.white : AdminUi.ink,
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 7),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.22)
                          : AdminUi.brandSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: selected ? Colors.white : AdminUi.brand,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}