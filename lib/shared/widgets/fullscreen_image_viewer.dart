// =============================================================================
// Tam ekran görüntüleyici — görev görseli + ekran görüntüsü önizleme için.
// InteractiveViewer ile pinch-zoom + pan destekli.
// =============================================================================

// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FullscreenImageViewer extends StatefulWidget {
  final String imageUrl;
  final String? heroTag;
  final String? caption;

  const FullscreenImageViewer({
    super.key,
    required this.imageUrl,
    this.heroTag,
    this.caption,
  });

  static void open(
    BuildContext context, {
    required String imageUrl,
    String? heroTag,
    String? caption,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => FullscreenImageViewer(
          imageUrl: imageUrl,
          heroTag: heroTag,
          caption: caption,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  late final TransformationController _ctrl;
  late final TapDownDetails _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    _ctrl = TransformationController();
    _doubleTapDetails = TapDownDetails();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (_ctrl.value != Matrix4.identity()) {
      _ctrl.value = Matrix4.identity();
    } else {
      // Çift dokunuşla hafif zoom (güvenli Matrix API)
      _ctrl.value = Matrix4.diagonal3Values(2.5, 2.5, 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.caption ?? '',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ),
      body: GestureDetector(
        onDoubleTapDown: (d) => _doubleTapDetails,
        onDoubleTap: _handleDoubleTap,
        child: Center(
          child: Hero(
            tag: widget.heroTag ?? widget.imageUrl,
            child: InteractiveViewer(
              transformationController: _ctrl,
              minScale: 1.0,
              maxScale: 5.0,
              child: Image.network(
                widget.imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image, color: Colors.white54, size: 64),
                      SizedBox(height: 8),
                      Text(
                        'Görsel yüklenemedi',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}