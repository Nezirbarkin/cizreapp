import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/music_track.dart';
import 'music_ui.dart';

/// "Hangi 15 saniye?" — şarkının hangi bölümünün iliştirileceğini seçtirir.
///
/// ## Neden gerçek bir dalga biçimi değil
///
/// Gerçek dalga biçimi çizmek şarkının tamamını çözümlemeyi (decode) gerektirir;
/// bu da ya yeni bir native bağımlılık ya da telefonu birkaç saniye meşgul eden
/// bir iş demek. Buradaki çubuklar SÜSTÜR ve öyle davranırlar: sabit bir
/// üreteçten gelirler, yeniden çizimde zıplamazlar, hiçbir veri iddia etmezler.
/// Kullanıcının gerçekten ihtiyacı olan geri bildirim — "şu an neresi çalıyor" —
/// önizleme düğmesiyle veriliyor, çizimle değil.
///
/// ## Süre bilinmiyorsa
///
/// MP3 olmayan dosyalarda süreyi paketsiz ölçemiyoruz. O durumda çubuk
/// devre dışı kalır ve başlangıç 0 olur: kullanıcıya yalan bir ölçek
/// göstermektense seçimi baştan almak dürüst olan.
class MusicTrimBar extends StatefulWidget {
  /// Şarkının toplam süresi. Bilinmiyorsa null.
  final int? totalMs;

  /// Seçili pencerenin başlangıcı.
  final int startMs;

  /// Pencere uzunluğu — ürün kararı gereği 15 saniye.
  final int windowMs;

  final ValueChanged<int> onChanged;

  /// Önizleme çalıyor mu? (düğmenin ikonu)
  final bool previewing;
  final VoidCallback? onPreviewTap;

  const MusicTrimBar({
    super.key,
    required this.totalMs,
    required this.startMs,
    required this.windowMs,
    required this.onChanged,
    this.previewing = false,
    this.onPreviewTap,
  });

  @override
  State<MusicTrimBar> createState() => _MusicTrimBarState();
}

class _MusicTrimBarState extends State<MusicTrimBar> {
  static const double _barHeight = 56;

  /// Sürüklemenin başladığı andaki başlangıç — parmağın gittiği yere değil,
  /// GİTTİĞİ KADAR kaydırmak için. Aksi hâlde pencere parmağın altına zıplardı.
  int _dragAnchorMs = 0;
  double _dragAnchorDx = 0;

  /// Kaydırılabilir en son başlangıç: pencere şarkının sonunu aşmasın.
  int get _maxStart {
    final total = widget.totalMs;
    if (total == null) return 0;
    final max = total - widget.windowMs;
    return max > 0 ? max : 0;
  }

  bool get _enabled => (widget.totalMs ?? 0) > widget.windowMs;

  void _applyDelta(double dx, double width) {
    if (!_enabled || width <= 0) return;
    final total = widget.totalMs!;
    final deltaMs = (dx / width * total).round();
    final next = (_dragAnchorMs + deltaMs).clamp(0, _maxStart);
    if (next != widget.startMs) widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = widget.totalMs;
    final start = widget.startMs.clamp(0, math.max(_maxStart, 0)).toInt();
    final end = start + widget.windowMs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Hangi ${(widget.windowMs / 1000).round()} saniye?',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              _enabled
                  ? '${formatDuration(start)} – ${formatDuration(end)}'
                  : 'baştan',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final fraction = (total == null || total <= 0)
                ? 0.0
                : start / total;
            final windowFraction = (total == null || total <= 0)
                ? 1.0
                : (widget.windowMs / total).clamp(0.08, 1.0);

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (d) {
                if (!_enabled) return;
                HapticFeedback.selectionClick();
                _dragAnchorMs = widget.startMs;
                _dragAnchorDx = d.localPosition.dx;
              },
              onHorizontalDragUpdate: (d) =>
                  _applyDelta(d.localPosition.dx - _dragAnchorDx, width),
              onTapDown: (d) {
                if (!_enabled || total == null) return;
                // Dokunulan nokta pencerenin ORTASI olsun; kullanıcı
                // "şurayı istiyorum" diye düşünür, "şuradan başlasın" diye değil.
                final centerMs = (d.localPosition.dx / width * total).round();
                final next = (centerMs - widget.windowMs ~/ 2).clamp(
                  0,
                  _maxStart,
                );
                widget.onChanged(next);
              },
              child: Container(
                height: _barHeight,
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? Colors.white10
                      : Colors.black.withValues(alpha: 0.04),
                  borderRadius: MusicUI.radius,
                ),
                clipBehavior: Clip.antiAlias,
                child: CustomPaint(
                  painter: _TrimPainter(
                    startFraction: fraction,
                    windowFraction: windowFraction,
                    enabled: _enabled,
                    baseColor: theme.brightness == Brightness.dark
                        ? Colors.white24
                        : Colors.black26,
                  ),
                  size: Size(width, _barHeight),
                ),
              ),
            );
          },
        ),
        if (widget.onPreviewTap != null) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: widget.onPreviewTap,
              icon: Icon(
                widget.previewing
                    ? Icons.stop_rounded
                    : Icons.play_arrow_rounded,
                size: 18,
              ),
              label: Text(widget.previewing ? 'Durdur' : 'Önizle'),
            ),
          ),
        ],
      ],
    );
  }
}

class _TrimPainter extends CustomPainter {
  final double startFraction;
  final double windowFraction;
  final bool enabled;
  final Color baseColor;

  const _TrimPainter({
    required this.startFraction,
    required this.windowFraction,
    required this.enabled,
    required this.baseColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const barWidth = 3.0;
    const gap = 3.0;
    final step = barWidth + gap;
    final count = (size.width / step).floor();

    final windowLeft = size.width * startFraction;
    final windowWidth = size.width * windowFraction;
    final windowRight = windowLeft + windowWidth;

    if (enabled) {
      // Seçili pencerenin zemini — çubuklardan ÖNCE çiziliyor ki çubuklar
      // üstünde kalsın.
      canvas.drawRect(
        Rect.fromLTWH(windowLeft, 0, windowWidth, size.height),
        Paint()..color = MusicUI.tint,
      );
    }

    final paint = Paint()..strokeCap = StrokeCap.round;

    for (var i = 0; i < count; i++) {
      final x = i * step + barWidth / 2 + gap / 2;
      // Sabit sözde-rastgele yükseklik: aynı i her zaman aynı yüksekliği
      // verir, böylece widget yeniden çizilince çubuklar titremez.
      final h = _heightAt(i, size.height);
      final inWindow = enabled && x >= windowLeft && x <= windowRight;

      paint
        ..color = inWindow ? MusicUI.accent : baseColor
        ..strokeWidth = barWidth;

      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        paint,
      );
    }
  }

  double _heightAt(int i, double maxHeight) {
    // Üç farklı frekansın toplamı: düzenli bir desene benzemeyen ama
    // tamamen belirlenimci bir profil.
    final v =
        math.sin(i * 0.7) * 0.5 +
        math.sin(i * 0.23 + 1.3) * 0.3 +
        math.sin(i * 1.9 + 0.4) * 0.2;
    final normalized = (v + 1) / 2; // 0..1
    return (maxHeight * 0.25) + normalized * (maxHeight * 0.55);
  }

  @override
  bool shouldRepaint(_TrimPainter old) =>
      old.startFraction != startFraction ||
      old.windowFraction != windowFraction ||
      old.enabled != enabled ||
      old.baseColor != baseColor;
}
