import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/profile_feature.dart';
import '../services/profile_feature_service.dart';
import 'creature_painters.dart';
import 'feature_icon_registry.dart';

/// Profilin arkasına/üstüne prosedürel efekt katmanı ekler. Katalogdaki yüzlerce
/// varyasyon aynı güvenli renderer anahtarlarını ve JSON ayarlarını kullanır.
class ProfilePrivilegesOverlay extends StatefulWidget {
  final String userId;
  final Widget child;

  const ProfilePrivilegesOverlay({
    super.key,
    required this.userId,
    required this.child,
  });

  @override
  State<ProfilePrivilegesOverlay> createState() =>
      _ProfilePrivilegesOverlayState();
}

class _ProfilePrivilegesOverlayState extends State<ProfilePrivilegesOverlay>
    with SingleTickerProviderStateMixin {
  final _service = ProfileFeatureService();
  late final AnimationController _controller;
  late Future<List<ProfileFeature>> _future;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _future = _service.getUserFeatures(widget.userId);
  }

  @override
  void didUpdateWidget(covariant ProfilePrivilegesOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _future = _service.getUserFeatures(widget.userId);
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
        final effects = (snapshot.data ?? const <ProfileFeature>[])
            .where((feature) => feature.kind == ProfileFeatureKind.effect)
            .take(3)
            .toList(growable: false);
        if (effects.isEmpty) return widget.child;

        final blink = effects.any((effect) => effect.rendererKey == 'blink');
        return AnimatedBuilder(
          animation: _controller,
          child: widget.child,
          builder: (context, child) {
            final pulse = blink
                ? 0.94 + math.sin(_controller.value * math.pi * 2) * 0.06
                : 1.0;
            return Stack(
              fit: StackFit.expand,
              children: [
                Opacity(opacity: pulse.clamp(0.86, 1.0), child: child),
                IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _ProfileEffectPainter(
                        effects: effects,
                        progress: _controller.value,
                      ),
                    ),
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

/// İsim yanında renkli tikleri ve hareketli ikonları gösterir. Her simgeye
/// dokunulduğunda ne anlama geldiğini açıklayan bilgi penceresi açılır.
class ProfilePrivilegeBadges extends StatelessWidget {
  final String userId;
  final int maximum;

  const ProfilePrivilegeBadges({
    super.key,
    required this.userId,
    this.maximum = 4,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ProfileFeature>>(
      future: ProfileFeatureService().getUserFeatures(userId),
      builder: (context, snapshot) {
        final features = (snapshot.data ?? const <ProfileFeature>[])
            .where(
              (item) =>
                  item.kind == ProfileFeatureKind.icon ||
                  item.kind == ProfileFeatureKind.badge,
            )
            .take(maximum)
            .toList(growable: false);
        if (features.isEmpty) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: features
              .map(
                (feature) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _FeatureButton(feature: feature),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _FeatureButton extends StatelessWidget {
  final ProfileFeature feature;

  const _FeatureButton({required this.feature});

  @override
  Widget build(BuildContext context) {
    final badge = feature.kind == ProfileFeatureKind.badge;
    return Semantics(
      button: true,
      label: '${feature.name}: ${feature.description}',
      child: InkResponse(
        radius: 20,
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                AnimatedPrivilegeIcon(feature: feature, size: 30),
                const SizedBox(width: 12),
                Expanded(child: Text(feature.name)),
              ],
            ),
            content: Text(
              feature.description.isEmpty
                  ? 'Bu kullanıcı ${feature.name} ayrıcalığına sahiptir.'
                  : feature.description,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Kapat'),
              ),
            ],
          ),
        ),
        child: badge
            ? Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: feature.primaryColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: feature.primaryColor.withValues(alpha: 0.35),
                      blurRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 15),
              )
            : AnimatedPrivilegeIcon(feature: feature, size: 23),
      ),
    );
  }
}

class AnimatedPrivilegeIcon extends StatefulWidget {
  final ProfileFeature feature;
  final double size;

  const AnimatedPrivilegeIcon({
    super.key,
    required this.feature,
    this.size = 24,
  });

  @override
  State<AnimatedPrivilegeIcon> createState() => _AnimatedPrivilegeIconState();
}

class _AnimatedPrivilegeIconState extends State<AnimatedPrivilegeIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    final speed = widget.feature.configDouble('speed', 1).clamp(0.3, 3.0);
    _controller =
        AnimationController(
          vsync: this,
          duration: Duration(milliseconds: (1900 / speed).round()),
        )..repeat(
          reverse: widget.feature.configString('motion', 'rotate') != 'rotate',
        );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = widget.feature.configString('motion', 'rotate');
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        Widget result = child!;
        switch (motion) {
          case 'pulse':
            result = Transform.scale(
              scale: 0.82 + _controller.value * 0.28,
              child: result,
            );
            break;
          case 'bounce':
            result = Transform.translate(
              offset: Offset(0, -math.sin(_controller.value * math.pi) * 5),
              child: result,
            );
            break;
          case 'swing':
            result = Transform.rotate(
              angle: (_controller.value - 0.5) * 0.55,
              child: result,
            );
            break;
          default:
            result = Transform.rotate(
              angle: _controller.value * math.pi * 2,
              child: result,
            );
        }
        return result;
      },
      child: Icon(
        profileFeatureIcon(widget.feature.rendererKey),
        size: widget.size,
        color: widget.feature.primaryColor,
        shadows: [
          Shadow(
            color: widget.feature.primaryColor.withValues(alpha: 0.4),
            blurRadius: 5,
          ),
        ],
      ),
    );
  }
}

class _ProfileEffectPainter extends CustomPainter {
  final List<ProfileFeature> effects;
  final double progress;

  const _ProfileEffectPainter({required this.effects, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (var effectIndex = 0; effectIndex < effects.length; effectIndex++) {
      final effect = effects[effectIndex];
      final count = (8 * effect.configDouble('intensity', 1)).round().clamp(
        6,
        34,
      );
      final speed = effect.configDouble('speed', 1);
      final particleSize = effect.configDouble('size', 1);
      final secondary = effect.secondaryColor ?? effect.primaryColor;

      // Satın alınabilir premium tüm-profil haleleri: tek seferlik tam
      // sahne çizimi, aşağıdaki parçacık-döngüsü desenine katılmaz.
      switch (effect.rendererKey) {
        case 'royal_aura':
          paintRoyalAuraEffect(
            canvas: canvas,
            size: size,
            progress: progress * speed,
            primaryColor: effect.primaryColor,
            secondaryColor: secondary,
          );
          continue;
        case 'galaxy_swirl':
          paintGalaxySwirlEffect(
            canvas: canvas,
            size: size,
            progress: progress * speed,
            primaryColor: effect.primaryColor,
            secondaryColor: secondary,
          );
          continue;
        case 'phoenix_flame':
          paintPhoenixFlameEffect(
            canvas: canvas,
            size: size,
            progress: progress * speed,
            primaryColor: effect.primaryColor,
            secondaryColor: secondary,
          );
          continue;
        case 'crystal_shimmer':
          paintCrystalShimmerEffect(
            canvas: canvas,
            size: size,
            progress: progress * speed,
            primaryColor: effect.primaryColor,
            secondaryColor: secondary,
          );
          continue;
        case 'thunder_storm':
          paintThunderStormEffect(
            canvas: canvas,
            size: size,
            progress: progress * speed,
            primaryColor: effect.primaryColor,
            secondaryColor: secondary,
          );
          continue;
      }

      final paint = Paint()
        ..color = effect.primaryColor.withValues(alpha: 0.38)
        ..strokeWidth = 1.4 * particleSize
        ..strokeCap = StrokeCap.round;

      for (var i = 0; i < count; i++) {
        final seed = i * 97 + effectIndex * 31 + effect.priority;
        final xBase = ((seed * 43) % 997) / 997;
        final phase = (progress * speed + ((seed * 17) % 101) / 101) % 1;
        final x = xBase * size.width;
        final y = phase * size.height;
        if (effect.rendererKey == 'procedural_effect') {
          _paintProcedural(
            canvas,
            size,
            paint,
            effect.configString('pattern', 'orbit'),
            effect.configString('particle', 'spark'),
            i,
            count,
            phase,
            progress * speed,
            particleSize,
          );
          continue;
        }
        switch (effect.rendererKey) {
          case 'rain':
            canvas.drawLine(
              Offset(x, y),
              Offset(x - 4, y + 15 * particleSize),
              paint,
            );
            break;
          case 'snow':
          case 'bubbles':
            canvas.drawCircle(
              Offset(x, y),
              (effect.rendererKey == 'snow' ? 2.2 : 4.2) * particleSize,
              paint,
            );
            break;
          case 'lightning':
            if (i < 5) {
              final path = Path()
                ..moveTo(x, y * 0.45)
                ..lineTo(x - 8, y * 0.45 + 18)
                ..lineTo(x + 2, y * 0.45 + 15)
                ..lineTo(x - 5, y * 0.45 + 35);
              canvas.drawPath(path, paint..strokeWidth = 2.4);
            }
            break;
          case 'hearts':
            final textPainter = TextPainter(
              text: TextSpan(
                text: '♥',
                style: TextStyle(
                  color: paint.color,
                  fontSize: 12 * particleSize,
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            textPainter.paint(canvas, Offset(x, size.height - y));
            break;
          case 'rotate':
          case 'aurora':
            final center = Offset(size.width / 2, size.height * 0.28);
            final angle = progress * math.pi * 2 * speed + i;
            final radius = 70.0 + (i % 6) * 22;
            canvas.drawCircle(
              center +
                  Offset(
                    math.cos(angle) * radius,
                    math.sin(angle) * radius * 0.45,
                  ),
              2.5 * particleSize,
              paint,
            );
            break;
          default:
            canvas.drawCircle(Offset(x, y), 2.8 * particleSize, paint);
        }
      }
    }
  }

  void _paintProcedural(
    Canvas canvas,
    Size size,
    Paint paint,
    String pattern,
    String particle,
    int index,
    int count,
    double phase,
    double time,
    double scale,
  ) {
    final center = size.center(Offset.zero);
    final angle = (math.pi * 2 / count) * index + time * math.pi * 2;
    late Offset point;
    switch (pattern) {
      case 'spiral':
        point =
            center +
            Offset(math.cos(angle), math.sin(angle)) *
                (phase * size.shortestSide * .48);
      case 'wave':
        point = Offset(
          phase * size.width,
          center.dy + math.sin(angle * 2) * size.height * .28,
        );
      case 'burst':
        point =
            center +
            Offset(math.cos(angle), math.sin(angle)) *
                (phase * size.longestSide * .55);
      case 'vortex':
        point =
            center +
            Offset(math.cos(angle + phase * 8), math.sin(angle + phase * 8)) *
                ((1 - phase) * size.shortestSide * .46);
      case 'grid':
        point = Offset(
          (index % 6 + phase) / 6 * size.width,
          (index ~/ 6 + phase) / math.max(1, count ~/ 6) * size.height,
        );
      case 'comet':
        point = Offset(
          phase * size.width,
          (phase * phase) * size.height + math.sin(angle) * 15,
        );
      case 'halo':
        point =
            center +
            Offset(math.cos(angle), math.sin(angle) * .35) *
                (size.shortestSide * (.18 + (index % 4) * .08));
      case 'zigzag':
        point = Offset(
          phase * size.width,
          ((index.isEven ? phase : 1 - phase) * size.height),
        );
      case 'fountain':
        point = Offset(
          center.dx + math.cos(angle) * phase * size.width * .45,
          size.height - math.sin(phase * math.pi) * size.height * .8,
        );
      case 'meteor':
        point = Offset(
          phase * size.width,
          (phase + index / count) % 1 * size.height,
        );
      case 'curtain':
        point = Offset(
          (index + .5) / count * size.width,
          phase * size.height + math.sin(angle) * 10,
        );
      default:
        point =
            center +
            Offset(
              math.cos(angle) * size.width * .44,
              math.sin(angle) * size.height * .44,
            );
    }
    _drawParticle(canvas, point, paint, particle, scale, angle);
  }

  void _drawParticle(
    Canvas canvas,
    Offset point,
    Paint paint,
    String particle,
    double scale,
    double angle,
  ) {
    switch (particle) {
      case 'diamond':
        final path = Path()
          ..moveTo(point.dx, point.dy - 4 * scale)
          ..lineTo(point.dx + 3 * scale, point.dy)
          ..lineTo(point.dx, point.dy + 4 * scale)
          ..lineTo(point.dx - 3 * scale, point.dy)
          ..close();
        canvas.drawPath(path, paint);
      case 'bubble':
        canvas.drawCircle(
          point,
          4 * scale,
          paint..style = PaintingStyle.stroke,
        );
      case 'pixel':
        canvas.drawRect(
          Rect.fromCenter(center: point, width: 4 * scale, height: 4 * scale),
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
            width: 3 * scale,
            height: 8 * scale,
          ),
          paint,
        );
        canvas.restore();
      case 'rune':
        canvas.drawLine(
          point - Offset(0, 4 * scale),
          point + Offset(0, 4 * scale),
          paint,
        );
        canvas.drawLine(point, point + Offset(3 * scale, -2 * scale), paint);
      case 'star':
        canvas.drawCircle(
          point,
          2.8 * scale,
          paint..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
        );
      default:
        canvas.drawCircle(point, 2.4 * scale, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ProfileEffectPainter oldDelegate) =>
      progress != oldDelegate.progress || effects != oldDelegate.effects;
}
