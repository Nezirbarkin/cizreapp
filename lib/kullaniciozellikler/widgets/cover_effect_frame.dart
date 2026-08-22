import 'package:flutter/material.dart';

import '../models/profile_feature.dart';
import '../services/profile_feature_service.dart';
import 'creature_painters.dart';
import 'renderer_registry.dart';

/// Mevcut kapak fotoğrafı tasarımını değiştirmeden üzerine atanmış kapak
/// dekorasyonunu (kelebek çayırı, aurora, yaprak dansı vb.) çizer. Avatar
/// tarafındaki [AvatarEffectFrame] ile aynı iskeleti kullanır, ama
/// `cover_effect` türünü ve geniş banner oranını hedefler.
class CoverEffectFrame extends StatefulWidget {
  final String userId;
  final Widget child;

  const CoverEffectFrame({
    super.key,
    required this.userId,
    required this.child,
  });

  @override
  State<CoverEffectFrame> createState() => _CoverEffectFrameState();
}

class _CoverEffectFrameState extends State<CoverEffectFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Future<List<ProfileFeature>> _future;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    _future = ProfileFeatureService().getUserFeatures(widget.userId);
  }

  @override
  void didUpdateWidget(covariant CoverEffectFrame oldWidget) {
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
            .where((item) => item.kind == ProfileFeatureKind.coverEffect)
            .firstOrNull;
        if (effect == null) return widget.child;
        return AnimatedBuilder(
          animation: _controller,
          child: widget.child,
          builder: (context, child) => Stack(
            fit: StackFit.passthrough,
            children: [
              if (child != null) child,
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _CoverEffectPainter(
                        feature: effect,
                        progress: _controller.value,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CoverEffectPainter extends CustomPainter {
  final ProfileFeature feature;
  final double progress;

  const _CoverEffectPainter({required this.feature, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final speed = feature.configDouble('speed', 1);
    final secondary = feature.secondaryColor ?? feature.primaryColor;
    final animated = progress * speed;

    // Yeni yüzey çizerleri tek yerde kayıtlı (renderer_registry.dart) — aynı
    // efekt hem avatar hem kapak için tek tanımdan çizilir.
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
      case 'butterfly_meadow_cover':
        paintButterflyMeadowCover(
          canvas: canvas,
          size: size,
          progress: animated,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        break;
      case 'aurora_veil_cover':
        paintAuroraVeilCover(
          canvas: canvas,
          size: size,
          progress: animated,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        break;
      case 'petal_drift_cover':
        paintPetalDriftCover(
          canvas: canvas,
          size: size,
          progress: animated,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        break;
      case 'firefly_dusk_cover':
        paintFireflyDuskCover(
          canvas: canvas,
          size: size,
          progress: animated,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        break;
      case 'starry_night_cover':
        paintStarryNightCover(
          canvas: canvas,
          size: size,
          progress: animated,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        break;
      case 'snowfall_cover':
        paintSnowfallCover(
          canvas: canvas,
          size: size,
          progress: animated,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        break;
      case 'golden_hour_cover':
        paintGoldenHourCover(
          canvas: canvas,
          size: size,
          progress: animated,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        break;
      case 'ocean_wave_cover':
        paintOceanWaveCover(
          canvas: canvas,
          size: size,
          progress: animated,
          primaryColor: feature.primaryColor,
          secondaryColor: secondary,
        );
        break;
      case 'firework_burst_cover':
        paintFireworkBurstCover(
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
  bool shouldRepaint(covariant _CoverEffectPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.feature != feature;
}
