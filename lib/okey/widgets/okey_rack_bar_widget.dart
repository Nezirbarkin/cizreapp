import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/okey_rack_layout.dart';
import '../engine/okey_tile.dart';
import '../theme/okey_rack_style.dart';
import '../theme/okey_theme.dart';
import 'okey_drag_payload.dart';
import 'okey_rack_chrome.dart';
import 'okey_table_metrics.dart';
import 'okey_tile_widget.dart';

/// Ekranın altındaki ahşap ıstaka. Sabit sayıda "slot"tan oluşur: bir slot ya
/// taş tutar ya da boştur. Boş slotlar, SERİ DİZ / ÇİFT DİZ sonrası gruplar
/// arasındaki ayırıcı boşluklardır (ör. `1 2 3 4 _ 11 11 11`).
///
/// Taşlar sürüklenerek başka bir slota taşınabilir (hedef doluysa yer
/// değiştirir). Sürükleme başlarken [onDragStart], bitince [onDragEnd]
/// çağrılır — bu süre boyunca provider yeniden çizim bildirimlerini erteler,
/// böylece realtime bir güncelleme sürükleme katmanıyla çakışmaz.
class OkeyRackBarWidget extends StatelessWidget {
  final List<OkeyTile?> slots;
  final Set<int> selectedIndices;
  final bool canSelect;
  final bool canDrag;
  final void Function(int slotIndex) onTap;
  final void Function(int from, int to) onMove;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  /// Desteden/ıskartadan sürüklenen taş ıstakaya bırakıldığında çağrılır.
  final void Function(OkeyDragSource source, int toSlot)? onDrawDropped;

  /// Yardımlı mod ipuçları (slot indeksleri).
  final Set<int> processableIndices;
  final Set<int> meldableIndices;

  /// ATILIRSA +101 CEZA yazacak ("işlek") taşların slotları. Yardımlı moda
  /// bağlı DEĞİLDİR: ipucu değil, bedel uyarısıdır.
  final Set<int> riskyIndices;

  /// OTOMATİK sayılan geçerli per/grup/çiftin parçası olan slotlar.
  final Set<int> completeMeldSlots;

  /// Bir perin/grubun SON slotu olan indeksler — bunlardan SONRA küçük bir
  /// boşluk bırakılır, böylece perler gözle ayırt edilir.
  final Set<int> groupEndSlots;

  /// KAPALI (arkası dönük) gösterilecek okey taşlarının slotları.
  /// Çift basınca açılır — bkz. [onDoubleTap].
  final Set<int> hiddenOkeySlots;
  final void Function(int slotIndex)? onDoubleTap;

  /// Ekrandan hesaplanan ölçüler (satır yüksekliği buradan gelir).
  final OkeyTableMetrics? metrics;

  /// Kendi ahşap gövdesini (gradyan + üst kenarlık + dolgu) çizsin mi?
  ///
  /// false ise bunları SARAN [OkeyRackPanel] üstlenir — böylece ÇİFT DİZ /
  /// SERİ DİZ düğmeleri de aynı ahşabın ÜSTÜNDE durur. Varsayılan true:
  /// bu widget'ı tek başına kuran testler ve çağrılar etkilenmez.
  final bool showChrome;

  const OkeyRackBarWidget({
    super.key,
    required this.slots,
    required this.selectedIndices,
    required this.onTap,
    required this.onMove,
    this.canSelect = true,
    this.canDrag = true,
    this.onDragStart,
    this.onDragEnd,
    this.onDrawDropped,
    this.processableIndices = const {},
    this.meldableIndices = const {},
    this.riskyIndices = const {},
    this.completeMeldSlots = const {},
    this.groupEndSlots = const {},
    this.hiddenOkeySlots = const {},
    this.onDoubleTap,
    this.metrics,
    this.showChrome = true,
  });

  @override
  Widget build(BuildContext context) {
    // Istaka KENDİ kısıtına uyar: [metrics] bir tercih olarak kullanılır ama
    // gerçekte verilen yükseklik daha küçükse satır yüksekliği ona göre
    // kısılır. Böylece ıstaka, metrics verilmeden veya beklenmedik bir
    // kutuda kullanıldığında da kendi içinde taşmaz.
    return LayoutBuilder(
      builder: (context, constraints) {
        var rowH = metrics?.rackRowHeight ?? 44.0;
        if (constraints.hasBoundedHeight && constraints.maxHeight.isFinite) {
          // Kendi gövdesini çizmiyorsa üst kenarlık ve dikey dolgu ZATEN
          // sarmalayıcı panel tarafından tüketilmiştir; burada yalnızca iki
          // satır arasındaki boşluk düşülür. İki kez düşülseydi satırlar
          // gereksiz yere kısalır, taşlar oranını korumak için incelirdi.
          final chrome = showChrome
              ? OkeyTableMetrics.rackChrome
              : okeyRackRowGap;
          final maxRow = (constraints.maxHeight - chrome) / 2;
          if (maxRow > 0 && rowH > maxRow) rowH = maxRow;
        }
        // Tavan, ölçü sözleşmesindeki tavanla AYNI olmalı: burada 46'da
        // kalınca ıstaka, metrics 62px'lik bir satır hesapladığında bile
        // 46'ya kırpılıyor ve tam genişlik ıstakanın tüm kazancı çöpe
        // gidiyordu (taşlar küçük kalıyor, gövde ortada boş uzuyordu).
        return _buildRack(rowH.clamp(10.0, 68.0).toDouble());
      },
    );
  }

  Widget _buildRack(double rowHeight) {
    const perRow = OkeyRackLayout.slotsPerRow;
    // GÖVDE, taş satırlarının ALTINDA ve dolgunun DIŞINDA durmalı: painter
    // ıstakanın tamamını (üst pah, ara raf, ön çıta) çizer, oysa satırlar o
    // şeritlerin arasına yerleşir. Bu yüzden dolgu Container'ın değil,
    // Stack'in İÇİNDEKİ satırların işidir.
    const chromePadding = EdgeInsets.fromLTRB(
      4,
      okeyRackTopBorder + okeyRackVerticalPadding,
      4,
      okeyRackLedgeHeight + okeyRackVerticalPadding,
    );

    return Stack(
      children: [
        // Kendi gövdesini çizen yol (ıstaka tek başına kurulduğunda) da AYNI
        // painter'ı kullanır — iki farklı ıstaka görüntüsü olmasın. Eskiden
        // burada düz bir gradyan vardı ve tek başına kurulan ıstaka, masadaki
        // takozdan bambaşka görünüyordu.
        if (showChrome)
          Positioned.fill(
            child: RepaintBoundary(
              child: IgnorePointer(
                child: ValueListenableBuilder<OkeyRackStyle>(
                  valueListenable: OkeyRackStylePrefs.instance.current,
                  builder: (context, style, _) => CustomPaint(
                    painter: OkeyRackBodyPainter(
                      style: style,
                      tileContactHeight:
                          okeyRackTopBorder + okeyRackVerticalPadding,
                      lipHeight: okeyRackLedgeHeight + okeyRackVerticalPadding,
                      rowGap: okeyRackRowGap,
                    ),
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: showChrome ? chromePadding : EdgeInsets.zero,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(OkeyRackLayout.rowCount, (row) {
              return Padding(
                padding: EdgeInsets.only(top: row == 0 ? 0 : okeyRackRowGap),
                // REPAINT SINIRI — bir satırdaki taş hareketi ÖTEKİ satırı
                // (ve altındaki ahşap gövdeyi) yeniden boyamaya zorlamasın.
                // Bir taşı seçmek 16 taşlık tek bir satırı ilgilendirir;
                // sınırsız halde ıstakanın tamamı + gövde painter'ı yeniden
                // boyanıyordu.
                child: RepaintBoundary(
                  child: _RackRow(
                    startIndex: row * perRow,
                    count: perRow,
                    slots: slots,
                    selectedIndices: selectedIndices,
                    canSelect: canSelect,
                    canDrag: canDrag,
                    onTap: onTap,
                    onMove: onMove,
                    onDragStart: onDragStart,
                    onDragEnd: onDragEnd,
                    onDrawDropped: onDrawDropped,
                    processableIndices: processableIndices,
                    meldableIndices: meldableIndices,
                    riskyIndices: riskyIndices,
                    completeMeldSlots: completeMeldSlots,
                    groupEndSlots: groupEndSlots,
                    hiddenOkeySlots: hiddenOkeySlots,
                    onDoubleTap: onDoubleTap,
                    rowHeight: rowHeight,
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _RackRow extends StatelessWidget {
  final int startIndex;
  final int count;
  final List<OkeyTile?> slots;
  final Set<int> selectedIndices;
  final bool canSelect;
  final bool canDrag;
  final void Function(int slotIndex) onTap;
  final void Function(int from, int to) onMove;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;
  final void Function(OkeyDragSource source, int toSlot)? onDrawDropped;
  final Set<int> processableIndices;
  final Set<int> meldableIndices;
  final Set<int> riskyIndices;
  final Set<int> completeMeldSlots;
  final Set<int> groupEndSlots;
  final Set<int> hiddenOkeySlots;
  final void Function(int slotIndex)? onDoubleTap;
  final double rowHeight;

  const _RackRow({
    required this.startIndex,
    required this.count,
    required this.slots,
    required this.selectedIndices,
    required this.canSelect,
    required this.canDrag,
    required this.onTap,
    required this.onMove,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onDrawDropped,
    required this.processableIndices,
    required this.meldableIndices,
    required this.riskyIndices,
    required this.completeMeldSlots,
    required this.groupEndSlots,
    required this.hiddenOkeySlots,
    required this.onDoubleTap,
    required this.rowHeight,
  });

  @override
  Widget build(BuildContext context) {
    // KAYDIRMA YOK — slotlar mevcut genişliği eşit paylaşır.
    //
    // Önce yatay bir SingleChildScrollView vardı. İki sorun çıkarıyordu:
    //  1) Yatay kaydırma jesti, taşı sürükleme jestiyle AYNI arenada
    //     yarışıyor; parmak yavaş hareket ettiğinde kaydırma kazanıp taş hiç
    //     kalkmıyordu (kullanıcı: "taş bırakılmıyor").
    //  2) Istakanın bir kısmı ekran dışında kalabiliyordu.
    // Artık taşlar daralarak sığar; ıstakanın tamamı her zaman görünür.
    // Slot genişliği burada HESAPLANIR ve taşa aynen verilir; böylece taşlar
    // birbirine bitişik durur. Expanded + sabit taş genişliği kombinasyonu,
    // taşı slotun ortasında yüzdürüp aralarında boşluk bırakıyordu.
    return SizedBox(
      height: rowHeight,
      child: LayoutBuilder(
        builder: (context, c) {
          final slotW = c.hasBoundedWidth && c.maxWidth > 0
              ? c.maxWidth / count
              : 30.0;
          return Row(
            children: List.generate(count, (i) {
              final slotIndex = startIndex + i;
              final tile = slotIndex < slots.length ? slots[slotIndex] : null;
              // Expanded + AÇIK ölçü birlikte kullanılır:
              //  * Expanded: 16 slotun toplamı genişliği ASLA aşamaz
              //    (yuvarlama hatası taşma yaratmaz),
              //  * açık ölçü: taş slotu tam doldurur, aralarında boşluk kalmaz.
              return Expanded(
                child: _RackSlot(
                  slotWidth: slotW,
                  slotHeight: rowHeight,
                  slotIndex: slotIndex,
                  tile: tile,
                  selected: selectedIndices.contains(slotIndex),
                  canSelect: canSelect,
                  canDrag: canDrag,
                  hintProcessable: processableIndices.contains(slotIndex),
                  hintMeldable: meldableIndices.contains(slotIndex),
                  hintRisky: riskyIndices.contains(slotIndex),
                  inCompleteMeld: completeMeldSlots.contains(slotIndex),
                  endsGroup: groupEndSlots.contains(slotIndex),
                  hiddenOkey: hiddenOkeySlots.contains(slotIndex),
                  onDoubleTap: onDoubleTap,
                  onTap: onTap,
                  onMove: onMove,
                  onDragStart: onDragStart,
                  onDragEnd: onDragEnd,
                  onDrawDropped: onDrawDropped,
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

/// Tek bir ıstaka slotu: taş varsa sürüklenebilir, her durumda bırakma hedefi.
class _RackSlot extends StatelessWidget {
  /// Bu slotun TAM ölçüsü — taş bu ölçüde çizilir, böylece aralarında
  /// görünür boşluk kalmaz. (Sabit taş genişliği + Expanded kombinasyonu
  /// taşı slotun ortasında yüzdürüp boşluk bırakıyordu.)
  final double slotWidth;
  final double slotHeight;

  final int slotIndex;
  final OkeyTile? tile;
  final bool selected;
  final bool canSelect;
  final bool canDrag;
  final bool hintProcessable;
  final bool hintMeldable;
  final bool hintRisky;
  final bool inCompleteMeld;

  /// Bu slot bir perin SON taşı mı? Öyleyse sağına küçük bir boşluk konur.
  final bool endsGroup;

  /// Bu slottaki taş okey ve KAPALI gösterilecek (çift basınca açılır).
  final bool hiddenOkey;
  final void Function(int slotIndex)? onDoubleTap;
  final void Function(int slotIndex) onTap;
  final void Function(int from, int to) onMove;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;
  final void Function(OkeyDragSource source, int toSlot)? onDrawDropped;

  const _RackSlot({
    required this.slotWidth,
    required this.slotHeight,
    required this.slotIndex,
    required this.tile,
    required this.selected,
    required this.canSelect,
    required this.canDrag,
    required this.hintProcessable,
    required this.hintMeldable,
    required this.hintRisky,
    required this.inCompleteMeld,
    required this.endsGroup,
    required this.hiddenOkey,
    required this.onDoubleTap,
    required this.onTap,
    required this.onMove,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onDrawDropped,
  });

  @override
  Widget build(BuildContext context) {
    final t = tile;
    final dragEnabled = t != null && canDrag;

    // BOŞ SLOT: hiçbir iz bırakmaz — ıstaka sade ahşap olarak görünür.
    // (Önce koyu bir "oyuk" çiziliyordu; ıstaka boş kart izleriyle dolu
    // görünüyordu. Slot yine de aynı yeri kaplar, çünkü taşlar arasındaki
    // grup boşlukları bu genişlikten oluşur ve sürükleme hedefi olarak
    // çalışmaya devam eder.)
    // Slot artık SABİT GENİŞLİKTE DEĞİL: Expanded içinde mevcut genişliği
    // paylaşır ve taş, FittedBox ile o genişliğe küçülerek sığar. Böylece
    // ıstaka yatay kaydırmaya (ve onun sürüklemeyle çakışmasına) gerek
    // duymadan her ekrana sığar.
    // PER ARASI BOŞLUK: bir perin son taşının sağında küçük bir pay bırakılır.
    // Boşluk, slotun kendisinden değil TAŞIN genişliğinden alınır — böylece
    // slot ızgarası (ve dolayısıyla sürükle-bırak hedefleri) kaymaz.
    const groupGap = 5.0;
    final tileW = endsGroup
        ? (slotWidth - groupGap).clamp(8.0, slotWidth)
        : slotWidth;

    final Widget visual = t == null
        ? Container(
            width: slotWidth,
            height: slotHeight,
            // Şeffaf ama BOYANAN bir kutu: görünmez olmasına rağmen dokunma
            // ve sürükle-bırak testlerine yakalanır. Tamamen boş bir SizedBox
            // hit-test almaz ve boş slota taş bırakılamaz hale gelirdi.
            color: Colors.transparent,
          )
        : (hiddenOkey
              // Okey taşı kapalı (arkası dönük) — çift basınca açılır
              ? OkeyTileWidget(
                  tile: t,
                  small: true,
                  tight: true,
                  width: tileW,
                  height: slotHeight,
                  faceDown: true,
                  selected: selected,
                  // Seçim geçişi YALNIZCA ıstakada anlamlı — masadaki ve
                  // ıskartadaki taşlar hiç seçilmez (bkz. animateSelection).
                  animateSelection: true,
                )
              : OkeyTileWidget(
                  tile: t,
                  selected: selected,
                  small: true,
                  tight: true,
                  width: tileW,
                  height: slotHeight,
                  hintProcessable: hintProcessable,
                  hintMeldable: hintMeldable,
                  hintRisky: hintRisky,
                  inCompleteMeld: inCompleteMeld,
                  animateSelection: true,
                ));

    // Taş slotun soluna yaslanır; artan pay sağda boşluk olarak kalır.
    final Widget aligned = SizedBox(
      width: slotWidth,
      height: slotHeight,
      child: Align(alignment: Alignment.centerLeft, child: visual),
    );

    final Widget tappable = GestureDetector(
      onTap: (t != null && canSelect) ? () => onTap(slotIndex) : null,
      // ÇİFT BASMA: kapalı okey taşını açar/kapatır
      onDoubleTap: (t != null && onDoubleTap != null)
          ? () => onDoubleTap!(slotIndex)
          : null,
      child: aligned,
    );

    // KRİTİK: Draggable ve DragTarget HER ZAMAN ağaçta durur; koşula göre
    // yalnızca ETKİNLİKLERİ değişir (maxSimultaneousDrags / onWillAccept).
    //
    // Neden: bu widget'lar StatefulWidget'tır. Koşullu olarak ağaca eklenip
    // çıkarılırlarsa, her yeniden kurulumda yeni bir StatefulElement mount
    // edilir. Bu mount bir başka build sürerken denk gelirse Flutter'ın
    // "aynı anda tek build hedefi" değişmezi bozuluyor
    // ('owner!._debugCurrentBuildTarget == this' assertion hatası).
    // Yapıyı sabit tutmak bu hata sınıfını tamamen ortadan kaldırır.
    // Uzun basma YOK: taş doğrudan tutulup sürüklenir (çift dokunma gerekmez).
    final Widget draggable = Draggable<OkeyDragPayload>(
      data: OkeyDragPayload.rack(slotIndex),
      maxSimultaneousDrags: dragEnabled ? 1 : 0,
      onDragStarted: onDragStart,
      onDraggableCanceled: (_, __) => onDragEnd?.call(),
      onDragEnd: (_) => onDragEnd?.call(),
      feedback: Material(
        color: Colors.transparent,
        child: t == null
            ? const SizedBox.shrink()
            : OkeyTileWidget(tile: t, selected: true),
      ),
      childWhenDragging: Opacity(opacity: 0.25, child: tappable),
      child: tappable,
    );

    return DragTarget<OkeyDragPayload>(
      onWillAcceptWithDetails: (d) =>
          d.data.isDraw || d.data.slotIndex != slotIndex,
      onAcceptWithDetails: (d) {
        if (d.data.isDraw) {
          // Taş, oyuncunun BIRAKTIĞI slota yerleşsin
          onDrawDropped?.call(d.data.source, slotIndex);
        } else {
          onMove(d.data.slotIndex, slotIndex);
        }
        onDragEnd?.call();
      },
      builder: (context, candidate, rejected) {
        if (candidate.isEmpty) return draggable;
        // Bırakma hedefi vurgusu — implicit animasyon KASITLI OLARAK
        // KULLANILMAZ: sürükleme sırasında aynı anda 32 slot da DragTarget,
        // parmak üzerlerinden geçerken hepsi build ediliyor — AnimatedContainer
        // her biri için bir AnimationController kurup söküyor olurdu ve tam
        // da performansın en kritik olduğu anda (aktif sürükleme) ek yük
        // bindirirdi. Düz ama daha belirgin bir altın çerçeve/dolgu tercih
        // edildi.
        return Container(
          decoration: BoxDecoration(
            color: OkeyColors.accentGold.withValues(alpha: 0.28),
            border: Border.all(color: OkeyColors.accentGold, width: 1.5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: draggable,
        );
      },
    );
  }
}

/// ISTAKANIN TAMAMI — ahşap gövde + iki taş satırı.
///
/// ## v3: ıstaka artık alt şeridin TAMAMI
///
/// Eskiden bu panelin iki yanında kimlik kartım ve DİZ düğmeleri vardı;
/// ıstaka ekranın ancak %70'ini alabiliyor, taşlar o yüzden küçük kalıyordu.
/// v3'te o kontroller keçenin alt kenarındaki konsola taşındı ve ıstaka
/// ekranın tamamına yayıldı — 892x412'de taş genişliği 38px'ten ~48px'e
/// çıktı.
///
/// ## Gövde neden CustomPaint
///
/// Ahşabın inandırıcılığı tek bir gradyandan gelmiyor; üst üste binen dört
/// şeyden geliyor: (1) dikey gradyan, (2) üst kenardaki cila çizgisi,
/// (3) taşların dibindeki temas gölgesi, (4) öne çıkan alt dudak. Bunları
/// iç içe Container'larla kurmak hem daha pahalı hem de her birine ayrı
/// padding hesabı gerektirir; tek bir painter hepsini bir geçişte çizer ve
/// [RepaintBoundary] sayesinde taş her hareket ettiğinde yeniden boyanmaz.
class OkeyRackPanel extends StatelessWidget {
  final Widget rack;

  const OkeyRackPanel({super.key, required this.rack});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // GÖVDE, SEÇİLİ TAKOZDAN gelir (kullanıcı isteği, 2026-09-07).
        // Tercih maçın değil kullanıcının ayarı olduğu için provider'dan
        // değil, doğrudan OkeyRackStylePrefs'ten dinlenir — masaya girmeden
        // (bekleme odası, önizleme) de aynı ıstaka görünür.
        Positioned.fill(
          child: RepaintBoundary(
            child: IgnorePointer(
              child: ValueListenableBuilder<OkeyRackStyle>(
                valueListenable: OkeyRackStylePrefs.instance.current,
                builder: (context, style, _) => CustomPaint(
                  painter: OkeyRackBodyPainter(
                    style: style,
                    // Ölçüler ıstakanın geometri sabitlerinden gelir; painter
                    // kendi başına ölçü uydurmaz, yoksa gövdedeki temas
                    // gölgesi taşların gerçek dibinden ayrışırdı.
                    tileContactHeight:
                        okeyRackTopBorder + okeyRackVerticalPadding,
                    lipHeight: okeyRackLedgeHeight + okeyRackVerticalPadding,
                    // ARA RAF: iki taş sırasının arasındaki kademe. Painter
                    // bunu bilmeden ıstaka tek katlı bir tahta gibi kalırdı.
                    rowGap: okeyRackRowGap,
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            6,
            okeyRackVerticalPadding + okeyRackTopBorder,
            6,
            okeyRackVerticalPadding + okeyRackLedgeHeight,
          ),
          child: rack,
        ),
      ],
    );
  }
}

/// NOT — ISTAKA GÖVDESİ ARTIK BURADA ÇİZİLMİYOR.
///
/// Gövde (ahşap/grafit gradyan, damar, cila, ön dudak) 2026-09-07'de
/// `theme/okey_rack_style.dart` içindeki [OkeyRackBodyPainter]'a taşındı:
/// kullanıcı ayarlardan takozunu değiştirebildiği için çizim artık tek bir
/// sabit palete bağlı değil. Geometri sabitleri (üst kenarlık, dikey dolgu,
/// dudak yüksekliği) hâlâ `okey_rack_chrome.dart` içinde ve painter'a
/// dışarıdan verilir — ölçü tek kaynakta kalsın diye.
