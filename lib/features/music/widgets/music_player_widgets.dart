import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../okey/services/okey_sound_service.dart';
import '../models/music_track.dart';
import 'music_ui.dart';

/// Oynatıcı yüzeylerinin (Müziğim kartı, tam ekran oynatıcı) ortak parçaları.
///
/// Hepsi uygulamanın TEK ses motorunu ([OkeySoundService]) okur ve ona yazar;
/// kendi durumları yoktur. Bu yüzden yan menüdeki plak kartında, bildirim
/// panelinde ya da burada yapılan bir değişiklik diğerlerinde de görünür.

/// Koyu oynatıcı zemini. Açık temalı uygulamanın içinde oynatıcıyı ayrı bir
/// "sahne" gibi öne çıkarır; plak ve pembe etiket bu zeminde parlıyor.
const LinearGradient kPlayerGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF241127), Color(0xFF5B1242), Color(0xFFB5175F)],
  stops: [0.0, 0.55, 1.0],
);

// ---------------------------------------------------------------------------
// DÖNEN PLAK
// ---------------------------------------------------------------------------

/// Kapak yerine dönen bir plak.
///
/// Kullanıcının cihazındaki dosyaların çoğunda kapak görseli yok (ya da
/// okumak için yeni bir paket gerekir); boş gri bir kare yerine her şarkıda
/// aynı kimliği taşıyan bir plak çiziyoruz. YALNIZCA çalarken döner —
/// duraklatılmış müzikte dönen bir animasyon hem yanlış bilgi verir hem pil
/// yakar. [RepaintBoundary] dönüşü ekranın geri kalanından yalıtır.
class SpinningDisc extends StatefulWidget {
  final double size;
  final bool playing;

  const SpinningDisc({super.key, required this.size, required this.playing});

  @override
  State<SpinningDisc> createState() => _SpinningDiscState();
}

class _SpinningDiscState extends State<SpinningDisc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _spin.repeat();
  }

  @override
  void didUpdateWidget(SpinningDisc old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.playing && _spin.isAnimating) {
      // stop(): açıyı KORUR — devam edince plak kaldığı yerden döner.
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: RotationTransition(
          turns: _spin,
          child: const CustomPaint(painter: _DiscPainter()),
        ),
      ),
    );
  }
}

class _DiscPainter extends CustomPainter {
  const _DiscPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    // Gövde
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF2B2530), Color(0xFF0E0B11)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // Oluklar — ince, düşük opaklıklı halkalar.
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.6, r * 0.008)
      ..color = Colors.white.withValues(alpha: 0.06);
    for (var f = 0.42; f < 0.97; f += 0.07) {
      canvas.drawCircle(c, r * f, groove);
    }

    // Işık yansıması — dönen disk üstünde kayan bir parıltı.
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.8),
      -math.pi * 0.85,
      math.pi * 0.35,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.12
        ..color = Colors.white.withValues(alpha: 0.05),
    );

    // Etiket
    canvas.drawCircle(
      c,
      r * 0.34,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [MusicUI.accent, MusicUI.accentDeep],
        ).createShader(Rect.fromCircle(center: c, radius: r * 0.34)),
    );
    canvas.drawCircle(
      c,
      r * 0.2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, r * 0.012)
        ..color = Colors.white.withValues(alpha: 0.35),
    );

    // Merkez deliği
    canvas.drawCircle(c, r * 0.045, Paint()..color = const Color(0xFF0E0B11));
  }

  @override
  bool shouldRepaint(_DiscPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// İLERLEME ÇUBUĞU
// ---------------------------------------------------------------------------

/// Sürüklenebilir ilerleme çubuğu + geçen/toplam süre.
///
/// Konum saniyede birkaç kez güncellenir; yalnızca bu widget yeniden çizilir,
/// ekranın geri kalanı değil. Kullanıcı sürüklerken çubuk parmağı izler —
/// oynatıcıdan gelen konum ona üstün gelmez, yoksa bırakana kadar geri
/// zıplardı. Bırakınca motor o noktaya atlar.
class MusicSeekBar extends StatefulWidget {
  final Color activeColor;
  final Color inactiveColor;
  final Color labelColor;

  const MusicSeekBar({
    super.key,
    this.activeColor = Colors.white,
    this.inactiveColor = Colors.white24,
    this.labelColor = Colors.white70,
  });

  @override
  State<MusicSeekBar> createState() => _MusicSeekBarState();
}

class _MusicSeekBarState extends State<MusicSeekBar> {
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final sound = OkeySoundService.instance;

    return ValueListenableBuilder<({Duration position, Duration total})>(
      valueListenable: sound.musicProgress,
      builder: (context, value, _) {
        final total = value.total.inMilliseconds.toDouble();
        final known = total > 0;
        final pos = (_dragMs ?? value.position.inMilliseconds.toDouble()).clamp(
          0.0,
          known ? total : 0.0,
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: widget.activeColor,
                inactiveTrackColor: widget.inactiveColor,
                thumbColor: widget.activeColor,
                overlayColor: widget.activeColor.withValues(alpha: 0.12),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                trackShape: const _FullWidthTrackShape(),
              ),
              child: Slider(
                value: known ? pos : 0,
                max: known ? total : 1,
                onChanged: known ? (v) => setState(() => _dragMs = v) : null,
                onChangeEnd: known
                    ? (v) async {
                        HapticFeedback.selectionClick();
                        await sound.seekMusic(
                          Duration(milliseconds: v.round()),
                        );
                        if (mounted) setState(() => _dragMs = null);
                      }
                    : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Text(
                    known ? formatDuration(pos.round()) : '0:00',
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.labelColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    known
                        // Kalan süre: yaygın oynatıcıların sağ köşedeki
                        // "-1:24" gösterimi.
                        ? '-${formatDuration((total - pos).round())}'
                        : '--:--',
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.labelColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Kaydırıcının yatay dolgusunu kaldırır — çubuk, altındaki süre
/// yazılarıyla aynı kenardan başlayıp bitsin.
class _FullWidthTrackShape extends RoundedRectSliderTrackShape {
  const _FullWidthTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final height = sliderTheme.trackHeight ?? 3;
    final top = offset.dy + (parentBox.size.height - height) / 2;
    return Rect.fromLTWH(offset.dx, top, parentBox.size.width, height);
  }
}

// ---------------------------------------------------------------------------
// AKTARIM DENETİMLERİ
// ---------------------------------------------------------------------------

/// Karışık · Önceki · Çal/Duraklat · Sonraki · Tekrar.
///
/// Durum doğrudan motordan okunur; çağıran taraf `musicState` değişince
/// yeniden çizmekle yükümlü (Müziğim ekranı ve tam ekran oynatıcı zaten
/// dinliyor).
class MusicTransportControls extends StatelessWidget {
  /// Ortadaki düğmenin çapı; kenar düğmeleri buna göre ölçeklenir.
  final double playSize;

  const MusicTransportControls({super.key, this.playSize = 60});

  @override
  Widget build(BuildContext context) {
    final sound = OkeySoundService.instance;
    final playing = sound.isMusicPlaying;
    final multi = sound.musicTrackCount > 1;
    final side = playSize * 0.5;

    final repeat = sound.repeatMode;
    final repeatTip = switch (repeat) {
      MusicRepeatMode.all => 'Tekrar: tümü',
      MusicRepeatMode.one => 'Tekrar: bu şarkı',
      MusicRepeatMode.off => 'Tekrar kapalı',
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _ToggleIcon(
          icon: Icons.shuffle_rounded,
          active: sound.isShuffle,
          size: side * 0.9,
          tooltip: sound.isShuffle ? 'Karışık açık' : 'Karışık kapalı',
          onTap: sound.toggleShuffle,
        ),
        _PlainIcon(
          icon: Icons.skip_previous_rounded,
          size: side * 1.2,
          tooltip: 'Önceki',
          onTap: sound.hasMusic ? sound.previousTrack : null,
        ),
        _PlayButton(
          size: playSize,
          playing: playing,
          onTap: sound.hasMusic ? sound.togglePlayPause : null,
        ),
        _PlainIcon(
          icon: Icons.skip_next_rounded,
          size: side * 1.2,
          tooltip: 'Sonraki',
          onTap: multi ? sound.nextTrack : null,
        ),
        _ToggleIcon(
          icon: repeat == MusicRepeatMode.one
              ? Icons.repeat_one_rounded
              : Icons.repeat_rounded,
          active: repeat != MusicRepeatMode.off,
          size: side * 0.9,
          tooltip: repeatTip,
          onTap: sound.cycleRepeatMode,
        ),
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  final double size;
  final bool playing;
  final VoidCallback? onTap;

  const _PlayButton({required this.size, required this.playing, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: playing ? 'Duraklat' : 'Çal',
      child: GestureDetector(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.lightImpact();
                onTap!();
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: MusicUI.accentDeep.withValues(
                  alpha: playing ? 0.45 : 0.25,
                ),
                blurRadius: playing ? 22 : 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey(playing),
              size: size * 0.55,
              color: MusicUI.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlainIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final String tooltip;
  final VoidCallback? onTap;

  const _PlainIcon({
    required this.icon,
    required this.size,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      iconSize: size,
      color: Colors.white,
      disabledColor: Colors.white24,
      icon: Icon(icon),
    );
  }
}

/// Karışık / tekrar: açıkken marka renginde ve altında küçük bir nokta.
///
/// Nokta, yalnızca renkle anlatılan durumu renk körlüğüne dayanıklı kılar
/// — yaygın oynatıcıların aynı işareti.
class _ToggleIcon extends StatelessWidget {
  final IconData icon;
  final bool active;
  final double size;
  final String tooltip;
  final Future<Object?> Function() onTap;

  const _ToggleIcon({
    required this.icon,
    required this.active,
    required this.size,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? MusicUI.accent : Colors.white54;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        radius: size,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: size, color: color),
              const SizedBox(height: 3),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: active ? 1 : 0,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: MusicUI.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
