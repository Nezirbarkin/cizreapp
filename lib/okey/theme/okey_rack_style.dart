import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ISTAKA (TAKOZ) GÖRÜNÜMLERİ — kullanıcı isteği, 2026-09-07:
/// "3-4 farklı takoz ekle, kullanıcı takozunu ayardan değiştirebilsin,
/// gerçek takoz gibi olsun".
///
/// ## Neden bir "tema" nesnesi, dört ayrı painter değil
///
/// Dört görünümün ÇİZİM MANTIĞI aynı: gövde gradyanı, üst kenar cilası,
/// taşların dibindeki temas gölgesi, ön dudak, dış kenar. Değişen yalnızca
/// renk paleti ve ahşap damarının şiddeti. Ayrı painter'lar yazmak, ileride
/// ıstaka geometrisi değiştiğinde (ki daha önce tam olarak bu oldu: dudak
/// yüksekliği değişince ıstaka kendi içinde taştı) dört yerde birden
/// güncelleme gerektirirdi.
///
/// ## "Gerçek takoz" ne demek
///
/// Gerçek okey ıstakası cilalı ahşaptır ve inandırıcılığı üç şeyden gelir:
///   1. tek renk değil, boyuna doğru koyulaşan bir gradyan,
///   2. gövde boyunca uzanan, kalınlığı ve koyuluğu değişen DAMAR çizgileri,
///   3. taşların dayandığı öne çıkık dudağın kendi ışığı ve gölgesi.
/// [grainOpacity] sıfır verilirse damar hiç çizilmez — modern (grafit)
/// görünüm bu şekilde aynı painter'ı kullanır.
@immutable
class OkeyRackStyle {
  /// Tercih olarak saklanan sabit anahtar. Renk/isim değişse bile aynı kalır.
  final String key;

  /// Ayarlar ekranında görünen ad.
  final String label;

  /// Gövdenin üstten dibe doğru dört durağı.
  final List<Color> body;

  /// Ön dudağın (taşların dayandığı çıta) üst ve alt rengi.
  final Color lipTop;
  final Color lipBottom;

  /// Dudağın üstündeki ince vurgu ipi — ahşapta pirinç, grafitte altın.
  final Color accent;

  /// Damar çizgilerinin rengi ve görünürlüğü (0 = damar yok).
  final Color grainColor;
  final double grainOpacity;

  /// Üst kenardaki cila ışığının şiddeti.
  final double glossOpacity;

  const OkeyRackStyle({
    required this.key,
    required this.label,
    required this.body,
    required this.lipTop,
    required this.lipBottom,
    required this.accent,
    required this.grainColor,
    required this.grainOpacity,
    this.glossOpacity = 0.12,
  });

  /// KOYU CEVİZ — varsayılan.
  ///
  /// Neden varsayılan bu: masa koyu mavi keçe, taşlar fildişi. Açık renk bir
  /// ahşap (bkz. [mese]) ekranın en geniş nesnesini en parlak nesne yapar ve
  /// göz taşlardan kayar — 2026-09-06'da turuncu ahşabın kaldırılma sebebi
  /// tam olarak buydu. Ceviz hem gerçek bir ıstaka ahşabıdır hem de fildişi
  /// taşların altında en yüksek kontrastı veren tondur.
  static const ceviz = OkeyRackStyle(
    key: 'ceviz',
    label: 'Ceviz',
    body: [
      Color(0xFF8A5A32),
      Color(0xFF6E4425),
      Color(0xFF44280F),
      Color(0xFF2A1708),
    ],
    lipTop: Color(0xFF89552C),
    lipBottom: Color(0xFF321D0B),
    accent: Color(0xFFD8B27A),
    grainColor: Color(0xFF2A1708),
    grainOpacity: 0.30,
  );

  /// AÇIK MEŞE — kahvehane ıstakasının klasik tonu.
  static const mese = OkeyRackStyle(
    key: 'mese',
    label: 'Meşe',
    body: [
      Color(0xFFD9AE74),
      Color(0xFFC0904F),
      Color(0xFF95642F),
      Color(0xFF6B451F),
    ],
    lipTop: Color(0xFFD2A469),
    lipBottom: Color(0xFF7A4E23),
    accent: Color(0xFFFFE2B0),
    grainColor: Color(0xFF6B4423),
    grainOpacity: 0.26,
    glossOpacity: 0.16,
  );

  /// MAUN — kırmızıya çalan, cilası yüksek ağır ahşap.
  static const maun = OkeyRackStyle(
    key: 'maun',
    label: 'Maun',
    body: [
      Color(0xFF8E4026),
      Color(0xFF6E2C18),
      Color(0xFF43150A),
      Color(0xFF2A0C05),
    ],
    lipTop: Color(0xFF8A3C22),
    lipBottom: Color(0xFF320F06),
    accent: Color(0xFFE7B98C),
    grainColor: Color(0xFF260A04),
    grainOpacity: 0.32,
    glossOpacity: 0.18,
  );

  /// GRAFİT — 2026-09-06'daki modern gövde. Ahşap değil, damar çizilmez.
  static const grafit = OkeyRackStyle(
    key: 'grafit',
    label: 'Grafit',
    body: [
      Color(0xFF3A4753),
      Color(0xFF2B3742),
      Color(0xFF1B242C),
      Color(0xFF10171D),
    ],
    lipTop: Color(0xFF2E3A45),
    lipBottom: Color(0xFF161E25),
    accent: Color(0xFFE8C069),
    grainColor: Color(0x00000000),
    grainOpacity: 0,
  );

  /// Ayarlar ekranında GÖSTERİLDİKLERİ sıra.
  static const List<OkeyRackStyle> all = [ceviz, mese, maun, grafit];

  static OkeyRackStyle byKey(String? key) {
    for (final s in all) {
      if (s.key == key) return s;
    }
    return ceviz;
  }
}

/// Seçili ıstakayı tutan ve cihazda saklayan tek nokta.
///
/// ## Neden provider değil, ValueNotifier
///
/// Istaka tercihi maçın değil KULLANICININ ayarı: sunucuya gitmez, masa
/// değişince sıfırlanmaz, izleyici modunda da geçerlidir. OkeyGameProvider'a
/// bağlansaydı yalnızca masa ekranında yaşardı ve masaya her girişte yeniden
/// okunması gerekirdi. Buradaki tek örnek uygulama açıkken hep hazırdır;
/// ıstakayı çizen widget doğrudan bunu dinler (bkz. OkeyRackPanel).
class OkeyRackStylePrefs {
  static const _prefsKey = 'okey_rack_style';

  static final OkeyRackStylePrefs instance = OkeyRackStylePrefs._();

  OkeyRackStylePrefs._();

  final ValueNotifier<OkeyRackStyle> current = ValueNotifier<OkeyRackStyle>(
    OkeyRackStyle.ceviz,
  );

  bool _loaded = false;

  /// Kayıtlı tercihi okur. ASLA hata fırlatmaz — okunamazsa varsayılan kalır.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      current.value = OkeyRackStyle.byKey(prefs.getString(_prefsKey));
    } catch (_) {
      // tercih okunamadıysa varsayılan ıstaka kullanılır
    }
  }

  Future<void> select(OkeyRackStyle style) async {
    if (current.value.key == style.key) return;
    current.value = style;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, style.key);
    } catch (_) {
      // kaydedilemezse seçim bu oturum boyunca geçerli kalır
    }
  }
}

/// Istaka gövdesini çizen painter — GERÇEK BİR TAKOZ GİBİ (kullanıcı isteği,
/// 2026-09-07: "takoz daha gerçekçi tasarımı uygula, gerçek görünümlü ıstaka
/// olsun, mevcut düz ıstakadır").
///
/// ## Neden eskisi "düz" görünüyordu
///
/// Eski çizim tek bir dikey gradyan + damar + bir dudak şeridiydi. Sorun renk
/// değil GEOMETRİYDİ: ıstaka, ekranda yalnızca taşların ARASINDA kalan üç ince
/// şeritten görünür (üst pah, iki sıra arası, ön çıta) ve o üç şerit birer
/// KADEME KENARIYSA takoz üç boyutlu okunur; düz birer renk bandıysa tahta
/// gibi okunur. Eskiden aradaki şerit 2 pikseldi — ne pah ne gölge sığıyordu.
///
/// ## Gerçekçiliğin beş kaynağı
///
/// 1. **İki farklı kenar tipi.** Arka DUVARIN üst kenarı açıktan koyuya iner
///    (bkz. [_paintWallTop]); RAF ÇITASI ise ince bir temas gölgesiyle
///    başlar, ışık alan yatay yüzeyle devam eder, öne bakan yüzünde koyulaşır
///    (bkz. [_paintShelf]). İkisi aynı yardımcıdan çizilirse takoz yanlış
///    yerinden aydınlanır ve ara şerit bir raf değil bir çizgi gibi okunur.
/// 2. **Taşların arkası GÖLGEDİR.** Boş bir slotta ya da per boşluğunda
///    görünen yüzey ıstakanın dışı değil İÇİDİR. Bu gölge olmadan boş
///    slotlar tahtanın parlak üstü gibi durur ve takoz "üstüne taş dizilmiş
///    bir tahta"ya döner.
/// 3. **İki kademe iki tondadır.** Arka kademe öndekinden koyudur; gerçek bir
///    takozda arka raf hem daha uzaktır hem ön çıtanın gölgesindedir.
/// 4. **Uç kapakları.** Takoz sonsuz uzunlukta bir şerit değil, iki ucu olan
///    bir cisimdir: uçlarda ışık söner ve kenarın kıvrımı belli olur.
/// 5. **Damar ve cila.** Ahşap damarı BOYUNA uzanır; cila ışığı geniş ve
///    yumuşak bir bant hâlinde yansıtır.
///
/// [tileContactHeight] taşların dibinin başladığı yükseklik, [lipHeight] ön
/// çıtanın kalınlığı, [rowGap] iki taş sırası arasındaki ara raftır; üçü de
/// ıstakanın geometri sabitlerinden gelir (bkz. okey_rack_chrome.dart) —
/// painter kendi başına ölçü UYDURMAZ, yoksa çizdiği gölge taşların gerçek
/// dibinden ayrışırdı.
///
/// [rowGap] sıfır (varsayılan) verilirse ara raf hiç çizilmez: ayarlardaki
/// TEK SIRALIK önizleme painter'ı böyle kullanır.
class OkeyRackBodyPainter extends CustomPainter {
  final OkeyRackStyle style;
  final double tileContactHeight;
  final double lipHeight;
  final double rowGap;

  /// Küçük önizleme karelerinde gölge ve damar orantısız kalıyor; önizleme
  /// modunda dış gölge çizilmez ve damar seyreltilir.
  final bool preview;

  const OkeyRackBodyPainter({
    required this.style,
    required this.tileContactHeight,
    required this.lipHeight,
    this.rowGap = 0,
    this.preview = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final w = size.width;
    final h = size.height;

    // ÖN kenar arkadan daha yuvarlaktır: oyuncuya bakan kenar elle tutulan,
    // aşınmış kenardır; arka kenar tahtanın kesik ucudur.
    final radius = (h * 0.14).clamp(5.0, 16.0);
    final body = RRect.fromRectAndCorners(
      Rect.fromLTWH(0, 0, w, h),
      topLeft: Radius.circular(radius * 0.55),
      topRight: Radius.circular(radius * 0.55),
      bottomLeft: Radius.circular(radius),
      bottomRight: Radius.circular(radius),
    );

    // 1) MASAYA DÜŞEN GÖLGE — ıstaka keçenin ÜSTÜNDE duran bir cisimdir.
    if (!preview) {
      canvas.drawRRect(
        body.shift(const Offset(0, 4)),
        Paint()
          ..color = const Color(0x8A000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }

    // 2) GÖVDE — üstten dibe koyulaşan dört durak.
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: style.body,
          stops: const [0.0, 0.18, 0.74, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    canvas.save();
    canvas.clipRRect(body);

    // Taş alanının sınırları — ŞERİTLERİN yeri buradan çıkar.
    final topInset = tileContactHeight.clamp(0.0, h);
    final bottomInset = lipHeight.clamp(0.0, h - topInset);
    final tileBottom = h - bottomInset;
    // İki sıra eşit yükseklikte ve ARALARINDA rowGap var; ara raf bu yüzden
    // taş alanının tam ortasındadır (bkz. OkeyRackBarWidget: satırlar
    // padding'li kutuyu tam doldurur).
    final midCenter = (topInset + tileBottom) / 2;

    // 3) AHŞAP DAMARI — ıstakayı "ahşap rengi bir dikdörtgen"den ayıran şey.
    if (style.grainOpacity > 0) _paintGrain(canvas, w, h);

    // 4) İKİ KADEME İKİ TON. Arka kademe (üst yarı) öndekinden koyu: hem
    //    daha uzak, hem ön çıtanın gölgesinde. Tek gradyanla yapılamaz —
    //    gradyan sürekli, kademe ise BASAMAKLIDIR.
    if (rowGap > 0 && midCenter > topInset) {
      canvas.drawRect(
        Rect.fromLTRB(0, 0, w, midCenter),
        Paint()..color = const Color(0x24000000),
      );
    }

    // 5) SIRA YUVALARI — taşların DURDUĞU oyuklar.
    //
    // Kritik ayrıntı: bir slot boşken ya da taşlar arasında per boşluğu
    // varken oyuncunun gördüğü yüzey, ıstakanın DIŞI değil İÇİDİR — arka
    // duvarın dibi, yani gölgede kalan yer. Bu gölge çizilmeyince boş
    // slotlar "tahtanın üstü" gibi parlıyor ve takoz, üstüne taş DİZİLMİŞ
    // düz bir tahta gibi okunuyordu; taşların İÇİNDE durduğu bir ıstaka
    // gibi değil.
    //
    // Gölge yukarıda en koyudur (taşın arkaya dayandığı yer), öne doğru
    // ışığa açılır.
    final rowBands = rowGap > 0
        ? [
            (topInset, midCenter - rowGap / 2),
            (midCenter + rowGap / 2, tileBottom),
          ]
        : [(topInset, tileBottom)];
    for (final (rowTop, rowBottom) in rowBands) {
      if (rowBottom <= rowTop) continue;
      final rect = Rect.fromLTRB(0, rowTop, w, rowBottom);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.46),
              Colors.black.withValues(alpha: 0.20),
              Colors.black.withValues(alpha: 0.06),
            ],
            stops: const [0.0, 0.45, 1.0],
          ).createShader(rect),
      );
    }

    // 6) CİLA — üst kenarda keskin bir ışık, altında hızla sönen parlaklık.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h * 0.30),
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: style.glossOpacity),
                Colors.white.withValues(alpha: 0),
              ],
            ).createShader(Rect.fromLTWH(0, 0, w, h * 0.30)),
    );

    // 7) ARKA TAHTANIN ÜST KENARI. Işık yukarıdan geldiği için tahtanın
    //    ÜST pahı en parlak yerdir; aşağı indikçe taşların dibindeki temas
    //    gölgesine karışır. Taşlar gövdenin üstünde YÜZMEZ, arkasındaki
    //    tahtaya DAYANIR.
    _paintWallTop(canvas, w: w, top: 0, face: topInset);

    // 8) ARA RAF — arka kademenin ön çıtası. Üstü ışık alır, altı ÖN sıraya
    //    gölge düşürür; ıstakaya "iki katlı" hissini veren tek şerit budur.
    if (rowGap > 0) {
      final gapTop = midCenter - rowGap / 2;
      final gapRect = Rect.fromLTRB(0, gapTop, w, gapTop + rowGap);
      canvas.drawRect(
        gapRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [style.lipTop, style.lipBottom],
          ).createShader(gapRect),
      );
      _paintShelf(canvas, w: w, top: gapTop, face: rowGap, lightAlpha: 0.26);
    }

    // 9) ÖN ÇITA — taşların düşmesini engelleyen dudak. Kendi gradyanı,
    //    üstünde pirinç/altın vurgu ipi, en altta öne düşen koyu ön yüzü var.
    if (bottomInset > 0) {
      final lipRect = Rect.fromLTRB(0, tileBottom, w, h);
      canvas.drawRect(
        lipRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [style.lipTop, style.lipBottom],
            stops: const [0.28, 1.0],
          ).createShader(lipRect),
      );
      _paintShelf(
        canvas,
        w: w,
        top: tileBottom,
        face: bottomInset,
        lightAlpha: 0.30,
      );
      // VURGU İPİ — çıtanın üstündeki ince şerit. Temas gölgesinin hemen
      // ALTINA düşer ki iki çizgi birbirini yutmasın.
      final threadY = tileBottom + _bevelOf(bottomInset) + 0.6;
      canvas.drawLine(
        Offset(0, threadY),
        Offset(w, threadY),
        Paint()
          ..color = style.accent.withValues(alpha: 0.45)
          ..strokeWidth = 1.0,
      );
      // ÖN YÜZ — çıtanın oyuncuya bakan, ışık almayan alt kesimi.
      final faceTop = h - (bottomInset * 0.34).clamp(1.2, 4.0);
      final faceRect = Rect.fromLTRB(0, faceTop, w, h);
      canvas.drawRect(
        faceRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.0),
              Colors.black.withValues(alpha: 0.34),
            ],
          ).createShader(faceRect),
      );
    }

    // 10) UÇ KAPAKLARI — takozun iki ucu. Işık uçlarda söner ve kenarın
    //    kıvrımı ince bir ışık ipiyle belli olur. Bunlar olmadan ıstaka,
    //    ekranın bir kenarından öbürüne uzanan sonsuz bir şerit gibi durur.
    final capW = (w * 0.035).clamp(6.0, 26.0);
    for (final left in const [true, false]) {
      final rect = left
          ? Rect.fromLTWH(0, 0, capW, h)
          : Rect.fromLTWH(w - capW, 0, capW, h);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: left ? Alignment.centerLeft : Alignment.centerRight,
            end: left ? Alignment.centerRight : Alignment.centerLeft,
            colors: [
              Colors.black.withValues(alpha: 0.30),
              Colors.black.withValues(alpha: 0.0),
            ],
          ).createShader(rect),
      );
      final x = left ? 0.9 : w - 0.9;
      canvas.drawLine(
        Offset(x, radius * 0.4),
        Offset(x, h - radius * 0.6),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.10)
          ..strokeWidth = 1.2,
      );
    }

    canvas.restore();

    // 11) DIŞ KENAR — gövdeyi keçeden keskin biçimde ayırır.
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x9E000000),
    );
  }

  /// Bir kademe kenarındaki PAH kalınlığı — şeridin kendi boyuyla orantılı
  /// ama hiçbir zaman kıl kadar ince ya da şeridi yutacak kadar kalın değil.
  static double _bevelOf(double face) => (face * 0.26).clamp(0.6, 2.4);

  /// ARKA TAHTANIN ÜST KENARI — taşların ARKASINDA yükselen duvar.
  ///
  /// Işık yukarıdan gelir: en üstteki pah parlar, aşağı inildikçe yüzey
  /// taşların dibindeki temas gölgesine gömülür. Sıralama bu yüzden
  /// AÇIK → KOYU'dur.
  void _paintWallTop(
    Canvas canvas, {
    required double w,
    required double top,
    required double face,
  }) {
    if (face <= 0 || w <= 0) return;
    final rect = Rect.fromLTRB(0, top, w, top + face);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.16),
            Colors.black.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.46),
          ],
          stops: const [0.0, 0.35, 1.0],
        ).createShader(rect),
    );
    // Tahtanın kesik üst kenarı — cilanın yakaladığı keskin ışık ipi.
    canvas.drawRect(
      Rect.fromLTRB(0, top, w, top + _bevelOf(face)),
      Paint()..color = Colors.white.withValues(alpha: 0.34),
    );
  }

  /// BİR RAF ÇITASI — taşların dayandığı, öne bakan kademe.
  ///
  /// ## Sıralama neden tam olarak bu (temas → ışık → düşen yüz)
  ///
  /// Çıtanın ÜST YÜZEYİ yataydır ve ışığı doğrudan alır; ama tam üstünde
  /// duran taş sırası oraya kısa bir temas gölgesi düşürür. Aşağı inildikçe
  /// yüzey öne kıvrılıp oyuncuya bakan DİKEY yüze döner ve ışıktan çıkar.
  /// Yani şerit: ince koyu temas → parlak yatay yüzey → koyulaşan ön yüz.
  ///
  /// İlk denemede sıralama tersti (en üst parlak, altı koyu). Fiziksel
  /// karşılığı "tahtanın kesik üst kenarı"dır, yani ARKA DUVARIN kenarı —
  /// bkz. [_paintWallTop]. İki kademeyi aynı yardımcıdan çizmek, ıstakayı
  /// tam da yanlış yerinden aydınlatıyordu: iki sıra arasındaki şerit
  /// bir raf değil, bir çizgi gibi okunuyordu.
  void _paintShelf(
    Canvas canvas, {
    required double w,
    required double top,
    required double face,
    required double lightAlpha,
  }) {
    if (face <= 0 || w <= 0) return;
    final rect = Rect.fromLTRB(0, top, w, top + face);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: lightAlpha),
            Colors.black.withValues(alpha: 0.10),
            Colors.black.withValues(alpha: 0.52),
          ],
          stops: const [0.0, 0.30, 0.62, 1.0],
        ).createShader(rect),
    );
  }

  /// DAMAR — boyuna uzanan, kalınlığı ve koyuluğu değişen eğri çizgiler.
  ///
  /// Rastgelelik SABİT TOHUMLUDUR: her karede yeniden üretilseydi ıstaka
  /// titrer, ekran görüntüleri de birbirini tutmazdı.
  ///
  /// ## Neden her koyu çizginin bir de AÇIK eşi var
  ///
  /// İlk sürümde yalnızca koyu çizgiler vardı ve ıstaka uzaktan "düz kahve
  /// bir tahta" gibi okunuyordu: tek yönlü koyulaşma, ahşabın kendi ışığını
  /// vermez. Gerçek ahşapta damar bir ÇİFTTİR — koyu lif ve onun hemen
  /// yanındaki, ışığı yakalayan açık kenar. Açık eşi eklemek, aynı sayıda
  /// çizgiyle dokuyu görünür kılar; alternatif, koyuların sayısını artırmaktı
  /// ve o da tahtayı çizik gibi gösteriyordu.
  void _paintGrain(Canvas canvas, double w, double h) {
    final rnd = math.Random(20260907);
    final lines = preview ? 11 : 30;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < lines; i++) {
      // Damarlar üst yarıda biraz daha sık: ıstakayı aydınlatan ışık üstten
      // gelir, doku orada okunur.
      final y = h * (0.05 + 0.9 * math.pow(rnd.nextDouble(), 1.2));
      final amplitude = h * (0.015 + rnd.nextDouble() * 0.06);
      final phase = rnd.nextDouble() * math.pi * 2;
      final waves = 0.8 + rnd.nextDouble() * 2.2;
      final depth = 1 - (y / h) * 0.3;
      final alpha = style.grainOpacity * (0.5 + rnd.nextDouble() * 0.5) * depth;
      final width = 0.7 + rnd.nextDouble() * 1.9;

      Path traceAt(double offset) {
        final path = Path()..moveTo(0, y + offset);
        const steps = 22;
        for (var s = 1; s <= steps; s++) {
          final x = w * s / steps;
          final dy =
              math.sin(phase + (s / steps) * math.pi * 2 * waves) * amplitude;
          path.lineTo(x, y + offset + dy);
        }
        return path;
      }

      canvas.drawPath(
        traceAt(0),
        paint
          ..color = style.grainColor.withValues(alpha: alpha.clamp(0.0, 1.0))
          ..strokeWidth = width,
      );
      // Koyu lifin ışık alan kenarı — koyunun HEMEN üstünde, daha ince ve
      // çok daha soluk.
      canvas.drawPath(
        traceAt(-(width * 0.9)),
        paint
          ..color = Colors.white.withValues(
            alpha: (alpha * 0.34).clamp(0.0, 1.0),
          )
          ..strokeWidth = width * 0.55,
      );
    }

    // Birkaç geniş, yumuşak bant: ahşabın "levha" hissi. Çizgilerden farkı
    // kenarının olmaması — doku değil, ton farkı. Keskin dikdörtgen yerine
    // dikey gradyanla çizilir; keskin kenar tahtaya bant yapıştırılmış gibi
    // görünüyordu.
    for (var i = 0; i < (preview ? 2 : 5); i++) {
      final y = h * rnd.nextDouble();
      final band = h * (0.06 + rnd.nextDouble() * 0.16);
      final rect = Rect.fromLTWH(0, y, w, band);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              style.grainColor.withValues(alpha: 0),
              style.grainColor.withValues(alpha: style.grainOpacity * 0.26),
              style.grainColor.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(OkeyRackBodyPainter old) =>
      old.style.key != style.key ||
      old.tileContactHeight != tileContactHeight ||
      old.lipHeight != lipHeight ||
      old.rowGap != rowGap ||
      old.preview != preview;
}
