import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/okey_theme.dart';

/// Sıradaki oyuncunun AVATARININ ETRAFINDAKİ süre halkası.
///
/// ## Neden ekranın altındaki süre çubuğunun yerine
///
/// v4'te süre, ıstakanın hemen üstünde 4 piksellik bir çizgiydi
/// (`OkeyTurnTimerBar`, artık silindi). İki sorunu vardı:
///
///  1. **Yanlış yerdeydi.** Çubuk her zaman ekranın altındaydı; oysa süre
///     SIRASI GELEN OYUNCUNUN süresidir. Karşıdaki oyuncu düşünürken
///     oyuncunun gözü masanın üstünde, sayaç ise ekranın dibindeydi —
///     "kimin süresi bu" sorusu her seferinde yeniden soruluyordu.
///  2. **Yer yiyordu.** 4 piksel az gibi görünür ama ıstaka satırı ekran
///     yüksekliğinin %34'ünden türer; o 4 piksel doğrudan TAŞ BOYUNDAN
///     kısılıyordu.
///
/// Artık süre, sırası gelen oyuncunun avatarının etrafında bir yay olarak
/// döner: bilgi, ait olduğu nesnenin üstünde durur. Kazanılan dikey bütçe
/// ıstakaya gider.
///
/// ## Yay nasıl okunur
///
/// Yay, avatarın ZATEN VAR OLAN halkasının tam üstüne çizilir — kutuyu
/// büyütmez. Büyütseydi sıra dolaştıkça dört avatar sırayla şişip inecek,
/// masa nefes alıyormuş gibi titreyecekti.
///
/// Tam halka = sürenin tamamı. Yay saat yönünde KISALARAK tükenir; son
/// [urgentSeconds] saniyede pirinçten kızıla döner ve halkanın etrafında
/// bir parıltı belirir. Renk değişimi yalnızca süslemek için değil: oyuncu
/// masaya bakarken yayın uzunluğunu ölçmez, RENGİNİ fark eder.
class OkeyTurnRing extends StatelessWidget {
  /// Kalan saniye.
  final ValueListenable<int> secondsLeft;

  /// Turun toplam süresi — odadan gelir, admin panelinden ayarlanabilir.
  final int totalSeconds;

  /// Yayın kalınlığı. Avatarın KENDİ halka kalınlığıyla aynı verilir ki yay
  /// halkanın üstüne birebir otursun.
  final double stroke;

  /// Köşe yarıçapı. 0 = DAİRE (yatay plakaların yuvarlak avatarı), pozitif
  /// değer = yuvarlatılmış KARE (dikey levhaların kare avatarı).
  ///
  /// İki biçim de aynı yolu (path) izler ve yay her ikisinde de saat
  /// 12'den başlayıp saat yönünde tükenir: oyuncu masanın dört kenarında
  /// aynı hareketi görür.
  final double cornerRadius;

  /// Kalan süre bunun altına düşünce halka kızıla döner.
  static const int urgentSeconds = 5;

  /// Yayın TAM DAİREYE oranı.
  ///
  /// Ayrı bir fonksiyon çünkü yay bir [CustomPainter] içinde çiziliyor:
  /// widget ağacında ölçülebilir bir kutu yok, yani testin "süre azalınca
  /// yay kısalıyor mu" sorusunu sorabileceği başka bir yer de yok.
  @visibleForTesting
  static double fractionFor(int secondsLeft, int totalSeconds) {
    final total = totalSeconds <= 0 ? 20 : totalSeconds;
    return secondsLeft.clamp(0, total) / total;
  }

  const OkeyTurnRing({
    super.key,
    required this.secondsLeft,
    required this.stroke,
    this.totalSeconds = 20,
    this.cornerRadius = 0,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: secondsLeft,
      builder: (context, seconds, _) {
        return CustomPaint(
          painter: _TurnRingPainter(
            fraction: fractionFor(seconds, totalSeconds),
            stroke: stroke,
            urgent: seconds <= urgentSeconds,
            cornerRadius: cornerRadius,
          ),
        );
      },
    );
  }
}

class _TurnRingPainter extends CustomPainter {
  final double fraction;
  final double stroke;
  final bool urgent;
  final double cornerRadius;

  const _TurnRingPainter({
    required this.fraction,
    required this.stroke,
    required this.urgent,
    required this.cornerRadius,
  });

  /// Normal akış: pirinç. Bu renk masa temasından BAĞIMSIZDIR — süre, masa
  /// hangi renk olursa olsun aynı işareti taşımalı.
  static const Color _brass = Color(0xFFE4B04C);
  static const Color _brassBright = Color(0xFFF6D48A);
  static const Color _urgent = Color(0xFFE05A4E);
  static const Color _urgentBright = Color(0xFFFF9A90);

  /// Yayın izlediği yol. Her iki biçimde de SAAT 12'den başlar ve saat
  /// yönünde ilerler.
  Path _ringPath(Rect rect) {
    if (cornerRadius <= 0) {
      return Path()..addArc(rect, -math.pi / 2, math.pi * 2);
    }
    // Köşeleri yuvarlatılmış kare, elle kurulur: `addRRect` yolun BAŞINI
    // köşeye koyar, yay o zaman saat 12'den değil sol üst köşeden tükenirdi.
    final r = math.min(cornerRadius, math.min(rect.width, rect.height) / 2);
    final cx = rect.center.dx;
    final radius = Radius.circular(r);
    return Path()
      ..moveTo(cx, rect.top)
      ..lineTo(rect.right - r, rect.top)
      ..arcToPoint(Offset(rect.right, rect.top + r), radius: radius)
      ..lineTo(rect.right, rect.bottom - r)
      ..arcToPoint(Offset(rect.right - r, rect.bottom), radius: radius)
      ..lineTo(rect.left + r, rect.bottom)
      ..arcToPoint(Offset(rect.left, rect.bottom - r), radius: radius)
      ..lineTo(rect.left, rect.top + r)
      ..arcToPoint(Offset(rect.left + r, rect.top), radius: radius)
      ..lineTo(cx, rect.top);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      0,
      0,
      size.width,
      size.height,
    ).deflate(stroke / 2);
    if (rect.width <= 0 || rect.height <= 0) return;

    final path = _ringPath(rect);

    // 1. RAY (boş kısım) — her zaman tam tur. Yalnızca dolu yay çizilseydi
    //    oyuncu "ne kadarı gitti" sorusuna referans bulamazdı.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = const Color(0x1FFFFFFF),
    );

    if (fraction <= 0) return;

    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final visible = metric.extractPath(0, metric.length * fraction);

    // 2. PARILTI — yalnızca son saniyelerde. Sürekli açık olsaydı masadaki
    //    en parlak nesne olur, taşları bastırırdı.
    if (urgent) {
      canvas.drawPath(
        visible,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 2.2
          ..strokeCap = StrokeCap.round
          ..color = _urgent.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }

    // 3. YAY — ucu açık renkte biter: hareketin YÖNÜ (nereye doğru
    //    kısaldığı) böylece tek karede okunur.
    canvas.drawPath(
      visible,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: math.pi * 1.5,
          colors: urgent
              ? const [_urgent, _urgentBright]
              : const [_brass, _brassBright],
          stops: const [0, 1],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_TurnRingPainter old) =>
      old.fraction != fraction ||
      old.urgent != urgent ||
      old.stroke != stroke ||
      old.cornerRadius != cornerRadius;
}

/// BARAJ ÖLÇERİ — 101 puana ne kadar kaldığını UZUNLUKLA anlatan çubuk.
///
/// Rozetteki "78/101" yazısı doğru ama yavaş okunur: iki sayıyı karşılaştırıp
/// oranı zihinde kurmak gerekir. Çubuk aynı bilgiyi bakışta verir; sayı
/// yalnızca doğrulama içindir.
///
/// Açıldıktan sonra ölçer DOLU kalır ve rengi değişmez — "baraj aşıldı" artık
/// sabit bir durumdur, ölçer o andan sonra bir hedef değil bir rozettir.
class OkeyBarajMeter extends StatelessWidget {
  final int points;
  final int required;
  final bool isOpen;
  final double height;

  const OkeyBarajMeter({
    super.key,
    required this.points,
    required this.required,
    required this.isOpen,
    this.height = 6,
  });

  @override
  Widget build(BuildContext context) {
    final target = required <= 0 ? 1 : required;
    final ratio = isOpen ? 1.0 : (points / target).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color(0x8C000000),
          borderRadius: BorderRadius.circular(height),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: ratio == 0 ? 0.001 : ratio,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFC48C22), Color(0xFFF6D48A)],
                ),
                borderRadius: BorderRadius.circular(height),
                boxShadow: [
                  if (ratio >= 1)
                    const BoxShadow(color: Color(0x8CE4B04C), blurRadius: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// TUR ŞERİDİ — `çek → düzenle → at`.
///
/// Yeni oyuncunun en sık sorduğu soru "şimdi ne yapmalıyım" değil, "sıra
/// hangi adımda" sorusudur: taşı çektiğini unutup tekrar çekmeye çalışır,
/// ya da atacak taşı seçmesi gerektiğini fark etmez. Şerit, turun neresinde
/// olduğunu üç noktayla söyler; aktif adım pirinç bir hapla vurgulanır.
///
/// ## Neden DÖRT değil ÜÇ adım
///
/// İlk taslakta `çek · diz · işle · at` vardı. "Diz" ve "işle" ayrı birer
/// adım GİBİ duruyordu ama oyunun durumundan TÜRETİLEMİYORDU: oyuncunun
/// ıstakasını dizip dizmediği, işleyip işlemediği sunucuda bir aşama
/// değil. O iki nokta her turda sönük kalacaktı — yani şerit, bilmediği
/// bir şeyi biliyormuş gibi yapacaktı.
///
/// Üç adımın üçü de gerçek durumdan okunur: taş çekilebiliyor mu, taş
/// çekildi ama atılacak taş seçilmedi mi, seçildi mi.
///
/// Öğretici DEĞİLDİR: hiçbir şey anlatmaz, yalnızca konumu gösterir. Bu
/// yüzden kapatılabilir bir ipucu balonu değil, masanın kalıcı bir parçası.
class OkeyPhaseRail extends StatelessWidget {
  /// 0 = çek, 1 = düzenle, 2 = at. Sıra bende değilse -1 (hiçbiri yanmaz).
  final int step;
  final double height;

  const OkeyPhaseRail({super.key, required this.step, this.height = 14});

  static const List<String> _labels = ['ÇEK', 'DÜZENLE', 'AT'];

  @override
  Widget build(BuildContext context) {
    final fs = (height * 0.55).clamp(6.5, 9.5).toDouble();

    return MediaQuery.withNoTextScaling(
      child: SizedBox(
        height: height,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < _labels.length; i++) ...[
              if (i > 0)
                Container(
                  width: (height * 0.55).clamp(6.0, 11.0),
                  height: 1,
                  color: i <= step
                      ? const Color(0x8CE4B04C)
                      : const Color(0x33F5EBD8),
                ),
              if (i == step)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: height * 0.30,
                    vertical: height * 0.10,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFF8DA8A), Color(0xFFE4B04C)],
                    ),
                    borderRadius: BorderRadius.circular(height * 0.36),
                  ),
                  child: Text(
                    _labels[i],
                    style: TextStyle(
                      fontSize: fs,
                      height: 1.0,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                      color: const Color(0xFF2A1A05),
                    ),
                  ),
                )
              else
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: height * 0.16),
                  child: Text(
                    _labels[i],
                    style: TextStyle(
                      fontSize: fs,
                      height: 1.0,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: i < step
                          ? const Color(0x99E4B04C)
                          : OkeyV3.textFaint,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
