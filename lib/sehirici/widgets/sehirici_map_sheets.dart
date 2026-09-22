import 'package:flutter/material.dart';

import '../../core/theme/app_map_style.dart';
import '../../core/utils/map_vehicle_painters.dart';
import '../models/sehirici_models.dart';
import '../utils/sehirici_arrivals.dart';
import '../utils/sehirici_route_geometry.dart';
import 'sehirici_common_widgets.dart';

/// Haritadaki alt sayfaların ortak çerçevesi: yuvarlak üst köşe, tutamaç,
/// güvenli alan boşluğu.
class SehiriciSheetFrame extends StatelessWidget {
  final Widget child;
  const SehiriciSheetFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4.5,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

TextStyle _muted(BuildContext context, {double size = 12.5, FontWeight? w}) =>
    TextStyle(
      fontSize: size,
      fontWeight: w,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
    );

// ─────────────────────────────────────────────────────────────
// Durak
// ─────────────────────────────────────────────────────────────

/// Durağa dokunulunca açılan alt sayfa: durak bilgisi + bu duraktan geçen
/// hatların CANLI varış süreleri.
class SehiriciStopSheet extends StatelessWidget {
  final String stopId;
  final String name;
  final String? code;
  final String? address;

  /// Bu duraktan geçen hatlar (boşsa henüz hiçbir hatta bağlı değil).
  final List<SehiriciLine> lines;

  /// Şehirdeki tüm aktif seferler; ilgili olanlar burada süzülür.
  final List<SehiriciActiveTrip> trips;

  /// null → favori yıldızı gösterilmez.
  final bool? isFavorite;
  final VoidCallback? onToggleFavorite;
  final ValueChanged<SehiriciLine>? onLineTap;
  final VoidCallback? onDirections;

  const SehiriciStopSheet({
    super.key,
    required this.stopId,
    required this.name,
    this.code,
    this.address,
    required this.lines,
    required this.trips,
    this.isFavorite,
    this.onToggleFavorite,
    this.onLineTap,
    this.onDirections,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final arrivals =
        arrivalsForStop(stopId: stopId, lines: lines, trips: trips);
    final colors = lines.map((l) => l.color).take(3).toList();

    return SehiriciSheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 40,
                child: Center(
                  child: SehiriciStopIcon(height: 54, lineColors: colors),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (code != null && code!.isNotEmpty)
                          SehiriciStatusPill(
                            label: 'Kod $code',
                            color: kStopBlue,
                            dense: true,
                          ),
                        Text(
                          lines.isEmpty
                              ? 'Henüz bir hatta bağlı değil'
                              : '${lines.length} hat geçiyor',
                          style: _muted(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isFavorite != null)
                IconButton(
                  tooltip: isFavorite! ? 'Favoriden çıkar' : 'Favorilere ekle',
                  onPressed: onToggleFavorite,
                  icon: Icon(
                    isFavorite! ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: isFavorite! ? Colors.amber.shade600 : null,
                    size: 28,
                  ),
                ),
            ],
          ),
          if (address != null && address!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.place_outlined,
                    size: 17,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
                const SizedBox(width: 6),
                Expanded(child: Text(address!, style: _muted(context, size: 13))),
              ],
            ),
          ],
          if (lines.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              'YAKLAŞAN ARAÇLAR',
              style: _muted(context, size: 11, w: FontWeight.w800)
                  .copyWith(letterSpacing: 0.8),
            ),
            const SizedBox(height: 8),
            for (final line in lines)
              _LineArrivalRow(
                line: line,
                arrival: _bestFor(line, arrivals),
                anyPassed: arrivals.any((a) => a.line.id == line.id && a.passed),
                onTap: onLineTap == null ? null : () => onLineTap!(line),
              ),
          ],
          if (onDirections != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onDirections,
                icon: const Icon(Icons.directions_walk_rounded, size: 19),
                label: const Text('Yürüyerek yol tarifi'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Hattın durağa henüz gelmemiş en yakın aracı (yoksa null).
  static SehiriciStopArrival? _bestFor(
    SehiriciLine line,
    List<SehiriciStopArrival> arrivals,
  ) {
    for (final a in arrivals) {
      if (a.line.id == line.id && !a.passed) return a;
    }
    return null;
  }
}

class _LineArrivalRow extends StatelessWidget {
  final SehiriciLine line;
  final SehiriciStopArrival? arrival;
  final bool anyPassed;
  final VoidCallback? onTap;

  const _LineArrivalRow({
    required this.line,
    required this.arrival,
    required this.anyPassed,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                SehiriciLineBadge.forLine(line, height: 30, minWidth: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.name.isEmpty ? 'Hat ${line.code}' : line.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(_subtitle(), style: _muted(context, size: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SehiriciVehicleIcon.forLine(line, height: 34),
                const SizedBox(width: 10),
                _trailing(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    final a = arrival;
    if (a == null) {
      return anyPassed ? 'Araç bu durağı geçti' : 'Şu an aktif sefer yok';
    }
    if (a.onBreak) return 'Araç molada';
    if (a.trip.nextStopName != null) {
      return 'Sıradaki: ${a.trip.nextStopName}';
    }
    return 'Yolda';
  }

  Widget _trailing(BuildContext context) {
    final a = arrival;
    if (a == null || a.onBreak || a.minutes == null) {
      return SizedBox(
        width: 54,
        child: Text(
          a?.onBreak == true ? 'Mola' : '—',
          textAlign: TextAlign.center,
          style: _muted(context, size: 13, w: FontWeight.w700),
        ),
      );
    }
    final soon = a.minutes! <= 2;
    final color = soon ? const Color(0xFF16A34A) : line.color;
    return Container(
      constraints: const BoxConstraints(minWidth: 54),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        formatArrivalMinutes(a.minutes!),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 14,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Araç
// ─────────────────────────────────────────────────────────────

/// Araca dokunulunca açılan alt sayfa.
class SehiriciTripSheet extends StatelessWidget {
  final SehiriciActiveTrip trip;
  final SehiriciLine line;

  /// Bu araç şu an takip ediliyor mu?
  final bool following;
  final VoidCallback? onFollow;
  final VoidCallback? onShowLine;

  const SehiriciTripSheet({
    super.key,
    required this.trip,
    required this.line,
    this.following = false,
    this.onFollow,
    this.onShowLine,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onBreak = trip.status == SehiriciTripStatus.paused;
    final speed = trip.currentSpeed;
    final heading = trip.currentHeading;
    final started = trip.startedAt?.toLocal();

    return SehiriciSheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 78,
                decoration: BoxDecoration(
                  color: line.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: SehiriciVehicleIcon.forLine(line, height: 64),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SehiriciLineBadge(
                          code: trip.lineCode.isEmpty ? line.code : trip.lineCode,
                          color: line.color,
                          height: 28,
                          minWidth: 46,
                        ),
                        const SizedBox(width: 8),
                        SehiriciStatusPill(
                          label: onBreak ? 'Molada' : 'Yolda',
                          color: onBreak
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF16A34A),
                          icon: onBreak
                              ? Icons.pause_circle_outline_rounded
                              : Icons.radio_button_checked_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      trip.lineName.isEmpty ? line.name : trip.lineName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                    if (trip.driverName != null) ...[
                      const SizedBox(height: 3),
                      Text('Şoför: ${trip.driverName}', style: _muted(context)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.speed_rounded,
                  label: 'Hız',
                  value: (speed != null && speed > 0.5)
                      ? '${speed.toStringAsFixed(0)} km/sa'
                      : 'Duruyor',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatTile(
                  icon: Icons.explore_outlined,
                  label: 'Yön',
                  value: (heading != null && heading > 0)
                      ? bearingToCardinal(heading)
                      : '—',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatTile(
                  icon: Icons.schedule_rounded,
                  label: 'Varış',
                  value: trip.etaMinutes != null
                      ? formatArrivalMinutes(trip.etaMinutes!)
                      : '—',
                ),
              ),
            ],
          ),
          if (trip.nextStopName != null) ...[
            const SizedBox(height: 10),
            _InfoRow(
              icon: Icons.flag_rounded,
              iconColor: line.color,
              text: 'Sıradaki durak: ${trip.nextStopName}',
            ),
          ],
          if (trip.licensePlate != null)
            _InfoRow(
              icon: Icons.confirmation_number_outlined,
              text: 'Plaka: ${trip.licensePlate}',
            ),
          if (trip.workingHoursStart != null && trip.workingHoursEnd != null)
            _InfoRow(
              icon: Icons.access_time_rounded,
              text: 'Çalışma saatleri: '
                  '${trip.workingHoursStart!.format(context)} – '
                  '${trip.workingHoursEnd!.format(context)}',
            ),
          if (started != null)
            _InfoRow(
              icon: Icons.play_circle_outline_rounded,
              text: 'Sefer ${_hhmm(started)}\'den beri sürüyor',
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onFollow,
                  icon: Icon(
                    following
                        ? Icons.gps_fixed_rounded
                        : Icons.my_location_rounded,
                    size: 19,
                  ),
                  label: Text(following ? 'Takip ediliyor' : 'Takip et'),
                  style: FilledButton.styleFrom(
                    backgroundColor: line.color,
                    foregroundColor: sehiriciOnColor(line.color),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              if (onShowLine != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onShowLine,
                    icon: const Icon(Icons.alt_route_rounded, size: 19),
                    label: const Text('Hattı göster'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon,
                  size: 15,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _muted(context, size: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String text;

  const _InfoRow({required this.icon, required this.text, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        children: [
          Icon(icon,
              size: 18,
              color: iconColor ??
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55)),
          const SizedBox(width: 9),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5))),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Katmanlar
// ─────────────────────────────────────────────────────────────

/// Haritanın "Katmanlar" sayfası: zemin türü, açık/koyu görünüm, trafik ve
/// durak adları.
class SehiriciMapLayersSheet extends StatelessWidget {
  final ValueNotifier<bool> traffic;
  final ValueNotifier<bool> stopLabels;

  const SehiriciMapLayersSheet({
    super.key,
    required this.traffic,
    required this.stopLabels,
  });

  @override
  Widget build(BuildContext context) {
    return SehiriciSheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Harita katmanları',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          _SectionLabel('HARİTA TÜRÜ'),
          ValueListenableBuilder<MapBaseType>(
            valueListenable: MapTypePreference.choice,
            builder: (context, type, _) => Row(
              children: [
                for (final t in MapBaseType.values) ...[
                  Expanded(
                    child: _OptionCard(
                      selected: type == t,
                      icon: t == MapBaseType.standard
                          ? Icons.map_outlined
                          : Icons.satellite_alt_rounded,
                      label: MapTypePreference.labelOf(t),
                      onTap: () => MapTypePreference.set(t),
                    ),
                  ),
                  if (t != MapBaseType.values.last) const SizedBox(width: 10),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionLabel('GÖRÜNÜM'),
          ValueListenableBuilder<MapThemeChoice>(
            valueListenable: MapThemePreference.choice,
            builder: (context, choice, _) => Row(
              children: [
                for (final c in MapThemeChoice.values) ...[
                  Expanded(
                    child: _OptionCard(
                      selected: choice == c,
                      icon: MapThemePreference.iconOf(c),
                      label: MapThemePreference.labelOf(c),
                      onTap: () => MapThemePreference.set(c),
                    ),
                  ),
                  if (c != MapThemeChoice.values.last) const SizedBox(width: 10),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<bool>(
            valueListenable: stopLabels,
            builder: (context, on, _) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: on,
              onChanged: (v) => stopLabels.value = v,
              title: const Text('Durak adları',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Yakınlaşınca durak isimlerini göster'),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: traffic,
            builder: (context, on, _) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: on,
              onChanged: (v) => traffic.value = v,
              title: const Text('Trafik durumu',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Yoldaki yoğunluğu renklerle göster'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: _muted(context, size: 11, w: FontWeight.w800)
              .copyWith(letterSpacing: 0.8),
        ),
      );
}

class _OptionCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _OptionCard({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    return Material(
      color: selected
          ? accent.withValues(alpha: 0.12)
          : scheme.onSurface.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? accent : Colors.transparent,
              width: 1.6,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: selected ? accent : scheme.onSurface, size: 24),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? accent : scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
