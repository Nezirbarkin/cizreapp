import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/admin/widgets/admin_ui.dart';
import '../models/sehirici_models.dart';
import '../services/sehirici_errors.dart';
import '../widgets/sehirici_common_widgets.dart';
import 'sehirici_admin_controller.dart';
import 'sehirici_admin_kit.dart';

// ─────────────────────────────────────────────────────────────
// Şoför ekle
// ─────────────────────────────────────────────────────────────

/// Kullanıcı arayıp şoför olarak ekler. Sonuç: eklendiyse `true`.
Future<bool> showSehiriciDriverAdd(
  BuildContext context, {
  required SehiriciAdminController controller,
}) async {
  final changed = await showSehiriciSheet<bool>(
    context,
    heightFactor: 0.85,
    builder: (_) => _DriverAddSheet(controller: controller),
  );
  return changed == true;
}

class _DriverAddSheet extends StatefulWidget {
  final SehiriciAdminController controller;
  const _DriverAddSheet({required this.controller});

  @override
  State<_DriverAddSheet> createState() => _DriverAddSheetState();
}

class _DriverAddSheetState extends State<_DriverAddSheet> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = const [];
  bool _searching = false;
  String? _addingId;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final found = await widget.controller.driverService.searchProfiles(value);
      if (!mounted || _search.text != value) return;
      setState(() {
        _results = found;
        _searching = false;
      });
    });
  }

  Future<void> _add(Map<String, dynamic> profile) async {
    setState(() {
      _addingId = profile['id'] as String;
      _error = null;
    });
    try {
      await widget.controller.driverService
          .createDriverOrThrow(profileId: profile['id'] as String);
      await widget.controller.reloadDrivers();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _addingId = null;
          _error = sehiriciErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing =
        widget.controller.drivers.map((d) => d.profileId).toSet();
    return SehiriciSheetScaffold(
      title: 'Şoför Ekle',
      subtitle: 'Uygulama kullanıcılarından seçin',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SehiriciSearchField(
              controller: _search,
              hint: 'Ad veya kullanıcı adı ara (en az 2 harf)',
              onChanged: _onChanged,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_error!,
                    style: const TextStyle(
                        color: Color(0xFF991B1B), fontWeight: FontWeight.w600)),
              ),
            ),
          Expanded(
            child: _searching
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? AdminEmpty(
                        icon: Icons.person_search_rounded,
                        title: _search.text.trim().length < 2
                            ? 'Kullanıcı arayın'
                            : 'Sonuç bulunamadı',
                        subtitle: 'Şoför olarak eklemek istediğiniz kişinin '
                            'adını veya kullanıcı adını yazın.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final p = _results[i];
                          final already = existing.contains(p['id']);
                          final name = adminDisplayName(p);
                          return AdminCard(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            child: Row(
                              children: [
                                AdminAvatar(
                                  url: p['avatar_url'] as String?,
                                  name: name,
                                  radius: 22,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800)),
                                      Text('@${p['username'] ?? ''}',
                                          style: const TextStyle(
                                              fontSize: 12.5,
                                              color: AdminUi.muted)),
                                    ],
                                  ),
                                ),
                                if (already)
                                  const AdminBadge(
                                      label: 'Zaten şoför',
                                      color: Colors.green,
                                      icon: Icons.check_rounded)
                                else
                                  FilledButton(
                                    onPressed:
                                        _addingId != null ? null : () => _add(p),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AdminUi.brand,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    child: _addingId == p['id']
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white),
                                          )
                                        : const Text('Ekle'),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Hat ata
// ─────────────────────────────────────────────────────────────

/// Şoföre hat atar (ya da atamayı kaldırır). Sonuç: değiştiyse `true`.
Future<bool> showSehiriciDriverAssign(
  BuildContext context, {
  required SehiriciAdminController controller,
  required SehiriciDriver driver,
}) async {
  final changed = await showSehiriciSheet<bool>(
    context,
    heightFactor: 0.8,
    builder: (_) => _DriverAssignSheet(controller: controller, driver: driver),
  );
  return changed == true;
}

class _DriverAssignSheet extends StatefulWidget {
  final SehiriciAdminController controller;
  final SehiriciDriver driver;
  const _DriverAssignSheet({required this.controller, required this.driver});

  @override
  State<_DriverAssignSheet> createState() => _DriverAssignSheetState();
}

class _DriverAssignSheetState extends State<_DriverAssignSheet> {
  late String? _selected = widget.driver.assignedLineId;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.driverService
          .assignLineOrThrow(widget.driver.id, _selected);
      await widget.controller.reloadDrivers();
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

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final lines = controller.lines;
    return SehiriciSheetScaffold(
      title: 'Hat Ata',
      subtitle: widget.driver.displayName,
      bottomBar: FilledButton.icon(
        onPressed: _saving || _selected == widget.driver.assignedLineId
            ? null
            : _save,
        icon: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.check_rounded),
        label: Text(_selected == null ? 'Atamayı Kaldır' : 'Hattı Ata'),
        style: FilledButton.styleFrom(
          backgroundColor: AdminUi.brand,
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_error!,
                  style: const TextStyle(
                      color: Color(0xFF991B1B), fontWeight: FontWeight.w600)),
            ),
          _AssignTile(
            selected: _selected == null,
            onTap: () => setState(() => _selected = null),
            leading: const Icon(Icons.link_off_rounded, color: AdminUi.muted),
            title: 'Hat atanmasın',
            subtitle: 'Şoför sefer başlatamaz.',
          ),
          for (final line in lines)
            Builder(builder: (context) {
              final other = controller.driverOfLine(line.id);
              final takenByOther = other != null && other.id != widget.driver.id;
              return _AssignTile(
                selected: _selected == line.id,
                disabled: takenByOther,
                onTap: () => setState(() => _selected = line.id),
                leading: SehiriciLineBadge.forLine(line, height: 30, minWidth: 44),
                title: line.name,
                subtitle: takenByOther
                    ? '${other.displayName} şoförüne atanmış'
                    : '${line.stops.length} durak',
                trailing: SehiriciVehicleIcon.forLine(line, height: 36),
              );
            }),
          if (lines.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Bu şehirde henüz hat yok. Önce Hatlar sekmesinden hat ekleyin.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AdminUi.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _AssignTile extends StatelessWidget {
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;
  final Widget leading;
  final Widget? trailing;
  final String title;
  final String subtitle;

  const _AssignTile({
    required this.selected,
    required this.onTap,
    required this.leading,
    required this.title,
    required this.subtitle,
    this.disabled = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: disabled ? 0.5 : 1,
        child: Material(
          color: selected ? AdminUi.brand.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: disabled ? null : onTap,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? AdminUi.brand : AdminUi.line,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  SizedBox(width: 48, child: Center(child: leading)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(subtitle,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: disabled
                                    ? const Color(0xFFB45309)
                                    : AdminUi.muted)),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected ? AdminUi.brand : AdminUi.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Şoför bilgisi düzenle
// ─────────────────────────────────────────────────────────────

/// Ehliyet no ve telefonu düzenler. Sonuç: kaydedildiyse `true`.
Future<bool> showSehiriciDriverEdit(
  BuildContext context, {
  required SehiriciAdminController controller,
  required SehiriciDriver driver,
}) async {
  final changed = await showSehiriciSheet<bool>(
    context,
    heightFactor: 0.6,
    builder: (_) => _DriverEditSheet(controller: controller, driver: driver),
  );
  return changed == true;
}

class _DriverEditSheet extends StatefulWidget {
  final SehiriciAdminController controller;
  final SehiriciDriver driver;
  const _DriverEditSheet({required this.controller, required this.driver});

  @override
  State<_DriverEditSheet> createState() => _DriverEditSheetState();
}

class _DriverEditSheetState extends State<_DriverEditSheet> {
  late final TextEditingController _license =
      TextEditingController(text: widget.driver.licenseNumber ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.driver.phone ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _license.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.driverService.updateDriverOrThrow(
        widget.driver.id,
        licenseNumber: _license.text,
        phone: _phone.text,
      );
      await widget.controller.reloadDrivers();
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

  @override
  Widget build(BuildContext context) {
    return SehiriciSheetScaffold(
      title: 'Şoför Bilgileri',
      subtitle: widget.driver.displayName,
      leading: AdminAvatar(
        url: widget.driver.avatarUrl,
        name: widget.driver.displayName,
        radius: 22,
      ),
      bottomBar: FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.check_rounded),
        label: const Text('Kaydet'),
        style: FilledButton.styleFrom(
          backgroundColor: AdminUi.brand,
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_error!,
                  style: const TextStyle(
                      color: Color(0xFF991B1B), fontWeight: FontWeight.w600)),
            ),
          TextField(
            controller: _license,
            decoration: sehiriciInput('Ehliyet / belge no',
                icon: Icons.badge_outlined),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: sehiriciInput('Telefon',
                hint: '05xx xxx xx xx', icon: Icons.phone_outlined),
          ),
        ],
      ),
    );
  }
}

