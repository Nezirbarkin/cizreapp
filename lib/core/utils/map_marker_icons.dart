import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'map_vehicle_painters.dart';

export 'map_vehicle_painters.dart'
    show
        MapVehicleShape,
        MapStopStyle,
        MapStopState,
        MapStopDetail,
        mapVehicleLogicalSize,
        mapStopLogicalSize,
        kStopBlue,
        kStopSelected;

/// Harita marker'ları için tepeden görünüm araç, durak ve etiket bitmap'leri.
///
/// Çizimlerin kendisi `map_vehicle_painters.dart`'tadır; bu sınıf onları
/// **yüksek çözünürlüklü** ([pixelRatio]×) PNG'ye çevirip `BitmapDescriptor`
/// yapar. Önceden bitmap 1× üretiliyor, eklenti bunu ekran yoğunluğuyla
/// büyüttüğü için (imagePixelRatio verilmediğinde 1.0 varsayılır) 3× ekranlarda
/// bulanık görünüyordu. Şimdi bitmap 3× çizilir ve mantıksal (dp) boyut
/// `width/height` ile açıkça verilir — her yoğunlukta aynı boyutta ve keskin.
///
/// Araç görselleri yön (heading) ile döndürülmek üzere **burnu yukarı** çizilir:
/// `Marker(rotation: heading, flat: true, anchor: Offset(0.5, 0.5))`.
/// Metin döndürülmemeli — etiket için ayrı bir marker kullanın
/// ([label]); o dönmeyen (billboard) marker'dır.
///
/// Üretilen her bitmap süreç boyunca cache'lenir.
class MapMarkerIcons {
  const MapMarkerIcons._();

  /// Bitmap'lerin çizildiği piksel oranı. 3, günümüz telefonlarının çoğunun
  /// yoğunluğudur; daha düşük yoğunlukta eklenti aşağı ölçekler.
  static const double pixelRatio = 3.0;

  static final Map<String, BitmapDescriptor> _cache = {};

  /// Bitmap'e çizilen yazıların ailesi. Android'de zaten varsayılan olan Roboto
  /// açıkça istenir (yazı metrikleri harita etiketlerinde tutarlı kalsın); yoksa
  /// (iOS, web) motor kendi sistem fontuna düşer.
  static const String _labelFont = 'Roboto';

  /// Test/geliştirme için cache'i boşaltır.
  static void clearCache() => _cache.clear();

  /// Önbellekteki bitmap sayısı (yalnız testler için).
  static int get cacheSize => _cache.length;

  // ─────────────────────────────────────────────
  // Araç
  // ─────────────────────────────────────────────

  /// Aracın 1× ölçekteki mantıksal boyu.
  static Size vehicleSize(MapVehicleShape shape, {double scale = 1}) {
    final base = mapVehicleLogicalSize(shape);
    return Size(base.width * scale, base.height * scale);
  }

  /// Tepeden görünüm araç ikonu. [color] gövde rengidir (şehiriçi hattın
  /// rengi, kuryede turuncu). [scale], uzaktan bakışta ikonu küçültmek için.
  static Future<BitmapDescriptor> vehicle({
    required MapVehicleShape shape,
    required Color color,
    double scale = 1,
  }) async {
    final key = 'v_${shape.name}_${color.toARGB32()}_${_scaleKey(scale)}';
    final cached = _cache[key];
    if (cached != null) return cached;
    final icon = await _draw(
      size: _snap(vehicleSize(shape, scale: scale)),
      painter: (canvas, size) => paintMapVehicle(canvas, size, shape, color),
      fallbackHue: BitmapDescriptor.hueRed,
    );
    _cache[key] = icon;
    return icon;
  }

  /// Admin'in yüklediği görselden araç ikonu.
  ///
  /// [rotationDegrees] görselin "burnu" yukarı bakmıyorsa düzeltir (saat yönünde).
  /// [cacheKey] görselin adresi + sürümü olmalı (aynı adres yeniden yüklenince
  /// eski bitmap dönmesin diye `updated_at` da içermeli).
  static Future<BitmapDescriptor?> vehicleFromImage({
    required Uint8List bytes,
    required String cacheKey,
    int rotationDegrees = 0,
    double scale = 1,
    double longSide = 80,
  }) async {
    final key = 'vi_${cacheKey}_${rotationDegrees}_${_scaleKey(scale)}';
    final cached = _cache[key];
    if (cached != null) return cached;
    final icon = await _drawImage(
      bytes: bytes,
      rotationDegrees: rotationDegrees,
      longSide: longSide * scale,
      shadow: true,
    );
    if (icon != null) _cache[key] = icon;
    return icon;
  }

  /// Bir aracın üzerine konacak etiket için gereken saydam boşluk: araç
  /// bitmap'inin yarı yüksekliği + küçük bir pay. [label] çağrısında `gap`
  /// olarak verilir; etiket araca değecek kadar YAKIN ama binmeyecek kadar
  /// uzakta durur.
  static double labelGapFor(MapVehicleShape shape, {double scale = 1}) =>
      vehicleSize(shape, scale: scale).height / 2 + 1;

  // ─────────────────────────────────────────────
  // Etiket
  // ─────────────────────────────────────────────

  /// Aracın üzerinde duran dönmeyen etiket (ör. "ŞEHİRİÇİ · 4A", "KURYE").
  ///
  /// [badge] verilirse iki bölümlü çizilir: solda koyu zeminde [text],
  /// sağda [background] renginde [badge] (hat kodu). Bitmap'in altına [gap]
  /// kadar saydam boşluk bırakılır; marker `anchor: Offset(0.5, 1.0)` ile
  /// yerleştirildiğinde etiket araç marker'ının tam üstünde, ona değmeden durur.
  static Future<BitmapDescriptor> label({
    required String text,
    required Color background,
    Color foreground = Colors.white,
    double gap = 24,
    String? badge,
  }) async {
    final key = 'l_${text}_${badge ?? ''}_${background.toARGB32()}_'
        '${foreground.toARGB32()}_${gap.toStringAsFixed(0)}';
    final cached = _cache[key];
    if (cached != null) return cached;

    final textPainter = _labelTextPainter(text, foreground, 9);
    final badgePainter =
        badge == null ? null : _labelTextPainter(badge, Colors.white, 10.5);
    const padH = 5.0;
    const padV = 2.6;
    const tail = 3.5;
    final leftW = textPainter.width + padH * 2;
    final rightW = badgePainter == null ? 0.0 : badgePainter.width + padH * 1.6;
    final pillW = leftW + rightW;
    final pillH = textPainter.height + padV * 2;
    // Kenarlık + gölge için 4 dp pay.
    final size = Size(pillW + 8, pillH + tail + gap + 8);

    final icon = await _draw(
      size: _snap(size),
      painter: (canvas, s) {
        final origin = const Offset(4, 3);
        final pill = RRect.fromRectAndRadius(
          Rect.fromLTWH(origin.dx, origin.dy, pillW, pillH),
          Radius.circular(pillH / 2),
        );
        // Gölge — koyu haritada da etiketi zeminden ayırır.
        canvas.drawRRect(
          pill.shift(const Offset(0, 1.6)),
          Paint()
            ..color = Colors.black.withValues(alpha: 0.30)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.6),
        );
        // Kuyruk: pill'in altından aşağı bakan üçgen (aracı işaret eder).
        final tailColor =
            badgePainter == null ? background : const Color(0xFF1B2330);
        final tailPath = Path()
          ..moveTo(s.width / 2 - 3.6, origin.dy + pillH - 1)
          ..lineTo(s.width / 2 + 3.6, origin.dy + pillH - 1)
          ..lineTo(s.width / 2, origin.dy + pillH + tail)
          ..close();
        canvas.drawPath(tailPath, Paint()..color = tailColor);
        if (badgePainter == null) {
          canvas.drawRRect(pill, Paint()..color = background);
        } else {
          // Sol: koyu; sağ: hat rengi.
          canvas.save();
          canvas.clipRRect(pill);
          canvas.drawRect(
            Rect.fromLTWH(origin.dx, origin.dy, leftW, pillH),
            Paint()..color = const Color(0xFF1B2330),
          );
          canvas.drawRect(
            Rect.fromLTWH(origin.dx + leftW, origin.dy, rightW, pillH),
            Paint()..color = background,
          );
          canvas.restore();
        }
        canvas.drawRRect(
          pill,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.95)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.1,
        );
        textPainter.paint(
          canvas,
          Offset(origin.dx + padH, origin.dy + padV),
        );
        badgePainter?.paint(
          canvas,
          Offset(
            origin.dx + leftW + (rightW - badgePainter.width) / 2,
            origin.dy + padV,
          ),
        );
      },
      fallbackHue: BitmapDescriptor.hueAzure,
    );
    _cache[key] = icon;
    return icon;
  }

  static TextPainter _labelTextPainter(
      String text, Color color, double fontSize) {
    return TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontFamily: _labelFont,
          fontSize: fontSize,
          height: 1.05,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.15,
        ),
      ),
    )..layout();
  }

  /// Durak adı etiketi: beyaz haleli koyu yazı (Google'ın kendi etiketleri gibi).
  ///
  /// Bitmap'in solunda [leftGap] kadar saydam boşluk bırakılır; böylece etiket
  /// durak simgesinin SAĞINDA durur.
  ///  • [lift] == 0 (merkezden yerleşen nokta durak): marker `anchor: Offset(0, 0.5)`.
  ///  • [lift] > 0 (alt-ortadan yerleşen levha/iğne): marker `anchor: Offset(0, 1)`;
  ///    yazı, marker konumunun [lift] dp YUKARISINDA — levhanın ortasıyla hizalanır.
  static Future<BitmapDescriptor> stopLabel({
    required String text,
    required bool dark,
    double leftGap = 16,
    double lift = 0,
  }) async {
    final key = 'sl_${text}_${dark ? 1 : 0}_${leftGap.toStringAsFixed(0)}_'
        '${lift.toStringAsFixed(0)}';
    final cached = _cache[key];
    if (cached != null) return cached;

    TextPainter build(Color color) => TextPainter(
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: color,
              fontFamily: _labelFont,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        )..layout(maxWidth: 150);

    final fill = build(dark ? const Color(0xFFF1F4F9) : const Color(0xFF1F2937));
    final halo = TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: _labelFont,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          height: 1.1,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeJoin = StrokeJoin.round
            ..color = dark ? const Color(0xFF12151A) : Colors.white,
        ),
      ),
    )..layout(maxWidth: 150);

    final height = lift > 0 ? lift * 2 : fill.height + 8;
    final size = Size(leftGap + fill.width + 8, height);
    final icon = await _draw(
      size: _snap(size),
      painter: (canvas, s) {
        final at = Offset(leftGap, (s.height - fill.height) / 2);
        halo.paint(canvas, at);
        fill.paint(canvas, at);
      },
      fallbackHue: BitmapDescriptor.hueAzure,
    );
    _cache[key] = icon;
    return icon;
  }

  // ─────────────────────────────────────────────
  // Durak
  // ─────────────────────────────────────────────

  static Size stopSize(MapStopStyle style, MapStopDetail detail,
      {double scale = 1}) {
    final base = mapStopLogicalSize(style, detail);
    return Size(base.width * scale, base.height * scale);
  }

  /// Hazır çizimle durak ikonu. [lineColors] duraktan geçen hatların renkleri
  /// (en çok 3 çizilir, tek hatta iğne/nokta o renge boyanır).
  static Future<BitmapDescriptor> stop({
    required MapStopStyle style,
    MapStopDetail detail = MapStopDetail.near,
    MapStopState state = MapStopState.normal,
    List<Color> lineColors = const [],
    bool isStart = false,
    bool isEnd = false,
    double scale = 1,
  }) async {
    final colors = lineColors.take(3).toList(growable: false);
    final key = 's_${style.name}_${detail.name}_${state.name}_'
        '${colors.map((c) => c.toARGB32().toRadixString(16)).join('-')}_'
        '${isStart ? 1 : 0}${isEnd ? 1 : 0}_${_scaleKey(scale)}';
    final cached = _cache[key];
    if (cached != null) return cached;
    final icon = await _draw(
      size: _snap(stopSize(style, detail, scale: scale)),
      painter: (canvas, size) => paintMapStop(
        canvas,
        size,
        style,
        detail,
        state,
        colors,
        isStart: isStart,
        isEnd: isEnd,
      ),
      fallbackHue: BitmapDescriptor.hueAzure,
    );
    _cache[key] = icon;
    return icon;
  }

  /// Admin'in yüklediği görselden durak ikonu.
  static Future<BitmapDescriptor?> stopFromImage({
    required Uint8List bytes,
    required String cacheKey,
    int rotationDegrees = 0,
    double scale = 1,
    double longSide = 44,
  }) async {
    final key = 'si_${cacheKey}_${rotationDegrees}_${_scaleKey(scale)}';
    final cached = _cache[key];
    if (cached != null) return cached;
    final icon = await _drawImage(
      bytes: bytes,
      rotationDegrees: rotationDegrees,
      longSide: longSide * scale,
      shadow: true,
    );
    if (icon != null) _cache[key] = icon;
    return icon;
  }

  // ─────────────────────────────────────────────
  // Admin düzenleme simgeleri
  // ─────────────────────────────────────────────

  /// Numaralı damla iğne (admin haritadan durak dizerken sırayı gösterir).
  /// [number] null ise başın içinde yalnız renkli nokta çizilir. Alt uç
  /// koordinata oturur: `anchor: Offset(0.5, 1.0)`.
  static Size numberedPinSize({bool large = false}) =>
      large ? const Size(42, 54) : const Size(36, 46);

  static Future<BitmapDescriptor> numberedPin({
    int? number,
    required Color color,
    bool large = false,
  }) async {
    final key = 'np_${number ?? 'x'}_${color.toARGB32()}_${large ? 1 : 0}';
    final cached = _cache[key];
    if (cached != null) return cached;
    final icon = await _draw(
      size: _snap(numberedPinSize(large: large)),
      painter: (canvas, size) => _paintNumberedPin(canvas, size, number, color),
      fallbackHue: BitmapDescriptor.hueRed,
    );
    _cache[key] = icon;
    return icon;
  }

  static void _paintNumberedPin(
      Canvas canvas, Size size, int? number, Color color) {
    final cx = size.width / 2;
    final r = size.width / 2 - 3.5;
    final cy = r + 3;
    final tipY = size.height - 3;
    final a = math.acos(r / (tipY - cy));
    final head = Rect.fromCircle(center: Offset(cx, cy), radius: r);
    final path = Path()
      ..moveTo(cx, tipY)
      ..lineTo(cx - r * math.sin(a), cy + r * math.cos(a))
      ..arcTo(head, math.pi / 2 + a, 2 * math.pi - 2 * a, false)
      ..close();

    canvas.drawPath(
      path.shift(const Offset(0, 1.6)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4),
    );
    final hsl = HSLColor.fromColor(color);
    final light = hsl.withLightness((hsl.lightness + 0.12).clamp(0.0, 0.9)).toColor();
    final dark = hsl.withLightness((hsl.lightness * 0.72).clamp(0.05, 0.9)).toColor();
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx, 0),
          Offset(cx, size.height),
          [light, color, dark],
          const [0.0, 0.5, 1.0],
        ),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
    // Beyaz rozet + numara
    canvas.drawCircle(Offset(cx, cy), r * 0.66, Paint()..color = Colors.white);
    if (number == null) {
      canvas.drawCircle(Offset(cx, cy), r * 0.30, Paint()..color = dark);
      return;
    }
    final label = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: '$number',
        style: TextStyle(
          color: dark,
          fontFamily: _labelFont,
          fontWeight: FontWeight.w900,
          fontSize: number >= 100 ? r * 0.68 : (number >= 10 ? r * 0.82 : r * 1.0),
          height: 1.0,
        ),
      ),
    )..layout();
    label.paint(
      canvas,
      Offset(cx - label.width / 2, cy - label.height / 2),
    );
  }

  /// Rota noktası: [filled] true ise dolu renkli daire (başlangıç/bitiş),
  /// değilse renkli halkalı beyaz nokta (ara noktalar). Merkez koordinata oturur.
  static Future<BitmapDescriptor> routePoint({
    required Color color,
    double size = 14,
    bool filled = false,
  }) async {
    final key = 'rp_${color.toARGB32()}_${size.toStringAsFixed(0)}_${filled ? 1 : 0}';
    final cached = _cache[key];
    if (cached != null) return cached;
    final icon = await _draw(
      size: _snap(Size(size + 6, size + 6)),
      painter: (canvas, s) {
        final c = Offset(s.width / 2, s.height / 2);
        final r = size / 2;
        canvas.drawCircle(
          c.translate(0, 1),
          r + 1,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.28)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8),
        );
        canvas.drawCircle(c, r, Paint()..color = Colors.white);
        canvas.drawCircle(c, r - 2.2, Paint()..color = filled ? color : Colors.white);
        if (!filled) {
          canvas.drawCircle(
            c,
            r - 1.1,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.4
              ..color = color,
          );
        }
      },
      fallbackHue: BitmapDescriptor.hueOrange,
    );
    _cache[key] = icon;
    return icon;
  }
  // ─────────────────────────────────────────────
  // Diğer simgeler
  // ─────────────────────────────────────────────

  /// Kullanıcının konumu (halelenmiş mavi nokta).
  static Future<BitmapDescriptor> userLocation({double size = 46}) async {
    final key = 'u_${size.toStringAsFixed(0)}';
    final cached = _cache[key];
    if (cached != null) return cached;
    final icon = await _draw(
      size: Size(size, size),
      painter: paintUserLocation,
      fallbackHue: BitmapDescriptor.hueBlue,
    );
    _cache[key] = icon;
    return icon;
  }

  /// Rota üzerinde yön gösteren küçük ok (burnu yukarı; `rotation` ile çevrilir).
  static Future<BitmapDescriptor> routeArrow(Color color) async {
    final key = 'a_${color.toARGB32()}';
    final cached = _cache[key];
    if (cached != null) return cached;
    final icon = await _draw(
      size: const Size(14, 16),
      painter: (canvas, s) => paintRouteArrow(canvas, s, color),
      fallbackHue: BitmapDescriptor.hueAzure,
    );
    _cache[key] = icon;
    return icon;
  }

  // ─────────────────────────────────────────────
  // Çizim altyapısı
  // ─────────────────────────────────────────────

  static String _scaleKey(double scale) => scale.toStringAsFixed(2);

  /// Bitmap'in piksel boyu tam sayı olsun diye mantıksal boyu 1/[pixelRatio]
  /// adımına yuvarlar (kesirli piksel bulanıklık üretir).
  static Size _snap(Size size) => Size(
        (size.width * pixelRatio).ceil() / pixelRatio,
        (size.height * pixelRatio).ceil() / pixelRatio,
      );

  static Future<BitmapDescriptor> _draw({
    required Size size,
    required void Function(Canvas canvas, Size size) painter,
    required double fallbackHue,
  }) async {
    final pixelW = (size.width * pixelRatio).round();
    final pixelH = (size.height * pixelRatio).round();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, pixelW.toDouble(), pixelH.toDouble()),
    );
    canvas.scale(pixelRatio);
    painter(canvas, size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(pixelW, pixelH);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (bytes == null) return BitmapDescriptor.defaultMarkerWithHue(fallbackHue);
    return BitmapDescriptor.bytes(
      bytes.buffer.asUint8List(),
      width: size.width,
      height: size.height,
    );
  }

  /// Yüklenmiş bir görseli (PNG/WebP/JPEG) marker bitmap'ine çevirir: en/boy
  /// oranı korunur, uzun kenar [longSide] dp olur, [rotationDegrees] kadar
  /// çevrilir ve altına yumuşak gölge eklenir. Çözümlenemezse null döner —
  /// çağıran hazır çizime düşer.
  static Future<BitmapDescriptor?> _drawImage({
    required Uint8List bytes,
    required int rotationDegrees,
    required double longSide,
    required bool shadow,
  }) async {
    final ui.Codec codec;
    final ui.Image source;
    try {
      codec = await ui.instantiateImageCodec(bytes);
    } catch (_) {
      return null;
    }
    try {
      source = (await codec.getNextFrame()).image;
    } catch (_) {
      codec.dispose();
      return null;
    }
    try {
      final quarter = (rotationDegrees ~/ 90) % 2 == 1;
      final srcW = source.width.toDouble();
      final srcH = source.height.toDouble();
      if (srcW <= 0 || srcH <= 0) return null;
      // Döndürülmüş görselin kaplayacağı en/boy.
      final dispW = quarter ? srcH : srcW;
      final dispH = quarter ? srcW : srcH;
      final k = longSide / (dispW > dispH ? dispW : dispH);
      final fitW = dispW * k;
      final fitH = dispH * k;
      const margin = 5.0;
      final logical = _snap(Size(fitW + margin * 2, fitH + margin * 2));
      final src = source;

      return await _draw(
        size: logical,
        painter: (canvas, s) {
          final cx = s.width / 2;
          final cy = s.height / 2;
          // Döndürülmüş çizim: merkeze taşı → çevir → kaynak boyutuyla çiz.
          void drawRotated(Paint paint) {
            canvas.save();
            canvas.translate(cx, cy);
            canvas.rotate(rotationDegrees * 3.141592653589793 / 180);
            final drawW = quarter ? fitH : fitW;
            final drawH = quarter ? fitW : fitH;
            canvas.drawImageRect(
              src,
              Rect.fromLTWH(0, 0, srcW, srcH),
              Rect.fromCenter(center: Offset.zero, width: drawW, height: drawH),
              paint,
            );
            canvas.restore();
          }

          if (shadow) {
            canvas.saveLayer(
              Offset.zero & s,
              Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 2.2, sigmaY: 2.2),
            );
            canvas.translate(1.6, 2.2);
            drawRotated(
              Paint()
                ..filterQuality = FilterQuality.medium
                ..colorFilter = ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.38),
                  BlendMode.srcIn,
                ),
            );
            canvas.restore();
          }
          drawRotated(Paint()..filterQuality = FilterQuality.high);
        },
        fallbackHue: BitmapDescriptor.hueRed,
      );
    } finally {
      source.dispose();
      codec.dispose();
    }
  }
}
