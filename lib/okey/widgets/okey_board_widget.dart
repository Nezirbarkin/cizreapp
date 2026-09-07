import 'package:flutter/material.dart';

import '../engine/okey_board_layout.dart';
import '../engine/okey_meld_validator.dart';
import '../engine/okey_tile.dart';
import '../models/okey_models.dart';
import 'okey_board_grid.dart';
import 'okey_drag_payload.dart';
import 'okey_tile_widget.dart';

/// Masadaki bir perin KAÇ HÜCRE kapladığı: taşlar + iki uçtaki BOŞ hücreler.
///
/// ## Neden boş hücreler var
///
/// Masaya `2·3·4` konduğunda o perin SOLUNDA bir yer boştur — oraya `1`
/// gelir. Eskiden per, taşları kadar geniş çizilirdi; oyuncu bir taşın o
/// pere işlenip işlenemeyeceğini kafasından hesaplamak zorundaydı. Artık
/// per bir TABLO SATIRIDIR ve boş hücre "buraya bir taş gelebilir" der;
/// üstelik o hücrenin kendisi bırakma hedefidir.
@immutable
class OkeyMeldSlots {
  /// Perin SOLUNDAKİ boş hücre sayısı (0 veya 1).
  final int leading;

  /// Perin SAĞINDAKİ boş hücre sayısı (0 veya 1).
  final int trailing;

  /// Perin taş sayısı.
  final int tileCount;

  const OkeyMeldSlots({
    required this.leading,
    required this.trailing,
    required this.tileCount,
  });

  /// Tabloda kapladığı toplam hücre.
  int get total => leading + tileCount + trailing;

  /// Bir perin uçlarındaki genişleme hücrelerini hesaplar.
  ///
  /// * **seri** — 1'den küçük ve 13'ten büyük sayı olmadığı için, yalnızca
  ///   seri gerçekten o uca dayanmıyorsa hücre açılır (`2·3·4` → solda bir
  ///   hücre; `1·2·3` → solda hücre YOK).
  /// * **grup** — en fazla dört renk vardır; üç taşlıysa sağda bir hücre.
  /// * **çift / gösterge** — büyütülemez, hiç hücre açılmaz.
  ///
  /// [okeyTile] yoksa (ör. saf önizleme) genişleme hesaplanamaz; per
  /// yalnızca taşları kadar yer kaplar.
  factory OkeyMeldSlots.of(OkeyTableMeld meld, OkeyTile? okeyTile) {
    final count = meld.tiles.length;
    if (okeyTile == null ||
        meld.meldType == 'pair' ||
        meld.meldType == 'gosterge') {
      return OkeyMeldSlots(leading: 0, trailing: 0, tileCount: count);
    }

    final start = OkeyMeldValidator.findRunStart(meld.tiles, okeyTile);
    if (start != null) {
      final end = start + count - 1;
      return OkeyMeldSlots(
        leading: start > 1 ? 1 : 0,
        trailing: end < 13 ? 1 : 0,
        tileCount: count,
      );
    }

    // Grup (aynı rakam, farklı renkler): dördüncü renge yer.
    return OkeyMeldSlots(
      leading: 0,
      trailing: count < 4 ? 1 : 0,
      tileCount: count,
    );
  }
}

/// Masanın keçesindeki AÇILAN PERLER alanı.
///
/// ## Yeniden tasarım (2026-09) — HER PER MASADA GÖRÜNÜR
///
/// Önceki tahta taş ölçüsünü DIŞARIDAN alıyordu ve sığmayanı bir
/// `SingleChildScrollView`'a atıyordu. 101 Okey'de dört oyuncu 101'er puan
/// açtığında masada 12-16 per birikir; oyuncu masanın yarısını göremiyor,
/// hangi pere işleyeceğini bulmak için KAYDIRMAK zorunda kalıyordu. Gerçek
/// bir okey masasında böyle bir şey yoktur: açılan her per ortada durur.
///
/// Artık taş ölçüsü bir GİRDİ değil, bir ÇIKTIDIR: [OkeyBoardLayout] verilen
/// alana tüm perlerin sığdığı en büyük ölçüyü bulur. Per sayısı arttıkça
/// taşlar küçülür ama HİÇBİRİ gizlenmez.
///
/// ## KAYDIRMA YOK (kullanıcı kuralı, 2026-09)
///
/// "Taşlar tümü masaya düşeli kaydırma olmasın." Bu tahta hiçbir koşulda
/// kaydırılmaz: en küçük taş ölçüsünde bile sığmayan uç durumda bile
/// (pratikte 20+ per) bir kaydırma alanı DEĞİL, bir [FittedBox] devreye
/// girer — her per ekranda kalır, sadece bir tık daha küçülür.
///
/// [tileWidth] artık bir ÜST SINIRDIR (genelde ıstakadaki taş genişliği):
/// masadaki taş elimdeki taştan büyük olmamalı, yoksa uzaktaki masa
/// yakındaki elden büyük görünür ve derinlik hissi tersine döner.
class OkeyBoardWidget extends StatelessWidget {
  final List<OkeyTableMeld> melds;
  final bool canTapMelds;
  final void Function(int meldId)? onTapMeld;

  /// Bir taş doğrudan bu perin üzerine SÜRÜKLENİP bırakıldığında (işleme).
  final void Function(int meldId, int fromSlot)? onTileDroppedOnMeld;
  final VoidCallback? onDragEnd;

  /// Tahta boşken gösterilecek ipucu yazısı.
  final String emptyHint;

  /// Masadaki taşın ÜST SINIR genişliği (bkz. sınıf yorumu).
  final double? tileWidth;
  final double? tileHeight;

  /// O elin okey taşı — perlerin uçlarındaki BOŞ hücreleri hesaplamak için.
  ///
  /// Verilmezse per yalnızca taşları kadar yer kaplar (genişleme hücresi
  /// çizilmez). Bir seride jokerin hangi sayının yerine geçtiği ancak okey
  /// taşı bilinerek çözülebilir, o yüzden bu bilgi zorunlu değil ama
  /// olmadan tablo eksik kalır.
  final OkeyTile? okeyTile;

  const OkeyBoardWidget({
    super.key,
    required this.melds,
    this.canTapMelds = false,
    this.onTapMeld,
    this.onTileDroppedOnMeld,
    this.onDragEnd,
    this.emptyHint = 'Açılan perler masaya buraya serilir',
    this.tileWidth,
    this.tileHeight,
    this.okeyTile,
  });

  @override
  Widget build(BuildContext context) {
    if (melds.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            emptyHint,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0x3DFFFFFF),
              fontSize: 11,
              height: 1.35,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.hasBoundedWidth ? c.maxWidth : 320.0;
        final h = c.hasBoundedHeight ? c.maxHeight : 200.0;

        // Perin genişliği artık TAŞ SAYISI değil, HÜCRE sayısıdır: uçlardaki
        // boş genişleme hücreleri de yer kaplar. Hesaba katılmasaydı motor
        // her peri bir-iki hücre dar sanar, tahta gerçekte taşardı.
        final slots = [for (final m in melds) OkeyMeldSlots.of(m, okeyTile)];

        final fit = OkeyBoardLayout.fit(
          width: w,
          height: h,
          meldSizes: [for (final s in slots) s.total],
          maxTileWidth: tileWidth ?? okeyBoardTileWidth,
        );

        // PERLER ALT ALTA: sol üst köşeden başlar, aşağı doğru dizilir;
        // sütun masanın yüksekliğini doldurunca sağdan yeni bir sütun açılır
        // (kullanıcı isteği, 2026-09-05: "açılan perler alt alta dizilsin").
        //
        // Sütunlar ÜSTTEN, perler SOLDAN hizalanır: yeni bir per hep sıranın
        // sonuna eklenir ve önündekiler yerinden oynamaz.
        final board = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < fit.columns.length; c++) ...[
              if (c > 0) const SizedBox(width: OkeyBoardLayout.meldGap),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (
                    var k = 0;
                    k < fit.columns[c].meldIndices.length;
                    k++
                  ) ...[
                    if (k > 0) const SizedBox(height: OkeyBoardLayout.rowGap),
                    Builder(
                      builder: (_) {
                        final i = fit.columns[c].meldIndices[k];
                        return _MeldOnBoard(
                          // id ile keylenmiş: Flutter Element'i korur — giriş
                          // animasyonu SADECE yeni konan bir per için oynar.
                          key: ValueKey(melds[i].id),
                          meld: melds[i],
                          slots: slots[i],
                          tileWidth: fit.tileWidth,
                          tileHeight: fit.tileHeight,
                          onTap: canTapMelds && onTapMeld != null
                              ? () => onTapMeld!(melds[i].id)
                              : null,
                          onTileDropped: onTileDroppedOnMeld == null
                              ? null
                              : (slot) =>
                                    onTileDroppedOnMeld!(melds[i].id, slot),
                          onDragEnd: onDragEnd,
                        );
                      },
                    ),
                  ],
                ],
              ),
            ],
          ],
        );

        // Izgara ölçüsünün SAHİBİ. Kendisi bir şey çizmez (taşlar düz keçeye
        // yatar) ama hizalama regresyon testi bu çizimin köşesinden ölçtüğü
        // için anahtarı ve konumu korunmalıdır.
        final grid = Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(key: okeyBoardGridKey, painter: _GridPainter()),
          ),
        );

        // KAYDIRMA YOK — HİÇBİR KOŞULDA.
        //
        // KULLANICI KURALI: "taşlar tümü masaya düşeli kaydırma olmasın."
        // Gerçek bir okey masasında açılan perler ortada durur; oyuncunun
        // masanın yarısını görmek için parmağıyla kaydırması diye bir şey
        // yoktur. [OkeyBoardLayout] zaten alana sığan en büyük taş ölçüsünü
        // çözüyor; en küçük ölçüde bile sığmayan uç bir durumda (pratikte
        // 20+ per) tahta bir kaydırma alanına DEĞİL, bir FittedBox'a düşer:
        // taşlar bir tık daha küçülür ama hepsi ekranda kalır.
        final Widget content = fit.everythingFits
            ? board
            : FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: board,
              );

        // PERLER SOL ÜST KÖŞEDEN BAŞLAR ve alt alta dizilir (kullanıcı
        // isteği, 2026-09-05). Ortalanmış yerleşimde masanın dolduğu yön
        // belli değildi: ilk per keçenin tam ortasında asılı duruyor, ikinci
        // per gelince ikisi birden yana kayıyordu. Sabit bir başlangıç
        // köşesi, masanın "nereden nereye dolduğunu" tek bakışta okutur.
        final anchored = Align(alignment: Alignment.topLeft, child: content);

        // REPAINT SINIRI — masadaki perler, YANLARINDA oynayan
        // animasyonlar yüzünden yeniden boyanmasın.
        //
        // Aynı katmanda saniyede bir kendini çizen üç şey var: süre çizgisi,
        // sıra nabzı ve hediye kutlaması. Sınır olmadan, per sayısı arttıkça
        // pahalılaşan bu tahta (her taş: kırpma + gradyan + iki gölge) o
        // animasyonların her karesinde baştan boyanıyordu.
        return RepaintBoundary(
          child: Stack(
            children: [
              grid,
              Positioned.fill(child: anchored),
            ],
          ),
        );
      },
    );
  }
}

/// Masaya yatmış tek bir per — bir TABLO SATIRI.
///
/// ## Neden tablo
///
/// Per artık yalnızca yan yana taşlar değil, hücrelere bölünmüş bir
/// satırdır. Taşların olmadığı uç hücreler BOŞ çizilir ve tam olarak
/// oraya gelebilecek taşı işaret eder: `2·3·4` perinin solundaki boş
/// hücre "buraya 1 gelir" demektir. Hücre çizgileri arkaya, taşların
/// ALTINA çizilir; böylece taşlar birbirine bitişik kalır (aralarına
/// çizgi girip peri üç ayrı taşa bölmez) ama ızgara yine okunur.
class _MeldOnBoard extends StatelessWidget {
  final OkeyTableMeld meld;
  final OkeyMeldSlots slots;
  final double tileWidth;
  final double tileHeight;
  final VoidCallback? onTap;
  final void Function(int fromSlot)? onTileDropped;
  final VoidCallback? onDragEnd;

  const _MeldOnBoard({
    super.key,
    required this.meld,
    required this.slots,
    required this.tileWidth,
    required this.tileHeight,
    this.onTap,
    this.onTileDropped,
    this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < slots.leading; i++)
          _EmptyCell(width: tileWidth, height: tileHeight),
        for (final t in meld.tiles)
          OkeyTileWidget(
            tile: t,
            tight: true,
            flat: true,
            width: tileWidth,
            height: tileHeight,
          ),
        for (var i = 0; i < slots.trailing; i++)
          _EmptyCell(width: tileWidth, height: tileHeight),
      ],
    );

    // IZGARA taşların ALTINA çizilir: hücre sınırları görünür ama taşların
    // arasına bir çizgi girip peri parçalamaz.
    final tiles = Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _MeldGridPainter(
                cellWidth: tileWidth,
                cells: slots.total,
              ),
            ),
          ),
        ),
        row,
      ],
    );

    // PERİN OTURMA ZEMİNİ — keçeye oyulmuş hafif bir çukur.
    //
    // Bu zemin olmadan yan yana iki per tek bir taş dizisi gibi okunuyordu;
    // hangi taşın hangi pere ait olduğu ancak sayıları okuyarak anlaşılıyordu.
    final content = Container(
      padding: const EdgeInsets.all(OkeyBoardLayout.meldPadding),
      decoration: BoxDecoration(
        // Keçeye oyulmuş bir çukur: üstte koyu bir kenar (ışığın giremediği
        // yer), altta ince bir açık çizgi (çukurun karşı duvarına vuran
        // ışık). Düz bir yarı saydam kutu, perleri keçenin üstünde YÜZER
        // gösteriyordu.
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x59000000), Color(0x33000000)],
        ),
        borderRadius: BorderRadius.circular(6),
        // KENAR YALNIZCA ALTTA ve TAM 1px. İki ayrı gerekçe:
        //
        //  1) Flutter, FARKLI RENKLİ kenarları olan bir Border ile
        //     borderRadius'u kabul etmiyor ("A borderRadius can only be
        //     given on borders with uniform colors"). Çukur hissi bu yüzden
        //     kenardan değil, yukarıdaki gradyandan geliyor.
        //  2) Kalınlık, yerleşim motorundaki OkeyBoardLayout.meldBorderWidth
        //     ile AYNI olmalı. Border.all(0.8) denendiğinde motor her satırı
        //     0.6px eksik sanıp "sığdı" diyordu ve tahta gerçekte 1.8px
        //     taşıyordu.
        border: const Border(bottom: BorderSide(color: Color(0x1FFFFFFF))),
      ),
      foregroundDecoration: onTap == null
          ? null
          : BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: Colors.lightGreenAccent, width: 1.6),
            ),
      child: tiles,
    );

    // DİKKAT: her katman AYRI final değişkende — `x = DragTarget(... => x)`
    // yazımı widget'ı sonsuz kez kendi içine gömer.
    final Widget tappable = onTap == null
        ? content
        : GestureDetector(onTap: onTap, child: content);

    final bool accepts = onTileDropped != null;
    return DragTarget<OkeyDragPayload>(
      onWillAcceptWithDetails: (d) => accepts && d.data.isFromRack,
      onAcceptWithDetails: (d) {
        onTileDropped?.call(d.data.slotIndex);
        onDragEnd?.call();
      },
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        // Düz renk sıçraması yerine yumuşak geçiş + hafif büyüme — taşın
        // gerçekten "kabul edileceği" hissi verir.
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          transform: hovering
              ? (Matrix4.identity()..scaleByDouble(1.04, 1.04, 1.0, 1.0))
              : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovering
                ? Colors.lightGreenAccent.withValues(alpha: 0.25)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: tappable,
        );
      },
    );
  }
}

/// Perin ucundaki BOŞ hücre — "buraya bir taş gelebilir".
///
/// İçi boş bir kutu değil, hafifçe çökmüş ve kesikli kenarlı bir yuva:
/// taşların oturduğu dolu hücrelerden ilk bakışta ayrılır ama aynı ızgaraya
/// aittir.
class _EmptyCell extends StatelessWidget {
  final double width;
  final double height;

  const _EmptyCell({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Padding(
        padding: EdgeInsets.all(width * 0.10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x2B000000),
            borderRadius: BorderRadius.circular((width * 0.15).clamp(2.0, 7.0)),
            border: Border.all(color: const Color(0x33FFFFFF), width: 1),
          ),
          child: Center(
            child: Icon(
              Icons.add,
              size: width * 0.42,
              color: const Color(0x40FFFFFF),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bir perin arkasındaki hücre çizgileri.
class _MeldGridPainter extends CustomPainter {
  final double cellWidth;
  final int cells;

  const _MeldGridPainter({required this.cellWidth, required this.cells});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || cells < 2 || cellWidth <= 0) return;
    final paint = Paint()
      ..strokeWidth = 1
      ..color = const Color(0x14FFFFFF);
    for (var i = 1; i < cells; i++) {
      final x = cellWidth * i;
      if (x >= size.width) break;
      canvas.drawLine(Offset(x, 1), Offset(x, size.height - 1), paint);
    }
  }

  @override
  bool shouldRepaint(_MeldGridPainter oldDelegate) =>
      oldDelegate.cellWidth != cellWidth || oldDelegate.cells != cells;
}

/// Masadaki ızgara deseni.
///
/// KULLANICI İSTEĞİ: taşlar düz masaya (keçeye) yatıyor — üzerlerindeki
/// ızgara/tablo çizgileri kaldırıldı. Bu sınıf ve [okeyBoardGridKey] YİNE DE
/// duruyor (boş bir CustomPaint olarak): hizalama regresyon testi bu widget'ı
/// ANAHTARIYLA bulup ölçüm yapıyor — anahtar/konum kalmalı, sadece çizgiler
/// gitmeli.
class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Kasıtlı olarak boş — bkz. sınıf yorumu.
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}
