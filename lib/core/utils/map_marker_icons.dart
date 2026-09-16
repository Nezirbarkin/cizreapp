import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Harita marker'ları için kuşbakışı (tepeden) araç görselleri.
///
/// Önceden her harita kendi marker'ını "renkli disk + ortada Material ikonu"
/// olarak çiziyordu (üç ayrı dosyada üç kopya). Disk, haritada gerçek bir
/// araca benzemiyordu: hepsi aynı daireydi, yalnızca içindeki küçük glif
/// değişiyordu ve zoom'da glif okunmuyordu. Burada araçlar gerçek gövde
/// şekliyle çizilir — minibüs/dolmuş, otobüs, tramvay ve motokurye ayrı
/// siluetlerdir; tekerlek, dolu cam, ön/arka far ve kapı hattı var.
///
/// Görseller yön (heading) ile döndürülmek üzere **burnu yukarı** çizilir:
/// `Marker(rotation: heading, flat: true, anchor: Offset(0.5, 0.5))`.
/// Metin döndürülmemeli — etiket için ayrı bir marker kullanın
/// ([MapMarkerIcons.label]); o dönmeyen (billboard) marker'dır.
enum MapVehicleShape {
  /// Minibüs / dolmuş gövdesi (kısa, yüksek tavan).
  minibus,

  /// Şehir otobüsü (uzun gövde, üç cam bandı).
  bus,

  /// Tramvay (iki ucu eşit, tekerlek görünmez, pantograf çizgisi).
  tram,

  /// Binek araç (dolmuş taksi vb. — kısa, eğimli kaput).
  car,

  /// Motosiklet + arkasında teslimat kutusu (kurye).
  motorcycle,
}

/// Kuşbakışı araç/etiket marker bitmap'leri. Üretilen her bitmap süreç
/// boyunca cache'lenir (aynı tip+renk+metin bir kez çizilir).
class MapMarkerIcons {
  const MapMarkerIcons._();

  static final Map<String, BitmapDescriptor> _cache = {};

  /// Test/geliştirme için cache'i boşaltır.
  static void clearCache() => _cache.clear();

  /// Kuşbakışı araç ikonu. [color] gövde rengidir (şehiriçi hattın rengi,
  /// kuryede turuncu).
  static Future<BitmapDescriptor> vehicle({
    required MapVehicleShape shape,
    required Color color,
  }) async {
    final key = 'v_${shape.name}_${color.toARGB32()}';
    final cached = _cache[key];
    if (cached != null) return cached;
    final icon = await _draw(
      size: _canvasSize(shape),
      painter: (canvas, size) => _paintVehicle(canvas, size, shape, color),
      fallbackHue: BitmapDescriptor.hueRed,
    );
    _cache[key] = icon;
    return icon;
  }

  /// Aracın üzerinde duran dönmeyen etiket (ör. "ŞEHİRİÇİ · 4A", "KURYE").
  ///
  /// Bitmap'in altına [gap] kadar saydam boşluk bırakılır; marker
  /// `anchor: Offset(0.5, 1.0)` ile yerleştirildiğinde etiket araç
  /// marker'ının tam üstünde, ona değmeden durur.
  static Future<BitmapDescriptor> label({
    required String text,
    required Color background,
    Color foreground = Colors.white,
    double gap = 24,
  }) async {
    final key = 'l_${text}_${background.toARGB32()}_'
        '${foreground.toARGB32()}_${gap.toStringAsFixed(0)}';
    final cached = _cache[key];
    if (cached != null) return cached;

    final painter = _labelTextPainter(text, foreground);
    // Ölçüler küçültülmüş araç gövdesine göre seçildi (gövde ~50 px geniş):
    // pill bundan belirgin şekilde geniş/kalın olursa haritada aracı ezer.
    const padH = 3.5;
    const padV = 2.0;
    const tail = 3.0;
    final pillW = painter.width + padH * 2;
    final pillH = painter.height + padV * 2;
    // Kenarlık + gölge için 3 px pay.
    final size = Size(pillW + 6, pillH + tail + gap + 6);

    final icon = await _draw(
      size: size,
      painter: (canvas, s) {
        final pill = RRect.fromRectAndRadius(
          Rect.fromLTWH(3, 3, pillW, pillH),
          Radius.circular(pillH / 2),
        );
        // Gölge — koyu haritada da etiketi zeminden ayırır.
        canvas.drawRRect(
          pill.shift(const Offset(0, 1.5)),
          Paint()
            ..color = Colors.black.withValues(alpha: 0.28)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
        );
        // Kuyruk: pill'in altından aşağı bakan üçgen (aracı işaret eder).
        final tailPath = Path()
          ..moveTo(s.width / 2 - 3.5, 3 + pillH - 1)
          ..lineTo(s.width / 2 + 3.5, 3 + pillH - 1)
          ..lineTo(s.width / 2, 3 + pillH + tail)
          ..close();
        canvas.drawPath(tailPath, Paint()..color = background);
        canvas.drawRRect(pill, Paint()..color = background);
        canvas.drawRRect(
          pill,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0,
        );
        painter.paint(canvas, Offset(3 + padH, 3 + padV));
      },
      fallbackHue: BitmapDescriptor.hueAzure,
    );
    _cache[key] = icon;
    return icon;
  }

  /// Bir aracın üzerine konacak etiket için gereken saydam boşluk: araç
  /// bitmap'inin yarı yüksekliği + küçük bir pay. [label] çağrısında `gap`
  /// olarak verilir; etiket araca değecek kadar YAKIN ama binmeyecek kadar
  /// uzakta durur.
  static double labelGapFor(MapVehicleShape shape) =>
      _canvasSize(shape).height / 2 + 1;

  // ─────────────────────────────────────────────
  // Çizim
  // ─────────────────────────────────────────────

  static TextPainter _labelTextPainter(String text, Color color) {
    return TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          height: 1.05,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.1,
        ),
      ),
    )..layout();
  }

  /// Araç gövde boyutları. İlk sürüme göre ~%45 küçültüldü — harita
  /// üzerinde ölçekle orantısız, göze batan kocaman ikonlar yerine standart
  /// bir harita marker'ı büyüklüğüne (yaklaşık 36-44 px) yakın bir iz
  /// bırakır. Tüm iç detaylar (tekerlek, cam, ışık…) w/h'ye ORANLI
  /// hesaplandığı için küçülme kabalaşmaya değil, gerçek bir aracın
  /// küçültülmüş haline yol açar.
  static Size _canvasSize(MapVehicleShape shape) {
    switch (shape) {
      case MapVehicleShape.minibus:
        return const Size(42, 68);
      case MapVehicleShape.bus:
        return const Size(44, 80);
      case MapVehicleShape.tram:
        return const Size(40, 84);
      case MapVehicleShape.car:
        return const Size(40, 62);
      case MapVehicleShape.motorcycle:
        return const Size(36, 58);
    }
  }

  static Future<BitmapDescriptor> _draw({
    required Size size,
    required void Function(Canvas canvas, Size size) painter,
    required double fallbackHue,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, size.width, size.height),
    );
    painter(canvas, size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      size.width.ceil(),
      size.height.ceil(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (bytes == null) return BitmapDescriptor.defaultMarkerWithHue(fallbackHue);
    return BitmapDescriptor.bytes(bytes.buffer.asUint8List());
  }

  static void _paintVehicle(
    Canvas canvas,
    Size size,
    MapVehicleShape shape,
    Color color,
  ) {
    if (shape == MapVehicleShape.motorcycle) {
      _paintMotorcycle(canvas, size, color);
      return;
    }
    _paintBoxVehicle(canvas, size, shape, color);
  }

  /// Minibüs / otobüs / tramvay / binek: kuşbakışı gövde.
  ///
  /// Tüm kalınlık/blur değerleri [w]'ye ORANLI hesaplanır (sabit piksel
  /// değil) — aksi halde küçültülmüş gövdede çizgiler kalın/kaba kalır ve
  /// gerçekçilik yerine kabalaşma olur.
  static void _paintBoxVehicle(
    Canvas canvas,
    Size size,
    MapVehicleShape shape,
    Color color,
  ) {
    final w = size.width;
    final h = size.height;
    final isTram = shape == MapVehicleShape.tram;
    final isBus = shape == MapVehicleShape.bus;
    final isCar = shape == MapVehicleShape.car;

    final glass = const Color(0xFFBFD9EA).withValues(alpha: 0.92);
    final tyre = const Color(0xFF23262C);
    final roof = _lighten(color, 0.14);
    final shade = _darken(color, 0.22);
    final outlineStroke = (w * 0.032).clamp(0.9, 2.2);
    final frameStroke = (w * 0.018).clamp(0.6, 1.4);

    // Gölge (gövdenin altında, hafif aşağı kaydırılmış).
    final shadowRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(w * 0.16, h * 0.06, w * 0.84, h * 0.97),
      Radius.circular(w * 0.2),
    );
    canvas.drawRRect(
      shadowRect,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.045),
    );

    // Tekerlekler — gövdeden hafif taşar (tramvayda çizilmez).
    if (!isTram) {
      final wheelW = w * 0.11;
      final wheelH = h * (isCar ? 0.15 : 0.13);
      void wheel(double cx, double cy) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(cx, cy),
              width: wheelW,
              height: wheelH,
            ),
            Radius.circular(wheelW * 0.45),
          ),
          Paint()..color = tyre,
        );
      }

      wheel(w * 0.17, h * 0.25);
      wheel(w * 0.83, h * 0.25);
      wheel(w * 0.17, h * 0.76);
      wheel(w * 0.83, h * 0.76);
      if (isBus) {
        // Körüklü/uzun otobüste orta aks.
        wheel(w * 0.17, h * 0.58);
        wheel(w * 0.83, h * 0.58);
      }
    }

    // Gövde: burun (üst) daha yuvarlak, arka (alt) daha köşeli.
    final body = Rect.fromLTRB(w * 0.2, h * 0.04, w * 0.8, h * 0.96);
    final noseR = Radius.circular(w * (isCar ? 0.22 : 0.17));
    final tailR = Radius.circular(w * (isTram ? 0.17 : 0.09));
    final bodyRRect = RRect.fromRectAndCorners(
      body,
      topLeft: noseR,
      topRight: noseR,
      bottomLeft: tailR,
      bottomRight: tailR,
    );
    canvas.drawRRect(
      bodyRRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(body.left, body.top),
          Offset(body.right, body.top),
          [shade, color, _lighten(color, 0.08), shade],
          const [0.0, 0.3, 0.7, 1.0],
        ),
    );
    // İnce beyaz dış kontur: hem açık hem koyu harita zemininde ayrışır.
    canvas.drawRRect(
      bodyRRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.92)
        ..style = PaintingStyle.stroke
        ..strokeWidth = outlineStroke,
    );

    // Ön cam (burun) — dolu, gerçek bir ön camın parlaklığına yakın.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.26, h * 0.085, w * 0.74, h * 0.2),
        Radius.circular(w * 0.05),
      ),
      Paint()..color = glass,
    );

    // Yan cam bantları: DOLU cam + ince çerçeve (önceden yalnız çerçeve
    // çiziliyordu — dolu cam gerçek bir araç penceresine çok daha yakın).
    // Aralarında kalan ince şerit gövde metalini/kapı hattını temsil eder.
    final stripes = isBus ? 3 : 2;
    for (var i = 0; i < stripes; i++) {
      final top = h * (0.3 + i * (isBus ? 0.16 : 0.22));
      final rect = Rect.fromLTRB(w * 0.22, top, w * 0.78, top + h * 0.095);
      final rr = RRect.fromRectAndRadius(rect, Radius.circular(w * 0.025));
      canvas.drawRRect(rr, Paint()..color = glass.withValues(alpha: 0.85));
      canvas.drawRRect(
        rr,
        Paint()
          ..color = shade.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = frameStroke,
      );
    }

    // Tavan paneli: yalnızca pencere bantları arasında kalan, camın
    // görünmediği metal/tavan yüzeyini örter (artık camların ÜSTÜNE değil
    // ALTINA çiziliyor — üstte çizilseydi dolu camları gizlerdi).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.29, h * 0.205, w * 0.71, h * 0.28),
        Radius.circular(w * 0.05),
      ),
      Paint()..color = roof.withValues(alpha: 0.95),
    );

    // Arka cam.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.28, h * (isCar ? 0.78 : 0.86), w * 0.72, h * 0.935),
        Radius.circular(w * 0.04),
      ),
      Paint()..color = glass.withValues(alpha: 0.8),
    );

    if (isTram) {
      // Pantograf: tavanda boydan boya ince çizgi.
      canvas.drawLine(
        Offset(w * 0.5, h * 0.3),
        Offset(w * 0.5, h * 0.76),
        Paint()
          ..color = shade
          ..strokeWidth = (w * 0.03).clamp(0.8, 1.8),
      );
    } else {
      // Kapı hattı: cam bantları arasında, gövdeyi enine kesen ince bir
      // çizgi — kuşbakışı otobüs/minibüste kapı böyle okunur.
      final doorY = h * (isBus ? 0.62 : 0.56);
      canvas.drawLine(
        Offset(w * 0.22, doorY),
        Offset(w * 0.78, doorY),
        Paint()
          ..color = shade.withValues(alpha: 0.7)
          ..strokeWidth = (w * 0.02).clamp(0.6, 1.2),
      );
    }

    // Aynalar (burnun iki yanında).
    for (final cx in [w * 0.16, w * 0.84]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx, h * 0.165),
            width: w * 0.12,
            height: h * 0.032,
          ),
          Radius.circular(w * 0.025),
        ),
        Paint()..color = tyre,
      );
    }

    // Farlar (ön, sarı) + stoplar (arka, kırmızı) — yön artık kartondaki
    // ok yerine gerçek bir aracın ışıklarıyla okunuyor.
    for (final cx in [w * 0.33, w * 0.67]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx, h * 0.07),
            width: w * 0.13,
            height: h * 0.024,
          ),
          Radius.circular(w * 0.035),
        ),
        Paint()..color = const Color(0xFFFFE9A8),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx, h * 0.955),
            width: w * 0.11,
            height: h * 0.02,
          ),
          Radius.circular(w * 0.03),
        ),
        Paint()..color = const Color(0xFFE0483F),
      );
    }
  }

  /// Motokurye: kuşbakışı motosiklet + arkada teslimat kutusu.
  static void _paintMotorcycle(Canvas canvas, Size size, Color color) {
    final w = size.width;
    final h = size.height;
    final tyre = const Color(0xFF23262C);
    final metal = const Color(0xFF4B515B);
    final helmetStroke = (w * 0.028).clamp(0.8, 1.4);
    final boxStroke = (w * 0.032).clamp(0.9, 1.8);
    final bandStroke = (w * 0.028).clamp(0.7, 1.6);

    // Gölge.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.3, h * 0.1, w * 0.7, h * 0.95),
        Radius.circular(w * 0.2),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.055),
    );

    void wheel(double cy, double hFactor) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(w * 0.5, cy),
            width: w * 0.17,
            height: h * hFactor,
          ),
          Radius.circular(w * 0.08),
        ),
        Paint()..color = tyre,
      );
    }

    // Ön ve arka tekerlek.
    wheel(h * 0.17, 0.19);
    wheel(h * 0.63, 0.2);

    // Egzoz: arka teker yanında, gövdenin dışına taşan küçük bir çubuk —
    // motoru bisikletten ayıran sessiz bir detay.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.62, h * 0.58, w * 0.72, h * 0.72),
        Radius.circular(w * 0.02),
      ),
      Paint()..color = tyre.withValues(alpha: 0.85),
    );

    // Şasi / yakıt deposu.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.39, h * 0.2, w * 0.61, h * 0.68),
        Radius.circular(w * 0.08),
      ),
      Paint()..color = metal,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.36, h * 0.3, w * 0.64, h * 0.47),
        Radius.circular(w * 0.1),
      ),
      Paint()..color = color,
    );

    // Gidon: iki yana çıkan bar + siyah tutamaklar.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.27),
          width: w * 0.78,
          height: h * 0.045,
        ),
        Radius.circular(h * 0.02),
      ),
      Paint()..color = tyre,
    );
    // Aynalar: gidonun iki ucunda küçük oval çıkıntılar.
    for (final cx in [w * 0.13, w * 0.87]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, h * 0.235),
          width: w * 0.1,
          height: h * 0.03,
        ),
        Paint()..color = tyre,
      );
    }
    // Far.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.085),
          width: w * 0.2,
          height: h * 0.032,
        ),
        Radius.circular(w * 0.04),
      ),
      Paint()..color = const Color(0xFFFFE9A8),
    );

    // Sürücü: omuzlar + kask (tepeden bakışta en belirgin parça).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.5),
          width: w * 0.54,
          height: h * 0.14,
        ),
        Radius.circular(w * 0.1),
      ),
      Paint()..color = _darken(color, 0.25),
    );
    final helmetCenter = Offset(w * 0.5, h * 0.43);
    canvas.drawCircle(helmetCenter, w * 0.16, Paint()..color = Colors.white);
    canvas.drawCircle(
      helmetCenter,
      w * 0.16,
      Paint()
        ..color = tyre.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = helmetStroke,
    );
    // Vizör: kaskın ön tarafında koyu hilal.
    canvas.drawArc(
      Rect.fromCircle(center: helmetCenter, radius: w * 0.12),
      3.6,
      2.1,
      false,
      Paint()
        ..color = tyre
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.075,
    );
    // Parlama: kaskta küçük bir ışık vurgusu (mat plastik yerine gerçekçi
    // kavisli yüzey hissi verir).
    canvas.drawOval(
      Rect.fromCenter(
        center: helmetCenter + Offset(-w * 0.05, -h * 0.02),
        width: w * 0.06,
        height: h * 0.025,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.75),
    );

    // Teslimat kutusu (arkada) — kuryeyi motosikletten ayıran işaret.
    final box = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.8),
        width: w * 0.56,
        height: h * 0.2,
      ),
      Radius.circular(w * 0.06),
    );
    canvas.drawRRect(box, Paint()..color = color);
    canvas.drawRRect(
      box,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.92)
        ..style = PaintingStyle.stroke
        ..strokeWidth = boxStroke,
    );
    // Kutu üstündeki beyaz çapraz bant (taşıma kayışı).
    canvas.drawLine(
      Offset(w * 0.29, h * 0.8),
      Offset(w * 0.71, h * 0.8),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..strokeWidth = bandStroke,
    );
    canvas.drawLine(
      Offset(w * 0.5, h * 0.71),
      Offset(w * 0.5, h * 0.89),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..strokeWidth = bandStroke,
    );
    // Stop lambası: kutunun hemen altında küçük kırmızı ışık.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.925),
          width: w * 0.16,
          height: h * 0.018,
        ),
        Radius.circular(w * 0.03),
      ),
      Paint()..color = const Color(0xFFE0483F),
    );
  }

  static Color _lighten(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  static Color _darken(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }
}
