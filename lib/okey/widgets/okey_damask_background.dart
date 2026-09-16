import 'package:flutter/material.dart';

import '../theme/okey_table_theme.dart';
import '../theme/okey_theme.dart';

/// Masanın ARKA PLANI — MASA TEMASININ zemin tonu üzerine, o temaya özgü
/// bir kabartma DESENİ (bkz. [OkeyBackdropPattern]).
///
/// ## Neden CustomPainter, neden bir görsel değil
///
/// Referans masanın zemini tek renk değil: merkezden dışa açılan bir ışık,
/// üzerine düzenli aralıklarla yerleşmiş, zeminden yalnızca birkaç ton açık
/// KABARTMA bir doku var. Bunu bir PNG ile yapmak (a) her ekran oranında
/// ya gerilir ya kırpılır, (b) uygulamanın boyutunu büyütür, (c) her tema
/// için ayrı bir dosya ister. Vektörel çizim her çözünürlükte keskin kalır
/// ve tek bir [RepaintBoundary] arkasında BİR KEZ boyanır — taşlar hareket
/// ettikçe yeniden çizilmez.
///
/// ## Neden DÖRT AYRI desen, tek bir renklendirilmiş motif değil
///
/// Önceki sürümde her tema AYNI soluk kıvrım/yaprak (scroll) motifini
/// tekrarlıyordu, yalnızca rengi değişiyordu — kullanıcı bunu ("solukları
/// kaldır") ve masaya özgü bir yüzey istediğini bildirdi (2026-09-15).
/// Artık her tema KENDİ malzemesini taklit eden bir doku taşır: Yeşil
/// Çuha'da çapraz keçe dokuması, Kırmızı Kadife'de gerçek bir kadife
/// koltuğun düğmelemesi, Gece Modu'nda modern bir nokta ızgarası;
/// Kahvehane'de ise BİLEREK hiçbir desen yok — yalnızca temiz bir ışık
/// havuzu (bkz. [_paintWeave], [_paintTufted], [_paintGrid]).
///
/// ## Desenin kabartma hissi nereden geliyor
///
/// Tek bir açık çizgi/nokta "boyanmış" görünür. Kabartma, İKİ kopyanın üst
/// üste binmesinden doğar: önce hafifçe kaydırılmış KOYU bir kopya (gölge),
/// sonra tam yerinde AÇIK olan asıl çizgi/nokta. Işık yönü masanın geri
/// kalanıyla aynı: yukarıdan-soldan.
class OkeyDamaskBackground extends StatelessWidget {
  /// Motifin zeminden ne kadar ayrıştığı (0 = düz zemin, 1 = referans).
  final double ornamentStrength;

  const OkeyDamaskBackground({super.key, this.ornamentStrength = 1.0});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _DamaskPainter(strength: ornamentStrength),
        size: Size.infinite,
      ),
    );
  }
}

class _DamaskPainter extends CustomPainter {
  final double strength;

  /// AKTİF TEMANIN anahtarı — [shouldRepaint] yalnızca [strength]'i
  /// karşılaştırsaydı, kullanıcı Ayarlar'dan tema değiştirdiğinde (strength
  /// aynı kalırken renkler değiştiğinde) zemin YENİDEN BOYANMAZDI.
  final String _themeKey = OkeyTableThemePrefs.instance.current.value.key;

  _DamaskPainter({required this.strength});

  @override
  void paint(Canvas canvas, Size size) {
    // SONSUZ/GEÇERSİZ ÖLÇÜ KORUMASI: bu widget her zaman SINIRLI bir kutu
    // içinde kullanılır (bkz. OkeyRoomBackdrop'ta Positioned.fill), ama
    // `CustomPaint(size: Size.infinite)` sınırsız kısıtlar altında (ör.
    // yanlış kurulmuş bir test ağacı) gerçekten SONSUZ bir `size` alabilir.
    // Aşağıdaki desen döngüleri `size.width`/`size.height`i üst sınır
    // olarak kullanır; sonsuz bir üst sınır SONSUZ DÖNGÜ demektir. Erken
    // çıkış bunu imkânsız kılar.
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) {
      return;
    }
    final rect = Offset.zero & size;
    final deep = OkeyColors.damaskDeep;
    final mid = OkeyColors.damaskMid;
    final light = OkeyColors.damaskLight;

    // 1) ZEMİN — merkezden dışa açılan ışık. Düz bir renk, masaya
    //    "yuvarlaklık" vermiyordu; bu üç duraklı radyal, ortadaki oyun
    //    alanını kenarlardan bir tık öne çıkarır. Üç durak da aktif MASA
    //    TEMASINDAN gelir (bkz. OkeyTableTheme.damask*).
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.05),
          radius: 0.95,
          colors: [light, mid, deep],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );

    // 2) DESEN — HANGİ desenin çizileceği aktif MASA TEMASINDAN gelir (bkz.
    //    OkeyBackdropPattern). Kahvehane'de `plain` seçilidir: desen HİÇ
    //    çizilmez, yalnızca yukarıdaki ışık havuzu kalır (kullanıcı isteği,
    //    2026-09-15: "arka plandaki solukları kaldır").
    if (strength > 0) {
      canvas.save();
      canvas.clipRect(rect);
      switch (OkeyColors.backdropPattern) {
        case OkeyBackdropPattern.plain:
          break;
        case OkeyBackdropPattern.weave:
          _paintWeave(canvas, size, strength);
        case OkeyBackdropPattern.tufted:
          _paintTufted(canvas, size, strength);
        case OkeyBackdropPattern.grid:
          _paintGrid(canvas, size, strength);
      }
      canvas.restore();
    }

    // 3) VİNYET — kenarlar koyulaşır, göz masanın ortasında kalır.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.05),
          radius: 1.05,
          colors: [
            const Color(0x00000000),
            const Color(0x00000000),
            OkeyColors.damaskVignette.withValues(alpha: 0.42),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );
  }

  // -------------------------------------------------------------------
  // DESENLER — her biri GERÇEK bir yüzeyi taklit eder, hepsi aynı "kabartma"
  // dilini konuşur: koyu bir gölge kopyası + hemen üstünde açık bir asıl
  // çizgi/nokta. `strength` (0..1) genel şiddeti ölçekler.
  // -------------------------------------------------------------------

  /// ÇAPRAZ KEÇE DOKUMASI (Yeşil Çuha) — köşegen iki yönde ince çizgiler,
  /// baklava (diamond) deseni. Gerçek okey çuhasının dokunma hissi budur:
  /// tek yönlü bir tarama değil, ÖRGÜLÜ bir yüzey.
  void _paintWeave(Canvas canvas, Size size, double strength) {
    final step = (size.height * 0.055).clamp(22.0, 46.0);
    final shadow = Paint()
      ..strokeWidth = 1.1
      ..color = OkeyColors.damaskGrainShadow.withValues(alpha: 0.22 * strength);
    final light = Paint()
      ..strokeWidth = 0.8
      ..color = OkeyColors.damaskGrainLight.withValues(alpha: 0.10 * strength);

    void diagonals(Paint paint, double offset) {
      for (var x = -size.height + offset; x < size.width; x += step) {
        canvas.drawLine(
          Offset(x, 0),
          Offset(x + size.height, size.height),
          paint,
        );
      }
      for (var x = offset; x < size.width + size.height; x += step) {
        canvas.drawLine(
          Offset(x, 0),
          Offset(x - size.height, size.height),
          paint,
        );
      }
    }

    diagonals(shadow, 0.9);
    diagonals(light, 0);
  }

  /// KADİFE DÜĞMELEMESİ (Kırmızı Kadife) — chesterfield tarzı: düzenli
  /// aralıklı yumuşak düğmeler + komşularını bağlayan kırışık çizgiler.
  /// "Kadife" adını taşıyan tek temanın zemini gerçekten kadife gibi
  /// OKUNSUN diye — düz bir renk lekesi değil, dolgulu bir yüzey.
  void _paintTufted(Canvas canvas, Size size, double strength) {
    final step = (size.height * 0.16).clamp(64.0, 130.0);
    final half = step / 2;
    final creaseShadow = Paint()
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..color = OkeyColors.damaskGrainShadow.withValues(alpha: 0.22 * strength);
    final creaseLight = Paint()
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round
      ..color = OkeyColors.damaskGrainLight.withValues(alpha: 0.09 * strength);
    final buttonShadow = Paint()
      ..color = OkeyColors.damaskGrainShadow.withValues(alpha: 0.30 * strength);
    final buttonHighlight = Paint()
      ..color = OkeyColors.damaskGrainLight.withValues(alpha: 0.22 * strength);

    final cols = (size.width / step).ceil() + 2;
    final rows = (size.height / step).ceil() + 2;
    final r = step * 0.09;

    for (var row = -1; row < rows; row++) {
      for (var col = -1; col < cols; col++) {
        final cx = col * step.toDouble();
        final cy = row * step.toDouble();
        final center = Offset(cx, cy);

        // KIRIŞIK ÇİZGİLERİ — her düğme yalnızca İKİ AŞAĞI köşegenine
        // (güneydoğu/güneybatı) bağlanır. Yukarı yöndeki çizgiler ayrıca
        // çizilmez: onlar ÜSTTEKİ komşu düğmenin kendi güney çizgileridir —
        // ızgara her kenarı TAM BİR KEZ çizerek kendini tamamlar, ayrı bir
        // "üst satır" hesabına gerek kalmaz. Sonuç: her dört düğmenin
        // arasında kapanmış bir baklava (chesterfield) deseni.
        final se = center.translate(half, half);
        final sw = center.translate(-half, half);
        canvas.drawLine(center.translate(0, 1), se.translate(0, 1), creaseShadow);
        canvas.drawLine(center.translate(0, 1), sw.translate(0, 1), creaseShadow);
        canvas.drawLine(center, se, creaseLight);
        canvas.drawLine(center, sw, creaseLight);

        // DÜĞME — koyu bir gölge halkası + tam ortada ışığı yakalayan nokta.
        canvas.drawCircle(center.translate(0.6, 1.1), r, buttonShadow);
        canvas.drawCircle(center, r * 0.62, buttonHighlight);
      }
    }
  }

  /// MODERN NOKTA IZGARASI (Gece Modu) — ince, soğuk tonlu düzenli noktalar
  /// + aralarındaki hayalet çizgiler. Ahşap/kadife değil, fırçalanmış
  /// çeliğe yakışan dijital bir doku.
  void _paintGrid(Canvas canvas, Size size, double strength) {
    final step = (size.height * 0.09).clamp(34.0, 70.0);
    final line = Paint()
      ..strokeWidth = 0.7
      ..color = OkeyColors.damaskGrainLight.withValues(alpha: 0.06 * strength);
    final dot = Paint()
      ..color = OkeyColors.damaskGrainLight.withValues(alpha: 0.20 * strength);

    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    for (var y = 0.0; y < size.height; y += step) {
      for (var x = 0.0; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.4, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_DamaskPainter oldDelegate) =>
      oldDelegate.strength != strength || oldDelegate._themeKey != _themeKey;
}
