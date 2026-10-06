// Snapchat/Instagram tarzı tam ekran fotoğraf kırpma editörü.
//
// image_cropper'ın aksine tamamen Flutter widget'larıyla çizilir: web dahil
// her platformda aynı görünür, dart:ui üzerinden orijinal fotoğrafın ham
// piksellerinden kırpar (ekran çözünürlüğüne bağlı bir "screenshot" değildir).
//
// Kullanım:
// - `showImmersiveCropEditor(context, imageBytes: ..., shape: ...)` sabit
//   çerçeveyle (profil fotoğrafı, kapak) kırpılmış PNG baytlarını döner.
// - `showImmersiveAspectCropEditor(...)` oran seçenekli (gönderi fotoğrafı)
//   kırpma yapar; baytlarla birlikte seçilen oranı döner.
// Kullanıcı iptal ederse ikisi de null döner.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/utils/image_crop_utils.dart';

enum ImmersiveCropShape { circle, rect }

/// Oran seçenekli editördeki bir çerçeve seçeneği.
class ImmersiveCropAspect {
  const ImmersiveCropAspect({
    required this.label,
    required this.ratioLabel,
    required this.ratio,
  });

  /// "Dikey", "Kare"...
  final String label;

  /// "4:5", "1:1"...
  final String ratioLabel;

  /// Genişlik / yükseklik.
  final double ratio;
}

/// Kırpma sonucu: PNG baytları ve kırpıldığı çerçeve oranı.
class ImmersiveCropResult {
  const ImmersiveCropResult({required this.bytes, required this.aspectRatio});

  final Uint8List bytes;
  final double aspectRatio;
}

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
}) async {
  final result = await Navigator.of(context).push<ImmersiveCropResult?>(
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
  return result?.bytes;
}

/// Oran seçenekli dikdörtgen kırpma editörü (gönderi fotoğrafları).
///
/// Profil editöründen farkları: fotoğraf EKRANI değil ÇERÇEVEYİ kaplayacak
/// kadar küçültülebilir (yatay bir fotoğrafın tamamı yatay çerçeveye
/// sığdırılabilsin), alttaki çiplerle oran değiştirilebilir, çerçevede üçler
/// kuralı ızgarası çizilir ve çıktı genişliği [maxOutputWidth]'i ve kaynağın
/// kendi çözünürlüğünü aşmaz.
Future<ImmersiveCropResult?> showImmersiveAspectCropEditor(
  BuildContext context, {
  required Uint8List imageBytes,
  required String title,
  required List<ImmersiveCropAspect> aspects,
  required double initialAspect,
  int maxOutputWidth = 1080,
  String hintText = 'İki parmakla yakınlaştır • Sürükleyerek konumlandır',
  String footnote = '',
}) {
  assert(aspects.isNotEmpty, 'En az bir oran seçeneği gerekir');
  return Navigator.of(context).push<ImmersiveCropResult?>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ImmersiveCropScreen(
        initialBytes: imageBytes,
        shape: ImmersiveCropShape.rect,
        title: title,
        rectAspectRatio: initialAspect,
        hintText: hintText,
        sizeInfoText: footnote,
        onPickAnother: null,
        aspects: aspects,
        fitToHole: true,
        maxOutputWidth: maxOutputWidth,
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

  /// Doluysa altta oran çipleri gösterilir (yalnızca dikdörtgen).
  final List<ImmersiveCropAspect>? aspects;

  /// true: fotoğrafın kaplaması gereken alan ekran değil çerçevedir.
  final bool fitToHole;

  /// null: eski sabit çıktı boyutu (daire 1024, dikdörtgen 1280 genişlik).
  final int? maxOutputWidth;

  const _ImmersiveCropScreen({
    required this.initialBytes,
    required this.shape,
    required this.title,
    required this.rectAspectRatio,
    required this.hintText,
    required this.sizeInfoText,
    required this.onPickAnother,
    this.aspects,
    this.fitToHole = false,
    this.maxOutputWidth,
  }) : assert(!fitToHole || shape == ImmersiveCropShape.rect);

  @override
  State<_ImmersiveCropScreen> createState() => _ImmersiveCropScreenState();
}

class _ImmersiveCropScreenState extends State<_ImmersiveCropScreen> {
  late Uint8List _bytes;
  ui.Image? _image;

  /// Dikdörtgen çerçevenin güncel oranı (oran çipleriyle değişebilir).
  late double _aspect;

  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _startScale = 1.0;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;

  bool _saving = false;

  bool get _hasAspectOptions =>
      widget.aspects != null && widget.aspects!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _bytes = widget.initialBytes;
    _aspect = widget.rectAspectRatio;
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

  /// Fotoğrafın kaplaması gereken alan: eski editörde tüm ekran, oran
  /// seçenekli editörde yalnızca çerçeve.
  Size _coverArea(Size screenSize) =>
      widget.fitToHole ? _holeRect(screenSize).size : screenSize;

  /// Kaplanacak alanı tamamen dolduran taban ölçek (BoxFit.cover mantığı).
  double _baseScale(Size screenSize) {
    final img = _image!;
    final area = _coverArea(screenSize);
    final byWidth = area.width / img.width;
    final byHeight = area.height / img.height;
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
    }
    // Çerçeve ekran genişliğinde; çok uzun olursa (4:5 gibi) yükseklik
    // sınırlanır ve genişlik de ORANLA birlikte daraltılır. Eskiden yalnız
    // yükseklik kırpılıyordu: delik oranını kaybediyor, çıktı da (oranlı
    // boyutta üretildiği için) dikeyde gerilmiş çıkıyordu.
    final maxHeight = screenSize.height * (_hasAspectOptions ? 0.6 : 0.5);
    var h = screenSize.width / _aspect;
    if (h > maxHeight) h = maxHeight;
    final w = math.min(screenSize.width, h * _aspect);
    return Rect.fromCenter(
      center: Offset(screenSize.width / 2, screenSize.height * 0.5),
      width: w,
      height: h,
    );
  }

  void _clampOffset(Size screenSize) {
    final img = _image!;
    final total = _baseScale(screenSize) * _scale;
    final dispW = img.width * total;
    final dispH = img.height * total;
    // Fotoğraf ekranın (dikdörtgende çerçeveyle aynı) ortasına yerleşir; bu
    // yüzden kaplanacak alan da ortalanmış kabul edilir.
    final area = _coverArea(screenSize);
    final maxX = ((dispW - area.width) / 2).clamp(0.0, double.infinity);
    final maxY = ((dispH - area.height) / 2).clamp(0.0, double.infinity);
    _offset = Offset(_offset.dx.clamp(-maxX, maxX), _offset.dy.clamp(-maxY, maxY));
  }

  void _setAspect(double ratio) {
    if ((ratio - _aspect).abs() < 0.0001) return;
    setState(() {
      _aspect = ratio;
      // Çerçeve değişince konum sıfırlanır: eski konum yeni çerçevede
      // fotoğrafın dışına taşabilirdi.
      _scale = 1.0;
      _offset = Offset.zero;
    });
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
      final maxOutputWidth = widget.maxOutputWidth;
      final (int outW, int outH) = maxOutputWidth != null
          ? cropOutputSize(srcRect, _aspect, maxWidth: maxOutputWidth)
          : (isCircle ? 1024 : 1280, isCircle ? 1024 : (1280 / _aspect).round());

      final bytes = await renderImageRegionPng(img, srcRect, outW, outH);
      if (mounted) {
        Navigator.of(context).pop(ImmersiveCropResult(bytes: bytes, aspectRatio: _aspect));
      }
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
                            // Fotoğraf `cover` gereği ekrandan BÜYÜKTÜR ve
                            // taşması gerekir. Eskiden `Center > SizedBox`
                            // vardı: SizedBox ebeveyninin sınırını aşamadığı
                            // için fotoğraf ekran oranına EZİLİYOR, kırpma
                            // hesabı ise ezilmemiş boyuta göre yapılıyordu —
                            // kullanıcının gördüğü alanla çıktı farklıydı.
                            child: OverflowBox(
                              minWidth: 0,
                              minHeight: 0,
                              maxWidth: double.infinity,
                              maxHeight: double.infinity,
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
                          painter: _MaskPainter(
                            hole: _holeRect(screenSize),
                            shape: widget.shape,
                            showGrid: _hasAspectOptions,
                          ),
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
    final topPad = MediaQuery.paddingOf(context).top;
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
              tooltip: 'Vazgeç',
              background: Colors.black.withValues(alpha: 0.4),
              onTap: () => Navigator.of(context).pop(null),
            ),
            Text(
              widget.title,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
            ),
            _RoundIconButton(
              icon: Icons.check,
              tooltip: 'Onayla',
              background: Theme.of(context).colorScheme.primary,
              onTap: () => _confirm(screenSize),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.only(
          bottom: bottomPad + (_hasAspectOptions ? 20 : 28),
          top: _hasAspectOptions ? 36 : 60,
          left: 24,
          right: 24,
        ),
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
            if (_hasAspectOptions) ...[
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final aspect in widget.aspects!)
                    _AspectChip(
                      aspect: aspect,
                      selected: (aspect.ratio - _aspect).abs() < 0.0001,
                      onTap: () => _setAspect(aspect.ratio),
                    ),
                ],
              ),
              const SizedBox(height: 14),
            ],
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
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Oran seçeneği çipi: oranın küçük bir çerçeve simgesi + ad + oran.
class _AspectChip extends StatelessWidget {
  final ImmersiveCropAspect aspect;
  final bool selected;
  final VoidCallback onTap;

  const _AspectChip({required this.aspect, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.black : Colors.white;
    return Semantics(
      button: true,
      selected: selected,
      label: '${aspect.label} ${aspect.ratioLabel}',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? Colors.white : Colors.white.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectFrameIcon(ratio: aspect.ratio, color: foreground),
              const SizedBox(width: 7),
              Text(
                aspect.label,
                style: TextStyle(color: foreground, fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 4),
              Text(
                aspect.ratioLabel,
                style: TextStyle(
                  color: foreground.withValues(alpha: 0.7),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bir oranın küçük çerçeve simgesi (16 px yüksekliğe sığar).
class AspectFrameIcon extends StatelessWidget {
  const AspectFrameIcon({super.key, required this.ratio, required this.color, this.size = 16});

  final double ratio;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final w = ratio >= 1 ? size : size * ratio;
    final h = ratio >= 1 ? size / ratio : size;
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 1.6),
            borderRadius: BorderRadius.circular(2.5),
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color background;
  final VoidCallback onTap;

  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.background,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
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
      ),
    );
  }
}

class _MaskPainter extends CustomPainter {
  final Rect hole;
  final ImmersiveCropShape shape;
  final bool showGrid;

  _MaskPainter({required this.hole, required this.shape, this.showGrid = false});

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

    // Üçler kuralı ızgarası: fotoğrafı çerçevede konumlandırmayı kolaylaştırır.
    if (showGrid) {
      final gridPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.32)
        ..strokeWidth = 1;
      for (var i = 1; i < 3; i++) {
        final x = hole.left + hole.width * i / 3;
        final y = hole.top + hole.height * i / 3;
        canvas.drawLine(Offset(x, hole.top), Offset(x, hole.bottom), gridPaint);
        canvas.drawLine(Offset(hole.left, y), Offset(hole.right, y), gridPaint);
      }
    }

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
      oldDelegate.hole != hole || oldDelegate.shape != shape || oldDelegate.showGrid != showGrid;
}
