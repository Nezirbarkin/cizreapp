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
  /// (mavi alt çizgi).
  final bool hintMeldable;

  /// RİSKLİ TAŞ: masadaki açık bir pere işlenebiliyor, yani ıskartaya
  /// atılırsa +101 "işlek taş" cezası yazılır (kırmızı alt çizgi).
  ///
  /// [hintProcessable]'dan farkı YÖN: o "bunu işleyebilirsin" (fırsat), bu
  /// "bunu atma" (bedel). Eli açık oyuncuda ikisi aynı taşa denk gelir ve o
  /// zaman yeşil çerçeve zaten daha güçlü konuşur — kırmızı çizgi yalnızca
  /// yeşil YOKKEN çizilir, taş iki işaretle birden bezenmez.
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

  @override
  Widget build(BuildContext context) {
    final side = EdgeInsets.symmetric(horizontal: tight ? 0 : 1.5);
    final w = width ?? (small ? 30.0 : 42.0);
    final h = height ?? (small ? 40.0 : 56.0);

    // Köşe yuvarlaklığı taşın BOYUYLA ölçeklenir: sabit 6px, masadaki 14px'lik
    // küçük taşlarda yarıçapı taşın yarısına çıkarıp onu hapa çeviriyordu.
    final radius = (w * 0.15).clamp(2.5, 7.0);

    // Vurgu rengi — kenarlığı ve parıltıyı birlikte belirler.
    final Color? accent = highlightAsOkey
        ? OkeyColors.accentGold
        : inCompleteMeld
        ? OkeyColors.completeMeldGold
        : hintProcessable
        ? OkeyColors.hintProcessable
        : (selected ? const Color(0xFF4FC3F7) : null);

    final transform = selected
        ? (Matrix4.identity()..translateByDouble(0.0, -10.0, 0.0, 1.0))
        : Matrix4.identity();

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

    // ALT ÇİZGİ — tek bir şerit, iki anlam. Öncelik RİSKTE: bir taş hem
    // elimde per adayı olabilir hem de atıldığında ceza yazdırabilir;
    // ikisinden yalnızca biri gösterilecekse bedeli olan gösterilmeli.
    final Color? underline = hintProcessable
        ? null
        : hintRisky
        ? OkeyColors.hintRisky
        : (hintMeldable ? OkeyColors.hintMeldable : null);

    final foreground = underline == null
        ? null
        : BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border(bottom: BorderSide(color: underline, width: 3)),
          );

    final face = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _bodyBevel(radius),
          if (faceDown) _backFace(w) else _frontFace(w, h),
        ],
      ),
    );

    // Seçim geçişi kapalıysa DÜZ bir Container: aynı görüntü, State ve
    // AnimationController maliyeti olmadan (bkz. [animateSelection]).
    if (!animateSelection) {
      return Container(
        width: w,
        height: h,
        margin: side,
        transform: transform,
        decoration: decoration,
        foregroundDecoration: foreground,
        child: face,
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      width: w,
      height: h,
      margin: side,
      transform: transform,
      decoration: decoration,
      foregroundDecoration: foreground,
      child: face,
    );
  }

  // ---------------------------------------------------------------------
  // GÖVDE
  // ---------------------------------------------------------------------

  /// Taşın kalınlığını veren kenar: üst-sol açık, alt-sağ koyu.
  ///
  /// Dört kenar AYRI tonda — tek bir `Border.all` bunu veremez, çünkü ışığın
  /// bir yönü vardır ve tüm kenarlar aynı yönden aydınlanmaz.
  Widget _bodyBevel(double radius) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Color(0xE6FFFFFF), width: 1.4),
            left: BorderSide(color: Color(0x99FFFFFF), width: 1),
            bottom: BorderSide(color: Color(0x38000000), width: 1.6),
            right: BorderSide(color: Color(0x24000000), width: 1),
          ),
        ),
      ),
    );
  }

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

  // ---------------------------------------------------------------------
  // ÖN YÜZ
  // ---------------------------------------------------------------------

  Widget _frontFace(double w, double h) {
    final color = tile.isFalseJoker
        ? OkeyColors.falseJoker
        : OkeyColors.tileColorFor(tile.color!);

    // Oyuk yüzeyin payı taşla ölçeklenir; çok küçük taşta oyuk kaybolur ve
    // rakama daha çok yer kalır.
    final inset = (w * 0.11).clamp(1.5, 5.0);

    return Padding(
      padding: EdgeInsets.all(inset),
      child: DecoratedBox(
        // OYUK: ışık TERSİNE döner — üst kenar koyu, alt kenar açık. Beynin
        // "içeri çökmüş" olarak okuduğu şey tam olarak budur.
        // borderRadius YOK — bilerek.
        //
        // Flutter, FARKLI RENKLİ kenarları olan bir `Border` ile birlikte
        // `borderRadius` kabul etmez ("A borderRadius can only be given on
        // borders with uniform colors"). Oyuğun tüm anlamı zaten kenarların
        // farklı renkte olmasında: üst koyu, alt açık. Dolayısıyla yuvarlaklık
        // değil, kenar renkleri korunur — üstelik gerçek okey taşlarındaki
        // oyuk da köşeli bir dikdörtgendir. Taşın DIŞ köşeleri yukarıdaki
        // ClipRRect ile zaten yuvarlatılıyor.
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: Color(0x1F000000), width: 0.9),
            bottom: BorderSide(color: Color(0xB3FFFFFF), width: 0.9),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x14000000), Color(0x00000000)],
            stops: [0.0, 0.45],
          ),
        ),
        child: Center(
          // TAŞ = OYUN PARÇASI, METİN BLOĞU DEĞİL.
          //  1) withNoTextScaling — rakam sistemin yazı tipi ayarıyla BÜYÜMEZ;
          //     gerçek bir taşın üzerindeki rakam da büyümez ve büyüseydi
          //     sabit ölçülü taşın içinden taşardı.
          //  2) FittedBox — taşa doğal ölçüsünden küçük bir kutu verildiğinde
          //     içerik hata vermek yerine küçülerek sığar.
          child: MediaQuery.withNoTextScaling(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: tile.isFalseJoker
                  ? Icon(
                      Icons.auto_awesome,
                      color: color,
                      size: small ? 15 : 21,
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${tile.number}',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w900,
                            fontSize: small ? 16 : 22,
                            height: 1.0,
                            letterSpacing: -0.5,
                            // Rakam da kazınmış: altında bir piksellik açık
                            // gölge, onu yüzeyin İÇİNE oturtur.
                            shadows: const [
                              Shadow(
                                color: Color(0x66FFFFFF),
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: small ? 2 : 3),
                        // Gerçek okey taşlarındaki gibi rakamın altında aynı
                        // renkte küçük dolu çember.
                        Container(
                          width: small ? 4.5 : 6.5,
                          height: small ? 4.5 : 6.5,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x59FFFFFF),
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
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
  Widget _backFace(double w) {
    final d = w * 0.42;
    return Center(
      child: Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x1F000000), width: 0.9),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x0F000000), Color(0x40FFFFFF)],
          ),
        ),
      ),
    );
  }
}
