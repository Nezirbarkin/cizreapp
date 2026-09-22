import 'package:flutter/material.dart';

import '../../features/admin/widgets/admin_ui.dart';
import '../models/sehirici_icon_models.dart';
import '../widgets/sehirici_common_widgets.dart';
import 'sehirici_admin_controller.dart';
import 'sehirici_admin_kit.dart';
import 'sehirici_icon_editor_sheet.dart';

/// Admin > Şehiriçi > İkonlar: haritadaki araç ve durak ikonlarının
/// kütüphanesi. Hazır çizimler değiştirilebilir, kendi görseliniz yüklenebilir,
/// yeni araç türleri (Taksi, Servis …) eklenebilir.
class SehiriciAdminIconsTab extends StatefulWidget {
  final SehiriciAdminController controller;
  const SehiriciAdminIconsTab({super.key, required this.controller});

  @override
  State<SehiriciAdminIconsTab> createState() => _SehiriciAdminIconsTabState();
}

class _SehiriciAdminIconsTabState extends State<SehiriciAdminIconsTab> {
  SehiriciIconKind _kind = SehiriciIconKind.vehicle;

  SehiriciAdminController get c => widget.controller;

  Future<void> _open({SehiriciMarkerIcon? icon}) async {
    final changed = await showSehiriciIconEditor(
      context,
      controller: c,
      kind: icon?.kind ?? _kind,
      icon: icon,
    );
    if (changed && mounted) {
      sehiriciSnack(context, icon == null ? 'İkon eklendi.' : 'İkon güncellendi.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final icons = c.icons.where((i) => i.kind == _kind).toList()
          ..sort((a, b) {
            final o = a.sortOrder.compareTo(b.sortOrder);
            return o != 0 ? o : a.label.compareTo(b.label);
          });
        final vehicles = c.icons.where((i) => i.isVehicle).length;
        final stops = c.icons.where((i) => i.isStop).length;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(
                children: [
                  SehiriciSegmented<SehiriciIconKind>(
                    selected: _kind,
                    onChanged: (k) => setState(() => _kind = k),
                    items: [
                      (
                        value: SehiriciIconKind.vehicle,
                        label: 'Araçlar · $vehicles',
                        icon: Icons.directions_bus_rounded,
                      ),
                      (
                        value: SehiriciIconKind.stop,
                        label: 'Duraklar · $stops',
                        icon: Icons.signpost_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AdminUi.brandSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 18, color: AdminUi.brand),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _kind == SehiriciIconKind.vehicle
                                ? 'Her hat bir araç türü seçer; haritada o türün '
                                    'ikonu, hattın renginde ve gittiği yöne '
                                    'dönük görünür. Bir ikona dokunup hazır '
                                    'çizimi değiştirebilir veya kendi görselinizi '
                                    'yükleyebilirsiniz.'
                                : 'Haritadaki tüm duraklar varsayılan durak '
                                    'ikonuyla çizilir. Bir ikonu "Haritada bunu '
                                    'kullan" ile seçebilir, kendi görselinizi '
                                    'yükleyebilirsiniz.',
                            style: TextStyle(
                                fontSize: 12.5, color: AdminUi.brand, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _open(),
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: Text(_kind == SehiriciIconKind.vehicle
                          ? 'Yeni araç türü / ikon ekle'
                          : 'Yeni durak ikonu ekle'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AdminUi.brand,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SehiriciAsyncBody(
                loading: c.loadingIcons && c.icons.isEmpty,
                error: c.iconsError != null && c.icons.isEmpty
                    ? c.iconsError
                    : null,
                onRetry: c.reloadIcons,
                child: RefreshIndicator(
                  onRefresh: c.reloadIcons,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final columns = (box.maxWidth / 176).floor().clamp(2, 6);
                      return GridView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          mainAxisExtent: 214,
                        ),
                        itemCount: icons.length,
                        itemBuilder: (context, i) => _IconCard(
                          icon: icons[i],
                          usedBy: icons[i].isVehicle
                              ? c.lines
                                  .where((l) => l.vehicleKey == icons[i].key)
                                  .toList()
                              : const [],
                          sampleColor: _sampleColor(i),
                          onTap: () => _open(icon: icons[i]),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Color _sampleColor(int index) {
    const colors = [
      Color(0xFF1976D2),
      Color(0xFFE53935),
      Color(0xFF2E9E5B),
      Color(0xFF8E24AA),
      Color(0xFFF59E0B),
      Color(0xFF00897B),
    ];
    return colors[index % colors.length];
  }
}

class _IconCard extends StatelessWidget {
  final SehiriciMarkerIcon icon;
  final List usedBy;
  final Color sampleColor;
  final VoidCallback onTap;

  const _IconCard({
    required this.icon,
    required this.usedBy,
    required this.sampleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final inactive = !icon.isActive;
    return Opacity(
      opacity: inactive ? 0.6 : 1,
      child: AdminCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Önizleme: açık harita zemini, gerçek boyuta yakın.
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF2F1ED),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: icon.isVehicle
                          ? SehiriciVehicleIcon(
                              icon: icon,
                              color: sampleColor,
                              height: 92 * icon.scale.clamp(0.6, 1.3),
                              rotationDegrees: 18,
                            )
                          : SehiriciStopIcon(
                              icon: icon,
                              lineColors: [sampleColor],
                              height: 78 * icon.scale.clamp(0.6, 1.3),
                            ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          if (icon.isDefault)
                            const AdminBadge(
                              label: 'Varsayılan',
                              color: Color(0xFF16A34A),
                              icon: Icons.star_rounded,
                            ),
                          if (inactive)
                            const AdminBadge(
                              label: 'Pasif',
                              color: Color(0xFFD97706),
                            ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Icon(
                        icon.hasImage
                            ? Icons.image_rounded
                            : Icons.auto_awesome_rounded,
                        size: 16,
                        color: AdminUi.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    icon.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${icon.hasImage ? 'Özel görsel' : 'Hazır çizim'}'
                    '${icon.isBuiltin ? ' · Yerleşik' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: AdminUi.muted,
                        fontWeight: FontWeight.w600),
                  ),
                  // Araç kartlarında hep ikinci bir satır: kartlar aynı
                  // yükseklikte, görsel alanları hizalı kalır.
                  if (icon.isVehicle) ...[
                    const SizedBox(height: 3),
                    usedBy.isEmpty
                        ? const Text('Hiçbir hat kullanmıyor',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11.5,
                                color: AdminUi.muted,
                                fontWeight: FontWeight.w600))
                        : Text('${usedBy.length} hat kullanıyor',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11.5,
                                color: AdminUi.brand,
                                fontWeight: FontWeight.w800)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
