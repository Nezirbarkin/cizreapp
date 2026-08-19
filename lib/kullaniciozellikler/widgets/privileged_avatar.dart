import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/profile_feature.dart';
import '../services/profile_feature_service.dart';
import 'creature_painters.dart';
import 'feature_icon_registry.dart';
import 'renderer_registry.dart';

/// Mevcut avatar tasarımını değiştirmeden çevresine atanmış avatar efektini
/// çizer. Profil sayfasındaki hikâye halkası gibi mevcut görünümü korur.
class AvatarEffectFrame extends StatefulWidget {
  final String userId;
  final Widget child;

  const AvatarEffectFrame({
    super.key,
    required this.userId,
    required this.child,
  });

  @override
  State<AvatarEffectFrame> createState() => _AvatarEffectFrameState();
}

class _AvatarEffectFrameState extends State<AvatarEffectFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Future<List<ProfileFeature>> _future;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
    _future = ProfileFeatureService().getUserFeatures(widget.userId);
  }

  @override
  void didUpdateWidget(covariant AvatarEffectFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _future = ProfileFeatureService().getUserFeatures(widget.userId);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ProfileFeature>>(
      future: _future,
      builder: (context, snapshot) {
        final effect = (snapshot.data ?? const <ProfileFeature>[])
            .where((item) => item.kind == ProfileFeatureKind.avatarEffect)
            .firstOrNull;
        if (effect == null) return widget.child;

        // "photo_" önekli efektler çerçeve değildir — doğrudan fotoğrafın
        // kendi yüzeyine (dairesel kırpılarak) biner, halka çizilmez.
        if (isPhotoOverlayEffect(effect)) {
          return AnimatedBuilder(
            animation: _controller,
            child: widget.child,
            builder: (context, child) => ClipOval(
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  if (child != null) child,
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _AvatarPhotoOverlayPainter(
                          feature: effect,
                          progress: _controller.value,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return AnimatedBuilder(
          animation: _controller,
          child: widget.child,
          builder: (context, child) => Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _AvatarEffectPainter(
                    feature: effect,
                    progress: _controller.value,
                  ),
                ),
              ),
              Padding(padding: const EdgeInsets.all(7), child: child),
            ],
          ),
        );
      },
    );
  }
}

/// "photo_" önekli renderer_key'ler çerçeve/yaratık değil, fotoğrafın kendi
/// yüzeyine binen bir overlay efektidir (şimşek, yağmur, eski TV vb.).
bool isPhotoOverlayEffect(ProfileFeature feature) =>
    feature.rendererKey.startsWith('photo_');

/// Profil resmi, ona atanmış hareketli avatar efekti ve isteğe bağlı sosyal
/// ikon/tiklerini tek bir izole bileşende gösterir.
class PrivilegedAvatar extends StatefulWidget {
  final String userId;
  final String username;
  final String? avatarUrl;
  final double radius;
  final VoidCallback? onTap;
  final bool showSocialPrivileges;
  final int maximumBadges;

  const PrivilegedAvatar({
    super.key,
    required this.userId,
    required this.username,
    required this.avatarUrl,
    this.radius = 24,
    this.onTap,
    this.showSocialPrivileges = false,
    this.maximumBadges = 3,
  });

  @override
  State<PrivilegedAvatar> createState() => _PrivilegedAvatarState();
}

class _PrivilegedAvatarState extends State<PrivilegedAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Future<List<ProfileFeature>> _future;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
    _future = ProfileFeatureService().getUserFeatures(widget.userId);
  }

  @override
  void didUpdateWidget(covariant PrivilegedAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _future = ProfileFeatureService().getUserFeatures(widget.userId);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final extent = widget.radius * 2 + 18;
    return FutureBuilder<List<ProfileFeature>>(
      future: _future,
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <ProfileFeature>[];
        final effect = all
            .where((item) => item.kind == ProfileFeatureKind.avatarEffect)
            .firstOrNull;
        final privileges = all
            .where(
              (item) =>
                  item.kind == ProfileFeatureKind.badge ||
                  item.kind == ProfileFeatureKind.icon,
            )
            .take(widget.maximumBadges)
            .toList(growable: false);
        final isPhotoOverlay = effect != null && isPhotoOverlayEffect(effect);

        return GestureDetector(
          onTap: widget.onTap,
          child: SizedBox(
            width: extent,
            height: extent,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (effect != null && !isPhotoOverlay)
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _AvatarEffectPainter(
                            feature: effect,
                            progress: _controller.value,
                          ),
                        ),
                      ),
                    ),
                  _animatedAvatar(effect),
                  if (isPhotoOverlay)
                    ClipOval(
                      child: SizedBox(
                        width: widget.radius * 2,
                        height: widget.radius * 2,
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: _AvatarPhotoOverlayPainter(
                                feature: effect,
                                progress: _controller.value,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (widget.showSocialPrivileges && privileges.isNotEmpty)
                    Positioned(
                      right: -4,
                      bottom: -7,
                      child: _CompactPrivileges(features: privileges),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _animatedAvatar(ProfileFeature? effect) {
    final pulse = effect?.rendererKey == 'pulse_glow'
        ? 0.94 + math.sin(_controller.value * math.pi * 2) * 0.06
        : 1.0;
    return Transform.scale(
      scale: pulse,
      child: CircleAvatar(
        radius: widget.radius,
        backgroundColor: Theme.of(context).colorScheme.primary,
        backgroundImage: widget.avatarUrl?.isNotEmpty == true
            ? NetworkImage(widget.avatarUrl!)
            : null,
        child: widget.avatarUrl?.isNotEmpty == true
            ? null
            : Text(
                widget.username.isEmpty
                    ? '?'
                    : widget.username
                          .substring(0, math.min(2, widget.username.length))
                          .toUpperCase(),
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: widget.radius * 0.58,
                ),
              ),
      ),
    );
  }
}

class _CompactPrivileges extends StatelessWidget {
  final List<ProfileFeature> features;

  const _CompactPrivileges({required this.features});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: features
          .map((feature) {
            final badge = feature.kind == ProfileFeatureKind.badge;
            return GestureDetector(
              onTap: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(feature.name),
                  content: Text(feature.description),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Kapat'),
                    ),
                  ],
                ),
              ),
              child: Container(
                width: 17,
                height: 17,
                margin: const EdgeInsets.only(left: 1),
                decoration: BoxDecoration(
                  color: badge ? feature.primaryColor : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 3),
                  ],
                ),
                child: Icon(
                  badge ? Icons.check : profileFeatureIcon(feature.rendererKey),
                  size: 11,
                  color: badge ? Colors.white : feature.primaryColor,
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

/// "photo_" önekli efektleri doğrudan fotoğrafın (dairesel kırpılmış) yüzeyi
/// üzerine çizer — çerçeve/halka çizmez, sadece fotoğrafın kendisini kaplar.
class _AvatarPhotoOverlayPainter extends CustomPainter {
  final ProfileFeature feature;
  final double progress;

  const _AvatarPhotoOverlayPainter({
    required this.feature,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final speed = feature.configDouble('speed', 1);
    final secondary = feature.secondaryColor ?? feature.primaryColor;
    final animated = progress * speed;

    // Yeni yüzey çizerleri tek yerde kayıtlı (renderer_registry.dart).
    if (tryPaintSurface(
      rendererKey: feature.rendererKey,
      canvas: canvas,
      size: size,
      progress: animated,
      primaryColor: feature.primaryColor,
      secondaryColor: secondary,
    )) {
      return;
    }

    switch (feature.rendererKey) {
      case 'photo_lightning_strike':
        paintPhotoLightningStrike(
          canvas: canvas,
          size: size,
          progress: animated,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        break;
      case 'photo_rain_overlay':
        paintPhotoRainOverlay(
          canvas: canvas,
          size: size,
          progress: animated,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        break;
      case 'photo_old_tv':
        paintPhotoOldTvEffect(
          canvas: canvas,
          size: size,
          progress: animated,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        break;
      case 'photo_snow_overlay':
        paintPhotoSnowOverlay(
          canvas: canvas,
          size: size,
          progress: animated,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        break;
      case 'photo_fog_overlay':
        paintPhotoFogOverlay(
          canvas: canvas,
          size: size,
          progress: animated,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        break;
      case 'photo_heat_wave':
        paintPhotoHeatWave(
          canvas: canvas,
          size: size,
          progress: animated,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        break;
      case 'photo_neon_glitch':
        paintPhotoNeonGlitch(
          canvas: canvas,
          size: size,
          progress: animated,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        break;
      case 'photo_vhs_static':
        paintPhotoVhsStatic(
          canvas: canvas,
          size: size,
          progress: animated,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        break;
      case 'photo_film_grain':
        paintPhotoFilmGrain(
          canvas: canvas,
          size: size,
          progress: animated,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        break;
      case 'photo_sun_flare':
        paintPhotoSunFlare(
          canvas: canvas,
          size: size,
          progress: animated,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        break;
      case 'photo_bokeh_lights':
        paintPhotoBokehLights(
          canvas: canvas,
          size: size,
          progress: animated,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        break;
      case 'photo_ice_frost':
        paintPhotoIceFrost(
          canvas: canvas,
          size: size,
          progress: animated,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        break;
      case 'photo_confetti_burst':
        paintPhotoConfettiBurst(
          canvas: canvas,
          size: size,
          progress: animated,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        break;
      case 'photo_bubble_overlay':
        paintPhotoBubbleOverlay(
          canvas: canvas,
          size: size,
          progress: animated,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        break;
      case 'photo_crack_glass':
        paintPhotoCrackGlass(
          canvas: canvas,
          size: size,
          progress: animated,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        break;
      case 'photo_smoke_drift':
        paintPhotoSmokeDrift(
          canvas: canvas,
          size: size,
          progress: animated,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        break;
      case 'photo_flame_overlay':
        paintPhotoFlameOverlay(
          canvas: canvas,
          size: size,
          progress: animated,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _AvatarPhotoOverlayPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.feature != feature;
}

class _AvatarEffectPainter extends CustomPainter {
  final ProfileFeature feature;
  final double progress;

  const _AvatarEffectPainter({required this.feature, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 6;
    final speed = feature.configDouble('speed', 1);
    final thickness = feature.configDouble('thickness', 2.2);
    final count = (feature.config['particle_count'] as num?)?.toInt() ?? 10;
    final secondary = feature.secondaryColor ?? feature.primaryColor;
    final rotation = progress * math.pi * 2 * speed;
    final procedural = feature.rendererKey == 'avatar_procedural';
    final pattern = feature.configString('pattern', 'orbit');

    // Yeni çerçeve çizerleri tek yerde kayıtlı (renderer_registry.dart).
    if (tryPaintFrame(
      rendererKey: feature.rendererKey,
      canvas: canvas,
      center: center,
      radius: radius,
      progress: progress * speed,
      primaryColor: feature.primaryColor,
      secondaryColor: secondary,
    )) {
      return;
    }

    // Satın alınabilir hayvan/doğa figürü dekorasyonları: mevcut halka/parçacık
    // deseninin yerine tamamen kendi prosedürel çizimlerini kullanır.
    switch (feature.rendererKey) {
      case 'snake_coil':
        paintSnakeCoil(
          canvas: canvas,
          center: center,
          radius: radius,
          progress: progress * speed,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return;
      case 'butterfly_land':
        paintButterflyLandingOnAvatar(
          canvas: canvas,
          center: center,
          radius: radius,
          progress: progress * speed,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return;
      case 'firefly_dance':
        paintFirefliesAvatar(
          canvas: canvas,
          center: center,
          radius: radius,
          progress: progress * speed,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return;
      case 'cat_paw_peek':
        paintCatPawPeek(
          canvas: canvas,
          center: center,
          radius: radius,
          progress: progress * speed,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return;
      case 'royal_gold_frame':
        paintRoyalGoldFrame(
          canvas: canvas,
          center: center,
          radius: radius,
          progress: progress * speed,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return;
      case 'koi_swim':
        paintKoiSwim(
          canvas: canvas,
          center: center,
          radius: radius,
          progress: progress * speed,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return;
      case 'owl_perch':
        paintOwlPerch(
          canvas: canvas,
          center: center,
          radius: radius,
          progress: progress * speed,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return;
      case 'dragon_wisp':
        paintDragonWisp(
          canvas: canvas,
          center: center,
          radius: radius,
          progress: progress * speed,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return;
      case 'star_confetti_frame':
        paintStarConfettiFrame(
          canvas: canvas,
          center: center,
          radius: radius,
          progress: progress * speed,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        return;
    }

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = thickness
      ..shader = SweepGradient(
        colors: [feature.primaryColor, secondary, feature.primaryColor],
        transform: GradientRotation(rotation),
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    switch (feature.rendererKey) {
      case 'pulse_glow':
        final pulse = 1 + math.sin(rotation) * 0.07;
        canvas.drawCircle(
          center,
          radius * pulse,
          ringPaint..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
        break;
      case 'rainbow_ring':
      case 'portal':
      case 'neon_ring':
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          rotation,
          math.pi * 1.45,
          false,
          ringPaint,
        );
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius - 4),
          -rotation,
          math.pi,
          false,
          ringPaint..strokeWidth = math.max(1, thickness * 0.55),
        );
        break;
      default:
        canvas.drawCircle(center, radius, ringPaint);
    }

    final particlePaint = Paint()..color = feature.primaryColor;
    for (var i = 0; i < count; i++) {
      final angle = rotation + (math.pi * 2 / count) * i;
      final orbit = radius + (i.isEven ? 1 : -2);
      final point = procedural
          ? _proceduralPoint(pattern, center, radius, angle, i, count)
          : center + Offset(math.cos(angle), math.sin(angle)) * orbit;
      if (feature.rendererKey == 'heart_orbit') {
        final text = TextPainter(
          text: TextSpan(
            text: '♥',
            style: TextStyle(color: feature.primaryColor, fontSize: 7 + i % 3),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, point - const Offset(4, 4));
      } else if (feature.rendererKey == 'crown_glow' && i == 0) {
        final text = TextPainter(
          text: TextSpan(
            text: '♛',
            style: TextStyle(color: feature.primaryColor, fontSize: 15),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, Offset(center.dx - 7, 0));
      } else {
        canvas.drawCircle(point, 1.6 + (i % 3) * 0.7, particlePaint);
      }
    }
  }

  Offset _proceduralPoint(
    String pattern,
    Offset center,
    double radius,
    double angle,
    int index,
    int count,
  ) {
    return switch (pattern) {
      'spiral' =>
        center +
            Offset(math.cos(angle), math.sin(angle)) *
                (radius * (.62 + (index / count) * .4)),
      'wave' =>
        center +
            Offset(
              math.cos(angle) * radius,
              math.sin(angle * 2) * radius * .24,
            ),
      'burst' =>
        center +
            Offset(math.cos(angle), math.sin(angle)) *
                (radius * (.8 + math.sin(angle * 3) * .18)),
      'vortex' =>
        center +
            Offset(
                  math.cos(angle + index * .12),
                  math.sin(angle + index * .12),
                ) *
                (radius * (.68 + (index % 4) * .1)),
      'grid' =>
        center +
            Offset(
              ((index % 4) - 1.5) * radius * .48,
              ((index ~/ 4) - 1.5) * radius * .35,
            ),
      'comet' =>
        center +
            Offset(math.cos(angle), math.sin(angle)) *
                (radius + math.sin(angle * .5) * 6),
      'halo' =>
        center +
            Offset(math.cos(angle) * radius, math.sin(angle) * radius * .36),
      'zigzag' =>
        center +
            Offset(math.cos(angle), math.sin(angle)) *
                (index.isEven ? radius : radius * .72),
      'fountain' =>
        center +
            Offset(
              math.cos(angle) * radius * .7,
              -math.sin((index + 1) / count * math.pi) * radius,
            ),
      'meteor' =>
        center +
            Offset(math.cos(angle) * radius, math.sin(angle + .7) * radius),
      'curtain' =>
        center +
            Offset(
              ((index + .5) / count * 2 - 1) * radius,
              math.sin(angle) * radius,
            ),
      _ => center + Offset(math.cos(angle) * radius, math.sin(angle) * radius),
    };
  }

  @override
  bool shouldRepaint(covariant _AvatarEffectPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.feature != feature;
}
