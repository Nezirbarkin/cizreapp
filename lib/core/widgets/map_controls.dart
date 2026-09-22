import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_map_style.dart';

/// Haritalar üzerinde kullanılan ortak "cam" (frosted glass) kontrolleri.
///
/// Google'ın gömülü `zoomControlsEnabled` butonları platforma göre değişen,
/// eski görünümlü gri kutulardır ve tema ile uyumsuzdur. Harita ekranlarında
/// onları kapatıp buradaki kontrolleri kullanıyoruz: tüm haritalarda aynı
/// yuvarlatılmış, bulanık zeminli, ince kenarlıklı görünüm.

/// Tek bir yüzen cam buton (zoom +/‑, konumuma git, tam ekran …).
class MapGlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  /// Butonun kenar uzunluğu.
  final double size;

  /// İkon rengi — verilmezse temaya göre otomatik seçilir.
  /// Vurgulu bir eylem için (ör. aktif çizim modu) tema rengi verilebilir.
  final Color? iconColor;

  /// İkonun altında/yerinde dönen bir yükleniyor göstergesi çizer.
  final bool busy;

  const MapGlassButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 42,
    this.iconColor,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = iconColor ?? (isDark ? Colors.white : const Color(0xFF1F2937));
    final disabled = onPressed == null || busy;

    final button = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: (isDark ? Colors.black : Colors.white)
                .withValues(alpha: isDark ? 0.55 : 0.82),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: (isDark ? Colors.white : Colors.black)
                  .withValues(alpha: isDark ? 0.12 : 0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: disabled ? null : onPressed,
              child: SizedBox(
                width: size,
                height: size,
                child: Center(
                  child: busy
                      ? SizedBox(
                          width: size * 0.42,
                          height: size * 0.42,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(fg),
                          ),
                        )
                      : Icon(
                          icon,
                          size: size * 0.48,
                          color: disabled ? fg.withValues(alpha: 0.4) : fg,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// Harita görünümünü Otomatik → Açık → Koyu arasında çeviren cam düğme.
///
/// Tercih [MapThemePreference] üzerinde cihaz yereli olarak saklanır; admin
/// panelindeki haritalarda bu düğme vardır ve seçim tüm haritalara uygulanır.
/// Haritanın seçimi anında uygulaması için [MapStyleBuilder] ile sarılması
/// gerekir.
class MapThemeToggleButton extends StatelessWidget {
  final double size;

  const MapThemeToggleButton({super.key, this.size = 42});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MapThemeChoice>(
      valueListenable: MapThemePreference.choice,
      builder: (context, choice, _) => MapGlassButton(
        icon: MapThemePreference.iconOf(choice),
        size: size,
        tooltip: 'Harita görünümü: ${MapThemePreference.labelOf(choice)}'
            ' (değiştir)',
        onPressed: MapThemePreference.cycle,
      ),
    );
  }
}

/// Harita zeminini Standart ↔ Uydu arasında çeviren cam düğme.
///
/// Tercih [MapTypePreference] üzerinde cihaz yereli saklanır. Haritanın
/// seçimi anında uygulaması için `mapType`'ı [MapTypePreference.choice]
/// ile besleyin (bkz. şehiriçi canlı harita).
class MapBaseTypeToggleButton extends StatelessWidget {
  final double size;

  const MapBaseTypeToggleButton({super.key, this.size = 42});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MapBaseType>(
      valueListenable: MapTypePreference.choice,
      builder: (context, type, _) => MapGlassButton(
        icon: MapTypePreference.iconOf(type),
        size: size,
        tooltip: 'Harita türü: ${MapTypePreference.labelOf(type)} (değiştir)',
        onPressed: MapTypePreference.toggle,
      ),
    );
  }
}

/// Buzlu cam yüzey: çip şeridi, durum hapı ve bilgi kartları için ortak zemin.
class MapGlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Zemin opaklığı; yoğun içerik (yazı) için yükseltilir.
  final double? opacity;

  const MapGlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.radius = 16,
    this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: (isDark ? const Color(0xFF12151A) : Colors.white)
                .withValues(alpha: opacity ?? (isDark ? 0.72 : 0.86)),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: (isDark ? Colors.white : Colors.black)
                  .withValues(alpha: isDark ? 0.12 : 0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Dikey cam buton yığını — butonlar arasında tutarlı boşluk bırakır.
class MapGlassControls extends StatelessWidget {
  final List<Widget> children;
  final double spacing;

  const MapGlassControls({
    super.key,
    required this.children,
    this.spacing = 8,
  });

  @override
  Widget build(BuildContext context) {
    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) spaced.add(SizedBox(height: spacing));
      spaced.add(children[i]);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: spaced);
  }
}

/// Zoom +/‑ ikilisi. Hemen her haritada aynı şekilde tekrar ediyordu.
class MapZoomControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final double size;

  /// Zoom düğmelerinin üstüne harita görünümü (Otomatik/Açık/Koyu) düğmesini
  /// de ekler. Admin haritalarında açıktır.
  final bool showThemeToggle;

  const MapZoomControls({
    super.key,
    required this.onZoomIn,
    required this.onZoomOut,
    this.size = 42,
    this.showThemeToggle = false,
  });

  @override
  Widget build(BuildContext context) {
    return MapGlassControls(
      children: [
        if (showThemeToggle) MapThemeToggleButton(size: size),
        MapGlassButton(
          icon: Icons.add,
          tooltip: 'Yakınlaştır',
          onPressed: onZoomIn,
          size: size,
        ),
        MapGlassButton(
          icon: Icons.remove,
          tooltip: 'Uzaklaştır',
          onPressed: onZoomOut,
          size: size,
        ),
      ],
    );
  }
}

/// Harita üstünde ipucu/bilgi gösteren cam şerit.
///
/// Eskiden bu iş `Colors.black.withValues(alpha: 0.45)` dolgulu, köşesiz,
/// haritanın tamamına yapışan bir şeritle yapılıyordu; bu sürüm yüzen,
/// yuvarlatılmış ve tema ile uyumlu.
class MapHintBar extends StatelessWidget {
  final String text;
  final IconData icon;

  /// Verilirse şeridin sağında bir kapatma (×) düğmesi çizilir.
  final VoidCallback? onDismiss;

  /// Vurgulu (ör. aktif çizim modu) görünüm için dolgu rengi.
  final Color? accentColor;

  const MapHintBar({
    super.key,
    required this.text,
    this.icon = Icons.touch_app,
    this.onDismiss,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = accentColor;
    final bg = accent != null
        ? accent.withValues(alpha: 0.92)
        : (isDark ? Colors.black : Colors.white)
            .withValues(alpha: isDark ? 0.6 : 0.85);
    final fg = accent != null
        ? Colors.white
        : (isDark ? Colors.white : const Color(0xFF1F2937));

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: EdgeInsets.fromLTRB(12, 9, onDismiss != null ? 4 : 12, 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: (isDark ? Colors.white : Colors.black)
                  .withValues(alpha: isDark ? 0.12 : 0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: fg),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  icon: Icon(Icons.close, size: 16, color: fg),
                  onPressed: onDismiss,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  tooltip: 'Kapat',
                ),
            ],
          ),
        ),
      ),
    );
  }
}
