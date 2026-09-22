import 'package:flutter/material.dart';

import '../../features/admin/widgets/admin_ui.dart';
import '../models/sehirici_models.dart';
import '../services/sehirici_errors.dart';
import '../widgets/sehirici_common_widgets.dart';
import 'sehirici_admin_controller.dart';
import 'sehirici_admin_kit.dart';
import 'sehirici_driver_sheets.dart';

enum _DriverFilter { all, assigned, unassigned, onDuty }

/// Admin > Şehiriçi > Şoförler: şoför kartları, hat atama, bilgi düzenleme.
class SehiriciAdminDriversTab extends StatefulWidget {
  final SehiriciAdminController controller;
  const SehiriciAdminDriversTab({super.key, required this.controller});

  @override
  State<SehiriciAdminDriversTab> createState() =>
      _SehiriciAdminDriversTabState();
}

class _SehiriciAdminDriversTabState extends State<SehiriciAdminDriversTab> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  _DriverFilter _filter = _DriverFilter.all;

  SehiriciAdminController get c => widget.controller;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<SehiriciDriver> get _visible {
    final q = sehiriciFold(_query.trim());
    return c.drivers.where((d) {
      switch (_filter) {
        case _DriverFilter.assigned:
          if (d.assignedLineId == null) return false;
        case _DriverFilter.unassigned:
          if (d.assignedLineId != null) return false;
        case _DriverFilter.onDuty:
          if (!d.isOnDuty) return false;
        case _DriverFilter.all:
          break;
      }
      if (q.isEmpty) return true;
      return sehiriciFold(d.fullName).contains(q) ||
          sehiriciFold(d.username).contains(q) ||
          sehiriciFold(d.licenseNumber ?? '').contains(q) ||
          sehiriciFold(d.phone ?? '').contains(q);
    }).toList()
      ..sort((a, b) => sehiriciFold(a.displayName).compareTo(sehiriciFold(b.displayName)));
  }

  Future<void> _add() async {
    final added = await showSehiriciDriverAdd(context, controller: c);
    if (added && mounted) sehiriciSnack(context, 'Şoför eklendi.');
  }

  Future<void> _assign(SehiriciDriver d) async {
    if (c.cityId == null) {
      sehiriciSnack(context, 'Önce üstten bir şehir seçin.', error: true);
      return;
    }
    final changed =
        await showSehiriciDriverAssign(context, controller: c, driver: d);
    if (changed && mounted) sehiriciSnack(context, 'Hat ataması güncellendi.');
  }

  Future<void> _edit(SehiriciDriver d) async {
    final changed = await showSehiriciDriverEdit(context, controller: c, driver: d);
    if (changed && mounted) sehiriciSnack(context, 'Şoför bilgileri güncellendi.');
  }

  Future<void> _delete(SehiriciDriver d) async {
    final ok = await sehiriciConfirm(
      context,
      icon: Icons.person_remove_rounded,
      title: '${d.displayName} şoförlükten çıkarılsın mı?',
      message: 'Şoför kaydı ve hat ataması silinir. Kullanıcının hesabı '
          'silinmez; istediğinizde yeniden şoför ekleyebilirsiniz.',
      confirmLabel: 'Çıkar',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await c.driverService.deleteDriverOrThrow(d.id);
      await c.reloadDrivers();
      if (mounted) sehiriciSnack(context, 'Şoför çıkarıldı.');
    } catch (e) {
      if (mounted) sehiriciSnack(context, sehiriciErrorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => SehiriciAsyncBody(
        loading: c.loadingDrivers && c.drivers.isEmpty,
        error: c.driversError != null && c.drivers.isEmpty ? c.driversError : null,
        onRetry: c.reloadDrivers,
        child: _content(context),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final visible = _visible;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: SehiriciSearchField(
                  controller: _search,
                  hint: 'Şoför ara',
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                label: const Text('Ekle'),
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
          padding: const EdgeInsets.only(left: 16, bottom: 6),
          child: AdminChipBar<_DriverFilter>(
            selected: _filter,
            onSelected: (f) => setState(() => _filter = f),
            items: [
              (value: _DriverFilter.all, label: 'Tümü', icon: null, count: c.drivers.length),
              (
                value: _DriverFilter.assigned,
                label: 'Hat atanmış',
                icon: null,
                count: c.drivers.where((d) => d.assignedLineId != null).length
              ),
              (
                value: _DriverFilter.unassigned,
                label: 'Atanmamış',
                icon: Icons.warning_amber_rounded,
                count: c.drivers.where((d) => d.assignedLineId == null).length
              ),
              (
                value: _DriverFilter.onDuty,
                label: 'Görevde',
                icon: Icons.circle,
                count: c.drivers.where((d) => d.isOnDuty).length
              ),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? AdminEmpty(
                  icon: Icons.badge_outlined,
                  title: c.drivers.isEmpty ? 'Henüz şoför yok' : 'Sonuç bulunamadı',
                  subtitle: c.drivers.isEmpty
                      ? 'Bir kullanıcıyı şoför olarak ekleyip ona hat atayın; '
                          'kendi telefonundan sefer başlatıp canlı konum paylaşır.'
                      : 'Arama veya filtreyi değiştirin.',
                  action: c.drivers.isEmpty
                      ? FilledButton.icon(
                          onPressed: _add,
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                          label: const Text('İlk şoförü ekle'),
                          style: FilledButton.styleFrom(
                              backgroundColor: AdminUi.brand),
                        )
                      : null,
                )
              : RefreshIndicator(
                  onRefresh: c.reloadDrivers,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final d = visible[i];
                      return _DriverCard(
                        driver: d,
                        line: c.lineById(d.assignedLineId),
                        onAssign: () => _assign(d),
                        onEdit: () => _edit(d),
                        onDelete: () => _delete(d),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _DriverCard extends StatelessWidget {
  final SehiriciDriver driver;
  final SehiriciLine? line;
  final VoidCallback onAssign;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DriverCard({
    required this.driver,
    required this.line,
    required this.onAssign,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final hasHours = driver.workingHoursStart != null && driver.workingHoursEnd != null;
    return AdminCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 6, 10),
            child: Row(
              children: [
                AdminAvatar(
                  url: driver.avatarUrl,
                  name: driver.displayName,
                  radius: 24,
                  online: driver.isOnDuty,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(driver.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w800)),
                      if (driver.username.isNotEmpty)
                        Text('@${driver.username}',
                            style: const TextStyle(
                                fontSize: 12.5, color: AdminUi.muted)),
                    ],
                  ),
                ),
                if (driver.isOnDuty)
                  const AdminBadge(
                      label: 'Görevde', color: Color(0xFF16A34A), icon: Icons.circle),
                PopupMenuButton<String>(
                  tooltip: 'Daha fazla',
                  onSelected: (v) {
                    if (v == 'edit') onEdit();
                    if (v == 'delete') onDelete();
                  },
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit_outlined, size: 20),
                        SizedBox(width: 12),
                        Text('Bilgileri düzenle'),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.person_remove_outlined,
                            size: 20, color: Color(0xFFDC2626)),
                        SizedBox(width: 12),
                        Text('Şoförlükten çıkar',
                            style: TextStyle(color: Color(0xFFDC2626))),
                      ]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (line != null)
                    Container(
                      padding: const EdgeInsets.fromLTRB(5, 4, 12, 4),
                      decoration: BoxDecoration(
                        color: line!.color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SehiriciLineBadge.forLine(line!, height: 24, minWidth: 36),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 170),
                            child: Text(line!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12.5, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    )
                  else
                    const SehiriciMetaChip(
                      icon: Icons.link_off_rounded,
                      label: 'Hat atanmadı',
                      color: Color(0xFFD97706),
                    ),
                  if ((driver.licenseNumber ?? '').isNotEmpty)
                    SehiriciMetaChip(
                        icon: Icons.badge_outlined, label: driver.licenseNumber!),
                  if ((driver.phone ?? '').isNotEmpty)
                    SehiriciMetaChip(
                        icon: Icons.phone_outlined, label: driver.phone!),
                  if (hasHours)
                    SehiriciMetaChip(
                      icon: Icons.schedule_rounded,
                      label: '${_hm(driver.workingHoursStart!)}–${_hm(driver.workingHoursEnd!)}',
                    ),
                  if (driver.autoTripEnabled)
                    const SehiriciMetaChip(
                      icon: Icons.autorenew_rounded,
                      label: 'Otomatik sefer',
                      color: Color(0xFF1976D2),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: AdminUi.line),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                SehiriciCardAction(
                  icon: Icons.alt_route_rounded,
                  label: line == null ? 'Hat ata' : 'Hattı değiştir',
                  onTap: onAssign,
                ),
                const Spacer(),
                SehiriciCardAction(
                  icon: Icons.edit_outlined,
                  label: 'Düzenle',
                  onTap: onEdit,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "07:00:00" → "07:00" (veritabanı saniyeyi de döndürür).
String _hm(String time) => RegExp(r'^\d{1,2}:\d{2}').stringMatch(time) ?? time;
