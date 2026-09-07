import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/okey_theme.dart';

/// KAMERANIN masaya bakış açısı (derece).
///
/// ## Bu, ıstakanın KENDİ eğimi DEĞİLDİR
///
/// Kullanıcının sahne haritasında iki ayrı açı var ve ilk denememde bunları
/// karıştırdım:
///   * `Pitch Angle (phi): 18 deg` → ISTAKANIN KENDİ eğimi (arka panonun
///     geriye yatması). Nesneye ait, küçük bir açı.
///   * Kameranın masaya bakış açısı → sahnenin TAMAMINI etkiler. Haritada
///     çizilen eksenler (X/Y/Z) bu açıyla eğik.
///
/// 18°'yi KAMERA açısı sanıp projeksiyona verince, derinlik ekseni
/// `sin(18°) = 0.31` ile eziliyordu: yaw ±68° ile duran yan ıstakalar
/// ekranda 210px yerine ~78px'e düşüp küçük ahşap kamalara dönüştü.
/// Gerçek değer ~58°: masaya yukarıdan ama eğik bakan bir kamera. Yan
/// ıstakalar böylece referanstaki gibi UZUN ÇAPRAZ kutular olur.
const double kOkeyCameraPitchDeg = 58;

/// Masanın ahşap RAYI, KEÇESİ ve rakiplerin ISTAKALARI — saf dekoratif zemin.
///
/// Masa alanının tamamını kaplar ve üzerindeki gerçek etkileşimli katmanın
/// (oyuncu kartları, perler, aksiyonlar) ARKASINA biner; çağıran taraf
/// [IgnorePointer] ile sarar, bu yüzden hiçbir dokunma/sürükleme olayını
/// etkilemez.
///
/// ## Neden trapez değil
///
/// Önceki sürüm perspektif hissi için üstte daralan bir trapez çiziyordu.
/// Merkezi düzende dört oyuncu masanın dört KENARINDA oturuyor: daralan bir
/// üst kenar, karşıdaki oyuncunun kartını rayın dışında bırakıyor ve sol/sağ
/// oyuncuların ıskarta kutularını keçe yerine ahşabın üstüne düşürüyordu.
/// Gerçek 101 Okey masaları da yuvarlatılmış dikdörtgendir; perspektif
/// GEOMETRİDEN değil IŞIKTAN gelir.
///
/// ## 3D nereden geliyor (2026-09, kullanıcının referans görseli)
///
/// Referansta masa bir fotoğraf gibi duruyor. Onu tek bir düz gradyan
/// vermiyor; üst üste binen ŞU KATMANLAR veriyor:
///
///   1. **Dış gölge** — masa odanın zeminine oturur, altında yumuşak bir
///      gölge bırakır. Bu olmadan masa "yapıştırılmış" görünür.
///   2. **Ahşap ray + damar** — dikey gradyan tek başına plastik durur;
///      rayın uzunluğunca akan ince, düzensiz damar çizgileri ahşabı
///      ahşap yapar.
///   3. **Ray beveli** — üst kenarda açık bir cila çizgisi, iç kenarda koyu
///      bir düşüş. Işığın YUKARIDAN geldiği tek bir yön varsayımı, tüm
///      katmanlarda tutarlı uygulanır.
///   4. **Keçe vinyeti** — merkezde açık, kenarlarda koyu. Masanın üstüne
///      düşen lambanın ta kendisi.
///   5. **Keçe dokusu** — çapraz ince tarama; kumaşın örgüsünü taklit eder,
///      düz rengi "boya" olmaktan çıkarır.
///   6. **İç gölge** — rayın keçeye düşürdüğü gölge; keçenin rayın ALTINDA
///      kaldığını, aynı düzlemde olmadığını söyler.
///   7. **Rakip ıstakaları** — referanstaki gibi üç kenarda ahşap çıtalar.
///      Masanın "dört kişilik" olduğunu geometriyle anlatır.
///
/// Hepsi TEK paint çağrısında, RepaintBoundary içinde çizilir; [shouldRepaint]
/// yalnızca ölçüler değiştiğinde true döner.
class OkeyTableFeltPainter extends CustomPainter {
  /// Sol/sağ rakip ıstakalarının merkezleneceği şerit genişliği.
  final double sidePodWidth;

  /// Üstteki rakip ıstakasının hizalanacağı bandın yüksekliği.
  final double topBandHeight;

  /// Rakip ıstakaları çizilsin mi? (test/önizleme için kapatılabilir)
  final bool showOpponentRacks;

  const OkeyTableFeltPainter({
    this.sidePodWidth = 0,
    this.topBandHeight = 0,
    this.showOpponentRacks = true,
  });

  /// Ahşap rayın kalınlığı.
  ///
  /// TEK KAYNAK: hem burası hem de [OkeyTableScaffold] bunu kullanır —
  /// scaffold, oyuncu kartlarını ve perleri rayın İÇİNE (keçeye) yerleştirmek
  /// için aynı payı bırakmak zorundadır. İki yerde ayrı yazılsaydı, biri
  /// değişince kartlar sessizce ahşabın üstüne taşardı.
  static double railThicknessFor(Size size) =>
      (size.shortestSide * 0.05).clamp(7.0, 18.0);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final rail = railThicknessFor(size);
    final outerRadius = Radius.circular(
      (size.shortestSide * 0.10).clamp(16.0, 34.0),
    );
    final innerRadius = Radius.circular(
      ((size.shortestSide * 0.10).clamp(16.0, 34.0) - rail * 0.6).clamp(
        6.0,
        26.0,
      ),
    );

    final outerRect = Offset.zero & size;
    final outer = RRect.fromRectAndRadius(outerRect, outerRadius);

    // ---- 1) DIŞ GÖLGE -----------------------------------------------------
    // Masa odanın içinde bir CİSİM; altında gölgesi olmalı. Gölge aşağı
    // kaydırılır çünkü ışık yukarıdan gelir (tüm katmanlarda aynı varsayım).
    canvas.drawRRect(
      outer.shift(const Offset(0, 6)),
      Paint()
        ..color = const Color(0x8C000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );

    // ---- 2) AHŞAP RAY -----------------------------------------------------
    canvas.drawRRect(
      outer,
      Paint()..shader = OkeyColors.railGradient.createShader(outerRect),
    );

    // Ahşap damarı — rayın çevresinde akan ince, düzensiz çizgiler.
    _paintWoodGrain(canvas, outer, rail);

    // ---- 3) RAY BEVELİ ----------------------------------------------------
    // Üst kenardaki cila parlaklığı: ahşabın ışığı yakaladığı yer.
    canvas.save();
    canvas.clipRRect(outer);
    canvas.drawRRect(
      outer.deflate(0.9),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xC7FFEBC6), Color(0x1AFFEBC6), Color(0x00FFEBC6)],
          stops: [0.0, 0.35, 1.0],
        ).createShader(outerRect),
    );
    canvas.restore();

    // ---- KEÇE -------------------------------------------------------------
    final innerRect = outerRect.deflate(rail);
    if (innerRect.width <= 0 || innerRect.height <= 0) return;
    final inner = RRect.fromRectAndRadius(innerRect, innerRadius);

    // 4) Vinyet: masanın üst-ortasına düşen lamba.
    canvas.drawRRect(
      inner,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.45),
          radius: 1.05,
          colors: [
            OkeyColors.feltHighlight,
            OkeyColors.feltCenter,
            OkeyColors.feltMid,
            OkeyColors.tableFeltDeep,
            OkeyColors.feltRim,
          ],
          stops: [0.0, 0.2, 0.45, 0.78, 1.0],
        ).createShader(innerRect),
    );

    canvas.save();
    canvas.clipRRect(inner);

    // 5) Kumaş dokusu — çapraz ince tarama. Düz rengi "boya" olmaktan
    //    çıkarıp örgülü bir yüzeye çevirir.
    _paintFeltWeave(canvas, innerRect);

    // 5b) KEÇE FİLİGRANI — masanın ortasına basılmış soluk marka izi.
    //     Gerçek okey masalarında (ve referans görselde) keçenin ortasında
    //     böyle bir baskı vardır; keçeyi "boş yeşil alan" olmaktan çıkarır.
    _paintWatermark(canvas, innerRect);

    // 7) Rakip ıstakaları — keçenin İÇİNE, kırpma altında çizilir ki
    //    yuvarlatılmış köşelerden asla taşmasınlar.
    if (showOpponentRacks) {
      _paintOpponentRacks(canvas, innerRect);
    }

    // 6) İç gölge: rayın keçeye düşürdüğü gölge.
    canvas.drawRRect(
      inner.deflate(-3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..color = const Color(0x99000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.restore();

    // Keçe ile rayın birleştiği ince koyu ayrım çizgisi.
    canvas.drawRRect(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x8A000000),
    );
  }

  /// Ahşap damarı: rayın dört kenarında, kenara PARALEL akan ince çizgiler.
  ///
  /// Rastgelelik SABİT tohumludur — her karede farklı bir desen çizilseydi
  /// (ekran boyutu değişiminde) ahşap "titrerdi".
  void _paintWoodGrain(Canvas canvas, RRect outer, double rail) {
    final rnd = math.Random(7);
    final rect = outer.outerRect;
    canvas.save();
    canvas.clipRRect(outer);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Kenar başına 3 damar; her biri rayın kalınlığı içinde rastgele bir
    // derinlikte akar ve hafifçe dalgalanır.
    for (var edge = 0; edge < 4; edge++) {
      for (var i = 0; i < 3; i++) {
        final depth = rail * (0.2 + rnd.nextDouble() * 0.6);
        paint
          ..strokeWidth = 0.6 + rnd.nextDouble() * 0.9
          ..color = (rnd.nextBool()
              ? const Color(0x33FFD9A0)
              : const Color(0x40402008));

        final path = Path();
        final wobble = 0.8 + rnd.nextDouble() * 1.6;
        switch (edge) {
          case 0: // üst
            path.moveTo(rect.left, rect.top + depth);
            for (var x = rect.left; x <= rect.right; x += 18) {
              path.lineTo(x, rect.top + depth + math.sin(x / 42 + i) * wobble);
            }
            break;
          case 1: // alt
            path.moveTo(rect.left, rect.bottom - depth);
            for (var x = rect.left; x <= rect.right; x += 18) {
              path.lineTo(
                x,
                rect.bottom - depth + math.sin(x / 38 + i) * wobble,
              );
            }
            break;
          case 2: // sol
            path.moveTo(rect.left + depth, rect.top);
            for (var y = rect.top; y <= rect.bottom; y += 18) {
              path.lineTo(rect.left + depth + math.sin(y / 40 + i) * wobble, y);
            }
            break;
          default: // sağ
            path.moveTo(rect.right - depth, rect.top);
            for (var y = rect.top; y <= rect.bottom; y += 18) {
              path.lineTo(
                rect.right - depth + math.sin(y / 44 + i) * wobble,
                y,
              );
            }
        }
        canvas.drawPath(path, paint);
      }
    }
    canvas.restore();
  }

  /// Keçe dokusu — 45° çapraz iki yönlü ince tarama.
  ///
  /// Alfa BİLEREK çok düşük (~%2): amaç deseni GÖRMEK değil, düz yüzeyin
  /// "dijital" hissini kırmak. Yüksek alfada masa çizgili bir örtüye döner.
  void _paintFeltWeave(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..strokeWidth = 1
      ..color = const Color(0x08FFFFFF);
    const step = 7.0;
    for (var x = rect.left - rect.height; x < rect.right; x += step) {
      canvas.drawLine(
        Offset(x, rect.top),
        Offset(x + rect.height, rect.bottom),
        paint,
      );
    }
    final paint2 = Paint()
      ..strokeWidth = 1
      ..color = const Color(0x06000000);
    for (var x = rect.left; x < rect.right + rect.height; x += step) {
      canvas.drawLine(
        Offset(x, rect.top),
        Offset(x - rect.height, rect.bottom),
        paint2,
      );
    }
  }

  /// Keçenin ortasındaki soluk "101 OKEY" baskısı.
  ///
  /// TextPainter kullanılmaz: bu katman her yeniden çizimde metin
  /// biçimlendirmesi yapmamalı ve sistem yazı tipine bağımlı olmamalı
  /// (yazı tipi ölçüsü değişince filigran ortadan kayardı). Bunun yerine
  /// basit geometri: iç içe iki halka + ortada bir elmas. Marka değil,
  /// keçeye basılmış bir DESEN.
  void _paintWatermark(Canvas canvas, Rect felt) {
    final c = felt.center;
    final r = felt.shortestSide * 0.26;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0x0DFFFFFF);

    canvas.drawCircle(c, r, paint..strokeWidth = 2.5);
    canvas.drawCircle(c, r * 0.74, paint..strokeWidth = 1.2);

    final d = r * 0.34;
    final diamond = Path()
      ..moveTo(c.dx, c.dy - d)
      ..lineTo(c.dx + d, c.dy)
      ..lineTo(c.dx, c.dy + d)
      ..lineTo(c.dx - d, c.dy)
      ..close();
    canvas.drawPath(diamond, paint..strokeWidth = 2);
    canvas.drawPath(diamond, Paint()..color = const Color(0x08FFFFFF));
  }

  /// Üç rakibin ISTAKASI — referanstaki gibi masayı çerçeveleyen ahşap
  /// tahtalar.
  ///
  /// Bunlar dekordur (rakiplerin taşları zaten gizlidir) ama masayı "dört
  /// kişilik bir okey masası" yapan şey tam olarak budur: avatarlar tek
  /// başına havada duruyormuş gibiydi. Referansta ıstakalar masanın en
  /// belirgin öğelerinden biri — bu yüzden İNCE ÇUBUK değil, KALIN TAHTA
  /// olarak çizilirler.
  void _paintOpponentRacks(Canvas canvas, Rect felt) {
    // Ölçüler masanın kısa kenarından türetilir.
    final unit = felt.shortestSide;
    final depth = (unit * 0.075).clamp(12.0, 30.0); // ıstakanın derinliği
    final height = (unit * 0.085).clamp(13.0, 34.0); // arka panonun yüksekliği

    // ÜST — karşıdaki oyuncu. Yaw 0: tam karşıdan görünür.
    paintOkeyRackBox(
      canvas,
      center: Offset(
        felt.center.dx,
        felt.top + math.max(topBandHeight * 0.5, height * 1.4),
      ),
      length: felt.width * 0.42,
      depth: depth,
      height: height,
      yawDeg: 0,
    );

    // SOL / SAĞ — yaw ±58°: sahne haritasındaki gibi bu iki ıstaka masaya
    // AÇIYLA oturur, ekran eksenine paralel DEĞİLDİR. Kamera açısıyla
    // (kOkeyCameraPitchDeg) birlikte ekranda uzun ÇAPRAZ kutular verir.
    final sideX = math.max(sidePodWidth, depth * 2.4) * 0.52;
    final sideLen = felt.height * 0.66;
    paintOkeyRackBox(
      canvas,
      center: Offset(felt.left + sideX, felt.center.dy),
      length: sideLen,
      depth: depth,
      height: height,
      yawDeg: -58,
    );
    paintOkeyRackBox(
      canvas,
      center: Offset(felt.right - sideX, felt.center.dy),
      length: sideLen,
      depth: depth,
      height: height,
      yawDeg: 58,
    );
  }

  @override
  bool shouldRepaint(OkeyTableFeltPainter old) =>
      old.sidePodWidth != sidePodWidth ||
      old.topBandHeight != topBandHeight ||
      old.showOpponentRacks != showOpponentRacks;
}

/// Bir ISTAKAYI GERÇEK BİR 3B KUTU olarak çizer.
///
/// ## Neden projeksiyon, neden düz dikdörtgen değil
///
/// Önceki sürüm ıstakayı ekran eksenine paralel bir dikdörtgen + gradyanla
/// "3B gibi" göstermeye çalışıyordu. Kullanıcının sahne haritası bunun
/// yetmediğini net biçimde söylüyor: her ıstakanın bir POZİSYONU, bir
/// PITCH açısı (φ ≈ 18°) ve bir YAW açısı (θ ≈ ±45°) var — yani nesne
/// masada AÇIYLA duruyor ve üst/ön/yan yüzeyleri AYRI AYRI görünüyor.
/// Gradyan bunu veremez; yüzeylerin gerçekten ayrı çizilmesi gerekir.
///
/// ## Projeksiyon
///
/// Klasik aksonometrik izdüşüm — perspektif bölmesi YOK (masa öğeleri
/// birbirine yakın derinlikte; bölme yapmak kenarları eğriltir, kazancı
/// olmaz):
///
///   1. Nokta önce Z ekseni etrafında `yaw` kadar döndürülür
///   2. Derinlik ekseni (y) `sin(pitch)` ile ezilir → masaya yatma
///   3. Yükseklik (z) `cos(pitch)` ile yukarı taşınır
///
/// ## Boyama sırası
///
/// Arka pano → uç kapaklar → üst yüzey → ön yüzey. Ressam algoritması:
/// uzaktakiler önce. Sıra bozulursa ön yüzey arkada kalır ve kutu içi
/// dışına dönmüş görünür.
void paintOkeyRackBox(
  Canvas canvas, {
  required Offset center,
  required double length,
  required double depth,
  required double height,
  required double yawDeg,
  double pitchDeg = kOkeyCameraPitchDeg,
}) {
  if (length <= 0 || depth <= 0 || height <= 0) return;

  final yaw = yawDeg * math.pi / 180;
  final pitch = pitchDeg * math.pi / 180;
  final cy = math.cos(yaw);
  final sy = math.sin(yaw);
  final sp = math.sin(pitch);
  final cp = math.cos(pitch);

  Offset p(double x, double y, double z) {
    final rx = x * cy - y * sy;
    final ry = x * sy + y * cy;
    return Offset(center.dx + rx, center.dy + ry * sp - z * cp);
  }

  final hl = length / 2;
  final hd = depth / 2;

  Path quad(Offset a, Offset b, Offset c, Offset d) => Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy)
    ..lineTo(c.dx, c.dy)
    ..lineTo(d.dx, d.dy)
    ..close();

  // ---- Kutunun köşeleri --------------------------------------------------
  // y = -hd  ARKA (uzak),  y = +hd  ÖN (yakın)
  final backTopL = p(-hl, -hd, height);
  final backTopR = p(hl, -hd, height);
  final backBotL = p(-hl, -hd, 0);
  final backBotR = p(hl, -hd, 0);
  final frontTopL = p(-hl, hd, height * 0.42);
  final frontTopR = p(hl, hd, height * 0.42);
  final frontBotL = p(-hl, hd, 0);
  final frontBotR = p(hl, hd, 0);

  // ---- Masaya düşen gölge ------------------------------------------------
  canvas.drawPath(
    quad(backBotL, backBotR, frontBotR, frontBotL).shift(const Offset(2, 5)),
    Paint()
      ..color = const Color(0x8A000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
  );

  // ---- 1) ARKA PANONUN DIŞ YÜZÜ (en uzak) --------------------------------
  canvas.drawPath(
    quad(backTopL, backTopR, backBotR, backBotL),
    Paint()..color = const Color(0xFF6B4113),
  );

  // ---- 2) UÇ KAPAKLAR (yan yüzeyler) -------------------------------------
  final capPaint = Paint()..color = const Color(0xFF8A5A20);
  canvas.drawPath(quad(backTopL, frontTopL, frontBotL, backBotL), capPaint);
  canvas.drawPath(quad(backTopR, frontTopR, frontBotR, backBotR), capPaint);

  // ---- 3) ÜST YÜZEY (ışığı en çok alan) ----------------------------------
  // Arka panonun üstünden ön dudağa inen eğik yüzey: taşlar buraya dayanır.
  final topRect = Rect.fromPoints(backTopL, frontTopR);
  canvas.drawPath(
    quad(backTopL, backTopR, frontTopR, frontTopL),
    Paint()
      ..shader =
          const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF2CB84), Color(0xFFCE9748)],
          ).createShader(
            topRect.isEmpty ? const Rect.fromLTWH(0, 0, 1, 1) : topRect,
          ),
  );

  // ---- 4) OLUK — taşların dibinin oturduğu kanal --------------------------
  final grooveBackL = p(-hl + depth * 0.25, -hd * 0.15, height * 0.46);
  final grooveBackR = p(hl - depth * 0.25, -hd * 0.15, height * 0.46);
  final grooveFrontR = p(hl - depth * 0.25, hd * 0.35, height * 0.44);
  final grooveFrontL = p(-hl + depth * 0.25, hd * 0.35, height * 0.44);
  canvas.drawPath(
    quad(grooveBackL, grooveBackR, grooveFrontR, grooveFrontL),
    Paint()..color = const Color(0x8A2E1808),
  );

  // ---- 5) ÖN YÜZEY (en yakın, dudak) -------------------------------------
  final frontRect = Rect.fromPoints(frontTopL, frontBotR);
  canvas.drawPath(
    quad(frontTopL, frontTopR, frontBotR, frontBotL),
    Paint()
      ..shader =
          const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE6B871), Color(0xFF9A6526)],
          ).createShader(
            frontRect.isEmpty ? const Rect.fromLTWH(0, 0, 1, 1) : frontRect,
          ),
  );

  // ---- 6) KENAR ÇİZGİLERİ — kutunun formunu keskinleştirir ---------------
  final edge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = const Color(0x8AFFE6BE);
  canvas.drawPath(quad(backTopL, backTopR, frontTopR, frontTopL), edge);
  canvas.drawPath(
    quad(frontTopL, frontTopR, frontBotR, frontBotL),
    edge..color = const Color(0x4DFFE6BE),
  );
}
