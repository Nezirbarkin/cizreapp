import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/utils/map_vehicle_painters.dart';
import '../../core/widgets/map_vehicle_thumb.dart';
import '../models/sehirici_icon_models.dart';
import '../models/sehirici_models.dart';
import '../services/sehirici_icon_catalog.dart';

/// Renk üzerindeki yazı rengi: açık zeminde koyu, koyu zeminde beyaz.
Color sehiriciOnColor(Color background) =>
    background.computeLuminance() > 0.62
        ? const Color(0xFF111827)
        : Colors.white;

/// "#RRGGBB" → [Color]; bozuksa [fallback].
Color sehiriciParseColor(String? hex,
    {Color fallback = const Color(0xFF1976D2)}) {
  if (hex == null) return fallback;
  final cleaned = hex.trim().replaceFirst('#', '');
  if (cleaned.length != 6) return fallback;
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return fallback;
  return Color(0xFF000000 | value);
}

/// Color → "#RRGGBB".
String sehiriciColorHex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Hat kodunu hat renginde yuvarlatılmış rozet olarak gösterir (durak
/// levhalarındaki hat numarası tabelası gibi).
class SehiriciLineBadge extends StatelessWidget {
  final String code;
  final Color color;
  final double height;
  final double? minWidth;

  const SehiriciLineBadge({
    super.key,
    required this.code,
    required this.color,
    this.height = 26,
    this.minWidth,
  });

  factory SehiriciLineBadge.forLine(SehiriciLine line,
          {Key? key, double height = 26, double? minWidth}) =>
      SehiriciLineBadge(
        key: key,
        code: line.code,
        color: line.color,
        height: height,
        minWidth: minWidth,
      );

  @override
  Widget build(BuildContext context) {
    final fg = sehiriciOnColor(color);
    // DİKKAT: Container'a `alignment` VERMEYİN — alignment'lı Container sınırlı
    // genişlikte (Wrap gibi) tüm genişliği kaplar ve rozet şeride dönüşür.
    // Ortalama, kendi boyunu küçülten Row ile yapılır.
    return Container(
      constraints: BoxConstraints(
        minWidth: minWidth ?? height * 1.25,
        minHeight: height,
      ),
      padding: EdgeInsets.symmetric(horizontal: height * 0.34),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(height * 0.32),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.32),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              code.isEmpty ? '—' : code,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w800,
                fontSize: height * 0.5,
                height: 1.0,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Haritadaki aracın küçük resmi: kütüphanedeki ikonu (hazır çizim ya da
/// yüklenmiş görsel) gösterir. Liste ve admin ekranlarında Material ikonu
/// yerine kullanılır — haritada görülenin aynısı.
class SehiriciVehicleIcon extends StatelessWidget {
  /// Hattın araç türü anahtarı. [icon] verilirse yok sayılır.
  final String? vehicleKey;
  final SehiriciMarkerIcon? icon;
  final Color color;
  final double height;

  /// Saat yönünde derece (yön demosu için).
  final double rotationDegrees;

  const SehiriciVehicleIcon({
    super.key,
    this.vehicleKey,
    this.icon,
    required this.color,
    this.height = 44,
    this.rotationDegrees = 0,
  });

  factory SehiriciVehicleIcon.forLine(SehiriciLine line,
          {Key? key, double height = 44}) =>
      SehiriciVehicleIcon(
        key: key,
        vehicleKey: line.vehicleKey,
        color: line.color,
        height: height,
      );

  @override
  Widget build(BuildContext context) {
    final catalog = SehiriciIconCatalog.instance;
    return ListenableBuilder(
      listenable: catalog,
      builder: (context, _) {
        final ic = icon ?? catalog.resolveVehicle(vehicleKey);
        return _VehicleImage(
          icon: ic,
          color: color,
          height: height,
          rotationDegrees: rotationDegrees,
        );
      },
    );
  }
}

class _VehicleImage extends StatelessWidget {
  final SehiriciMarkerIcon icon;
  final Color color;
  final double height;
  final double rotationDegrees;

  const _VehicleImage({
    required this.icon,
    required this.color,
    required this.height,
    required this.rotationDegrees,
  });

  @override
  Widget build(BuildContext context) {
    final painted = MapVehicleThumb(
      shape: icon.vehicleShape,
      color: color,
      height: height,
    );
    Widget child = painted;
    if (icon.hasImage) {
      child = SizedBox(
        height: height,
        child: RotatedBox(
          quarterTurns: (icon.imageRotation ~/ 90) % 4,
          child: Image.network(
            icon.imageUrl!,
            height: height,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            // Görsel açılmazsa harita gibi hazır çizime düş.
            errorBuilder: (_, __, ___) => painted,
            loadingBuilder: (_, image, progress) =>
                progress == null ? image : painted,
          ),
        ),
      );
    }
    if (rotationDegrees != 0) {
      child = Transform.rotate(
        angle: rotationDegrees * math.pi / 180,
        child: child,
      );
    }
    return child;
  }
}

/// Durak ikonunun küçük resmi (varsayılan durak ikonu ya da verilen ikon).
class SehiriciStopIcon extends StatelessWidget {
  final SehiriciMarkerIcon? icon;
  final MapStopState state;
  final List<Color> lineColors;
  final double height;

  const SehiriciStopIcon({
    super.key,
    this.icon,
    this.state = MapStopState.normal,
    this.lineColors = const [],
    this.height = 48,
  });

  @override
  Widget build(BuildContext context) {
    final catalog = SehiriciIconCatalog.instance;
    return ListenableBuilder(
      listenable: catalog,
      builder: (context, _) {
        final ic = icon ?? catalog.stopIcon;
        if (ic.hasImage) {
          return SizedBox(
            height: height,
            child: RotatedBox(
              quarterTurns: (ic.imageRotation ~/ 90) % 4,
              child: Image.network(
                ic.imageUrl!,
                height: height,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => MapStopThumb(
                  style: ic.stopStyle,
                  state: state,
                  lineColors: lineColors,
                  height: height,
                ),
              ),
            ),
          );
        }
        return MapStopThumb(
          style: ic.stopStyle,
          state: state,
          lineColors: lineColors,
          height: height,
        );
      },
    );
  }
}

/// "CANLI" göstergesi: nabız atan yeşil nokta + metin.
class SehiriciLiveDot extends StatefulWidget {
  final Color color;
  final double size;
  final bool pulsing;

  const SehiriciLiveDot({
    super.key,
    this.color = const Color(0xFF22C55E),
    this.size = 8,
    this.pulsing = true,
  });

  @override
  State<SehiriciLiveDot> createState() => _SehiriciLiveDotState();
}

class _SehiriciLiveDotState extends State<SehiriciLiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant SehiriciLiveDot old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.pulsing && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 2.4,
      height: s * 2.4,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = widget.pulsing ? _controller.value : 0.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.pulsing)
                Container(
                  width: s + s * 1.4 * t,
                  height: s + s * 1.4 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.35 * (1 - t)),
                  ),
                ),
              Container(
                width: s,
                height: s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Küçük durum hapı ("Yolda", "Mola", "Rota yok" …).
class SehiriciStatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool dense;

  const SehiriciStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 9,
        vertical: dense ? 2.5 : 3.5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: dense ? 10.5 : 11.5,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bölüm başlığı: büyük harfli küçük etiket + isteğe bağlı sayaç/eylem.
class SehiriciSectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final Widget? action;

  const SehiriciSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// Özet kutusu: renkli ikon + büyük sayı + etiket.
class SehiriciStatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const SehiriciStatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

/// Küçük bilgi çipi: ikon + metin (süre, ücret, durak sayısı …).
class SehiriciMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const SehiriciMetaChip({
    super.key,
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = color ?? scheme.onSurface.withValues(alpha: 0.62);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: (color ?? scheme.onSurface).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
