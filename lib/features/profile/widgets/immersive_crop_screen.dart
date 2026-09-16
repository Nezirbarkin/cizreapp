// Snapchat/Instagram tarzı tam ekran fotoğraf kırpma editörü.
//
// image_cropper'ın aksine tamamen Flutter widget'larıyla çizilir: web dahil
// her platformda aynı görünür, dart:ui üzerinden orijinal fotoğrafın ham
// piksellerinden kırpar (ekran çözünürlüğüne bağlı bir "screenshot" değildir).
//
// Kullanım: `showImmersiveCropEditor(context, imageBytes: ..., shape: ...)`
// kırpılmış PNG baytlarını döner; kullanıcı iptal ederse null döner.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum ImmersiveCropShape { circle, rect }

/// Tam ekran, karartılmış maskeli kırpma editörünü açar.
///
/// [imageBytes] orijinal (kırpılmamış) fotoğraf baytlarıdır. Kullanıcı
/// sürükleyip kıstırarak konumlandırır; onayladığında kırpılmış PNG baytları
/// döner, geri/iptal ile null döner.
Future<Uint8List?> showImmersiveCropEditor(
  BuildContext context, {
  required Uint8List imageBytes,
  required ImmersiveCropShape shape,
  required String title,
  double rectAspectRatio = 16 / 9,
  String hintText = 'İki parmakla yakınlaştır • Sürükleyerek konumlandır',
  String sizeInfoText = '',
  Future<Uint8List?> Function()? onPickAnother,
}) {
  return Navigator.of(context).push<Uint8List?>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ImmersiveCropScreen(
        initialBytes: imageBytes,
        shape: shape,
        title: title,
        rectAspectRatio: rectAspectRatio,
        hintText: hintText,
        sizeInfoText: sizeInfoText,
        onPickAnother: onPickAnother,
      ),
    ),
  );
}

class _ImmersiveCropScreen extends StatefulWidget {
  final Uint8List initialBytes;
  final ImmersiveCropShape shape;
  final String title;
  final double rectAspectRatio;
  final String hintText;
  final String sizeInfoText;
  final Future<Uint8List?> Function()? onPickAnother;

  const _ImmersiveCropScreen({
    required this.initialBytes,
    required this.shape,
    required this.title,
    required this.rectAspectRatio,
    required this.hintText,
    required this.sizeInfoText,
    required this.onPickAnother,
  });

  @override
  State<_ImmersiveCropScreen> createState() => _ImmersiveCropScreenState();
}

class _ImmersiveCropScreenState extends State<_ImmersiveCropScreen> {
  late Uint8List _bytes;
  ui.Image? _image;

  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _startScale = 1.0;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _bytes = widget.initialBytes;
    _decode();
  }

  Future<void> _decode() async {
    final codec = await ui.instantiateImageCodec(_bytes);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() {
      _image = frame.image;
      _scale = 1.0;
      _offset = Offset.zero;
    });
  }

  /// Ekranı tamamen kaplamak için gereken taban ölçek (BoxFit.cover mantığı).
  double _baseScale(Size screenSize) {
    final img = _image!;
    final byWidth = screenSize.width / img.width;
    final byHeight = screenSize.height / img.height;
    return byWidth > byHeight ? byWidth : byHeight;
  }

  /// Karartılmış maskenin ortasındaki "delik" — fotoğrafın görünür kalacağı alan.
  Rect _holeRect(Size screenSize) {
    if (widget.shape == ImmersiveCropShape.circle) {
      final d = (screenSize.width * 0.68).clamp(120.0, screenSize.height * 0.55);
      return Rect.fromCenter(
        center: Offset(screenSize.width / 2, screenSize.height * 0.44),
        width: d,
        height: d,
      );
    } else {
      final w = screenSize.width;
      var h = w / widget.rectAspectRatio;
      h = h.clamp(80.0, screenSize.height * 0.5);
      return Rect.fromCenter(
        center: Offset(screenSize.width / 2, screenSize.height * 0.5),
        width: w,
        height: h,
      );
    }
  }

  void _clampOffset(Size screenSize) {
    final img = _image!;
    final total = _baseScale(screenSize) * _scale;
    final dispW = img.width * total;
    final dispH = img.height * total;
    final maxX = ((dispW - screenSize.width) / 2).clamp(0.0, double.infinity);
    final maxY = ((dispH - screenSize.height) / 2).clamp(0.0, double.infinity);
    _offset = Offset(_offset.dx.clamp(-maxX, maxX), _offset.dy.clamp(-maxY, maxY));
  }

  Future<void> _pickAnother() async {
    if (widget.onPickAnother == null) return;
    final newBytes = await widget.onPickAnother!();
    if (newBytes == null || !mounted) return;
    setState(() {
      _bytes = newBytes;
      _image = null;
    });
    await _decode();
  }

  Future<void> _confirm(Size screenSize) async {
    if (_image == null || _saving) return;
    setState(() => _saving = true);
    try {
      final img = _image!;
      final total = _baseScale(screenSize) * _scale;
      final imgLeft = screenSize.width / 2 + _offset.dx - (img.width * total) / 2;
      final imgTop = screenSize.height / 2 + _offset.dy - (img.height * total) / 2;
      final hole = _holeRect(screenSize);

      final srcRect = Rect.fromLTRB(
        ((hole.left - imgLeft) / total).clamp(0.0, img.width.toDouble()),
        ((hole.top - imgTop) / total).clamp(0.0, img.height.toDouble()),
        ((hole.right - imgLeft) / total).clamp(0.0, img.width.toDouble()),
        ((hole.bottom - imgTop) / total).clamp(0.0, img.height.toDouble()),
      );

      final bool isCircle = widget.shape == ImmersiveCropShape.circle;
      final int outW = isCircle ? 1024 : 1280;
      final int outH = isCircle ? 1024 : (1280 / widget.rectAspectRatio).round();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final dst = Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble());
      // Beyaz zemin: JPEG'e sıkıştırırken saydamlık siyaha dönmesin diye.
      canvas.drawRect(dst, Paint()..color = Colors.white);
      canvas.drawImageRect(img, srcRect, dst, Paint()..filterQuality = FilterQuality.high);
      final picture = recorder.endRecording();
      final outImage = await picture.toImage(outW, outH);
      final byteData = await outImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('PNG kodlanamadı');

      if (mounted) Navigator.of(context).pop(byteData.buffer.asUint8List());
    } catch (e) {
      debugPrint('Kırpma hatası: $e');
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fotoğraf kırpılamadı: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _image == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : LayoutBuilder(
              builder: (context, constraints) {
                final screenSize = constraints.biggest;
                final img = _image!;
                final base = _baseScale(screenSize);

                return GestureDetector(
                  onScaleStart: (details) {
                    _startScale = _scale;
                    _startOffset = _offset;
                    _startFocal = details.focalPoint;
                  },
                  onScaleUpdate: (details) {
                    setState(() {
                      _scale = (_startScale * details.scale).clamp(1.0, 5.0);
                      _offset = _startOffset + (details.focalPoint - _startFocal);
                      _clampOffset(screenSize);
                    });
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRect(
                        child: Transform.translate(
                          offset: _offset,
                          child: Transform.scale(
                            scale: _scale,
                            child: Center(
                              child: SizedBox(
                                width: img.width * base,
                                height: img.height * base,
                                child: RawImage(image: img, fit: BoxFit.fill),
                              ),
                            ),
                          ),
                        ),
                      ),
                      IgnorePointer(
                        child: CustomPaint(
                          size: screenSize,
                          painter: _MaskPainter(hole: _holeRect(screenSize), shape: widget.shape),
                        ),
                      ),
                      _buildTopBar(screenSize),
                      _buildBottomBar(),
                      if (_saving)
                        Container(
                          color: Colors.black45,
                          child: const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildTopBar(Size screenSize) {
    final topPad = MediaQuery.of(context).padding.top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(top: topPad + 12, left: 18, right: 18, bottom: 20),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x8C000000), Color(0x00000000)],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _RoundIconButton(
              icon: Icons.close,
              background: Colors.black.withValues(alpha: 0.4),
              onTap: () => Navigator.of(context).pop(null),
            ),
            Text(
              widget.title,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
            ),
            _RoundIconButton(
              icon: Icons.check,
              background: Theme.of(context).colorScheme.primary,
              onTap: () => _confirm(screenSize),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.only(bottom: bottomPad + 28, top: 60, left: 24, right: 24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0x9E000000), Color(0x00000000)],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.hintText,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5),
              textAlign: TextAlign.center,
            ),
            if (widget.onPickAnother != null) ...[
              const SizedBox(height: 14),
              GestureDetector(
                onTap: _pickAnother,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.photo_library_outlined, size: 17, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Galeriden Seç',
                        style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (widget.sizeInfoText.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                widget.sizeInfoText,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final Color background;
  final VoidCallback onTap;

  const _RoundIconButton({required this.icon, required this.background, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _MaskPainter extends CustomPainter {
  final Rect hole;
  final ImmersiveCropShape shape;

  _MaskPainter({required this.hole, required this.shape});

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final holePath = Path();
    if (shape == ImmersiveCropShape.circle) {
      holePath.addOval(hole);
    } else {
      holePath.addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(4)));
    }
    final masked = Path.combine(PathOperation.difference, full, holePath);
    canvas.drawPath(masked, Paint()..color = Colors.black.withValues(alpha: 0.62));

    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    if (shape == ImmersiveCropShape.circle) {
      canvas.drawOval(hole, borderPaint);
    } else {
      canvas.drawRRect(RRect.fromRectAndRadius(hole, const Radius.circular(4)), borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MaskPainter oldDelegate) =>
      oldDelegate.hole != hole || oldDelegate.shape != shape;
}
