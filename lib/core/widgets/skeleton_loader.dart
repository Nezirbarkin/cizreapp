import 'package:flutter/material.dart';

/// Skeleton Loader Widget
/// Veri yüklenirken shimmer efekti göstererek "content flashing" sorununu çözer
class SkeletonLoader extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final Color? baseColor;
  final Color? highlightColor;

  const SkeletonLoader({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.baseColor,
    this.highlightColor,
  });

  /// Yuvarlak avatar skeleton
  factory SkeletonLoader.avatar({double size = 50}) {
    return SkeletonLoader(
      width: size,
      height: size,
      borderRadius: BorderRadius.circular(size / 2),
    );
  }

  /// Text skeleton (satır yüksekliğinde)
  factory SkeletonLoader.text({double? width, double height = 14}) {
    return SkeletonLoader(
      width: width,
      height: height,
      borderRadius: BorderRadius.circular(4),
    );
  }

  /// Rectangle (kart vb.)
  factory SkeletonLoader.rect({
    double? width,
    double height = 100,
    BorderRadius? borderRadius,
  }) {
    return SkeletonLoader(
      width: width,
      height: height,
      borderRadius: borderRadius ?? BorderRadius.circular(12),
    );
  }

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AnimatedShimmer(
      animation: _animation,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: widget.baseColor ?? Colors.grey.shade300,
          borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class _AnimatedShimmer extends AnimatedWidget {
  final Widget child;

  const _AnimatedShimmer({
    required Animation<double> animation,
    required this.child,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    final animation = listenable as Animation<double>;
    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (bounds) {
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.grey.shade300,
            Colors.grey.shade100,
            Colors.grey.shade300,
          ],
          stops: const [0.0, 0.5, 1.0],
          transform: _SlidingGradientTransform(
            slidePercent: animation.value,
          ),
        ).createShader(bounds);
      },
      child: child,
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform({required this.slidePercent});

  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0.0, 0.0);
  }
}

/// Pre-built skeleton layouts
class Skeletons {
  /// Post kartı skeleton
  static Widget postCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Avatar + Name + Time
          Row(
            children: [
              SkeletonLoader.avatar(size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLoader.text(width: 120),
                    const SizedBox(height: 4),
                    SkeletonLoader.text(width: 80, height: 12),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Content
          SkeletonLoader.text(height: 16),
          const SizedBox(height: 4),
          SkeletonLoader.text(height: 16),
          const SizedBox(height: 4),
          SkeletonLoader.text(width: 200, height: 16),
          const SizedBox(height: 12),
          // Image placeholder
          SkeletonLoader.rect(height: 200),
        ],
      ),
    );
  }

  /// Comment skeleton
  static Widget comment() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonLoader.avatar(size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonLoader.text(width: 100, height: 14),
              const SizedBox(height: 4),
              SkeletonLoader.text(height: 14),
              const SizedBox(height: 4),
              SkeletonLoader.text(width: 150, height: 14),
            ],
          ),
        ),
      ],
    );
  }

  /// Product card skeleton
  static Widget productCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonLoader.rect(
          height: 150,
          borderRadius: BorderRadius.circular(16),
        ),
        const SizedBox(height: 8),
        SkeletonLoader.text(height: 16),
        const SizedBox(height: 4),
        SkeletonLoader.text(width: 80, height: 14),
        const SizedBox(height: 8),
        SkeletonLoader.text(width: 60, height: 18),
      ],
    );
  }

  /// Shop card skeleton
  static Widget shopCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonLoader.rect(
          height: 120,
          borderRadius: BorderRadius.circular(16),
        ),
        const SizedBox(height: 8),
        SkeletonLoader.text(height: 16),
        const SizedBox(height: 4),
        SkeletonLoader.text(width: 100, height: 14),
      ],
    );
  }

  /// List item skeleton (chat, notification vs.)
  static Widget listItem({bool leadingAvatar = true}) {
    return Row(
      children: [
        if (leadingAvatar) ...[
          SkeletonLoader.avatar(size: 48),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonLoader.text(height: 16),
              const SizedBox(height: 6),
              SkeletonLoader.text(width: double.infinity, height: 14),
              const SizedBox(height: 4),
              SkeletonLoader.text(width: 200, height: 14),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SkeletonLoader.text(width: 50, height: 14),
      ],
    );
  }

  /// Detail page header skeleton
  static Widget detailHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SkeletonLoader.avatar(size: 60),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonLoader.text(height: 20),
                  const SizedBox(height: 8),
                  SkeletonLoader.text(width: 150, height: 14),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SkeletonLoader.rect(height: 16),
        const SizedBox(height: 8),
        SkeletonLoader.rect(height: 16),
        const SizedBox(height: 8),
        SkeletonLoader.rect(height: 16),
      ],
    );
  }

  /// Grid item skeleton
  static Widget gridItem() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonLoader.rect(
          height: 100,
          borderRadius: BorderRadius.circular(12),
        ),
        const SizedBox(height: 8),
        SkeletonLoader.text(height: 14),
        const SizedBox(height: 4),
        SkeletonLoader.text(width: 60, height: 12),
      ],
    );
  }

  /// Circle avatar with name skeleton
  static Widget userTile() {
    return Row(
      children: [
        SkeletonLoader.avatar(size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonLoader.text(width: 120, height: 16),
              const SizedBox(height: 4),
              SkeletonLoader.text(width: 80, height: 12),
            ],
          ),
        ),
      ],
    );
  }

  /// Multiple skeleton items
  static Widget list({int count = 5, bool leadingAvatar = true}) {
    return Column(
      children: List.generate(
        count,
        (index) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Skeletons.listItem(leadingAvatar: leadingAvatar),
        ),
      ),
    );
  }

  /// Grid of skeleton items
  static Widget grid({int crossAxisCount = 2, int itemCount = 6}) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) => Skeletons.gridItem(),
    );
  }
}
