import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Masanın ortasındaki AÇILAN PER BÖLMESİ — koyu, içe çökmüş bir yüzey.
///
/// ## Neden içe çökmüş (inset) bir yüzey
///
/// Referans masada perlerin serildiği alan zeminin ÜSTÜNDE duran bir kart
/// değil, zeminin İÇİNE oyulmuş bir tabladır: üst kenarı koyu (ışık oraya
/// girmez), alt kenarı açık (taban ışığı yakalar). Bu ters ışık, aynı
/// yüzeyi "kabartma" değil "oyuk" olarak okutan tek şeydir — taşlar da o
/// oyuğun içine yatar.
///
/// ## Bölme çizgisi KALDIRILDI (kullanıcı isteği, 2026-09-06)
///
/// Tabla eskiden ince dikey çizgilerle iki eşit bölmeye ayrılıyordu; gerekçe
/// "göz perleri gruplar" idi. İki şey o gerekçeyi çürüttü:
///
///  1. Perler artık sol üstten AŞAĞI doğru sütun sütun diziliyor
///     (bkz. OkeyBoardLayout). Dikey bir çizgi bu akışı bölüyor, perler
///     çizginin üstünden geçiyordu.
///  2. Filigran bölme BAŞINA çiziliyordu: iki bölme = ekranda İKİ KEZ
///     "CizreApp 101 OKEY". Marka baskısı tekrar edince dekor olmaktan çıkıp
///     desen hâline geliyordu.
///
/// Artık tek bir tabla ve ORTADA tek bir filigran var.
class OkeyMeldBay extends StatelessWidget {
  /// Tablanın içine serilen içerik (perler ya da boş ipucu).
  final Widget child;

  /// Ortadaki "CizreApp 101 OKEY" filigranı çizilsin mi.
  final bool watermark;

  /// İçeriğin tabla kenarından uzaklığı.
  final EdgeInsets padding;

  /// Tablanın üst kenarına yazılan küçük başlık (ör. "ÇİFTLER").
  ///
  /// Dar bölme boşken hiçbir şey söylemiyordu: oyuncu orayı bir dekor sanıp
  /// çiftlerin nereye gittiğini arıyordu. Başlık, bölme boşken bile ne işe
  /// yaradığını anlatır.
  final String? title;

  const OkeyMeldBay({
    super.key,
    required this.child,
    this.watermark = true,
    this.padding = const EdgeInsets.all(6),
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xD105202C), Color(0xC4093344)],
        ),
        border: Border.all(color: const Color(0x14FFFFFF)),
        boxShadow: const [
          // Tablanın DIŞ kenarındaki ince ışık: oyuğun ağzı.
          BoxShadow(color: Color(0x1FFFFFFF), offset: Offset(0, 1)),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(painter: _BayPainter(watermark: watermark)),
              ),
            ),
          ),
          if (title != null)
            Positioned(
              top: 3,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: MediaQuery.withNoTextScaling(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      title!,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 8,
                        height: 1.0,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                        color: Color(0x59FFFFFF),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: Padding(
              padding: title == null
                  ? padding
                  : padding.add(const EdgeInsets.only(top: 9)),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _BayPainter extends CustomPainter {
  final bool watermark;

  const _BayPainter({required this.watermark});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(12),
    );

    canvas.save();
    canvas.clipRRect(rrect);

    // 1) OYUK IŞIĞI — üstte koyu, altta açık. Kabartmanın TERSİ.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.22),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x59000000), Color(0x00000000)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.22)),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.86, size.width, size.height * 0.14),
      Paint()
        ..shader =
            const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00FFFFFF), Color(0x0FFFFFFF)],
            ).createShader(
              Rect.fromLTWH(
                0,
                size.height * 0.86,
                size.width,
                size.height * 0.14,
              ),
            ),
    );

    // 2) FİLİGRAN — TABLANIN ORTASINDA, TEK.
    //
    // Bölme çizgileri ve bölme başına tekrarlanan filigran kaldırıldı
    // (bkz. sınıf yorumu): iki kez yazılan marka, dekor olmaktan çıkıp
    // desen hâline geliyordu.
    //
    // Ölçü tablanın DAR kenarına bağlı: yalnız genişliğe bağlansaydı, geniş
    // ama basık bir tablada filigran üstten ve alttan taşardı.
    if (watermark && size.width > 90 && size.height > 60) {
      _drawWatermark(
        canvas,
        size.center(Offset.zero),
        math.min(size.width, size.height * 1.9),
      );
    }

    canvas.restore();
  }

  /// Soluk, kazınmış marka baskısı: "CizreApp" + "101" + "OKEY" kurdelesi.
  ///
  /// Kurdelede tek başına "OKEY" yazıyordu; masaya bakan oyuncu hangi
  /// uygulamada oynadığını görmüyordu. Filigran artık markanın tamamını
  /// söyler ama YİNE dekordur: kontrastı taşların altında kalacak kadar
  /// düşük tutulur, okunmaya değil "keçeye basılmış" görünmeye çalışır.
  void _drawWatermark(Canvas canvas, Offset center, double bayWidth) {
    final fontSize = (bayWidth * 0.30).clamp(16.0, 70.0);

    void text(String value, double size, Offset at, Color color, double sp) {
      final tp = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w900,
            letterSpacing: sp,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }

    // ÜST SATIR — "CizreApp".
    //
    // BELİRGİNLİK ARTIRILDI (kullanıcı isteği, 2026-09-06: "CizreApp yazısını
    // biraz daha belirgin et"). Marka önce yalnızca koyu bir gölgeyle
    // yazılıyordu; koyu mavi keçenin üstünde koyu bir yazı neredeyse
    // görünmüyordu. Artık ASIL yazı AÇIK renkte, gölgesi koyu — yani zeminle
    // arasında gerçek bir kontrast var.
    //
    // Yine de bir FİLİGRAN: taşların altında kalacak kadar saydam. Amaç
    // okunmak değil, "keçeye basılmış" görünmek.
    final brandSize = fontSize * 0.36;
    text(
      'CizreApp',
      brandSize,
      center.translate(0, -fontSize * 0.82 + 1.2),
      const Color(0x40000000),
      brandSize * 0.16,
    );
    text(
      'CizreApp',
      brandSize,
      center.translate(0, -fontSize * 0.82),
      const Color(0x73FFFFFF),
      brandSize * 0.16,
    );

    // Kazınmış etki: bir piksel aşağıda koyu gölge, tam yerinde açık asıl.
    text(
      '101',
      fontSize,
      center.translate(0, -fontSize * 0.22 + 1.6),
      const Color(0x4D000000),
      1,
    );
    text(
      '101',
      fontSize,
      center.translate(0, -fontSize * 0.22),
      const Color(0x59FFFFFF),
      1,
    );

    // Kurdele.
    final ribbonW = fontSize * 2.5;
    final ribbonH = fontSize * 0.46;
    final ribbon = Rect.fromCenter(
      center: center.translate(0, fontSize * 0.42),
      width: ribbonW,
      height: ribbonH,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(ribbon, Radius.circular(ribbonH * 0.22)),
      Paint()..color = const Color(0x40000000),
    );
    text(
      'OKEY',
      ribbonH * 0.62,
      ribbon.center,
      const Color(0x8AFFFFFF),
      ribbonH * 0.14,
    );
  }

  @override
  bool shouldRepaint(_BayPainter oldDelegate) =>
      oldDelegate.watermark != watermark;
}
