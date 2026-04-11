// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Web platformunda içerik için maksimum genişlik ve responsive düzen sağlar
class ResponsiveWrapper extends StatelessWidget {
  final Widget child;
  final bool centerContent;
  final double maxWidth;
  final Color? backgroundColor;
  final bool showBackground;

  const ResponsiveWrapper({
    super.key,
    required this.child,
    this.centerContent = true,
    this.maxWidth = 800,
    this.backgroundColor,
    this.showBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    // Mobil platformda olduğu gibi child'ı doğrudan döndür
    if (!kIsWeb) {
      return child;
    }

    final screenSize = MediaQuery.of(context).size;
    // Mobil web cihazlar için threshold'u 600px'e düşürdük (önceden 800px idi)
    // Bu sayede mobil web tarayıcılarda desktop modu devreye girmeyecek
    final isDesktop = screenSize.width > 600;
    final bgColor = backgroundColor ?? Theme.of(context).colorScheme.surface;

    // Mobil web cihazlarda child'ı doğrudan döndür (mobil uygulama gibi)
    if (!isDesktop) {
      return child;
    }

    // Web platformunda responsive wrapper uygula (sadece gerçek desktop cihazlarda)
    Widget content = child;

    if (centerContent) {
      content = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
    }

    // Arkaplan için Container
    if (showBackground) {
      content = Container(
        color: bgColor,
        child: content,
      );
    }

    // Ekran genişliğine göre padding ekle
    content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: content,
    );

    return content;
  }
}

/// Web'de ekran yapısını koruyan scaffold wrapper
class ResponsiveScaffoldWrapper extends StatelessWidget {
  final Widget child;
  final bool extendBody;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;

  const ResponsiveScaffoldWrapper({
    super.key,
    required this.child,
    this.extendBody = false,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
  });

  @override
  Widget build(BuildContext context) {
    // Mobil platformda olduğu gibi child'ı doğrudan döndür
    if (!kIsWeb) {
      return child;
    }

    // Web'de maksimum genişlik ile merkezi layout
    final screenSize = MediaQuery.of(context).size;
    // Mobil web cihazlar için threshold'u 600px'e düşürdük
    final isDesktop = screenSize.width > 600;

    // Mobil web tarayıcılarda child'ı doğrudan döndür (mobil uygulama gibi)
    if (!isDesktop) {
      return child;
    }

    // Masaüstünde FloatingActionButton'ı ortalı göstermek için Stack kullanıyoruz
    final fab = floatingActionButton;
    final fabCentered = fab != null
        ? Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: fab,
            ),
          )
        : null;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      extendBody: extendBody,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: screenSize.width > 900
                  ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ]
                  : null,
            ),
            child: child,
          ),
        ),
      ),
      floatingActionButton: fabCentered,
      floatingActionButtonLocation: floatingActionButtonLocation,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

/// Web'de bottom navigation bar için responsive wrapper
class ResponsiveBottomNav extends StatelessWidget {
  final Widget child;

  const ResponsiveBottomNav({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return child;
    }

    final screenSize = MediaQuery.of(context).size;
    // Mobil web cihazlar için threshold'u 600px'e düşürdük
    final isDesktop = screenSize.width > 600;

    if (!isDesktop) {
      return child;
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: child,
      ),
    );
  }
}
