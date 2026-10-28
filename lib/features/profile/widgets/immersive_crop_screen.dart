// Snapchat/Instagram tarzı tam ekran fotoğraf kırpma editörü.
//
// image_cropper'ın aksine tamamen Flutter widget'larıyla çizilir: web dahil
// her platformda aynı görünür, dart:ui üzerinden orijinal fotoğrafın ham
// piksellerinden kırpar (ekran çözünürlüğüne bağlı bir "screenshot" değildir).
//
// Kullanım:
// - `showImmersiveCropEditor(context, imageBytes: ..., shape: ...)` sabit
//   çerçeveyle (profil fotoğrafı, kapak) kırpılmış PNG baytlarını döner.
//   Üstte/altta sabit çubuklu düzen: kenardan kenara çerçeve, yakınlaştırma
//   kaydırıcısı, döndür / aynala / sıfırla araçları.
// - `showImmersiveAspectCropEditor(...)` oran seçenekli (gönderi fotoğrafı)
//   kırpma yapar; baytlarla birlikte seçilen oranı döner.
// Kullanıcı iptal ederse ikisi de null döner.
//
// İki editörde de fotoğrafın kaplaması gereken alan ÇERÇEVEDİR, ekran değil:
// en uzak yakınlaştırmada fotoğrafın kısa kenarının tamamı çerçeveye girer.
// Kıstırma parmakların altındaki noktayı yerinde tutar; çift dokunuş ve fare
// tekerleği de yakınlaştırır.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/image_crop_utils.dart';

enum ImmersiveCropShape { circle, rect }

const String _defaultHint =
    'İki parmakla ya da çift dokunarak yakınlaştır • Sürükleyerek konumlandır';

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

/// Sabit çerçeveli kırpma editörünü açar (profil fotoğrafı, kapak).
///
/// [imageBytes] orijinal (kırpılmamış) fotoğraf baytlarıdır. Kullanıcı
/// sürükleyip kıstırarak, kaydırıcıyla ya da çift dokunarak konumlandırır,
/// isterse döndürür/aynalar; onayladığında kırpılmış PNG baytları döner,
/// geri/iptal ile null döner. Çıktı kenarı daire için 1024, dikdörtgen için
/// 1280 px'i ve seçilen bölgenin kendi çözünürlüğünü aşmaz.
Future<Uint8List?> showImmersiveCropEditor(
  BuildContext context, {
  required Uint8List imageBytes,
  required ImmersiveCropShape shape,
  required String title,
  double rectAspectRatio = 16 / 9,
  String hintText = _defaultHint,
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
/// Profil editöründen farkları: fotoğraf tam ekrana yayılır, çubuklar üstünde
/// geçişli durur, alttaki çiplerle oran değiştirilebilir, çerçevede üçler
/// kuralı ızgarası hep çizilir ve çıktı genişliği [maxOutputWidth]'i ve
/// kaynağın kendi çözünürlüğünü aşmaz.
Future<ImmersiveCropResult?> showImmersiveAspectCropEditor(
  BuildContext context, {
  required Uint8List imageBytes,
  required String title,
  required List<ImmersiveCropAspect> aspects,
  required double initialAspect,
  int maxOutputWidth = 1080,
  String hintText = _defaultHint,
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

  /// Doluysa altta oran çipleri gösterilir (yalnızca dikdörtgen) ve editör
  /// tam ekran düzende açılır.
  final List<ImmersiveCropAspect>? aspects;

  /// null: daire 1024, dikdörtgen 1280 px genişlik sınırı.
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
    this.maxOutputWidth,
  });

  @override
  State<_ImmersiveCropScreen> createState() => _ImmersiveCropScreenState();
}

class _ImmersiveCropScreenState extends State<_ImmersiveCropScreen>
    with SingleTickerProviderStateMixin {
  static const double _maxScale = 5.0;

  /// Yakınlaştır/uzaklaştır düğmelerinin bir adımı.
  static const double _zoomStep = 1.5;

  /// Çift dokunuşun yakınlaştırdığı ölçek.
  static const double _doubleTapScale = 2.5;

  /// Sabit çubuklu düzende çerçevenin kırpma alanı kenarlarına uzaklığı.
  static const double _framedHoleMargin = 20;

  late Uint8List _bytes;

  /// Çözülmüş orijinal fotoğraf.
  ui.Image? _source;

  /// Ekranda gösterilen ve kırpılan görsel: döndürülmüş/aynalanmışsa ondan
  /// üretilmiş kopya, değilse [_source]'un kendisi.
  ui.Image? _image;

  /// Ekrandaki görüntü = önce aynala ([_mirrored]), sonra [_quarterTurns] kez
  /// saat yönünün tersine 90° döndür.
  int _quarterTurns = 0;
  bool _mirrored = false;

  /// Dikdörtgen çerçevenin güncel oranı (oran çipleriyle değişebilir).
  late double _aspect;

  /// 1 = fotoğraf çerçeveyi tam kaplar (en uzak hali).
  double _scale = 1.0;

  /// Fotoğraf merkezinin çerçeve merkezine göre kayması.
  Offset _offset = Offset.zero;

  double _startScale = 1.0;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;

  /// Son yerleşimdeki kırpma alanı; çerçeve bunun içinde hesaplanır. Alt
  /// çubuktaki düğmeler de bu değerle çalışır.
  Size _viewport = Size.zero;

  /// Parmak/kaydırıcı hareket halindeyken ızgara görünür.
  bool _interacting = false;
  bool _transforming = false;
  bool _saving = false;

  late final AnimationController _zoomAnimation;
  double _animFromScale = 1.0;
  double _animToScale = 1.0;
  Offset _animFromOffset = Offset.zero;
  Offset _animToOffset = Offset.zero;

  // Çift dokunuş ham işaretçi olaylarından sayılır: DoubleTapGestureRecognizer
  // ilk dokunuşta yarışmayı bekletir, kıstırmayı ve düğmeleri geciktirirdi.
  int _activePointers = 0;
  bool _tapCancelled = false;
  Offset? _tapDownPosition;
  Duration? _tapDownTime;
  Offset? _lastTapPosition;
  Duration? _lastTapTime;

  bool get _hasAspectOptions =>
      widget.aspects != null && widget.aspects!.isNotEmpty;

  bool get _isCircle => widget.shape == ImmersiveCropShape.circle;

  /// Çerçevenin (ve çıktının) oranı: daire her zaman kare.
  double get _frameAspect => _isCircle ? 1.0 : _aspect;

  bool get _isPristine =>
      _quarterTurns == 0 &&
      !_mirrored &&
      (_scale - 1).abs() < 0.001 &&
      _offset.distance < 0.5;

  @override
  void initState() {
    super.initState();
    _bytes = widget.initialBytes;
    _aspect = widget.rectAspectRatio;
    _zoomAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(_onZoomAnimationTick);
    _decode();
  }

  @override
  void dispose() {
    _zoomAnimation.dispose();
    _disposeImages();
    super.dispose();
  }

  /// RawImage kendi kopyasını tuttuğu için tutamaçlarımız her an bırakılabilir.
  void _disposeImages() {
    final image = _image;
    final source = _source;
    _image = null;
    _source = null;
    if (image != null && !identical(image, source)) image.dispose();
    source?.dispose();
  }

  Future<void> _decode() async {
    final bytes = _bytes;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted || !identical(bytes, _bytes)) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _disposeImages();
        _source = frame.image;
        _image = frame.image;
        _quarterTurns = 0;
        _mirrored = false;
        _scale = 1.0;
        _offset = Offset.zero;
      });
    } catch (e) {
      debugPrint('Fotoğraf çözülemedi: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fotoğraf açılamadı. Lütfen başka bir fotoğraf seçin.'),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.of(context).pop(null);
    }
  }

  /// Karartılmış maskenin ortasındaki "delik" — kırpılacak alan.
  Rect _holeRect(Size viewport) {
    if (_hasAspectOptions) {
      // Tam ekran düzen: çerçeve ekran genişliğinde; çok uzun olursa (4:5
      // gibi) yükseklik sınırlanır ve genişlik de ORANLA birlikte daraltılır.
      // Eskiden yalnız yükseklik kırpılıyordu: delik oranını kaybediyor,
      // çıktı da (oranlı boyutta üretildiği için) dikeyde gerilmiş çıkıyordu.
      final maxHeight = viewport.height * 0.6;
      var h = viewport.width / _aspect;
      if (h > maxHeight) h = maxHeight;
      final w = math.min(viewport.width, h * _aspect);
      return Rect.fromCenter(
        center: viewport.center(Offset.zero),
        width: w,
        height: h,
      );
    }
    // Sabit çubuklu düzen: çerçeve kırpma alanına kenarlarda pay bırakarak
    // olabildiğince büyük sığar (dar ekranda genişlik, geniş pencerede
    // yükseklik belirler).
    final maxW = math.max(0.0, viewport.width - 2 * _framedHoleMargin);
    final maxH = math.max(0.0, viewport.height - 2 * _framedHoleMargin);
    var w = maxW;
    var h = w / _frameAspect;
    if (h > maxH) {
      h = maxH;
      w = h * _frameAspect;
    }
    return Rect.fromCenter(
      center: viewport.center(Offset.zero),
      width: w,
      height: h,
    );
  }

  /// Çerçeveyi tamamen dolduran taban ölçek (BoxFit.cover mantığı).
  double _baseScale(Rect hole) {
    final img = _image!;
    return math.max(hole.width / img.width, hole.height / img.height);
  }

  /// Fotoğrafın ekranda (kırpma alanı koordinatlarında) kapladığı dikdörtgen.
  Rect _imageRect(Rect hole) {
    final img = _image!;
    final total = _baseScale(hole) * _scale;
    return Rect.fromCenter(
      center: hole.center + _offset,
      width: img.width * total,
      height: img.height * total,
    );
  }

  /// Kaymayı, fotoğraf çerçeveyi her yönden kaplamaya devam edecek şekilde
  /// sınırlar.
  Offset _clampedOffset(Offset offset, double scale, Rect hole) {
    final img = _image!;
    final total = _baseScale(hole) * scale;
    final maxX = math.max(0.0, (img.width * total - hole.width) / 2);
    final maxY = math.max(0.0, (img.height * total - hole.height) / 2);
    return Offset(offset.dx.clamp(-maxX, maxX), offset.dy.clamp(-maxY, maxY));
  }

  /// [focal] noktasındaki (kırpma alanı koordinatı) fotoğraf pikseli yerinde
  /// kalacak şekilde [targetScale]'e yakınlaştırır.
  void _zoomTo(double targetScale, Offset focal, {bool animate = false}) {
    if (_image == null) return;
    final hole = _holeRect(_viewport);
    final scale = targetScale.clamp(1.0, _maxScale);
    final center = hole.center + _offset;
    final newCenter = focal + (center - focal) * (scale / _scale);
    final offset = _clampedOffset(newCenter - hole.center, scale, hole);
    if (animate) {
      _animFromScale = _scale;
      _animToScale = scale;
      _animFromOffset = _offset;
      _animToOffset = offset;
      _zoomAnimation.forward(from: 0);
    } else {
      _zoomAnimation.stop();
      setState(() {
        _scale = scale;
        _offset = offset;
      });
    }
  }

  void _zoomBy(double factor) =>
      _zoomTo(_scale * factor, _holeRect(_viewport).center, animate: true);

  void _onZoomAnimationTick() {
    // Uç değerler kaplama koşulunu sağlıyor; koşul ölçek ve kaymada doğrusal
    // olduğu için doğrusal ara değerler de sağlar.
    final t = Curves.easeOutCubic.transform(_zoomAnimation.value);
    setState(() {
      _scale = ui.lerpDouble(_animFromScale, _animToScale, t)!;
      _offset = Offset.lerp(_animFromOffset, _animToOffset, t)!;
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    _zoomAnimation.stop();
    _startScale = _scale;
    _startOffset = _offset;
    _startFocal = details.localFocalPoint;
    setState(() => _interacting = true);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_image == null) return;
    final hole = _holeRect(_viewport);
    final scale = (_startScale * details.scale).clamp(1.0, _maxScale);
    // Parmakların başladığı noktadaki fotoğraf pikseli parmakların altında
    // kalır; parmaklar kayınca fotoğraf da onlarla birlikte kayar.
    final startCenter = hole.center + _startOffset;
    final center = details.localFocalPoint +
        (startCenter - _startFocal) * (scale / _startScale);
    setState(() {
      _scale = scale;
      _offset = _clampedOffset(center - hole.center, scale, hole);
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_interacting) setState(() => _interacting = false);
  }

  /// Fare tekerleği / dokunmatik yüzey kaydırması imlecin altına yakınlaştırır.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _image == null) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      final scroll = resolved as PointerScrollEvent;
      _zoomTo(
        _scale * math.exp(-scroll.scrollDelta.dy / 300),
        scroll.localPosition,
      );
    });
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers++;
    if (_activePointers == 1) {
      _tapCancelled = false;
      _tapDownPosition = event.localPosition;
      _tapDownTime = event.timeStamp;
    } else {
      // İkinci parmak: kıstırma, dokunuş değil.
      _tapCancelled = true;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    final down = _tapDownPosition;
    if (down != null && (event.localPosition - down).distance > kTouchSlop) {
      _tapCancelled = true;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers = math.max(0, _activePointers - 1);
    if (_activePointers > 0) return;
    if (_interacting) setState(() => _interacting = false);

    final down = _tapDownPosition;
    final downTime = _tapDownTime;
    _tapDownPosition = null;
    _tapDownTime = null;
    final isTap = !_tapCancelled &&
        down != null &&
        downTime != null &&
        event.timeStamp - downTime <= kLongPressTimeout;
    if (!isTap) {
      _lastTapTime = null;
      return;
    }

    final lastTime = _lastTapTime;
    final lastPosition = _lastTapPosition;
    if (lastTime != null &&
        lastPosition != null &&
        event.timeStamp - lastTime <= kDoubleTapTimeout &&
        (event.localPosition - lastPosition).distance <= kDoubleTapSlop) {
      _lastTapTime = null;
      _onDoubleTap(event.localPosition);
    } else {
      _lastTapTime = event.timeStamp;
      _lastTapPosition = event.localPosition;
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activePointers = math.max(0, _activePointers - 1);
    _tapCancelled = true;
    if (_activePointers == 0 && _interacting) {
      setState(() => _interacting = false);
    }
  }

  /// Uzaktaysa dokunulan noktaya yakınlaştırır, yakındaysa en uzağa döner.
  void _onDoubleTap(Offset position) {
    if (_image == null || _saving || _transforming) return;
    _zoomTo(_scale > 1.05 ? 1.0 : _doubleTapScale, position, animate: true);
  }

  Future<void> _rotateLeft() => _reorient(
        quarterTurns: (_quarterTurns + 1) % 4,
        mirrored: _mirrored,
        // Görüntü çerçeve merkezinde döner; kayma da onunla birlikte döner.
        offset: Offset(_offset.dy, -_offset.dx),
      );

  Future<void> _mirror() => _reorient(
        // Ekrandaki görüntü yatayda aynalanır:
        // aynala ∘ döndür(t) = döndür(−t) ∘ aynala.
        quarterTurns: (4 - _quarterTurns) % 4,
        mirrored: !_mirrored,
        offset: Offset(-_offset.dx, _offset.dy),
      );

  Future<void> _reorient({
    required int quarterTurns,
    required bool mirrored,
    required Offset offset,
  }) async {
    final source = _source;
    if (source == null || _transforming || _saving) return;
    _zoomAnimation.stop();
    setState(() => _transforming = true);
    try {
      // Her seferinde orijinalden üretilir: art arda döndürmede kayıp birikmez.
      final next = quarterTurns == 0 && !mirrored
          ? source
          : await renderOrientedImage(
              source,
              quarterTurns: quarterTurns,
              mirrored: mirrored,
            );
      if (!mounted || !identical(source, _source)) {
        if (!identical(next, source)) next.dispose();
        return;
      }
      final previous = _image;
      setState(() {
        _image = next;
        _quarterTurns = quarterTurns;
        _mirrored = mirrored;
        // Dikdörtgen çerçevede taban ölçek döndürmeyle değişir.
        _offset = _clampedOffset(offset, _scale, _holeRect(_viewport));
      });
      if (previous != null &&
          !identical(previous, source) &&
          !identical(previous, next)) {
        previous.dispose();
      }
    } catch (e) {
      debugPrint('Fotoğraf döndürülemedi: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fotoğraf döndürülemedi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted && _transforming) setState(() => _transforming = false);
    }
  }

  void _reset() {
    final source = _source;
    if (source == null || _transforming || _saving) return;
    _zoomAnimation.stop();
    final previous = _image;
    setState(() {
      _image = source;
      _quarterTurns = 0;
      _mirrored = false;
      _scale = 1.0;
      _offset = Offset.zero;
    });
    if (previous != null && !identical(previous, source)) previous.dispose();
  }

  void _setAspect(double ratio) {
    if ((ratio - _aspect).abs() < 0.0001) return;
    _zoomAnimation.stop();
    setState(() {
      _aspect = ratio;
      // Çerçeve değişince konum sıfırlanır: eski konum yeni çerçevede
      // fotoğrafın dışına taşabilirdi.
      _scale = 1.0;
      _offset = Offset.zero;
    });
  }

  Future<void> _pickAnother() async {
    if (widget.onPickAnother == null || _transforming || _saving) return;
    final newBytes = await widget.onPickAnother!();
    if (newBytes == null || !mounted) return;
    _zoomAnimation.stop();
    setState(() {
      _disposeImages();
      _bytes = newBytes;
    });
    await _decode();
  }

  Future<void> _confirm() async {
    final img = _image;
    if (img == null || _saving || _transforming) return;
    final hole = _holeRect(_viewport);
    if (hole.isEmpty) return;
    _zoomAnimation.stop();
    setState(() => _saving = true);
    try {
      final total = _baseScale(hole) * _scale;
      final imageRect = _imageRect(hole);
      final srcRect = Rect.fromLTRB(
        ((hole.left - imageRect.left) / total).clamp(0.0, img.width.toDouble()),
        ((hole.top - imageRect.top) / total).clamp(0.0, img.height.toDouble()),
        ((hole.right - imageRect.left) / total).clamp(0.0, img.width.toDouble()),
        ((hole.bottom - imageRect.top) / total).clamp(0.0, img.height.toDouble()),
      );

      final aspect = _frameAspect;
      final maxWidth = widget.maxOutputWidth ?? (_isCircle ? 1024 : 1280);
      final (int outW, int outH) = cropOutputSize(srcRect, aspect, maxWidth: maxWidth);

      final bytes = await renderImageRegionPng(img, srcRect, outW, outH);
      if (mounted) {
        Navigator.of(context).pop(ImmersiveCropResult(bytes: bytes, aspectRatio: aspect));
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
      body: _hasAspectOptions ? _buildImmersiveLayout() : _buildFramedLayout(),
    );
  }

  /// Gönderi editörü: fotoğraf tam ekran, çubuklar üstünde geçişli.
  Widget _buildImmersiveLayout() {
    if (_image == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = constraints.biggest;
        return Stack(
          fit: StackFit.expand,
          children: [
            _buildCropArea(),
            _buildImmersiveTopBar(),
            _buildImmersiveBottomBar(),
            if (_saving) const _BusyOverlay(),
          ],
        );
      },
    );
  }

  /// Profil/kapak editörü: sabit üst çubuk, ortada kırpma alanı, altta
  /// yakınlaştırma ve araçlar. Çerçeve hiçbir çubuğun altına girmez.
  Widget _buildFramedLayout() {
    return Stack(
      children: [
        Column(
          children: [
            _buildFramedTopBar(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _viewport = constraints.biggest;
                  if (_image == null) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  }
                  return _buildCropArea();
                },
              ),
            ),
            _buildFramedBottomBar(),
          ],
        ),
        if (_saving) const Positioned.fill(child: _BusyOverlay()),
      ],
    );
  }

  Widget _buildCropArea() {
    final img = _image!;
    final hole = _holeRect(_viewport);
    // Ekran döndü/pencere boyutu değiştiyse eski kayma yeni çerçevede
    // fotoğrafın dışına taşabilir: çizmeden önce sınırlanır.
    _offset = _clampedOffset(_offset, _scale, hole);
    final showGrid = _hasAspectOptions || _interacting;

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      onPointerSignal: _onPointerSignal,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Fotoğraf gerçek boyutunda yerleşir (ezilmez): ekranda görülen
            // alan ile kırpılan alan birebir aynı hesaptan gelir.
            Positioned.fromRect(
              rect: _imageRect(hole),
              child: RawImage(
                image: img,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
              ),
            ),
            IgnorePointer(
              child: CustomPaint(
                painter: _MaskPainter(hole: hole, shape: widget.shape),
              ),
            ),
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: showGrid ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: CustomPaint(
                  painter: _GridPainter(hole: hole, shape: widget.shape),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImmersiveTopBar() {
    final topPad = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: _OverlayBar(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x8C000000), Color(0x00000000)],
        ),
        padding: EdgeInsets.only(top: topPad + 12, left: 18, right: 18, bottom: 20),
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
              onTap: _confirm,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImmersiveBottomBar() {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: _OverlayBar(
        gradient: const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0x9E000000), Color(0x00000000)],
        ),
        padding: EdgeInsets.only(bottom: bottomPad + 20, top: 36, left: 24, right: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            _HintText(widget.hintText),
            if (widget.sizeInfoText.isNotEmpty) ...[
              const SizedBox(height: 10),
              _InfoText(widget.sizeInfoText),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFramedTopBar() {
    final ready = _image != null && !_transforming;
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _RoundIconButton(
                icon: Icons.close,
                tooltip: 'Vazgeç',
                background: Colors.white.withValues(alpha: 0.12),
                onTap: () => Navigator.of(context).pop(null),
              ),
              Expanded(
                child: Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              _RoundIconButton(
                icon: Icons.check,
                tooltip: 'Onayla',
                background: Theme.of(context).colorScheme.primary,
                onTap: ready ? _confirm : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFramedBottomBar() {
    final ready = _image != null && !_transforming && !_saving;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildZoomRow(enabled: ready),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ToolButton(
                  icon: Icons.rotate_90_degrees_ccw,
                  label: 'Döndür',
                  onTap: ready ? _rotateLeft : null,
                ),
                _ToolButton(
                  icon: Icons.flip,
                  label: 'Aynala',
                  onTap: ready ? _mirror : null,
                ),
                _ToolButton(
                  icon: Icons.restart_alt,
                  label: 'Sıfırla',
                  onTap: ready && !_isPristine ? _reset : null,
                ),
                if (widget.onPickAnother != null)
                  _ToolButton(
                    icon: Icons.photo_library_outlined,
                    label: 'Galeriden Seç',
                    onTap: ready ? _pickAnother : null,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _HintText(widget.hintText),
            if (widget.sizeInfoText.isNotEmpty) ...[
              const SizedBox(height: 6),
              _InfoText(widget.sizeInfoText),
            ],
          ],
        ),
      ),
    );
  }

  /// Uzaklaştır — kaydırıcı — yakınlaştır. Kaydırıcı ve düğmeler çerçevenin
  /// ortasına göre yakınlaştırır.
  Widget _buildZoomRow({required bool enabled}) {
    final scale = _scale.clamp(1.0, _maxScale);
    return Row(
      children: [
        IconButton(
          tooltip: 'Uzaklaştır',
          color: Colors.white,
          disabledColor: Colors.white38,
          icon: const Icon(Icons.zoom_out),
          onPressed: enabled && scale > 1.001 ? () => _zoomBy(1 / _zoomStep) : null,
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: Colors.white24,
              disabledActiveTrackColor: Colors.white38,
              disabledInactiveTrackColor: Colors.white12,
              disabledThumbColor: Colors.white38,
            ),
            child: Slider(
              value: scale,
              min: 1.0,
              max: _maxScale,
              semanticFormatterCallback: (v) => 'Yakınlaştırma ${v.toStringAsFixed(1)} kat',
              onChangeStart: enabled
                  ? (_) {
                      _zoomAnimation.stop();
                      setState(() => _interacting = true);
                    }
                  : null,
              onChanged: enabled ? (v) => _zoomTo(v, _holeRect(_viewport).center) : null,
              onChangeEnd: enabled ? (_) => setState(() => _interacting = false) : null,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Yakınlaştır',
          color: Colors.white,
          disabledColor: Colors.white38,
          icon: const Icon(Icons.zoom_in),
          onPressed: enabled && scale < _maxScale - 0.001 ? () => _zoomBy(_zoomStep) : null,
        ),
      ],
    );
  }
}

/// Tam ekran düzendeki geçişli çubuk. Geçiş zemini dokunuşları yutmaz:
/// çubuğun boş yerinden başlayan sürükleme de fotoğrafı kaydırır.
class _OverlayBar extends StatelessWidget {
  const _OverlayBar({required this.gradient, required this.padding, required this.child});

  final Gradient gradient;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
          ),
        ),
        Padding(padding: padding, child: child),
      ],
    );
  }
}

class _BusyOverlay extends StatelessWidget {
  const _BusyOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black45,
      child: const Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }
}

class _HintText extends StatelessWidget {
  const _HintText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5),
      textAlign: TextAlign.center,
    );
  }
}

class _InfoText extends StatelessWidget {
  const _InfoText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11.5),
      textAlign: TextAlign.center,
    );
  }
}

/// Alt araç çubuğundaki simge + etiket düğmesi.
class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null ? Colors.white38 : Colors.white;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 64, minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
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
  final VoidCallback? onTap;

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
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
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

/// Üçler kuralı ızgarası: fotoğrafı çerçevede konumlandırmayı kolaylaştırır.
/// Dairede çizgiler dairenin içinde kalır.
class _GridPainter extends CustomPainter {
  final Rect hole;
  final ImmersiveCropShape shape;

  _GridPainter({required this.hole, required this.shape});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (shape == ImmersiveCropShape.circle) {
      canvas.clipPath(Path()..addOval(hole));
    } else {
      canvas.clipRect(hole);
    }
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = hole.left + hole.width * i / 3;
      final y = hole.top + hole.height * i / 3;
      canvas.drawLine(Offset(x, hole.top), Offset(x, hole.bottom), gridPaint);
      canvas.drawLine(Offset(hole.left, y), Offset(hole.right, y), gridPaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.hole != hole || oldDelegate.shape != shape;
}
