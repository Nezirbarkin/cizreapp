import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// "ŞİMDİ ÇALIYOR" paneli — arka plan müziğinin uygulama içindeki kartı.
///
/// ## Neden bu tasarım
///
/// Önceki hâli tek satırlık düz bir şeritti: ▶ düğmesi + kesilmiş şarkı adı.
/// İki sorunu vardı. Birincisi, uzun şarkı adları "..." ile kırpıldığı için
/// kullanıcı ne çaldığını göremiyordu. İkincisi, müziğin ÇALIP çalmadığı
/// yalnızca düğmenin ikonundan anlaşılıyordu — panele bakan göz bunu
/// aramak zorundaydı.
///
/// Bu kart ikisini de HAREKETLE çözer:
/// * Sığmayan şarkı adı kesilmez, kayan yazı (marquee) olarak akar; sığan
///   adın üzerinden yavaş bir parlama geçer — yani yazı her hâlükârda
///   "canlı"dır.
/// * Kapak bir plak gibi döner ve üstündeki ekolayzır çubukları oynar.
///   Müzik duraklatıldığında ikisi de DONAR. Durum, ikon okumadan görülür.
///
/// ## Hareket duraklayınca gerçekten durur
///
/// Dekoratif animasyonlar arka planda dönmeye devam ederse pil yakar ve
/// duraklatılmış müzikte yanlış bilgi verir. Bu yüzden her denetleyici
/// [playing] bayrağına bağlanır: `false` iken hepsi durdurulur.
class NowPlayingPanel extends StatefulWidget {
  /// Çalan (veya duraklatılmış) şarkının görünen adı.
  final String trackName;

  /// Müzik ŞU AN çalıyor mu? Tüm animasyonlar buna bağlıdır.
  final bool playing;

  /// Çalma listesinde birden çok şarkı var mı (önceki/sonraki gösterilsin mi).
  ///
  /// Kaçıncı şarkıda olduğumuz BİLEREK yazılmıyor: kullanıcı için bilgi
  /// değeri yok, dar kartta ise şarkı adından yer çalıyordu.
  final bool showTrackNav;

  /// Konum/uzunluk akışı. `null` verilirse ilerleme çubuğu belirsiz
  /// (indeterminate) modda çalışır — yani "çalıyor" der ama nereye
  /// geldiğini söylemez.
  final ValueListenable<({Duration position, Duration total})>? progress;

  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const NowPlayingPanel({
    super.key,
    required this.trackName,
    required this.playing,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    this.showTrackNav = false,
    this.progress,
  });

  @override
  State<NowPlayingPanel> createState() => _NowPlayingPanelState();
}

class _NowPlayingPanelState extends State<NowPlayingPanel>
    with TickerProviderStateMixin {
  /// Plağın dönüşü — 9 sn'de bir tur. Daha hızlısı bu boyutta bir kapakta
  /// dönme değil titreşim gibi görünüyor.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 9000),
  );

  /// Kapağın çevresindeki nefes alan ışık.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  /// ▶ ↔ ⏸ geçişi. Ani ikon değişimi yerine çizgiler birbirine dönüşür.
  late final AnimationController _playPause = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  @override
  void initState() {
    super.initState();
    _playPause.value = widget.playing ? 1 : 0;
    _applyMotion();
  }

  @override
  void didUpdateWidget(NowPlayingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) _applyMotion();
  }

  /// Çalma durumunu animasyonlara uygular.
  void _applyMotion() {
    if (widget.playing) {
      if (!_spin.isAnimating) _spin.repeat();
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
      _playPause.forward();
    } else {
      // stop(): değeri KORUYARAK durdurur — plak kaldığı açıda donar,
      // devam edilince sıfırdan başlamaz.
      _spin.stop();
      _pulse.stop();
      _playPause.reverse();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    _playPause.dispose();
    super.dispose();
  }

  void _tap(VoidCallback action) {
    HapticFeedback.selectionClick();
    action();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 7, 6, 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        // Camsı kart: altındaki tema rengini geçirir, kendi rengi yoktur —
        // kullanıcı temayı değiştirdiğinde panel de onunla değişir.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.22),
            Colors.white.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 9,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          _Artwork(
            spin: _spin,
            pulse: _pulse,
            playing: widget.playing,
            size: 36,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MarqueeText(
                  text: widget.trackName,
                  animate: widget.playing,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 5),
                _ProgressLine(
                  progress: widget.progress,
                  playing: widget.playing,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          if (widget.showTrackNav)
            _RoundButton(
              icon: Icons.skip_previous_rounded,
              semantic: 'Önceki şarkı',
              onTap: () => _tap(widget.onPrevious),
            ),
          _RoundButton.playPause(
            progress: _playPause,
            playing: widget.playing,
            onTap: () => _tap(widget.onPlayPause),
          ),
          if (widget.showTrackNav)
            _RoundButton(
              icon: Icons.skip_next_rounded,
              semantic: 'Sonraki şarkı',
              onTap: () => _tap(widget.onNext),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// KAPAK — dönen plak
// ---------------------------------------------------------------------------

class _Artwork extends StatelessWidget {
  final Animation<double> spin;
  final Animation<double> pulse;
  final bool playing;
  final double size;

  const _Artwork({
    required this.spin,
    required this.pulse,
    required this.playing,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: pulse,
        builder: (context, child) {
          final t = playing ? Curves.easeInOut.transform(pulse.value) : 0.0;
          return DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.08 + 0.14 * t),
                  blurRadius: 8 + 8 * t,
                  spreadRadius: 0.5 + t,
                ),
              ],
            ),
            child: child,
          );
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Plağın kendisi döner; rozet DÖNMEZ (dönseydi çubuklar yan
            // yatardı), bu yüzden ikisi ayrı katmanda.
            Positioned.fill(
              child: RotationTransition(
                turns: spin,
                child: CustomPaint(painter: _VinylPainter()),
              ),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: _EqualizerBadge(playing: playing, size: size * 0.42),
            ),
          ],
        ),
      ),
    );
  }
}

/// Plak: koyu disk + oluklar + pembe etiket + ışık huzmesi.
///
/// Işık huzmesi ŞART: dairesel simetrik bir disk dönerken hiç dönmüyormuş
/// gibi görünür. Huzme (ve etiketin üstündeki çentik) dönüşü gözle
/// görülebilir kılan tek ayrıntıdır.
class _VinylPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    // Gövde.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF23212B), Color(0xFF0D0C11)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // Oluklar.
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.white.withValues(alpha: 0.07);
    for (var k = 0.52; k < 0.98; k += 0.14) {
      canvas.drawCircle(c, r * k, groove);
    }

    // Işık huzmesi — iki karşıt yay.
    final sheen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = r * 0.28
      ..color = Colors.white.withValues(alpha: 0.10);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.72),
      -1.9,
      0.9,
      false,
      sheen,
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.72),
      1.25,
      0.55,
      false,
      sheen..color = Colors.white.withValues(alpha: 0.05),
    );

    // Etiket.
    final lr = r * 0.42;
    canvas.drawCircle(
      c,
      lr,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFF69A8), Color(0xFFD91A73)],
        ).createShader(Rect.fromCircle(center: c, radius: lr)),
    );

    // Etiketteki nota — kapağı "müzik" yapan işaret.
    final note = Paint()..color = Colors.white.withValues(alpha: 0.95);
    final head = c.translate(-lr * 0.16, lr * 0.30);
    canvas.drawCircle(head, lr * 0.26, note);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(head.dx + lr * 0.16, c.dy - lr * 0.55, lr * 0.15, lr * 0.85),
        Radius.circular(lr * 0.08),
      ),
      note,
    );

    // İğne deliği.
    canvas.drawCircle(c, r * 0.05, Paint()..color = const Color(0xFF15141A));
  }

  @override
  bool shouldRepaint(_VinylPainter oldDelegate) => false;
}

/// Kapağın köşesindeki oynayan ekolayzır. Müzik durunca çubuklar en alt
/// seviyeye iner ve orada kalır.
class _EqualizerBadge extends StatefulWidget {
  final bool playing;
  final double size;
  const _EqualizerBadge({required this.playing, required this.size});

  @override
  State<_EqualizerBadge> createState() => _EqualizerBadgeState();
}

class _EqualizerBadgeState extends State<_EqualizerBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  /// Çubukların birbirinden farklı oynaması için faz kaymaları. Hepsi aynı
  /// fazda olsaydı ekolayzır değil, tek parça bir blok görünürdü.
  static const _phases = [0.0, 0.42, 0.78];

  /// DURAKLATILMIŞ hâldeki sabit boylar. Üçü de en alta inseydi rozet
  /// "..." gibi okunurdu; kademeli duruş "susmuş bir ekolayzır" der.
  static const _resting = [0.55, 0.95, 0.35];

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(_EqualizerBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.playing && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF12111A).withValues(alpha: 0.92),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _EqualizerPainter(
            t: _c.value,
            phases: _phases,
            resting: _resting,
            playing: widget.playing,
          ),
        ),
      ),
    );
  }
}

class _EqualizerPainter extends CustomPainter {
  final double t;
  final List<double> phases;
  final List<double> resting;
  final bool playing;

  _EqualizerPainter({
    required this.t,
    required this.phases,
    required this.resting,
    required this.playing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barW = size.width * 0.14;
    final gap = size.width * 0.09;
    final total = phases.length * barW + (phases.length - 1) * gap;
    var x = (size.width - total) / 2;
    final bottom = size.height * 0.74;
    final maxH = size.height * 0.48;
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.95);

    for (var i = 0; i < phases.length; i++) {
      final wave = playing
          ? (math.sin((t + phases[i]) * 2 * math.pi) + 1) / 2
          : resting[i];
      final h = maxH * (0.22 + 0.78 * wave);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, bottom - h, barW, h),
          Radius.circular(barW / 2),
        ),
        paint,
      );
      x += barW + gap;
    }
  }

  @override
  bool shouldRepaint(_EqualizerPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.playing != playing;
}

// ---------------------------------------------------------------------------
// KAYAN / PARLAYAN ŞARKI ADI
// ---------------------------------------------------------------------------

/// Sığmayan metni kaydırır, sığanı parlatır.
///
/// Neden iki ayrı davranış: kaydırma yalnızca metin taşıyorsa bir işe yarar;
/// kısa bir ad boşuna kaydırılırsa okunması zorlaşır. Kısa adda hareket
/// ihtiyacını üzerinden geçen ışık karşılar.
class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final bool animate;

  const _MarqueeText({
    required this.text,
    required this.style,
    required this.animate,
  });

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  );

  /// İki kopya arasındaki boşluk — kesintisiz döngüyü mümkün kılan şey.
  static const _gap = 44.0;

  /// Kaydırma hızı (saniyede piksel). Okunabilirliğin sınırı: daha hızlısı
  /// takip edilemiyor, daha yavaşı sabit gibi duruyor.
  static const _speed = 34.0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Denetleyiciyi build SIRASINDA değil, kare sonrasında başlatır/durdurur:
  /// build içinde animasyon başlatmak aynı karede yeniden çizim tetikler.
  void _sync({required bool shouldRun, required Duration duration}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_c.duration != duration) _c.duration = duration;
      if (shouldRun && !_c.isAnimating) {
        _c.repeat();
      } else if (!shouldRun && _c.isAnimating) {
        _c.stop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();
        final textWidth = painter.width;
        final height = painter.height;
        final maxWidth = constraints.maxWidth;
        final overflows = textWidth > maxWidth + 0.5;

        if (!overflows) {
          _sync(shouldRun: false, duration: _c.duration ?? Duration.zero);
          return SizedBox(
            height: height,
            width: double.infinity,
            child: _Shimmer(
              animate: widget.animate,
              child: Text(
                widget.text,
                maxLines: 1,
                softWrap: false,
                style: widget.style,
              ),
            ),
          );
        }

        final travel = textWidth + _gap;
        _sync(
          shouldRun: widget.animate,
          duration: Duration(
            milliseconds: (travel / _speed * 1000).round().clamp(4000, 40000),
          ),
        );

        final label = Text(
          widget.text,
          maxLines: 1,
          softWrap: false,
          style: widget.style,
        );

        return ClipRect(
          child: ShaderMask(
            // Kenarlarda erime: yazının kutunun içinden çıkıp girdiği yer
            // keskin bir kesikle bitmesin.
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [
                Colors.transparent,
                Colors.white,
                Colors.white,
                Colors.transparent,
              ],
              stops: [0, (10 / maxWidth).clamp(0.0, 0.4), 0.9, 1],
            ).createShader(rect),
            child: SizedBox(
              height: height,
              width: double.infinity,
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, child) => Transform.translate(
                  offset: Offset(-travel * _c.value, 0),
                  child: child,
                ),
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: double.infinity,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      label,
                      const SizedBox(width: _gap),
                      label,
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Metnin üzerinden geçen ışık bandı.
class _Shimmer extends StatefulWidget {
  final Widget child;
  final bool animate;

  const _Shimmer({required this.child, required this.animate});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(_Shimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.animate && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        // Band -0.3'ten 1.3'e süzülür; ekranın dışından girip dışına çıkar.
        final t = -0.3 + 1.6 * _c.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.white.withValues(alpha: 0.72),
              Colors.white,
              Colors.white.withValues(alpha: 0.72),
            ],
            stops: [
              (t - 0.16).clamp(0.0, 1.0),
              t.clamp(0.0, 1.0),
              (t + 0.16).clamp(0.0, 1.0),
            ],
          ).createShader(rect),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ---------------------------------------------------------------------------
// İLERLEME ÇUBUĞU
// ---------------------------------------------------------------------------

/// Şarkının neresinde olduğumuzu gösteren ince çizgi + süre.
///
/// Konum saniyede birkaç kez değişiyor; bu yüzden yalnızca BU parça
/// [ValueListenableBuilder] ile dinler. Panelin geri kalanı (kapak, ad,
/// düğmeler) o güncellemelerde yeniden çizilmez.
class _ProgressLine extends StatelessWidget {
  final ValueListenable<({Duration position, Duration total})>? progress;
  final bool playing;

  const _ProgressLine({required this.progress, required this.playing});

  static String _mmss(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final listenable = progress;
    if (listenable == null) {
      return _Bar(fraction: null, playing: playing);
    }
    return ValueListenableBuilder<({Duration position, Duration total})>(
      valueListenable: listenable,
      builder: (context, value, _) {
        final total = value.total.inMilliseconds;
        final fraction = total > 0
            ? (value.position.inMilliseconds / total).clamp(0.0, 1.0)
            : null;
        return LayoutBuilder(
          builder: (context, constraints) {
            // DAR ALANDA SÜRE KISALIR. "1:02 / 3:15" yazısı, yan menü dar bir
            // telefonda çubuğa kalan yerin yarısını yiyordu; çubuk okunmaz
            // hâle geliyordu. Geniş kartta tam süre, darda yalnızca geçen
            // süre yazılır.
            final showTotal = total > 0 && constraints.maxWidth >= 160;
            return Row(
              children: [
                Expanded(child: _Bar(fraction: fraction, playing: playing)),
                const SizedBox(width: 7),
                Text(
                  showTotal
                      ? '${_mmss(value.position)} / ${_mmss(value.total)}'
                      : _mmss(value.position),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 9.5,
                    height: 1,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Çizginin kendisi. [fraction] null ise (uzunluk henüz bilinmiyor) sağa
/// doğru süzülen bir parıltı gösterir — "çalışıyor ama nerede olduğunu
/// bilmiyorum" durumunun dürüst karşılığı.
class _Bar extends StatefulWidget {
  final double? fraction;
  final bool playing;

  const _Bar({required this.fraction, required this.playing});

  @override
  State<_Bar> createState() => _BarState();
}

class _BarState extends State<_Bar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  bool get _indeterminate => widget.fraction == null && widget.playing;

  @override
  void initState() {
    super.initState();
    if (_indeterminate) _c.repeat();
  }

  @override
  void didUpdateWidget(_Bar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_indeterminate && !_c.isAnimating) {
      _c.repeat();
    } else if (!_indeterminate && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 3,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          return Stack(
            children: [
              // Yol.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (widget.fraction != null)
                // Dolgu. 260 ms'lik yumuşatma, konum bildirimleri arasındaki
                // sıçramayı akışa çevirir.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.linear,
                  width: w * widget.fraction!,
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.45),
                        blurRadius: 5,
                      ),
                    ],
                  ),
                )
              else if (widget.playing)
                // Parıltı Positioned ile DEĞİL, Align ile konumlanır:
                // Positioned yalnızca Stack'in DOĞRUDAN çocuğu olabilir,
                // AnimatedBuilder'ın içinden verilseydi çalışma anında
                // "Incorrect use of ParentDataWidget" ile patlardı.
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, child) => Align(
                      alignment: Alignment(-1 + 2 * _c.value, 0),
                      child: child,
                    ),
                    child: Container(
                      width: w * 0.34,
                      height: 3,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 0.85),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// KÜÇÜK PARÇALAR
// ---------------------------------------------------------------------------

/// Dairesel denetim düğmesi. Basıldığında hafifçe küçülür — dokunuşun
/// kaydedildiğini söyleyen en ucuz geri bildirim.
class _RoundButton extends StatefulWidget {
  final IconData? icon;
  final String semantic;
  final VoidCallback onTap;
  final bool filled;

  /// ▶/⏸ düğmesi için: ikon yerine iki durum arasında geçen animasyon.
  final Animation<double>? playPauseProgress;

  const _RoundButton({
    required this.icon,
    required this.semantic,
    required this.onTap,
  }) : playPauseProgress = null,
       filled = false;

  const _RoundButton.playPause({
    required Animation<double> progress,
    required bool playing,
    required this.onTap,
  }) : playPauseProgress = progress,
       icon = null,
       filled = true,
       semantic = playing ? 'Duraklat' : 'Çal';

  @override
  State<_RoundButton> createState() => _RoundButtonState();
}

class _RoundButtonState extends State<_RoundButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final size = widget.filled ? 30.0 : 24.0;
    return Semantics(
      button: true,
      label: widget.semantic,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _down ? 0.88 : 1,
          duration: const Duration(milliseconds: 110),
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: widget.filled ? 0.24 : 0),
              border: widget.filled
                  ? Border.all(color: Colors.white.withValues(alpha: 0.30))
                  : null,
            ),
            child: widget.playPauseProgress != null
                ? AnimatedIcon(
                    icon: AnimatedIcons.play_pause,
                    progress: widget.playPauseProgress!,
                    color: Colors.white,
                    size: 17,
                  )
                : Icon(widget.icon, color: Colors.white, size: 17),
          ),
        ),
      ),
    );
  }
}
