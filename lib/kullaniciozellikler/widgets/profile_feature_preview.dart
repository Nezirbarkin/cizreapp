import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/profile_feature.dart';
import 'creature_painters.dart';
import 'profile_privileges.dart';
import 'renderer_registry.dart';

/// Katalogdaki özelliği gerçek rengi, hareket geometrisi ve parçacık karakteri
/// ile gösteren ortak canlı önizleme. Admin ve kullanıcı katalogları aynı
/// renderer'ı kullanır; böylece birbirinden farklı kayıtlar ayırt edilebilir.
class ProfileFeaturePreview extends StatefulWidget {
  final ProfileFeature feature;
  final double size;
  final BorderRadius borderRadius;

  const ProfileFeaturePreview({
    super.key,
    required this.feature,
    this.size = 64,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
  });

  @override
  State<ProfileFeaturePreview> createState() => _ProfileFeaturePreviewState();
}

class _ProfileFeaturePreviewState extends State<ProfileFeaturePreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feature = widget.feature;
    return Semantics(
      label: '${feature.name} canlı önizlemesi',
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                feature.primaryColor.withValues(alpha: 0.20),
                (feature.secondaryColor ?? feature.primaryColor).withValues(
                  alpha: 0.08,
                ),
                const Color(0xFF121826),
              ],
            ),
          ),
          child:
              feature.kind == ProfileFeatureKind.icon ||
                  feature.kind == ProfileFeatureKind.badge
              ? Center(
                  child: AnimatedPrivilegeIcon(
                    feature: feature,
                    size: widget.size * 0.48,
                  ),
                )
              : AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    painter: _FeaturePreviewPainter(
                      feature: feature,
                      progress: _controller.value,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _FeaturePreviewPainter extends CustomPainter {
  final ProfileFeature feature;
  final double progress;

  const _FeaturePreviewPainter({required this.feature, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final speed = feature.configDouble('speed', 1);
    final time = progress * math.pi * 2 * speed;
    final pattern = feature.configString(
      'pattern',
      _legacyPattern(feature.rendererKey),
    );
    final particle = feature.configString(
      'particle',
      _legacyParticle(feature.rendererKey),
    );
    final secondary = feature.secondaryColor ?? feature.primaryColor;
    final count = ((feature.config['particle_count'] as num?)?.toInt() ?? 14)
        .clamp(7, 28);
    final avatar = feature.kind == ProfileFeatureKind.avatarEffect;

    if (avatar) {
      final avatarRadius = size.shortestSide * .26;
      canvas.drawCircle(
        center,
        avatarRadius,
        Paint()
          ..shader = LinearGradient(
            colors: [feature.primaryColor, secondary],
          ).createShader(Rect.fromCircle(center: center, radius: avatarRadius)),
      );
      canvas.drawCircle(
        center,
        avatarRadius * .78,
        Paint()..color = const Color(0xFF263247),
      );
      final headPaint = Paint()..color = Colors.white.withValues(alpha: .88);
      canvas.drawCircle(
        center - Offset(0, avatarRadius * .18),
        avatarRadius * .22,
        headPaint,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: center + Offset(0, avatarRadius * .32),
          width: avatarRadius * .78,
          height: avatarRadius * .52,
        ),
        headPaint,
      );
    }

    if (_paintCreature(canvas, size, center, secondary, avatar)) return;

    final paint = Paint()
      ..color = feature.primaryColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.2, size.shortestSide * .025);
    final glowPaint = Paint()
      ..color = secondary.withValues(alpha: .55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    for (var i = 0; i < count; i++) {
      final phase = (progress * speed + i / count) % 1;
      final angle = time + (math.pi * 2 / count) * i;
      final point = _point(
        pattern,
        center,
        size,
        angle,
        phase,
        i,
        count,
        avatar,
      );
      _particle(canvas, point, paint, glowPaint, particle, i, angle, size);
    }

    if (avatar) {
      final radius = size.shortestSide * .34;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        time,
        math.pi * 1.25,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.shortestSide * .025
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            colors: [feature.primaryColor, secondary, feature.primaryColor],
            transform: GradientRotation(time),
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  /// Satın alınabilir hayvan/doğa figürü dekorasyonları için önizlemeyi
  /// gerçek çizerleriyle üretir. Bilinmeyen bir renderer ise `false` döner ve
  /// çağıran yer jenerik desen/parçacık motoruna devam eder.
  bool _paintCreature(
    Canvas canvas,
    Size size,
    Offset center,
    Color secondary,
    bool avatar,
  ) {
    final radius = size.shortestSide * 0.36;

    // Yeni çizerler (2026-08-19 ve sonrası) tek yerde kayıtlı — bkz.
    // renderer_registry.dart. Eski key'ler aşağıdaki switch'te kalmaya devam
    // ediyor, davranışları değişmiyor.
    if (tryPaintSurface(
      rendererKey: feature.rendererKey,
      canvas: canvas,
      size: size,
      progress: progress,
      primaryColor: feature.primaryColor,
      secondaryColor: secondary,
    )) {
      return true;
    }
    if (tryPaintFrame(
      rendererKey: feature.rendererKey,
      canvas: canvas,
      center: center,
      radius: radius,
      progress: progress,
      primaryColor: feature.primaryColor,
      secondaryColor: secondary,
    )) {
      return true;
    }

    switch (feature.rendererKey) {
      case 'snake_coil':
        paintSnakeCoil(
          canvas: canvas,
          center: center,
          radius: radius,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'butterfly_land':
        paintButterflyLandingOnAvatar(
          canvas: canvas,
          center: center,
          radius: radius,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'firefly_dance':
        paintFirefliesAvatar(
          canvas: canvas,
          center: center,
          radius: radius,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'cat_paw_peek':
        paintCatPawPeek(
          canvas: canvas,
          center: center,
          radius: radius,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'butterfly_meadow_cover':
        paintButterflyMeadowCover(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'aurora_veil_cover':
        paintAuroraVeilCover(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'petal_drift_cover':
        paintPetalDriftCover(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'firefly_dusk_cover':
        paintFireflyDuskCover(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'royal_gold_frame':
        paintRoyalGoldFrame(
          canvas: canvas,
          center: center,
          radius: radius,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'koi_swim':
        paintKoiSwim(
          canvas: canvas,
          center: center,
          radius: radius,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'owl_perch':
        paintOwlPerch(
          canvas: canvas,
          center: center,
          radius: radius,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'dragon_wisp':
        paintDragonWisp(
          canvas: canvas,
          center: center,
          radius: radius,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'star_confetti_frame':
        paintStarConfettiFrame(
          canvas: canvas,
          center: center,
          radius: radius,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'starry_night_cover':
        paintStarryNightCover(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'snowfall_cover':
        paintSnowfallCover(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'golden_hour_cover':
        paintGoldenHourCover(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'ocean_wave_cover':
        paintOceanWaveCover(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'firework_burst_cover':
        paintFireworkBurstCover(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'royal_aura':
        paintRoyalAuraEffect(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'galaxy_swirl':
        paintGalaxySwirlEffect(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'phoenix_flame':
        paintPhoenixFlameEffect(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'crystal_shimmer':
        paintCrystalShimmerEffect(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'thunder_storm':
        paintThunderStormEffect(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'photo_lightning_strike':
        paintPhotoLightningStrike(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'photo_rain_overlay':
        paintPhotoRainOverlay(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'photo_old_tv':
        paintPhotoOldTvEffect(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'photo_snow_overlay':
        paintPhotoSnowOverlay(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'photo_fog_overlay':
        paintPhotoFogOverlay(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'photo_heat_wave':
        paintPhotoHeatWave(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'photo_neon_glitch':
        paintPhotoNeonGlitch(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'photo_vhs_static':
        paintPhotoVhsStatic(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'photo_film_grain':
        paintPhotoFilmGrain(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'photo_sun_flare':
        paintPhotoSunFlare(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'photo_bokeh_lights':
        paintPhotoBokehLights(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'photo_ice_frost':
        paintPhotoIceFrost(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'photo_confetti_burst':
        paintPhotoConfettiBurst(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'photo_bubble_overlay':
        paintPhotoBubbleOverlay(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'photo_crack_glass':
        paintPhotoCrackGlass(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'photo_smoke_drift':
        paintPhotoSmokeDrift(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      case 'photo_flame_overlay':
        paintPhotoFlameOverlay(
          canvas: canvas,
          size: size,
          progress: progress,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return true;
      default:
        return false;
    }
  }

  Offset _point(
    String pattern,
    Offset center,
    Size size,
    double angle,
    double phase,
    int index,
    int count,
    bool avatar,
  ) {
    final rx = avatar ? size.width * .37 : size.width * .45;
    final ry = avatar ? size.height * .37 : size.height * .42;
    return switch (pattern) {
      'spiral' =>
        center +
            Offset(math.cos(angle), math.sin(angle)) *
                (size.shortestSide * (.08 + phase * .40)),
      'wave' => Offset(
        phase * size.width,
        center.dy + math.sin(angle * 1.7) * ry * .72,
      ),
      'burst' =>
        center +
            Offset(math.cos(angle), math.sin(angle)) *
                (size.shortestSide * phase * .55),
      'vortex' =>
        center +
            Offset(math.cos(angle + phase * 7), math.sin(angle + phase * 7)) *
                (size.shortestSide * (.42 - phase * .30)),
      'grid' => Offset(
        ((index % 4) + phase) / 4 * size.width,
        ((index ~/ 4) + phase) / math.max(1, count ~/ 4) * size.height,
      ),
      'comet' => Offset(
        phase * size.width,
        size.height * (.12 + phase * phase * .76) + math.sin(angle) * 5,
      ),
      'halo' =>
        center +
            Offset(
              math.cos(angle) * rx,
              math.sin(angle) * ry * (.24 + (index % 3) * .15),
            ),
      'zigzag' => Offset(
        phase * size.width,
        ((index.isEven ? phase : 1 - phase) * size.height),
      ),
      'fountain' => Offset(
        center.dx + math.cos(angle) * phase * rx,
        size.height - math.sin(phase * math.pi) * size.height * .88,
      ),
      'meteor' => Offset(
        phase * size.width,
        ((phase + index / count) % 1) * size.height,
      ),
      'curtain' => Offset(
        (index + .5) / count * size.width,
        phase * size.height + math.sin(angle) * 4,
      ),
      _ => center + Offset(math.cos(angle) * rx, math.sin(angle) * ry),
    };
  }

  void _particle(
    Canvas canvas,
    Offset point,
    Paint paint,
    Paint glowPaint,
    String particle,
    int index,
    double angle,
    Size size,
  ) {
    final unit = size.shortestSide / 64;
    canvas.drawCircle(point, 2.5 * unit, glowPaint);
    switch (particle) {
      case 'diamond':
        canvas.drawPath(
          Path()
            ..moveTo(point.dx, point.dy - 4 * unit)
            ..lineTo(point.dx + 3 * unit, point.dy)
            ..lineTo(point.dx, point.dy + 4 * unit)
            ..lineTo(point.dx - 3 * unit, point.dy)
            ..close(),
          paint,
        );
      case 'bubble':
        canvas.drawCircle(
          point,
          3.4 * unit,
          paint..style = PaintingStyle.stroke,
        );
      case 'pixel':
        canvas.drawRect(
          Rect.fromCenter(center: point, width: 4 * unit, height: 4 * unit),
          paint..style = PaintingStyle.fill,
        );
      case 'leaf':
      case 'petal':
        canvas.save();
        canvas.translate(point.dx, point.dy);
        canvas.rotate(angle);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: 3 * unit,
            height: 7 * unit,
          ),
          paint,
        );
        canvas.restore();
      case 'rune':
        canvas.drawLine(
          point - Offset(0, 4 * unit),
          point + Offset(0, 4 * unit),
          paint,
        );
        canvas.drawLine(point, point + Offset(3 * unit, -2 * unit), paint);
      case 'star':
        final path = Path();
        for (var j = 0; j < 10; j++) {
          final radius = (j.isEven ? 4.2 : 1.8) * unit;
          final a = -math.pi / 2 + j * math.pi / 5;
          final p = point + Offset(math.cos(a), math.sin(a)) * radius;
          if (j == 0) {
            path.moveTo(p.dx, p.dy);
          } else {
            path.lineTo(p.dx, p.dy);
          }
        }
        canvas.drawPath(path..close(), paint);
      case 'ember':
        canvas.drawOval(
          Rect.fromCenter(
            center: point,
            width: 3 * unit,
            height: (5 + index % 3) * unit,
          ),
          paint,
        );
      default:
        canvas.drawCircle(point, 2.2 * unit, paint);
    }
  }

  String _legacyPattern(String renderer) => switch (renderer) {
    'rain' || 'rain_border' => 'curtain',
    'lightning' || 'lightning_ring' => 'zigzag',
    'rotate' || 'orbit' => 'orbit',
    'bubbles' => 'fountain',
    'aurora' || 'portal' => 'vortex',
    'hearts' || 'heart_orbit' => 'halo',
    _ => 'burst',
  };

  String _legacyParticle(String renderer) => switch (renderer) {
    'bubbles' => 'bubble',
    'hearts' || 'heart_orbit' => 'petal',
    'snow' || 'snow_ring' => 'crystal',
    'lightning' || 'lightning_ring' => 'spark',
    'fire_ring' => 'ember',
    _ => 'star',
  };

  @override
  bool shouldRepaint(covariant _FeaturePreviewPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.feature != feature;
}
