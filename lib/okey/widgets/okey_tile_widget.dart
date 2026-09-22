import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/okey_tile.dart';
import '../theme/okey_theme.dart';

/// Tek bir Okey taşı.
///
/// ## Yeniden tasarım (2026-09)
///
/// Önceki taş, üzerine rakam yazılmış yuvarlak köşeli bir dikdörtgendi:
/// tek bir gradyan, bir parlaklık şeridi ve bir gölge. Ekranda "kart" gibi
/// duruyordu, elle tutulan bir parça gibi değil. Gerçek bir okey taşının
/// görünüşünü üç şey belirler ve üçü de artık burada:
///
///  1. **Gövde kabartması** — taş kalın bir plastiktir: üst-sol kenarı ışığı
///     yakalar, alt-sağ kenarı gölgeye düşer. Tek bir kenarlık bunu veremez;
///     dört kenar AYRI tonda çizilir.
///  2. **Oyuk yüzey** — rakam düz yüzeye basılı değil, hafifçe İÇERİ çökmüş
///     bir alana kazınmıştır. O çukurun üst kenarı koyu, alt kenarı açıktır
///     (kabartmanın TERSİ) — beynin "içeri" olarak okuduğu şey tam olarak bu
///     ters ışıktır.
///  3. **İki katmanlı gölge** — yüzeye değdiği yerde dar ve koyu bir temas
///     gölgesi, çevresinde geniş ve yumuşak bir ortam gölgesi. Tek gölge
///     taşı havada yüzüyormuş gibi gösterir.
///
/// Işık yönü masanın tamamıyla aynı varsayımı paylaşır: YUKARIDAN-SOLDAN
/// (bkz. OkeyTableFeltPainter).
///
/// ## TAŞIN YÜZÜ TEK BİR ÇİZİMDİR (performans, 2026-09-09)
///
/// Yukarıdaki üç katman bir zamanlar iç içe widget'larla kuruluyordu:
/// `ClipRRect > Stack > [DecoratedBox, Padding > DecoratedBox > Center >
/// FittedBox > Column > [Text, SizedBox, Container]]`. Ölçüldüğünde taş
/// BAŞINA 19 render nesnesi çıkıyordu ve masada aynı anda ~60 taş var.
/// Sonucu şuydu: ıstakanın TEK bir yeniden kurulumu — yani bir taşa dokunmak
/// — test makinesinde 22 ms sürüyordu; 60 fps'in tüm kare bütçesi 16 ms.
/// Üstelik her taşın `FittedBox > Text`'i her yerleşimde rakamı BAŞTAN
/// ölçüyordu.
///
/// Artık gövde kabartması, oyuk, rakam ve çember tek bir [CustomPainter]
/// içinde çizilir ([_OkeyTileFacePainter]) ve rakamların [TextPainter]'ları
/// önbelleğe alınır — masadaki tüm taşlar için en fazla birkaç yüz kombinasyon
/// vardır. Görüntü birebir aynıdır; değişen tek şey, aynı pikselleri kimin
/// ürettiğidir.
///
/// Dış gövde (gradyan, çerçeve, gölgeler) BİLEREK `Container` olarak kaldı:
/// seçim geçişini [AnimatedContainer] veriyor ve `BoxDecoration` gölgeleri
/// motorun kendi hızlı yolunda çiziyor.
class OkeyTileWidget extends StatelessWidget {
  final OkeyTile tile;
  final bool selected;
  final bool small;

  /// true ise taşın yan boşlukları KAPATILIR — ıstakada taşlar bitişik durur.
  final bool tight;

  /// Verilirse taş TAM BU ÖLÇÜDE çizilir (varsayılan sabit ölçüler yerine).
  ///
  /// NEDEN GEREKLİ: Istakada her slot mevcut genişliği eşit paylaşır. Taşın
  /// genişliği sabit kalırsa slot daha genişken taş ortada yüzer ve aradaki
  /// fark GÖRÜNÜR BOŞLUK olur.
  final double? width;
  final double? height;
  final bool faceDown;
  final bool highlightAsOkey;

  /// Yardımlı modda: bu taş masadaki bir pere İŞLENEBİLİR (yeşil vurgu).
  final bool hintProcessable;

  /// Yardımlı modda: bu taş elde başka taşlarla per/grup/çift oluşturabilir
  /// — taşın altında yumuşak MAVİ bir ışık havuzu (v5'e kadar alt çizgiydi).
  final bool hintMeldable;

  /// RİSKLİ TAŞ: masadaki açık bir pere işlenebiliyor, yani ıskartaya
  /// atılırsa +101 "işlek taş" cezası yazılır — taşın altında KIZIL bir
  /// ışık havuzu (v5'e kadar kırmızı alt çizgiydi).
  ///
  /// [hintProcessable]'dan farkı YÖN: o "bunu işleyebilirsin" (fırsat), bu
  /// "bunu atma" (bedel). Eli açık oyuncuda ikisi aynı taşa denk gelir ve o
  /// zaman yeşil çerçeve zaten daha güçlü konuşur — kızıl ışık yalnızca
  /// yeşil YOKKEN yanar, taş iki işaretle birden bezenmez.
  ///
  /// Bu bir UYARIDIR, engel değil; atmadan önceki onay kartı için bkz.
  /// `OkeyRiskyDiscardSheet`.
  final bool hintRisky;

  /// OTOMATİK sayılan geçerli bir per/grup/çiftin parçası (altın çerçeve).
  final bool inCompleteMeld;

  /// true ise taş MASAYA YATIRILMIŞ gibi durur: yalnızca temas gölgesi kalır.
  final bool flat;

  /// [selected] DEĞİŞTİĞİNDE yumuşak geçiş yapılsın mı?
  ///
  /// ## Neden varsayılan KAPALI (performans, 2026-09-05)
  ///
  /// Seçim geçişi bir `AnimatedContainer` gerektirir ve o bir
  /// StatefulWidget'tır: her taş için ayrı bir State + AnimationController
  /// kurulur. Masada aynı anda 60'a yakın taş vardır (22 ıstaka + 4 ıskarta
  /// + gösterge/deste + masaya açılmış perler) ama bunların yalnızca
  /// ISTAKADAKİLER seçilebilir. Geri kalan ~40 taş, hiç oynamayacak bir
  /// animasyonun kurulum ve yeniden kurulum bedelini her build'de ödüyordu.
  ///
  /// Bu yüzden animasyon ARTIK İSTEĞE BAĞLI: seçimi gerçekten değişebilen
  /// tek yer olan ıstaka açıkça `true` verir (bkz. OkeyRackBarWidget).
  final bool animateSelection;

  const OkeyTileWidget({
    super.key,
    required this.tile,
    this.selected = false,
    this.small = false,
    this.tight = false,
    this.width,
    this.height,
    this.faceDown = false,
    this.highlightAsOkey = false,
    this.hintProcessable = false,
    this.hintMeldable = false,
    this.hintRisky = false,
    this.inCompleteMeld = false,
    this.flat = false,
    this.animateSelection = false,
  });

  // ---------------------------------------------------------------------
  // TEST YARDIMCILARI
  // ---------------------------------------------------------------------
  //
  // Rakam/joker ikonu ve altındaki dolu çember artık widget ağacında bir
  // `Text`/`Icon`/`Container` DEĞİL — tek bir [_OkeyTileFacePainter] içinde
  // Canvas'a çiziliyor (bkz. sınıf dokümanı, "TAŞIN YÜZÜ TEK BİR ÇİZİMDİR").
  // Bu üç `@visibleForTesting` yardımcı, painter'ın ÇİZECEĞİ değerleri
  // context'siz ve painter'a hiç dokunmadan hesaplar; testler
  // `find.text(...)`/`find.byIcon(...)` yerine bunları okur.
  //
  // NEDEN AYRI BİR HESAP, `_glyphFor`İN AYNISI DEĞİL: `_glyphFor` tam
  // `TextStyle`i (renk + font + gölge) üretir ve `DefaultTextStyle.of
  // (context)`e ihtiyaç duyar; testler yalnızca "hangi rakam/ikon, hangi
  // renk" sorusuna cevap arıyor, tam stile değil.
  @visibleForTesting
  String? get debugNumberText =>
      (!faceDown && !tile.isFalseJoker) ? '${tile.number}' : null;

  @visibleForTesting
  bool get debugShowsJokerIcon => !faceDown && tile.isFalseJoker;

  @visibleForTesting
  Color get debugGlyphColor => tile.isFalseJoker
      ? OkeyColors.falseJoker
      : OkeyColors.tileColorFor(tile.color!);

  @override
  Widget build(BuildContext context) {
    final w = width ?? (small ? 30.0 : 42.0);
    final h = height ?? (small ? 40.0 : 56.0);

    // Köşe yuvarlaklığı taşın BOYUYLA ölçeklenir: sabit 6px, masadaki 14px'lik
    // küçük taşlarda yarıçapı taşın yarısına çıkarıp onu hapa çeviriyordu.
    final radius = (w * 0.15).clamp(2.5, 7.0).toDouble();

    // Vurgu rengi — kenarlığı ve parıltıyı birlikte belirler.
    final Color? accent = highlightAsOkey
        ? OkeyColors.accentGold
        : inCompleteMeld
        ? OkeyColors.completeMeldGold
        : hintProcessable
        ? OkeyColors.hintProcessable
        : (selected ? const Color(0xFF4FC3F7) : null);

    // BOŞ DÖNÜŞÜM AĞACA GİRMEZ: `Matrix4.identity()` de bir `Transform`
    // render nesnesi kurar ve masadaki ~40 taş hiç seçilmediği için onu
    // boşuna taşıyordu.
    //
    // Seçim geçişi AÇIK olan ıstaka taşlarında matris HER ZAMAN verilir:
    // [AnimatedContainer] null'a düşen bir özelliği animasyonsuz, aniden
    // uygular — taş yumuşakça inmek yerine yerine "zıplardı".
    final Matrix4? transform = selected
        ? (Matrix4.identity()..translateByDouble(0.0, -10.0, 0.0, 1.0))
        : (animateSelection ? Matrix4.identity() : null);

    final decoration = BoxDecoration(
      gradient: OkeyColors.tileGradient,
      borderRadius: BorderRadius.circular(radius),
      // İŞLEK TAŞ EN KALIN ÇERÇEVEYİ ALIR: masadaki bir pere işlenebilen taş,
      // oyuncunun o turda yapabileceği en değerli hamledir — diğer
      // vurgulardan (seçili, tamamlanmış per) daha yüksek sesle konuşmalı.
      border: accent == null
          ? Border.all(color: const Color(0x1F000000), width: 0.8)
          : Border.all(color: accent, width: hintProcessable ? 2.6 : 1.8),
      boxShadow: _shadows(),
    );

    // YÜZ — kabartma + oyuk + rakam/çember, TEK çizimde. Rakamın yazı tipi
    // ağaçtan çözülür ki taş ekranın geri kalanıyla aynı fontu kullansın
    // (eski `Text` de tam olarak bunu yapıyordu: kendi stilini
    // DefaultTextStyle'ın üstüne bindiriyordu).
    final face = CustomPaint(
      size: Size(w, h),
      painter: _OkeyTileFacePainter(
        radius: radius,
        faceDown: faceDown,
        // Oyuk yüzeyin payı taşla ölçeklenir; çok küçük taşta oyuk kaybolur ve
        // rakama daha çok yer kalır.
        inset: (w * 0.11).clamp(1.5, 5.0).toDouble(),
        glyph: faceDown ? null : _glyphFor(context),
      ),
    );

    // Seçim geçişi kapalıysa DÜZ bir Container: aynı görüntü, State ve
    // AnimationController maliyeti olmadan (bkz. [animateSelection]).
    if (!animateSelection) {
      return Container(
        width: w,
        height: h,
        // Sıfır kenar boşluğu da bir `Padding` render nesnesidir; ıstakadaki
        // bitişik taşlar (tight) onu hiç kurmasın.
        margin: tight ? null : const EdgeInsets.symmetric(horizontal: 1.5),
        transform: transform,
        decoration: decoration,
        child: face,
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      width: w,
      height: h,
      margin: tight ? null : const EdgeInsets.symmetric(horizontal: 1.5),
      transform: transform,
      decoration: decoration,
      child: face,
    );
  }

  /// Taşın üzerinde ne yazdığı — rakam + çember, ya da sahte okey ikonu.
  ///
  /// Stil BURADA (build içinde) çözülür, painter'ın içinde değil: painter'ın
  /// BuildContext'i yoktur, ağaçtaki [DefaultTextStyle] oradan okunamazdı.
  _TileGlyph _glyphFor(BuildContext context) {
    final color = tile.isFalseJoker
        ? OkeyColors.falseJoker
        : OkeyColors.tileColorFor(tile.color!);

    if (tile.isFalseJoker) {
      final size = small ? 15.0 : 21.0;
      return _TileGlyph.icon(
        text: String.fromCharCode(Icons.auto_awesome.codePoint),
        // İkon fontu ağaçtan hiçbir şey MİRAS ALMAZ (`Icon` widget'ı da
        // almaz): glifin kimliği tamamen font ailesinde.
        style: TextStyle(
          inherit: false,
          color: color,
          fontSize: size,
          fontFamily: Icons.auto_awesome.fontFamily,
          package: Icons.auto_awesome.fontPackage,
        ),
        boxSize: size,
      );
    }

    return _TileGlyph.number(
      text: '${tile.number}',
      style: DefaultTextStyle.of(context).style.merge(
        TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: small ? 16 : 22,
          height: 1.0,
          letterSpacing: -0.5,
          // Rakam da kazınmış: altında bir piksellik açık gölge, onu yüzeyin
          // İÇİNE oturtur.
          shadows: const [
            Shadow(color: Color(0x66FFFFFF), offset: Offset(0, 1)),
          ],
        ),
      ),
      // Gerçek okey taşlarındaki gibi rakamın altında aynı renkte küçük dolu
      // çember.
      pipColor: color,
      pipDiameter: small ? 4.5 : 6.5,
      pipGap: small ? 2 : 3,
    );
  }

  // ---------------------------------------------------------------------
  // GÖLGE
  // ---------------------------------------------------------------------

  /// GÖLGE — iki katman.
  ///
  /// Tek bulanık gölge taşı yüzeyin üstünde yüzüyormuş gibi gösterir.
  /// Gerçekte iki gölge vardır: değdiği yerde dar/koyu bir TEMAS gölgesi ve
  /// çevresinde geniş/açık bir ORTAM gölgesi.
  List<BoxShadow> _shadows() {
    // İŞLEK TAŞ PARLAR (kullanıcı isteği, 2026-09-06: "işlek taşlar daha
    // belirgin olsun").
    //
    // Yalnızca çerçeveyi kalınlaştırmak yetmiyordu: ıstakada 15 taş yan yana
    // dururken bir taşın çerçevesinin ötekinden kalın olduğunu görmek için
    // BAKMAK gerekiyor. Dışa vuran yeşil ışık ise çevre görüşle yakalanır —
    // oyuncu taşları tek tek incelemeden "şurada bir şey var" der.
    if (hintProcessable) {
      return const [
        BoxShadow(
          color: OkeyColors.hintProcessableGlow,
          blurRadius: 10,
          spreadRadius: 0.5,
        ),
        BoxShadow(
          color: Color(0x42000000),
          blurRadius: 2,
          offset: Offset(0, 1),
        ),
      ];
    }
    // ALTTAN IŞIK — çizgi değil (düzen v5).
    //
    // v4'te "işlek" ve "per adayı" taşlar, taşın altına çizilen 3 piksellik
    // RENKLİ BİR ŞERİTLE işaretleniyordu. O şerit taşın kendisine ait
    // değildi: fildişi bir nesnenin üstünde duran, oyunun malzemesiyle
    // hiç ilgisi olmayan bir arayüz çizgisiydi. Üstelik ıstakada taşlar
    // bitişik durduğu için şeritler birleşip tek bir renkli bant gibi
    // okunuyordu.
    //
    // Artık işaret IŞIKTIR: taşın altında bir havuz. Fiziksel dünyada bir
    // nesneyi işaretlemenin yolu budur ve masanın geri kalanıyla (tek
    // kaynaklı ışık, temas gölgeleri) aynı dili konuşur. Gölge AŞAĞI
    // kaydırılır ve yayılma NEGATİFTİR: ışık komşu taşlara taşmasın,
    // işaretlenen taşın altında kalsın.
    //
    // Öncelik RİSKTE: bir taş hem elimde per adayı olabilir hem de
    // atıldığında ceza yazdırabilir; ikisinden yalnızca biri
    // gösterilecekse BEDELİ OLAN gösterilmeli.
    if (hintRisky || hintMeldable) {
      final risky = hintRisky;
      return [
        BoxShadow(
          color: (risky ? OkeyColors.hintRisky : OkeyColors.hintMeldable)
              .withValues(alpha: risky ? 0.85 : 0.55),
          blurRadius: risky ? 9 : 7,
          spreadRadius: -1,
          offset: Offset(0, risky ? 4 : 3),
        ),
        const BoxShadow(
          color: Color(0x42000000),
          blurRadius: 2,
          offset: Offset(0, 1),
        ),
      ];
    }
    if (selected) {
      return const [
        BoxShadow(
          color: Color(0x42000000),
          blurRadius: 2,
          offset: Offset(0, 1),
        ),
        BoxShadow(
          color: Color(0x5E000000),
          blurRadius: 14,
          offset: Offset(0, 7),
        ),
      ];
    }
    if (flat) {
      // Masaya yatmış taş: yalnızca temas gölgesi. Hiç gölge olmasaydı taş
      // masaya BASILMIŞ bir çıkartma gibi görünürdü.
      return const [
        BoxShadow(
          color: Color(0x38000000),
          blurRadius: 2,
          offset: Offset(0, 1),
        ),
      ];
    }
    return const [
      BoxShadow(
        color: Color(0x40000000),
        blurRadius: 1.5,
        offset: Offset(0, 1),
      ),
      BoxShadow(color: Color(0x2B000000), blurRadius: 5, offset: Offset(0, 3)),
    ];
  }
}

// -----------------------------------------------------------------------
// TAŞIN YÜZÜ
// -----------------------------------------------------------------------

/// Taşın üzerindeki işaret — ya rakam + çember, ya da sahte okey ikonu.
@immutable
class _TileGlyph {
  final String text;
  final TextStyle style;

  /// İKON: glif, kenarı [boxSize] olan bir karenin ORTASINDA durur (`Icon`
  /// widget'ı da tam olarak böyle yapar). Rakamda null.
  final double? boxSize;

  /// RAKAM: altındaki dolu çemberin rengi/çapı ve arasındaki boşluk.
  final Color? pipColor;
  final double pipDiameter;
  final double pipGap;

  const _TileGlyph.icon({
    required this.text,
    required this.style,
    required double this.boxSize,
  }) : pipColor = null,
       pipDiameter = 0,
       pipGap = 0;

  const _TileGlyph.number({
    required this.text,
    required this.style,
    required Color this.pipColor,
    required this.pipDiameter,
    required this.pipGap,
  }) : boxSize = null;

  @override
  bool operator ==(Object other) =>
      other is _TileGlyph &&
      other.text == text &&
      other.style == style &&
      other.boxSize == boxSize &&
      other.pipColor == pipColor &&
      other.pipDiameter == pipDiameter &&
      other.pipGap == pipGap;

  @override
  int get hashCode =>
      Object.hash(text, style, boxSize, pipColor, pipDiameter, pipGap);
}

/// RAKAM ÖLÇÜMLERİ ÖNBELLEĞİ.
///
/// Bir [TextPainter.layout] çağrısı tek bir rakam için bile ucuz değildir ve
/// eskiden HER yerleşimde, HER taş için tekrarlanıyordu (`FittedBox > Text`).
/// Oysa masadaki tüm olasılıklar sayılıdır: 13 rakam × 4 renk × 2 boy, artı
/// sahte okey ikonu. Aynı (metin, stil) çifti yalnızca BİR KEZ ölçülür.
final Map<(String, TextStyle), TextPainter> _glyphPainters = {};

TextPainter _glyphPainter(String text, TextStyle style) {
  final key = (text, style);
  final cached = _glyphPainters[key];
  if (cached != null) return cached;
  // Tema/yazı tipi değişimleri yeni anahtarlar üretir; önbellek sınırsız
  // büyümesin diye tavana varınca komple boşaltılır (yeniden dolması birkaç
  // karelik iştir).
  if (_glyphPainters.length >= 256) _glyphPainters.clear();
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
    // TAŞ = OYUN PARÇASI, METİN BLOĞU DEĞİL: rakam, sistemin yazı tipi
    // ayarıyla BÜYÜMEZ. Gerçek bir taşın üzerindeki rakam da büyümez ve
    // büyüseydi sabit ölçülü taşın içinden taşardı. (Eski ağaçtaki
    // `MediaQuery.withNoTextScaling` bunun karşılığıydı.)
    textScaler: TextScaler.noScaling,
  )..layout();
  _glyphPainters[key] = painter;
  return painter;
}

/// Taşın kabartması, oyuğu ve üzerindeki işaret — TEK geçişte.
class _OkeyTileFacePainter extends CustomPainter {
  final double radius;
  final double inset;
  final bool faceDown;
  final _TileGlyph? glyph;

  const _OkeyTileFacePainter({
    required this.radius,
    required this.inset,
    required this.faceDown,
    required this.glyph,
  });

  /// OYUK: ışık TERSİNE döner — üst kenar koyu, alt kenar açık. Beynin
  /// "içeri çökmüş" olarak okuduğu şey tam olarak budur.
  static const _hollowGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x14000000), Color(0x00000000)],
    stops: [0.0, 0.45],
  );

  /// KAPALI TAŞIN ortasındaki soluk kabartma çember.
  static const _backGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x0F000000), Color(0x40FFFFFF)],
  );

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (rect.isEmpty) return;

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));

    // 1) GÖVDE KABARTMASI — taş kalın bir plastiktir: üst-sol kenarı ışığı
    //    yakalar, alt-sağ kenarı gölgeye düşer. Dört kenar AYRI tonda çizilir;
    //    tek bir `Border.all` bunu veremez, çünkü ışığın bir yönü vardır.
    paintBorder(
      canvas,
      rect,
      top: const BorderSide(color: Color(0xE6FFFFFF), width: 1.4),
      left: const BorderSide(color: Color(0x99FFFFFF), width: 1),
      bottom: const BorderSide(color: Color(0x38000000), width: 1.6),
      right: const BorderSide(color: Color(0x24000000), width: 1),
    );

    if (faceDown) {
      _paintBack(canvas, rect);
    } else if (glyph != null) {
      _paintFront(canvas, rect, glyph!);
    }
    canvas.restore();
  }

  // ---------------------------------------------------------------------
  // ÖN YÜZ
  // ---------------------------------------------------------------------

  void _paintFront(Canvas canvas, Rect rect, _TileGlyph g) {
    final face = Rect.fromLTRB(
      rect.left + inset,
      rect.top + inset,
      rect.right - inset,
      rect.bottom - inset,
    );
    if (face.width <= 0 || face.height <= 0) return;

    // 2) OYUK YÜZEY — gradyan + ters ışıklı iki kenar. Köşeler yuvarlatılmaz
    //    (gerçek okey taşlarındaki oyuk da köşeli bir dikdörtgendir); taşın
    //    DIŞ köşelerini yukarıdaki clipRRect zaten yuvarlatıyor.
    canvas.drawRect(face, Paint()..shader = _hollowGradient.createShader(face));
    paintBorder(
      canvas,
      face,
      top: const BorderSide(color: Color(0x1F000000), width: 0.9),
      bottom: const BorderSide(color: Color(0xB3FFFFFF), width: 0.9),
    );

    // 3) İŞARET — doğal ölçüsü hesaplanır, sığmıyorsa KÜÇÜLTÜLEREK sığdırılır
    //    (eski ağaçtaki `FittedBox(fit: BoxFit.scaleDown)` ile aynı kural:
    //    büyütmek yok, yalnızca küçültmek).
    final painter = _glyphPainter(g.text, g.style);
    final double naturalW;
    final double naturalH;
    if (g.boxSize != null) {
      naturalW = naturalH = g.boxSize!;
    } else {
      naturalW = math.max(painter.width, g.pipDiameter);
      naturalH = painter.height + g.pipGap + g.pipDiameter;
    }
    if (naturalW <= 0 || naturalH <= 0) return;

    final scale = math.min(
      1.0,
      math.min(face.width / naturalW, face.height / naturalH),
    );

    canvas.save();
    canvas.translate(face.center.dx, face.center.dy);
    if (scale != 1.0) canvas.scale(scale);
    canvas.translate(-naturalW / 2, -naturalH / 2);

    if (g.boxSize != null) {
      // İkon, kendi kare kutusunun ortasında durur.
      painter.paint(
        canvas,
        Offset((naturalW - painter.width) / 2, (naturalH - painter.height) / 2),
      );
    } else {
      // Rakam üstte, çember altta — ikisi de ortalanmış (eski `Column`).
      painter.paint(canvas, Offset((naturalW - painter.width) / 2, 0));
      final r = g.pipDiameter / 2;
      final cx = naturalW / 2;
      final cy = painter.height + g.pipGap + r;
      // Çemberin bir piksel altındaki açık iz — onu da yüzeye kazır.
      canvas.drawCircle(
        Offset(cx, cy + 1),
        r,
        Paint()..color = const Color(0x59FFFFFF),
      );
      canvas.drawCircle(Offset(cx, cy), r, Paint()..color = g.pipColor!);
    }
    canvas.restore();
  }

  // ---------------------------------------------------------------------
  // ARKA YÜZ (deste ve gizlenmiş okey)
  // ---------------------------------------------------------------------

  /// KAPALI TAŞ — açık taşlarla AYNI fildişi gövde, üzerinde rakam yok.
  ///
  /// Gövde rengi bilerek aynı: masadaki deste ve ıstakadaki kapalı okey,
  /// gerçek okey taşları gibi beyaz görünmeli (bir zamanlar koyu gri
  /// çizilirdi ve masaya ait olmayan bir nesne gibi duruyordu).
  /// Ayırt edici işaret, ortadaki soluk kabartma çemberdir.
  void _paintBack(Canvas canvas, Rect rect) {
    final d = rect.width * 0.42;
    if (d <= 0) return;
    final center = rect.center;
    final square = Rect.fromCenter(center: center, width: d, height: d);
    canvas.drawCircle(
      center,
      d / 2,
      Paint()..shader = _backGradient.createShader(square),
    );
    const borderWidth = 0.9;
    canvas.drawCircle(
      center,
      (d - borderWidth) / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..color = const Color(0x1F000000),
    );
  }

  @override
  bool shouldRepaint(_OkeyTileFacePainter old) =>
      old.radius != radius ||
      old.inset != inset ||
      old.faceDown != faceDown ||
      old.glyph != glyph;
}
