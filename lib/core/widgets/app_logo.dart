import 'package:flutter/material.dart';

/// CizreApp Logo Widget
/// Logo dosyalarını assets/logos/ klasöründen yükler
class AppLogo extends StatelessWidget {
  final double? width;
  final double? height;
  final BoxFit fit;
  final String variant; // 'default', 'white', 'dark'

  const AppLogo({
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.variant = 'default',
  });

  /// Varsayılan logo (koyu/yeşil)
  factory AppLogo.primary({
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
  }) {
    return AppLogo(
      width: width,
      height: height,
      fit: fit,
      variant: 'default',
    );
  }

  /// Beyaz arkaplan için koyu logo
  factory AppLogo.white({
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
  }) {
    return AppLogo(
      width: width,
      height: height,
      fit: fit,
      variant: 'white',
    );
  }

  /// Koyu arkaplan için beyaz logo
  factory AppLogo.dark({
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
  }) {
    return AppLogo(
      width: width,
      height: height,
      fit: fit,
      variant: 'dark',
    );
  }

  String get _logoAsset {
    switch (variant) {
      case 'white':
        return 'assets/logos/app_logo_white.png';
      case 'dark':
        return 'assets/logos/app_logo_dark.png';
      default:
        return 'assets/logos/app_logo.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Image.asset(
        _logoAsset,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          // Logo dosyası bulunamadıkça placeholder göster
          return Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.image_not_supported_outlined,
                    size: (width ?? 100) * 0.4,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Logo\nYükleniyor',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Splash Screen Logo Widget
class SplashLogo extends StatelessWidget {
  final double size;
  final Duration animationDuration;

  const SplashLogo({
    super.key,
    this.size = 200,
    this.animationDuration = const Duration(milliseconds: 800),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: animationDuration,
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          'assets/logos/splash_logo.png',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            // Splash logo dosyası yoksa placeholder göster
            return Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(
                  Icons.image_not_supported_outlined,
                  size: 48,
                  color: Colors.grey,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Küçük Logo (AppBar, Navbar vb. için)
class MiniLogo extends StatelessWidget {
  final double size;
  final Color? backgroundColor;

  const MiniLogo({
    super.key,
    this.size = 32,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Image.asset(
          'assets/logos/app_logo.png',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.store,
                size: 16,
                color: Colors.grey,
              ),
            );
          },
        ),
      ),
    );
  }
}
