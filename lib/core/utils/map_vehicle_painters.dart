import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Harita marker'ları ve listelerdeki küçük resimler için TEPEDEN GÖRÜNÜM
/// araç / durak çizimleri.
///
/// Bu dosya yalnızca [Canvas]'a çizer (bitmap üretimi `map_marker_icons.dart`,
/// widget'ı `map_vehicle_thumb.dart`). Tüm çizim MANTIKSAL (dp) ölçüde yapılır;
/// bitmap üretilirken tuval piksel oranıyla büyütülür, böylece yüksek
/// çözünürlüklü ekranlarda keskin durur.
///
/// Araçlar burnu YUKARI bakacak biçimde çizilir; haritada `Marker.rotation`
/// (heading) ile döndürülür. Işık sol-üstten gelir: gövde solda daha açık,
/// sağda daha koyudur. Kalınlık/blur değerleri [Size]'a ORANLIDIR — aksi halde
/// küçük çizimlerde çizgiler kaba kalır.

/// Hazır araç çizimleri. `sehirici_marker_icons.builtin_shape` değerleriyle
/// birebir aynı adları taşır.
enum MapVehicleShape {
  /// Minibüs: uzun şasili van gövdesi (Transit/Sprinter benzeri).
  minibus,

  /// Midibüs: kısa şehir otobüsü.
  midibus,

  /// Şehir otobüsü: uzun gövde, çatı klima üniteleri.
  bus,

  /// Dolmuş: minibüs gövdesi + çatıda "DOLMUŞ" tabelası.
  dolmus,

  /// Tramvay: iki ucu eşit, körüklü, çatıda pantograf.
  tram,

  /// Binek araç (sedan).
  car,

  /// Taksi: sedan + çatı lambası.
  taxi,

  /// Motosiklet + arkasında teslimat kutusu (kurye).
  motorcycle;

  /// `builtin_shape` metninden şekil; bilinmiyorsa null.
  static MapVehicleShape? fromKey(String? key) {
    for (final s in MapVehicleShape.values) {
      if (s.name == key) return s;
    }
    return null;
  }

  /// Kullanıcıya gösterilen ad (ikon düzenleyicide "hazır çizim" seçimi).
  String get label => switch (this) {
        MapVehicleShape.minibus => 'Minibüs',
        MapVehicleShape.midibus => 'Midibüs',
        MapVehicleShape.bus => 'Otobüs',
        MapVehicleShape.dolmus => 'Dolmuş',
        MapVehicleShape.tram => 'Tramvay',
        MapVehicleShape.car => 'Binek araç',
        MapVehicleShape.taxi => 'Taksi',
        MapVehicleShape.motorcycle => 'Motosiklet',
      };
}

/// Hazır durak çizimleri.
enum MapStopStyle {
  /// Direkli mavi durak levhası (varsayılan).
  sign,

  /// Otobüs simgeli modern harita iğnesi.
  pin,

  /// Yalın nokta.
  dot;

  static MapStopStyle? fromKey(String? key) {
    for (final s in MapStopStyle.values) {
      if (s.name == key) return s;
    }
    return null;
  }

  String get label => switch (this) {
        MapStopStyle.sign => 'Durak levhası',
        MapStopStyle.pin => 'Modern iğne',
        MapStopStyle.dot => 'Sade nokta',
      };

  /// Marker'ın koordinata oturan noktası: levha/iğnenin alt-orta noktası,
  /// nokta ise merkez.
  double get anchorY => this == MapStopStyle.dot ? 0.5 : 1.0;
}

/// Durağın haritadaki durumu.
enum MapStopState {
  normal,

  /// Kullanıcının dokunduğu / hattı vurgulanan durak.
  selected,

  /// Hattın ilk veya son durağı.
  terminal,
}

/// Uzaklığa göre ayrıntı düzeyi: uzaktan sade nokta, yakından tam levha.
/// (Şehir görünümünde 24 levha birbirini örter; nokta okunaklı kalır.)
enum MapStopDetail { far, mid, near }

// ─────────────────────────────────────────────
// Boyutlar (mantıksal dp)
// ─────────────────────────────────────────────

/// Aracın 1× ölçekteki tuval boyu. Gövde ~%80 genişliğe oturur; kalanı
/// aynalar ve tekerleklerin taşması içindir.
Size mapVehicleLogicalSize(MapVehicleShape shape) => switch (shape) {
      MapVehicleShape.minibus => const Size(32, 72),
      MapVehicleShape.dolmus => const Size(32, 72),
      MapVehicleShape.midibus => const Size(34, 84),
      MapVehicleShape.bus => const Size(36, 96),
      MapVehicleShape.tram => const Size(32, 104),
      MapVehicleShape.car => const Size(28, 58),
      MapVehicleShape.taxi => const Size(28, 58),
      // Kurye motoru mevcut haritalarda bu boyutla ayarlanmıştı; değiştirme.
      MapVehicleShape.motorcycle => const Size(36, 58),
    };

/// Durak çiziminin 1× tuval boyu.
Size mapStopLogicalSize(MapStopStyle style, MapStopDetail detail) {
  switch (style) {
    case MapStopStyle.sign:
      return switch (detail) {
        MapStopDetail.far => const Size(16, 16),
        MapStopDetail.mid => const Size(28, 40),
        MapStopDetail.near => const Size(34, 50),
      };
    case MapStopStyle.pin:
      return switch (detail) {
        MapStopDetail.far => const Size(16, 16),
        MapStopDetail.mid => const Size(28, 38),
        MapStopDetail.near => const Size(34, 46),
      };
    case MapStopStyle.dot:
      return switch (detail) {
        MapStopDetail.far => const Size(14, 14),
        MapStopDetail.mid => const Size(18, 18),
        MapStopDetail.near => const Size(22, 22),
      };
  }
}

// ─────────────────────────────────────────────
// Renk yardımcıları
// ─────────────────────────────────────────────

Color mapLighten(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
      .toColor();
}

Color mapDarken(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
      .toColor();
}

/// Çok açık/çok koyu hat renklerinde gövdenin haritada kaybolmaması için
/// parlaklığı makul aralığa çeker (beyaz hat rengi beyaz haritada görünmezdi).
Color _bodyColor(Color color) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness(hsl.lightness.clamp(0.24, 0.66)).toColor();
}

/// Üç renkli gradyanlar için eşit aralıklı durak noktaları
/// (dart:ui, 2'den fazla renkte durak noktası ister).
const List<double> _stops3 = [0.0, 0.5, 1.0];

const Color _tyre = Color(0xFF1B1E24);
const Color _glassTop = Color(0xFF2C4560);
const Color _glassBottom = Color(0xFF12202F);
const Color _headlight = Color(0xFFFFF4CF);
const Color _taillight = Color(0xFFE5392F);

// ─────────────────────────────────────────────
// Ortak parçalar
// ─────────────────────────────────────────────

Paint _fill(Color c) => Paint()
  ..color = c
  ..isAntiAlias = true;

Paint _stroke(Color c, double width) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..isAntiAlias = true;

/// Zemine düşen yumuşak gölge — sağ-alta kaymış (ışık sol-üstten).
void _groundShadow(Canvas canvas, RRect body, double blur, double alpha) {
  canvas.drawRRect(
    body.shift(Offset(body.width * 0.07, body.height * 0.018)),
    Paint()
      ..color = Colors.black.withValues(alpha: alpha)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
  );
}

void _wheel(Canvas canvas, Offset center, double w, double h) {
  final r = RRect.fromRectAndRadius(
    Rect.fromCenter(center: center, width: w, height: h),
    Radius.circular(w * 0.42),
  );
  canvas.drawRRect(r, _fill(_tyre));
  // Lastik yan duvarında ince açık vurgu.
  canvas.drawRRect(
    r.deflate(w * 0.2),
    _fill(Colors.white.withValues(alpha: 0.10)),
  );
}

/// Ön/arka cam: koyu mavi-gri geçişli, çapraz yansımalı.
void _glass(Canvas canvas, Path path, Rect bounds, {double reflect = 0.30}) {
  canvas.drawPath(
    path,
    Paint()
      ..shader = ui.Gradient.linear(
        bounds.topLeft,
        bounds.bottomRight,
        [_glassTop, _glassBottom],
      )
      ..isAntiAlias = true,
  );
  canvas.save();
  canvas.clipPath(path);
  // Çapraz parlama şeridi.
  final streak = Path()
    ..moveTo(bounds.left + bounds.width * 0.08, bounds.bottom)
    ..lineTo(bounds.left + bounds.width * 0.42, bounds.top)
    ..lineTo(bounds.left + bounds.width * 0.62, bounds.top)
    ..lineTo(bounds.left + bounds.width * 0.28, bounds.bottom)
    ..close();
  canvas.drawPath(
    streak,
    Paint()
      ..shader = ui.Gradient.linear(
        bounds.topLeft,
        bounds.bottomRight,
        [
          Colors.white.withValues(alpha: reflect),
          Colors.white.withValues(alpha: 0.02),
        ],
      ),
  );
  canvas.restore();
  canvas.drawPath(path, _stroke(Colors.black.withValues(alpha: 0.35), 0.4));
}

void _headlights(Canvas canvas, double left, double right, double y, double w,
    double h) {
  for (final cx in [left, right]) {
    final rr = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, y), width: w, height: h),
      Radius.circular(h * 0.5),
    );
    // Hafif ışıma.
    canvas.drawRRect(
      rr.inflate(h * 0.5),
      Paint()
        ..color = _headlight.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.9),
    );
    canvas.drawRRect(rr, _fill(_headlight));
  }
}

void _taillights(Canvas canvas, double left, double right, double y, double w,
    double h) {
  for (final cx in [left, right]) {
    final rr = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, y), width: w, height: h),
      Radius.circular(h * 0.4),
    );
    canvas.drawRRect(rr, _fill(_taillight));
    canvas.drawRRect(
      rr.deflate(h * 0.22),
      _fill(Colors.white.withValues(alpha: 0.28)),
    );
  }
}

void _mirror(Canvas canvas, Offset center, double w, double h, Color body,
    {required bool leftSide}) {
  // Sap.
  canvas.drawLine(
    Offset(center.dx + (leftSide ? w * 0.5 : -w * 0.5), center.dy),
    Offset(center.dx + (leftSide ? w * 0.9 : -w * 0.9), center.dy),
    _stroke(mapDarken(body, 0.18), math.max(0.7, h * 0.22)),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: w, height: h),
      Radius.circular(h * 0.45),
    ),
    _fill(const Color(0xFF14171C)),
  );
}

/// Gövde dolgusu: silindirik bir yüzey gibi kenarlarda koyu, ortada açık;
/// ışık soldan geldiği için sol yarı biraz daha parlak.
Shader _bodyShader(Rect r, Color color) {
  return ui.Gradient.linear(
    Offset(r.left, 0),
    Offset(r.right, 0),
    [
      mapDarken(color, 0.10),
      mapLighten(color, 0.10),
      mapLighten(color, 0.03),
      color,
      mapDarken(color, 0.20),
    ],
    const [0.0, 0.16, 0.42, 0.72, 1.0],
  );
}

void _bodyRim(Canvas canvas, RRect body, Color color, double w) {
  canvas.drawRRect(body, _stroke(mapDarken(color, 0.30), math.max(0.6, w * 0.02)));
  // Sol-üst kenarda ince ışık şeridi (koyu haritada gövdeyi zeminden ayırır).
  canvas.drawRRect(
    body.deflate(math.max(0.4, w * 0.012)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.5, w * 0.016)
      ..shader = ui.Gradient.linear(
        body.outerRect.topLeft,
        body.outerRect.bottomRight,
        [
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0.05),
        ],
      ),
  );
}

// ─────────────────────────────────────────────
// Araç çizimi (giriş noktası)
// ─────────────────────────────────────────────

void paintMapVehicle(
  Canvas canvas,
  Size size,
  MapVehicleShape shape,
  Color lineColor,
) {
  final color = _bodyColor(lineColor);
  switch (shape) {
    case MapVehicleShape.minibus:
      _paintVan(canvas, size, color, roofSign: false);
    case MapVehicleShape.dolmus:
      _paintVan(canvas, size, color, roofSign: true);
    case MapVehicleShape.midibus:
      _paintBus(canvas, size, color, pods: 1, articulated: false);
    case MapVehicleShape.bus:
      _paintBus(canvas, size, color, pods: 2, articulated: false);
    case MapVehicleShape.tram:
      _paintTram(canvas, size, color);
    case MapVehicleShape.car:
      _paintCar(canvas, size, color, taxi: false);
    case MapVehicleShape.taxi:
      _paintCar(canvas, size, const Color(0xFFF2B705), taxi: true);
    case MapVehicleShape.motorcycle:
      _paintMotorcycle(canvas, size, color);
  }
}

/// Minibüs / dolmuş: uzun şasili van.
void _paintVan(Canvas canvas, Size s, Color color, {required bool roofSign}) {
  final w = s.width, h = s.height;
  final bw = w * 0.76;
  final cx = w / 2;
  final left = cx - bw / 2, right = cx + bw / 2;
  final top = h * 0.02, bottom = h * 0.98;
  final rect = Rect.fromLTRB(left, top, right, bottom);
  final body = RRect.fromRectAndCorners(
    rect,
    topLeft: Radius.circular(bw * 0.34),
    topRight: Radius.circular(bw * 0.34),
    bottomLeft: Radius.circular(bw * 0.16),
    bottomRight: Radius.circular(bw * 0.16),
  );

  _groundShadow(canvas, body, w * 0.06, 0.34);

  // Tekerlekler gövdeden hafif taşar.
  for (final y in [h * 0.20, h * 0.76]) {
    _wheel(canvas, Offset(left, y), w * 0.10, h * 0.125);
    _wheel(canvas, Offset(right, y), w * 0.10, h * 0.125);
  }

  canvas.drawRRect(body, Paint()..shader = _bodyShader(rect, color));

  // Kaput: ön kısım biraz açık, ortasında kıvrım çizgisi.
  final hood = RRect.fromRectAndCorners(
    Rect.fromLTRB(left, top, right, h * 0.205),
    topLeft: Radius.circular(bw * 0.34),
    topRight: Radius.circular(bw * 0.34),
  );
  canvas.drawRRect(hood, _fill(Colors.white.withValues(alpha: 0.10)));
  canvas.drawLine(
    Offset(cx, top + h * 0.03),
    Offset(cx, h * 0.195),
    _stroke(mapDarken(color, 0.22).withValues(alpha: 0.55), 0.6),
  );
  // Ön tampon.
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTRB(left + bw * 0.08, top + h * 0.004, right - bw * 0.08,
          top + h * 0.03),
      Radius.circular(bw * 0.1),
    ),
    _fill(const Color(0xFF20242B)),
  );

  // Ön cam (cowl geniş → çatı başlığı dar).
  final ws = Path()
    ..moveTo(left + bw * 0.06, h * 0.212)
    ..lineTo(right - bw * 0.06, h * 0.212)
    ..lineTo(right - bw * 0.11, h * 0.325)
    ..lineTo(left + bw * 0.11, h * 0.325)
    ..close();
  _glass(canvas, ws, ws.getBounds());

  // Çatı paneli.
  final roof = RRect.fromRectAndRadius(
    Rect.fromLTRB(left + bw * 0.09, h * 0.335, right - bw * 0.09, h * 0.895),
    Radius.circular(bw * 0.16),
  );
  canvas.drawRRect(
    roof,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(roof.left, 0),
        Offset(roof.right, 0),
        [
          mapLighten(color, 0.13),
          mapLighten(color, 0.06),
          mapDarken(color, 0.02),
        ],
        _stops3,
      ),
  );
  canvas.drawRRect(roof, _stroke(mapDarken(color, 0.28).withValues(alpha: 0.6), 0.5));
  // Preslenmiş çatı nervürleri (gerçek van çatılarındaki uzunlamasına kıvrımlar).
  for (final rx in [cx - bw * 0.22, cx + bw * 0.22]) {
    canvas.drawLine(
      Offset(rx, roof.top + h * 0.03),
      Offset(rx, roof.bottom - h * 0.03),
      _stroke(mapDarken(color, 0.22).withValues(alpha: 0.30), 0.5),
    );
  }
  // Çatı sol yarısında ışık yansıması.
  canvas.save();
  canvas.clipRRect(roof);
  canvas.drawRect(
    Rect.fromLTRB(roof.left, roof.top, roof.left + roof.width * 0.4, roof.bottom),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(roof.left, 0),
        Offset(roof.left + roof.width * 0.4, 0),
        [Colors.white.withValues(alpha: 0.22), Colors.white.withValues(alpha: 0)],
      ),
  );
  canvas.restore();

  // Çatı havalandırmaları.
  for (final vy in [h * 0.47, h * 0.66]) {
    final vent = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, vy),
        width: bw * 0.42,
        height: h * 0.05,
      ),
      Radius.circular(bw * 0.06),
    );
    canvas.drawRRect(vent, _fill(const Color(0xFFE9EDF2)));
    canvas.drawRRect(vent, _stroke(const Color(0xFF55606E), 0.4));
    canvas.drawLine(
      Offset(cx - bw * 0.16, vy),
      Offset(cx + bw * 0.16, vy),
      _stroke(const Color(0xFF8A95A3), 0.4),
    );
  }

  if (roofSign) {
    // Dolmuş tabelası.
    final sign = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, h * 0.385),
        width: bw * 0.58,
        height: h * 0.05,
      ),
      Radius.circular(bw * 0.05),
    );
    canvas.drawRRect(
      sign.shift(const Offset(0.3, 0.6)),
      _fill(Colors.black.withValues(alpha: 0.25)),
    );
    canvas.drawRRect(sign, _fill(const Color(0xFFFFC107)));
    canvas.drawRRect(sign, _stroke(const Color(0xFF7A5B00), 0.5));
    // Yazıyı temsil eden iki koyu çizgi.
    canvas.drawLine(
      Offset(cx - bw * 0.2, h * 0.385),
      Offset(cx + bw * 0.2, h * 0.385),
      _stroke(const Color(0xFF3A2D00), math.max(0.8, h * 0.012)),
    );
  }

  // Arka cam + tampon.
  final rear = Path()
    ..addRRect(RRect.fromRectAndRadius(
      Rect.fromLTRB(left + bw * 0.13, h * 0.905, right - bw * 0.13, h * 0.948),
      Radius.circular(bw * 0.06),
    ));
  _glass(canvas, rear, rear.getBounds(), reflect: 0.2);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTRB(left + bw * 0.06, bottom - h * 0.022, right - bw * 0.06,
          bottom - h * 0.002),
      Radius.circular(bw * 0.08),
    ),
    _fill(const Color(0xFF20242B)),
  );

  _headlights(canvas, left + bw * 0.2, right - bw * 0.2, top + h * 0.014,
      bw * 0.17, h * 0.022);
  _taillights(canvas, left + bw * 0.13, right - bw * 0.13, bottom - h * 0.04,
      bw * 0.13, h * 0.022);

  _mirror(canvas, Offset(left - w * 0.075, h * 0.235), w * 0.085, h * 0.05, color,
      leftSide: true);
  _mirror(canvas, Offset(right + w * 0.075, h * 0.235), w * 0.085, h * 0.05,
      color,
      leftSide: false);

  _bodyRim(canvas, body, color, bw);
}

/// Şehir otobüsü / midibüs.
void _paintBus(
  Canvas canvas,
  Size s,
  Color color, {
  required int pods,
  required bool articulated,
}) {
  final w = s.width, h = s.height;
  final bw = w * 0.76;
  final cx = w / 2;
  final left = cx - bw / 2, right = cx + bw / 2;
  final top = h * 0.015, bottom = h * 0.985;
  final rect = Rect.fromLTRB(left, top, right, bottom);
  final body = RRect.fromRectAndCorners(
    rect,
    topLeft: Radius.circular(bw * 0.24),
    topRight: Radius.circular(bw * 0.24),
    bottomLeft: Radius.circular(bw * 0.14),
    bottomRight: Radius.circular(bw * 0.14),
  );

  _groundShadow(canvas, body, w * 0.06, 0.34);

  final axle1 = h * 0.15;
  final axle2 = pods >= 2 ? h * 0.72 : h * 0.70;
  for (final y in [axle1, axle2]) {
    _wheel(canvas, Offset(left, y), w * 0.10, h * (pods >= 2 ? 0.10 : 0.11));
    _wheel(canvas, Offset(right, y), w * 0.10, h * (pods >= 2 ? 0.10 : 0.11));
  }
  if (pods >= 2) {
    // Arka ikiz teker hissi (üçüncü aks).
    _wheel(canvas, Offset(left, h * 0.82), w * 0.10, h * 0.10);
    _wheel(canvas, Offset(right, h * 0.82), w * 0.10, h * 0.10);
  }

  canvas.drawRRect(body, Paint()..shader = _bodyShader(rect, color));

  // Ön cam: geniş, iki parça (ortada sil direği).
  final wsRect =
      Rect.fromLTRB(left + bw * 0.07, h * 0.03, right - bw * 0.07, h * 0.115);
  final ws = Path()
    ..addRRect(RRect.fromRectAndCorners(
      wsRect,
      topLeft: Radius.circular(bw * 0.18),
      topRight: Radius.circular(bw * 0.18),
      bottomLeft: Radius.circular(bw * 0.05),
      bottomRight: Radius.circular(bw * 0.05),
    ));
  _glass(canvas, ws, wsRect);
  canvas.drawLine(
    Offset(cx, wsRect.top + 0.5),
    Offset(cx, wsRect.bottom),
    _stroke(const Color(0xFF0B1118), 0.7),
  );
  // Hat/güzergâh tabelası (kehribar LED şerit).
  final destSign = RRect.fromRectAndRadius(
    Rect.fromLTRB(left + bw * 0.22, h * 0.121, right - bw * 0.22, h * 0.138),
    Radius.circular(bw * 0.04),
  );
  canvas.drawRRect(destSign, _fill(const Color(0xFF15181D)));
  canvas.drawRRect(
    destSign.deflate(0.5),
    _fill(const Color(0xFFFFA000).withValues(alpha: 0.9)),
  );

  // Çatı.
  final roof = RRect.fromRectAndRadius(
    Rect.fromLTRB(left + bw * 0.08, h * 0.15, right - bw * 0.08, h * 0.955),
    Radius.circular(bw * 0.13),
  );
  canvas.drawRRect(
    roof,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(roof.left, 0),
        Offset(roof.right, 0),
        [
          mapLighten(color, 0.16),
          mapLighten(color, 0.10),
          mapLighten(color, 0.04),
        ],
        _stops3,
      ),
  );
  canvas.drawRRect(roof, _stroke(mapDarken(color, 0.25).withValues(alpha: 0.5), 0.5));

  // Klima üniteleri / çatı kapakları.
  final podYs = pods >= 2 ? [h * 0.30, h * 0.60] : [h * 0.5];
  for (final py in podYs) {
    final pod = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, py),
        width: bw * 0.62,
        height: h * 0.105,
      ),
      Radius.circular(bw * 0.09),
    );
    canvas.drawRRect(
      pod.shift(const Offset(0.4, 0.8)),
      _fill(Colors.black.withValues(alpha: 0.22)),
    );
    canvas.drawRRect(
      pod,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(pod.left, pod.top),
          Offset(pod.right, pod.bottom),
          [const Color(0xFFF4F6F9), const Color(0xFFD5DBE3)],
        ),
    );
    canvas.drawRRect(pod, _stroke(const Color(0xFF68727F), 0.4));
    // Fan kanatçıkları.
    for (var i = -2; i <= 2; i++) {
      canvas.drawLine(
        Offset(cx + i * bw * 0.10, py - h * 0.038),
        Offset(cx + i * bw * 0.10, py + h * 0.038),
        _stroke(const Color(0xFF8994A2), 0.4),
      );
    }
  }
  // Ortadaki küçük kaçış kapağı.
  if (pods >= 2) {
    final hatch = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, h * 0.45), width: bw * 0.3, height: h * 0.038),
      Radius.circular(bw * 0.05),
    );
    canvas.drawRRect(hatch, _fill(mapLighten(color, 0.4)));
    canvas.drawRRect(hatch, _stroke(mapDarken(color, 0.2).withValues(alpha: 0.6), 0.4));
  }

  // Sol kenarda ışık.
  canvas.save();
  canvas.clipRRect(roof);
  canvas.drawRect(
    Rect.fromLTRB(roof.left, roof.top, roof.left + roof.width * 0.35, roof.bottom),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(roof.left, 0),
        Offset(roof.left + roof.width * 0.35, 0),
        [Colors.white.withValues(alpha: 0.28), Colors.white.withValues(alpha: 0)],
      ),
  );
  canvas.restore();

  // Arka cam.
  final rearRect =
      Rect.fromLTRB(left + bw * 0.16, h * 0.962, right - bw * 0.16, h * 0.985);
  final rear = Path()
    ..addRRect(RRect.fromRectAndRadius(rearRect, Radius.circular(bw * 0.05)));
  _glass(canvas, rear, rearRect, reflect: 0.16);

  _headlights(canvas, left + bw * 0.17, right - bw * 0.17, top + h * 0.011,
      bw * 0.16, h * 0.014);
  _taillights(canvas, left + bw * 0.11, right - bw * 0.11, bottom - h * 0.016,
      bw * 0.12, h * 0.016);

  _mirror(canvas, Offset(left - w * 0.07, h * 0.135), w * 0.085, h * 0.042, color,
      leftSide: true);
  _mirror(canvas, Offset(right + w * 0.07, h * 0.135), w * 0.085, h * 0.042,
      color,
      leftSide: false);

  _bodyRim(canvas, body, color, bw);
}

/// Tramvay: iki ucu eşit, ortada körük, çatıda iki pantograf.
void _paintTram(Canvas canvas, Size s, Color color) {
  final w = s.width, h = s.height;
  final bw = w * 0.74;
  final cx = w / 2;
  final left = cx - bw / 2, right = cx + bw / 2;
  final top = h * 0.012, bottom = h * 0.988;
  final rect = Rect.fromLTRB(left, top, right, bottom);
  final body = RRect.fromRectAndRadius(rect, Radius.circular(bw * 0.3));

  _groundShadow(canvas, body, w * 0.05, 0.32);
  canvas.drawRRect(body, Paint()..shader = _bodyShader(rect, color));

  // İki ucta ön cam.
  for (final atTop in [true, false]) {
    final r = atTop
        ? Rect.fromLTRB(left + bw * 0.10, h * 0.03, right - bw * 0.10, h * 0.085)
        : Rect.fromLTRB(left + bw * 0.10, h * 0.915, right - bw * 0.10, h * 0.97);
    final p = Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(bw * 0.14)));
    _glass(canvas, p, r);
  }

  // Çatı (açık) + orta körük.
  final roof = RRect.fromRectAndRadius(
    Rect.fromLTRB(left + bw * 0.08, h * 0.10, right - bw * 0.08, h * 0.90),
    Radius.circular(bw * 0.12),
  );
  canvas.drawRRect(
    roof,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(roof.left, 0),
        Offset(roof.right, 0),
        [mapLighten(color, 0.18), mapLighten(color, 0.11), mapLighten(color, 0.05)],
        _stops3,
      ),
  );
  canvas.drawRRect(roof, _stroke(mapDarken(color, 0.25).withValues(alpha: 0.5), 0.5));
  // Körük (eklem): enine koyu bant + kıvrımlar.
  final joint = Rect.fromLTRB(left + bw * 0.04, h * 0.475, right - bw * 0.04, h * 0.525);
  canvas.drawRRect(
    RRect.fromRectAndRadius(joint, Radius.circular(bw * 0.06)),
    _fill(const Color(0xFF1E2229)),
  );
  for (var i = 1; i <= 3; i++) {
    final yy = joint.top + joint.height * i / 4;
    canvas.drawLine(
      Offset(joint.left + 1, yy),
      Offset(joint.right - 1, yy),
      _stroke(const Color(0xFF444B56), 0.5),
    );
  }

  // Pantograf: iki eşkenar dörtgen kol + toplama çubuğu.
  for (final py in [h * 0.30, h * 0.70]) {
    final arm = Path()
      ..moveTo(cx, py - h * 0.05)
      ..lineTo(cx + bw * 0.22, py)
      ..lineTo(cx, py + h * 0.05)
      ..lineTo(cx - bw * 0.22, py)
      ..close();
    canvas.drawPath(arm, _stroke(const Color(0xFF39414C), math.max(0.8, w * 0.03)));
    canvas.drawLine(
      Offset(cx - bw * 0.3, py - h * 0.05),
      Offset(cx + bw * 0.3, py - h * 0.05),
      _stroke(const Color(0xFF20252C), math.max(1.0, w * 0.04)),
    );
  }

  // Şeritler (yan ışık hatları).
  _headlights(canvas, left + bw * 0.2, right - bw * 0.2, top + h * 0.01, bw * 0.14, h * 0.012);
  _taillights(canvas, left + bw * 0.2, right - bw * 0.2, bottom - h * 0.012, bw * 0.14, h * 0.012);

  _bodyRim(canvas, body, color, bw);
}

/// Binek / taksi (sedan).
void _paintCar(Canvas canvas, Size s, Color color, {required bool taxi}) {
  final w = s.width, h = s.height;
  final bw = w * 0.74;
  final cx = w / 2;
  final left = cx - bw / 2, right = cx + bw / 2;
  final top = h * 0.02, bottom = h * 0.98;
  final rect = Rect.fromLTRB(left, top, right, bottom);
  // Sedan silueti: burun daha dar, gövde ortada geniş.
  final body = RRect.fromRectAndCorners(
    rect,
    topLeft: Radius.circular(bw * 0.42),
    topRight: Radius.circular(bw * 0.42),
    bottomLeft: Radius.circular(bw * 0.26),
    bottomRight: Radius.circular(bw * 0.26),
  );

  _groundShadow(canvas, body, w * 0.06, 0.34);
  for (final y in [h * 0.22, h * 0.76]) {
    _wheel(canvas, Offset(left + bw * 0.02, y), w * 0.11, h * 0.15);
    _wheel(canvas, Offset(right - bw * 0.02, y), w * 0.11, h * 0.15);
  }
  canvas.drawRRect(body, Paint()..shader = _bodyShader(rect, color));

  // Kaput ortası kıvrımı.
  canvas.drawLine(
    Offset(cx, top + h * 0.05),
    Offset(cx, h * 0.27),
    _stroke(mapDarken(color, 0.2).withValues(alpha: 0.5), 0.5),
  );

  // Ön cam.
  final ws = Path()
    ..moveTo(left + bw * 0.10, h * 0.30)
    ..quadraticBezierTo(cx, h * 0.265, right - bw * 0.10, h * 0.30)
    ..lineTo(right - bw * 0.15, h * 0.42)
    ..lineTo(left + bw * 0.15, h * 0.42)
    ..close();
  _glass(canvas, ws, ws.getBounds());

  // Kabin çatısı.
  final roof = RRect.fromRectAndRadius(
    Rect.fromLTRB(left + bw * 0.12, h * 0.425, right - bw * 0.12, h * 0.66),
    Radius.circular(bw * 0.12),
  );
  canvas.drawRRect(
    roof,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(roof.left, 0),
        Offset(roof.right, 0),
        [mapLighten(color, 0.14), mapLighten(color, 0.06), color],
        _stops3,
      ),
  );
  canvas.drawRRect(roof, _stroke(mapDarken(color, 0.28).withValues(alpha: 0.5), 0.4));

  // Arka cam.
  final rw = Path()
    ..moveTo(left + bw * 0.15, h * 0.665)
    ..lineTo(right - bw * 0.15, h * 0.665)
    ..lineTo(right - bw * 0.10, h * 0.74)
    ..quadraticBezierTo(cx, h * 0.765, left + bw * 0.10, h * 0.74)
    ..close();
  _glass(canvas, rw, rw.getBounds(), reflect: 0.2);

  if (taxi) {
    final lamp = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, h * 0.545), width: bw * 0.5, height: h * 0.05),
      Radius.circular(bw * 0.06),
    );
    canvas.drawRRect(lamp.shift(const Offset(0.3, 0.6)), _fill(Colors.black.withValues(alpha: 0.28)));
    canvas.drawRRect(lamp, _fill(const Color(0xFFFFFDE7)));
    canvas.drawRRect(lamp, _stroke(const Color(0xFF6B5A00), 0.5));
    canvas.drawLine(
      Offset(cx - bw * 0.16, h * 0.545),
      Offset(cx + bw * 0.16, h * 0.545),
      _stroke(const Color(0xFF3A2D00), math.max(0.7, h * 0.01)),
    );
  }

  _headlights(canvas, left + bw * 0.2, right - bw * 0.2, top + h * 0.02, bw * 0.17, h * 0.024);
  _taillights(canvas, left + bw * 0.16, right - bw * 0.16, bottom - h * 0.034, bw * 0.15, h * 0.022);
  _mirror(canvas, Offset(left - w * 0.06, h * 0.315), w * 0.08, h * 0.05, color, leftSide: true);
  _mirror(canvas, Offset(right + w * 0.06, h * 0.315), w * 0.08, h * 0.05, color, leftSide: false);

  _bodyRim(canvas, body, color, bw);
}

/// Motokurye: kuşbakışı motosiklet + arkasında teslimat kutusu.
void _paintMotorcycle(Canvas canvas, Size size, Color color) {
  final w = size.width;
  final h = size.height;
  const tyre = _tyre;
  const metal = Color(0xFF4B515B);
  final helmetStroke = (w * 0.028).clamp(0.8, 1.4);
  final boxStroke = (w * 0.032).clamp(0.9, 1.8);
  final bandStroke = (w * 0.028).clamp(0.7, 1.6);

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
      _fill(tyre),
    );
  }

  wheel(h * 0.17, 0.19);
  wheel(h * 0.63, 0.2);

  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTRB(w * 0.62, h * 0.58, w * 0.72, h * 0.72),
      Radius.circular(w * 0.02),
    ),
    _fill(tyre.withValues(alpha: 0.85)),
  );

  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTRB(w * 0.39, h * 0.2, w * 0.61, h * 0.68),
      Radius.circular(w * 0.08),
    ),
    _fill(metal),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTRB(w * 0.36, h * 0.3, w * 0.64, h * 0.47),
      Radius.circular(w * 0.1),
    ),
    _fill(color),
  );

  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.27),
        width: w * 0.78,
        height: h * 0.045,
      ),
      Radius.circular(h * 0.02),
    ),
    _fill(tyre),
  );
  for (final cx in [w * 0.13, w * 0.87]) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, h * 0.235),
        width: w * 0.1,
        height: h * 0.03,
      ),
      _fill(tyre),
    );
  }
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.085),
        width: w * 0.2,
        height: h * 0.032,
      ),
      Radius.circular(w * 0.04),
    ),
    _fill(_headlight),
  );

  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.5),
        width: w * 0.54,
        height: h * 0.14,
      ),
      Radius.circular(w * 0.1),
    ),
    _fill(mapDarken(color, 0.25)),
  );
  final helmetCenter = Offset(w * 0.5, h * 0.43);
  canvas.drawCircle(helmetCenter, w * 0.16, _fill(Colors.white));
  canvas.drawCircle(
    helmetCenter,
    w * 0.16,
    _stroke(tyre.withValues(alpha: 0.55), helmetStroke),
  );
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
  canvas.drawOval(
    Rect.fromCenter(
      center: helmetCenter + Offset(-w * 0.05, -h * 0.02),
      width: w * 0.06,
      height: h * 0.025,
    ),
    _fill(Colors.white.withValues(alpha: 0.75)),
  );

  final box = RRect.fromRectAndRadius(
    Rect.fromCenter(
      center: Offset(w * 0.5, h * 0.8),
      width: w * 0.56,
      height: h * 0.2,
    ),
    Radius.circular(w * 0.06),
  );
  canvas.drawRRect(box, _fill(color));
  canvas.drawRRect(
    box,
    _stroke(Colors.white.withValues(alpha: 0.92), boxStroke),
  );
  canvas.drawLine(
    Offset(w * 0.29, h * 0.8),
    Offset(w * 0.71, h * 0.8),
    _stroke(Colors.white.withValues(alpha: 0.85), bandStroke),
  );
  canvas.drawLine(
    Offset(w * 0.5, h * 0.71),
    Offset(w * 0.5, h * 0.89),
    _stroke(Colors.white.withValues(alpha: 0.85), bandStroke),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.925),
        width: w * 0.16,
        height: h * 0.018,
      ),
      Radius.circular(w * 0.03),
    ),
    _fill(_taillight),
  );
}

// ─────────────────────────────────────────────
// Durak çizimi
// ─────────────────────────────────────────────

const Color kStopBlue = Color(0xFF1565D8);
const Color kStopBlueDark = Color(0xFF0B3D91);
const Color kStopSelected = Color(0xFFFF8F00);
const Color kStopStart = Color(0xFF2E9E5B);
const Color kStopEnd = Color(0xFFD9382C);

/// Durak çizimi. [lineColors] duraktan geçen hatların renkleridir (en çok 3
/// çizilir); tek hat varsa iğne/nokta o renge boyanır.
void paintMapStop(
  Canvas canvas,
  Size size,
  MapStopStyle style,
  MapStopDetail detail,
  MapStopState state,
  List<Color> lineColors, {
  bool isStart = false,
  bool isEnd = false,
}) {
  final accent = state == MapStopState.selected
      ? kStopSelected
      : (lineColors.length == 1 ? _bodyColor(lineColors.first) : kStopBlue);

  if (detail == MapStopDetail.far || style == MapStopStyle.dot) {
    _paintStopDot(canvas, size, accent, state, isStart: isStart, isEnd: isEnd);
    return;
  }
  switch (style) {
    case MapStopStyle.sign:
      _paintStopSign(canvas, size, state, lineColors,
          isStart: isStart, isEnd: isEnd);
    case MapStopStyle.pin:
      _paintStopPin(canvas, size, accent, state, lineColors,
          isStart: isStart, isEnd: isEnd);
    case MapStopStyle.dot:
      break;
  }
}

void _paintStopDot(
  Canvas canvas,
  Size s,
  Color accent,
  MapStopState state, {
  required bool isStart,
  required bool isEnd,
}) {
  final c = s.center(Offset.zero);
  final r = s.shortestSide / 2;
  canvas.drawCircle(
    c.translate(0, r * 0.14),
    r * 0.86,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.18),
  );
  canvas.drawCircle(c, r * 0.9, _fill(Colors.white));
  final terminalColor = isStart ? kStopStart : (isEnd ? kStopEnd : null);
  canvas.drawCircle(c, r * 0.68, _fill(terminalColor ?? accent));
  canvas.drawCircle(c, r * 0.24, _fill(Colors.white.withValues(alpha: 0.95)));
}

/// Otobüs ön görünüm piktogramı (durak levhalarındaki klasik simge). [box]
/// 20×20'lik kutuya oturur.
void _busGlyph(Canvas canvas, Rect box, Color fg, Color cut) {
  final u = box.width / 20;
  Rect r(double x, double y, double w, double h) =>
      Rect.fromLTWH(box.left + x * u, box.top + y * u, w * u, h * u);
  canvas.drawRRect(
    RRect.fromRectAndRadius(r(3, 1.5, 14, 14.5), Radius.circular(2.6 * u)),
    _fill(fg),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(r(5, 3.6, 10, 5.4), Radius.circular(1.2 * u)),
    _fill(cut),
  );
  canvas.drawRect(r(3, 10.4, 14, 1.1), _fill(cut.withValues(alpha: 0.55)));
  canvas.drawCircle(Offset(box.left + 6.4 * u, box.top + 13.2 * u), 1.15 * u, _fill(cut));
  canvas.drawCircle(Offset(box.left + 13.6 * u, box.top + 13.2 * u), 1.15 * u, _fill(cut));
  canvas.drawRRect(
    RRect.fromRectAndRadius(r(4.2, 15.6, 3, 2.6), Radius.circular(0.8 * u)),
    _fill(fg),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(r(12.8, 15.6, 3, 2.6), Radius.circular(0.8 * u)),
    _fill(fg),
  );
}

void _paintStopSign(
  Canvas canvas,
  Size s,
  MapStopState state,
  List<Color> lineColors, {
  required bool isStart,
  required bool isEnd,
}) {
  final w = s.width, h = s.height;
  final cx = w / 2;
  final selected = state == MapStopState.selected;
  final panelBlue = selected ? kStopSelected : kStopBlue;
  final panelDark = selected ? const Color(0xFFB85F00) : kStopBlueDark;

  final panelSize = w * 0.74;
  final panel = Rect.fromCenter(
    center: Offset(cx, panelSize / 2 + 1),
    width: panelSize,
    height: panelSize,
  );
  final hasChips = lineColors.isNotEmpty;
  final plateH = hasChips ? h * 0.15 : 0.0;
  final plate = Rect.fromLTWH(
    panel.left + panel.width * 0.08,
    panel.bottom + h * 0.012,
    panel.width * 0.84,
    plateH,
  );
  final poleTop = hasChips ? plate.bottom : panel.bottom;
  final baseY = h - 2.5;

  // Zemin gölgesi.
  canvas.drawOval(
    Rect.fromCenter(center: Offset(cx + w * 0.05, baseY), width: w * 0.42, height: h * 0.055),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.32)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.05),
  );
  // Direk.
  final pole = RRect.fromRectAndRadius(
    Rect.fromLTRB(cx - w * 0.035, poleTop - 1, cx + w * 0.035, baseY),
    Radius.circular(w * 0.03),
  );
  canvas.drawRRect(
    pole,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(pole.left, 0),
        Offset(pole.right, 0),
        [const Color(0xFFB9C0C9), const Color(0xFF7C8591)],
      ),
  );
  // Levha gölgesi + gövde.
  final panelR = RRect.fromRectAndRadius(panel, Radius.circular(panelSize * 0.16));
  canvas.drawRRect(
    panelR.shift(Offset(0, h * 0.02)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.30)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.045),
  );
  canvas.drawRRect(panelR.inflate(w * 0.03), _fill(Colors.white));
  canvas.drawRRect(
    panelR,
    Paint()
      ..shader = ui.Gradient.linear(
        panel.topLeft,
        panel.bottomRight,
        [mapLighten(panelBlue, 0.08), panelDark],
      ),
  );
  // Levha üstünde yumuşak parlama.
  canvas.save();
  canvas.clipRRect(panelR);
  canvas.drawRect(
    Rect.fromLTWH(panel.left, panel.top, panel.width, panel.height * 0.42),
    _fill(Colors.white.withValues(alpha: 0.10)),
  );
  canvas.restore();
  _busGlyph(
    canvas,
    Rect.fromCenter(center: panel.center, width: panelSize * 0.78, height: panelSize * 0.78),
    Colors.white,
    panelBlue,
  );

  // Hat renk plakası (gerçek duraklardaki hat numarası tabelası gibi).
  if (hasChips) {
    final plateR = RRect.fromRectAndRadius(plate, Radius.circular(plateH * 0.45));
    canvas.drawRRect(plateR.inflate(0.6), _fill(Colors.black.withValues(alpha: 0.18)));
    canvas.drawRRect(plateR, _fill(Colors.white));
    final shown = lineColors.take(3).toList();
    final slot = plate.width / shown.length;
    for (var i = 0; i < shown.length; i++) {
      canvas.drawCircle(
        Offset(plate.left + slot * (i + 0.5), plate.center.dy),
        plateH * 0.30,
        _fill(_bodyColor(shown[i])),
      );
    }
  }

  // Başlangıç / bitiş rozeti.
  if (isStart || isEnd) {
    final badge = Offset(panel.right - panelSize * 0.02, panel.top + panelSize * 0.02);
    canvas.drawCircle(badge, w * 0.115, _fill(Colors.white));
    canvas.drawCircle(badge, w * 0.085, _fill(isStart ? kStopStart : kStopEnd));
  }
}

void _paintStopPin(
  Canvas canvas,
  Size s,
  Color accent,
  MapStopState state,
  List<Color> lineColors, {
  required bool isStart,
  required bool isEnd,
}) {
  final w = s.width, h = s.height;
  final cx = w / 2;
  final r = w * 0.40;
  final cy = r + 2;
  final tip = Offset(cx, h - 2.5);

  final path = Path()
    ..moveTo(tip.dx, tip.dy)
    ..cubicTo(cx - r * 0.35, cy + r * 1.2, cx - r, cy + r * 0.55, cx - r, cy)
    ..arcToPoint(Offset(cx + r, cy), radius: Radius.circular(r), clockwise: true)
    ..cubicTo(cx + r, cy + r * 0.55, cx + r * 0.35, cy + r * 1.2, tip.dx, tip.dy)
    ..close();

  canvas.drawPath(
    path.shift(Offset(w * 0.04, h * 0.02)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.30)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.06),
  );
  canvas.drawPath(path, _fill(Colors.white));
  final inner = Path()..addPath(path, Offset.zero);
  canvas.save();
  canvas.translate(cx, cy);
  canvas.scale(0.9);
  canvas.translate(-cx, -cy);
  canvas.drawPath(
    inner,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(cx - r, cy - r),
        Offset(cx + r, cy + r * 1.4),
        [mapLighten(accent, 0.10), mapDarken(accent, 0.12)],
      ),
  );
  canvas.restore();
  canvas.drawCircle(Offset(cx, cy), r * 0.66, _fill(Colors.white));
  _busGlyph(
    canvas,
    Rect.fromCenter(center: Offset(cx, cy), width: r * 1.05, height: r * 1.05),
    accent,
    Colors.white,
  );
  if (isStart || isEnd) {
    final b = Offset(cx + r * 0.78, cy - r * 0.78);
    canvas.drawCircle(b, w * 0.10, _fill(Colors.white));
    canvas.drawCircle(b, w * 0.075, _fill(isStart ? kStopStart : kStopEnd));
  }
}

// ─────────────────────────────────────────────
// Diğer harita simgeleri
// ─────────────────────────────────────────────

/// Kullanıcının konumu: yumuşak hale + beyaz halkalı mavi nokta.
void paintUserLocation(Canvas canvas, Size s) {
  final c = s.center(Offset.zero);
  final r = s.shortestSide / 2;
  canvas.drawCircle(c, r * 0.98, _fill(const Color(0xFF2F80FF).withValues(alpha: 0.16)));
  canvas.drawCircle(c, r * 0.62, _fill(const Color(0xFF2F80FF).withValues(alpha: 0.22)));
  canvas.drawCircle(
    c.translate(0, r * 0.05),
    r * 0.36,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.08),
  );
  canvas.drawCircle(c, r * 0.36, _fill(Colors.white));
  canvas.drawCircle(c, r * 0.26, _fill(const Color(0xFF1A73E8)));
}

/// Rota üzerindeki yön oku (burnu yukarı).
void paintRouteArrow(Canvas canvas, Size s, Color color) {
  final w = s.width, h = s.height;
  final path = Path()
    ..moveTo(w * 0.5, h * 0.06)
    ..lineTo(w * 0.92, h * 0.86)
    ..lineTo(w * 0.5, h * 0.64)
    ..lineTo(w * 0.08, h * 0.86)
    ..close();
  canvas.drawPath(path, _fill(Colors.white.withValues(alpha: 0.95)));
  canvas.save();
  canvas.translate(w * 0.5, h * 0.55);
  canvas.scale(0.66);
  canvas.translate(-w * 0.5, -h * 0.55);
  canvas.drawPath(path, _fill(_bodyColor(color)));
  canvas.restore();
}
