import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_map_style.dart';
import '../../features/admin/widgets/admin_ui.dart';
import '../providers/sehirici_provider.dart';
import '../services/sehirici_errors.dart';
import 'sehirici_admin_controller.dart';
import 'sehirici_admin_kit.dart';

/// Admin > Şehiriçi > Ayarlar: modül, canlı konum, rota bakımı ve bu cihazın
/// harita görünümü.
class SehiriciAdminSettingsTab extends StatefulWidget {
  final SehiriciAdminController controller;
  const SehiriciAdminSettingsTab({super.key, required this.controller});

  @override
  State<SehiriciAdminSettingsTab> createState() =>
      _SehiriciAdminSettingsTabState();
}

class _SehiriciAdminSettingsTabState extends State<SehiriciAdminSettingsTab> {
  final Set<String> _saving = {};
  bool _routeBusy = false;

  SehiriciAdminController get c => widget.controller;

  void _refreshUserSide() {
    try {
      context.read<SehiriciProvider>().invalidateAllCaches();
    } catch (_) {}
  }

  Future<void> _save(String key, String value, {bool refreshUser = false}) async {
    if (_saving.contains(key)) return;
    setState(() => _saving.add(key));
    try {
      await c.updateSetting(key, value);
      if (refreshUser) _refreshUserSide();
    } catch (e) {
      if (mounted) sehiriciSnack(context, sehiriciErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  // ── Rota bakımı ──────────────────────────────────────────────

  Future<void> _sanitizeAll() async {
    setState(() => _routeBusy = true);
    try {
      final report = await c.lineService.sanitizeAllRoutePolylines();
      if (!mounted) return;
      if (report.isEmpty) {
        sehiriciSnack(context, 'Kayıtlı rotası olan hat yok.');
        return;
      }
      final changed = report.where((r) => r.saved).toList();
      if (changed.isEmpty) {
        sehiriciSnack(context, '${report.length} hat kontrol edildi, hepsi zaten temiz.');
      } else {
        final removed = changed.fold<int>(0, (s, r) => s + (r.before - r.after));
        sehiriciSnack(
          context,
          '${changed.length}/${report.length} hat temizlendi, $removed gürültülü nokta atıldı.',
        );
        await c.reloadCityData();
        _refreshUserSide();
      }
    } catch (e) {
      if (mounted) sehiriciSnack(context, 'Ayıklama başarısız: $e', error: true);
    } finally {
      if (mounted) setState(() => _routeBusy = false);
    }
  }

  Future<void> _clearAll() async {
    final lines = await c.lineService.getLinesWithRoute();
    if (!mounted) return;
    if (lines.isEmpty) {
      sehiriciSnack(context, 'Kayıtlı rotası olan hat yok.');
      return;
    }
    final ok = await sehiriciConfirm(
      context,
      icon: Icons.delete_sweep_rounded,
      title: 'Tüm rotalar silinsin mi?',
      message: '${lines.length} hattın kayıtlı rotası kalıcı olarak silinecek:\n\n'
          '${lines.map((l) => '• ${l.code} (${l.points.length} nokta)').join('\n')}\n\n'
          'Hatlar rotasız kalır ve haritada çizgi görünmez; her hattın rotası '
          'yeniden oluşturulmalıdır. Bu işlem geri alınamaz.',
      confirmLabel: 'Hepsini Sil',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _routeBusy = true);
    try {
      final result = await c.lineService.clearAllRoutePolylines();
      await c.reloadCityData();
      _refreshUserSide();
      if (mounted) {
        sehiriciSnack(
          context,
          result.failed == 0
              ? '${result.cleared} hattın rotası silindi.'
              : '${result.cleared} hat silindi, ${result.failed} hat başarısız.',
          error: result.failed > 0,
        );
      }
    } catch (e) {
      if (mounted) sehiriciSnack(context, 'Silme başarısız: $e', error: true);
    } finally {
      if (mounted) setState(() => _routeBusy = false);
    }
  }

  Future<void> _createMissingRoutes() async {
    final targets = c.linesNeedingRoute;
    if (targets.isEmpty) {
      sehiriciSnack(context, 'Rotası eksik ya da eski hat yok.');
      return;
    }
    final ok = await sehiriciConfirm(
      context,
      icon: Icons.auto_fix_high_rounded,
      title: '${targets.length} hat için rota oluşturulsun mu?',
      message: 'Duraklardan geçen gerçek yol rotaları otomatik hesaplanır:\n\n'
          '${targets.map((l) => '• ${l.code} — ${l.name}').join('\n')}',
      confirmLabel: 'Oluştur',
    );
    if (!ok || !mounted) return;
    setState(() => _routeBusy = true);
    final result = await c.createMissingRoutes();
    _refreshUserSide();
    if (!mounted) return;
    setState(() => _routeBusy = false);
    sehiriciSnack(
      context,
      result.failed.isEmpty
          ? '${result.done} hattın rotası oluşturuldu.'
          : '${result.done} hat tamamlandı, ${result.failed.length} hat başarısız: ${result.failed.join('; ')}',
      error: result.failed.isNotEmpty,
    );
  }

  // ── Arayüz ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final s = c.settings;
        if (s == null) {
          return SehiriciAsyncBody(
            loading: c.loadingSettings,
            error: null,
            child: AdminEmpty(
              icon: Icons.tune_rounded,
              title: 'Ayarlar okunamadı',
              action: FilledButton(
                onPressed: c.reloadSettings,
                child: const Text('Tekrar dene'),
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _SectionCard(
              title: 'Modül',
              icon: Icons.power_settings_new_rounded,
              children: [
                _SwitchRow(
                  title: 'Şehiriçi servisler açık',
                  subtitle: 'Kapalıyken uygulamada hiçbir kullanıcı bu özelliği görmez.',
                  value: s.moduleEnabled,
                  busy: _saving.contains('sehirici_module_enabled'),
                  onChanged: (v) => _save('sehirici_module_enabled', v.toString(),
                      refreshUser: true),
                ),
                const Divider(height: 1, color: AdminUi.line),
                _SwitchRow(
                  title: 'Kullanıcı favorileri',
                  subtitle: 'Kullanıcılar durakları favoriye ekleyip yaklaşma bildirimi alabilir.',
                  value: s.allowUserFavorites,
                  busy: _saving.contains('sehirici_allow_user_favorites'),
                  onChanged: (v) => _save('sehirici_allow_user_favorites', v.toString(),
                      refreshUser: true),
                ),
                const Divider(height: 1, color: AdminUi.line),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.location_city_rounded,
                          color: AdminUi.muted, size: 22),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Varsayılan şehir',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 14.5)),
                            Text('Uygulama açılınca gösterilecek şehir',
                                style: TextStyle(
                                    fontSize: 12.5, color: AdminUi.muted)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<String>(
                        value: c.cities.any((x) => x.id == s.defaultCityId)
                            ? s.defaultCityId
                            : '',
                        underline: const SizedBox.shrink(),
                        borderRadius: BorderRadius.circular(14),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('İlk şehir')),
                          for (final city in c.cities)
                            DropdownMenuItem(value: city.id, child: Text(city.name)),
                        ],
                        onChanged: _saving.contains('sehirici_default_city_id')
                            ? null
                            : (v) => _save('sehirici_default_city_id', v ?? '',
                                refreshUser: true),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            _SectionCard(
              title: 'Canlı konum',
              icon: Icons.gps_fixed_rounded,
              children: [
                _StepperRow(
                  title: 'Konum güncelleme aralığı',
                  subtitle: 'Şoför konumunu bu sıklıkta gönderir. Kısa aralık daha akıcı harita, daha çok pil/veri.',
                  value: s.locationUpdateIntervalSec,
                  unit: 'sn',
                  min: 5,
                  max: 60,
                  step: 5,
                  busy: _saving.contains('sehirici_location_update_interval_sec'),
                  onChanged: (v) =>
                      _save('sehirici_location_update_interval_sec', v.toString()),
                ),
                const Divider(height: 1, color: AdminUi.line),
                _StepperRow(
                  title: 'Varış süresi yenileme',
                  subtitle: 'Durak varış tahminlerinin yenilenme sıklığı.',
                  value: s.etaRefreshSeconds,
                  unit: 'sn',
                  min: 10,
                  max: 120,
                  step: 5,
                  busy: _saving.contains('sehirici_eta_refresh_seconds'),
                  onChanged: (v) =>
                      _save('sehirici_eta_refresh_seconds', v.toString()),
                ),
                const Divider(height: 1, color: AdminUi.line),
                _StepperRow(
                  title: 'Konum geçmişi saklama',
                  subtitle: 'Eski konum noktaları bu süreden sonra silinir.',
                  value: s.maxHistoryMinutes,
                  unit: 'dk',
                  min: 10,
                  max: 240,
                  step: 10,
                  busy: _saving.contains('sehirici_max_history_minutes'),
                  onChanged: (v) =>
                      _save('sehirici_max_history_minutes', v.toString()),
                ),
              ],
            ),
            _SectionCard(
              title: 'Hat rotaları',
              icon: Icons.route_rounded,
              children: [
                _SwitchRow(
                  title: 'Otomatik rota yazımı',
                  subtitle: 'Şoförün sürüşünden hat rotası üretilsin mi? Kapalıyken '
                      'rotalar yalnız admin tarafından oluşturulur — kirli rota oluşmaz.',
                  value: s.autoRouteEnabled,
                  busy: _saving.contains('sehirici_auto_route_enabled'),
                  onChanged: _routeBusy
                      ? null
                      : (v) => _save('sehirici_auto_route_enabled', v.toString(),
                          refreshUser: true),
                ),
                const Divider(height: 1, color: AdminUi.line),
                _ActionRow(
                  icon: Icons.auto_fix_high_rounded,
                  title: 'Eksik rotaları oluştur',
                  subtitle: 'Rotası olmayan veya eski kalan hatlar için duraklardan '
                      'geçen yol rotası hesaplar.',
                  busy: _routeBusy,
                  onTap: _createMissingRoutes,
                ),
                const Divider(height: 1, color: AdminUi.line),
                _ActionRow(
                  icon: Icons.cleaning_services_outlined,
                  title: 'Bozuk rotaları ayıkla',
                  subtitle: 'Rotaları silmez, temizler: üst üste binen noktaları ve '
                      'rotadan fırlayan hatalı fixleri atar.',
                  busy: _routeBusy,
                  onTap: _sanitizeAll,
                ),
                const Divider(height: 1, color: AdminUi.line),
                _ActionRow(
                  icon: Icons.delete_sweep_outlined,
                  title: 'Tüm rotaları sil',
                  subtitle: 'Bütün hatların kayıtlı rotasını kaldırır. Yeniden '
                      'oluşturulması gerekir.',
                  destructive: true,
                  busy: _routeBusy,
                  onTap: _clearAll,
                ),
              ],
            ),
            _SectionCard(
              title: 'Bu cihazdaki harita',
              icon: Icons.phone_android_rounded,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Görünüm',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<MapThemeChoice>(
                        valueListenable: MapThemePreference.choice,
                        builder: (_, choice, __) =>
                            SehiriciSegmented<MapThemeChoice>(
                          selected: choice,
                          onChanged: MapThemePreference.set,
                          items: [
                            for (final v in MapThemeChoice.values)
                              (
                                value: v,
                                label: MapThemePreference.labelOf(v),
                                icon: MapThemePreference.iconOf(v),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text('Harita türü',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<MapBaseType>(
                        valueListenable: MapTypePreference.choice,
                        builder: (_, type, __) => SehiriciSegmented<MapBaseType>(
                          selected: type,
                          onChanged: MapTypePreference.set,
                          items: [
                            for (final v in MapBaseType.values)
                              (
                                value: v,
                                label: MapTypePreference.labelOf(v),
                                icon: MapTypePreference.iconOf(v),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Bu tercihler yalnızca bu cihaza aittir; kullanıcıları etkilemez.',
                        style: TextStyle(fontSize: 12, color: AdminUi.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                Icon(icon, size: 16, color: AdminUi.brand),
                const SizedBox(width: 6),
                Text(
                  sehiriciUpper(title),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: AdminUi.muted,
                  ),
                ),
              ],
            ),
          ),
          AdminCard(padding: EdgeInsets.zero, child: Column(children: children)),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final bool busy;
  final ValueChanged<bool>? onChanged;

  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.fromLTRB(14, 4, 10, 4),
      value: value,
      onChanged: busy ? null : onChanged,
      activeTrackColor: AdminUi.brand,
      activeThumbColor: Colors.white,
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12.5, color: AdminUi.muted, height: 1.3)),
    );
  }
}

class _StepperRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final int value;
  final String unit;
  final int min;
  final int max;
  final int step;
  final bool busy;
  final ValueChanged<int> onChanged;

  const _StepperRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final canDec = !busy && value - step >= min;
    final canInc = !busy && value + step <= max;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14.5)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12.5, color: AdminUi.muted, height: 1.3)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: AdminUi.brandSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: canDec ? () => onChanged(value - step) : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                SizedBox(
                  width: 52,
                  child: busy
                      ? const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Text(
                          '$value $unit',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 13.5),
                        ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: canInc ? () => onChanged(value + step) : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool busy;
  final bool destructive;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.busy = false,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? const Color(0xFFDC2626) : AdminUi.ink;
    return InkWell(
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: color)),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12.5, color: AdminUi.muted, height: 1.3)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AdminUi.muted),
          ],
        ),
      ),
    );
  }
}
