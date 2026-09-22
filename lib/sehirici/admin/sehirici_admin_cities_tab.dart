import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/admin/widgets/admin_ui.dart';
import '../models/sehirici_models.dart';
import '../providers/sehirici_provider.dart';
import '../services/sehirici_errors.dart';
import '../widgets/sehirici_common_widgets.dart';
import 'sehirici_admin_controller.dart';
import 'sehirici_admin_kit.dart';
import 'sehirici_city_editor_sheet.dart';

/// Admin > Şehiriçi > Şehirler.
class SehiriciAdminCitiesTab extends StatelessWidget {
  final SehiriciAdminController controller;
  const SehiriciAdminCitiesTab({super.key, required this.controller});

  Future<void> _edit(BuildContext context, [SehiriciCity? city]) async {
    final changed =
        await showSehiriciCityEditor(context, controller: controller, city: city);
    if (changed && context.mounted) {
      sehiriciSnack(context, city == null ? 'Şehir eklendi.' : 'Şehir güncellendi.');
    }
  }

  Future<void> _toggle(BuildContext context, SehiriciCity city, bool value) async {
    try {
      await controller.cityService.saveCity(SehiriciCity(
        id: city.id,
        name: city.name,
        slug: city.slug,
        centerLat: city.centerLat,
        centerLng: city.centerLng,
        zoomLevel: city.zoomLevel,
        isActive: value,
      ));
      await controller.reloadCities();
      try {
        if (context.mounted) context.read<SehiriciProvider>().invalidateAllCaches();
      } catch (_) {}
    } catch (e) {
      if (context.mounted) sehiriciSnack(context, sehiriciErrorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final cities = controller.cities;
        return SehiriciAsyncBody(
          loading: controller.loadingCities && cities.isEmpty,
          error: cities.isEmpty ? controller.cityError : null,
          onRetry: controller.reloadCities,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _edit(context),
                    icon: const Icon(Icons.add_location_alt_rounded, size: 20),
                    label: const Text('Yeni Şehir'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AdminUi.brand,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: cities.isEmpty
                    ? const AdminEmpty(
                        icon: Icons.location_city_rounded,
                        title: 'Henüz şehir yok',
                        subtitle: 'Şehiriçi servisler için ilk şehri ekleyin.',
                      )
                    : RefreshIndicator(
                        onRefresh: controller.reloadCities,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                          itemCount: cities.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, i) {
                            final city = cities[i];
                            final selected = city.id == controller.cityId;
                            return AdminCard(
                              onTap: () => _edit(context, city),
                              borderColor:
                                  selected ? AdminUi.brand.withValues(alpha: 0.5) : null,
                              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: AdminUi.brandSoft,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(Icons.location_city_rounded,
                                        color: AdminUi.brand),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(city.name,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.w800)),
                                            ),
                                            if (selected) ...[
                                              const SizedBox(width: 8),
                                              AdminBadge(
                                                  label: 'Seçili',
                                                  color: AdminUi.brand),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${city.centerLat.toStringAsFixed(4)}, '
                                          '${city.centerLng.toStringAsFixed(4)} · '
                                          'yakınlık ${city.zoomLevel}',
                                          style: const TextStyle(
                                              fontSize: 12.5, color: AdminUi.muted),
                                        ),
                                        const SizedBox(height: 2),
                                        Text('/${city.slug}',
                                            style: const TextStyle(
                                                fontSize: 12, color: AdminUi.muted)),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: city.isActive,
                                    onChanged: (v) => _toggle(context, city, v),
                                    activeTrackColor: AdminUi.brand,
                                    activeThumbColor: Colors.white,
                                  ),
                                ],
                              ),
                            );
                          },
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
