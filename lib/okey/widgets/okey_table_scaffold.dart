import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/okey_theme.dart';
import 'okey_meld_bay.dart';
import 'okey_table_metrics.dart';

/// Masa alanının ölçüleriyle bir parça inşa eden fonksiyon.
typedef OkeyTablePart = Widget Function(BuildContext, OkeyTableMetrics);

/// 101 Okey masasının SAF YERLEŞİMİ — provider, model veya Supabase bilmez.
///
/// ## DÜZEN v4 (2026-09) — referans masa
///
/// ```
///  ┌──────────────────────── üst şerit ───────────────────────────────┐
///  │ [🪙 4.500][BONUS AL]     ● KARŞIDAKİ ●      [SATIN AL][💬][⌄]   │
///  ├───┬──────────────────────────────┬──────┬──────┬───┬────────────┤
///  │ ▭ │                              │ Tek  │      │ ▭ │            │
///  │ ▐ │      A Ç I L A N   P E R     │Yardım│ ek   │ ▐ │            │
///  │ S │        (geniş bölme)         │Katla.│bölme │ A │            │
///  │ O │                              │ 1 El │      │ Ğ │            │
///  │ L │                              │ ▭ ▭  │      │   │            │
///  │ ▭ │                              │  16  │      │ ▭ │            │
///  ├───┴──────────────────────────────┴──────┴──────┴───┴────────────┤
///  │ [SERİ AÇ][ÇİFT AÇ][İŞLE][AT]     ● BEN ● (0)                    │
///  ├──────────────────────────── süre ───────────────────────────────┤
///  │ [ÇİFT DİZ]████████ I S T A K A M ████████[SERİ DİZ]             │
///  └──────────────────────────────────────────────────────────────────┘
/// ```
///
/// ## v3'ten farkı ve NEDENİ
///
/// 1. **Iskartalar KÖŞELERE taşındı.** Artık her ıskarta, onu ATAN ile onu
///    ALAN oyuncunun ARASINDAKİ köşede durur: sol alt = solumdakinin attığı
///    (ben çekerim), sağ alt = benim attığım (sağımdaki çeker), sağ üst =
///    sağımdakinin attığı, sol üst = karşımdakinin attığı. Yerleşimin
///    kendisi oyunun yönünü anlatır; v3'te ıskartalar kartların yanındaydı
///    ve kimin kimden çektiği yalnızca renkten okunuyordu.
///
/// 2. **Dizme düğmeleri ıstakanın iki ucuna geçti.** ÇİFT DİZ / SERİ DİZ
///    ıstakayı yeniden dizer; ıstakadan uzakta, hamle düğmelerinin arasında
///    durmaları hem yanlış komşuluk hem de boşa giden konsol alanıydı.
///
/// 3. **Ahşap ray ve keçe kalktı.** Zemin artık tek parça ornamentli koyu
///    mavi bir yüzey; perler onun İÇİNE oyulmuş koyu tablalara serilir
///    (bkz. [OkeyMeldBay]).
///
/// ## Neden Column + SizedBox (sürprizsiz kutular)
///
/// Row/Column'da bir çocuk doğal genişliğini isterse kardeşlerini ezer ve
/// Flutter bunu ancak ÇALIŞMA ANINDA "overflowed by N pixels" diye bildirir.
/// Burada her bölge [OkeyTableMetrics]'ten AÇIK bir kutu ölçüsü alır;
/// kutuların toplamı tanım gereği ekranı geçmez, kutunun İÇİ sığmazsa
/// FittedBox küçültür. Taşma bir kaza değil, yapısal olarak imkânsızdır.
///
/// ## KRİTİK KURAL
///
/// Iskarta kutuları HİÇBİR KOŞULDA gizlenmez. O kutular aynı zamanda taş
/// çekme/atma için bırakma hedefidir; yer kazanmak uğruna gizlenirlerse
/// oyun oynanamaz hale gelir.
class OkeyTableScaffold extends StatelessWidget {
  /// Yerleşimi ETKİLEMEYEN, üste binen hata şeridi (yoksa null).
  final Widget? errorBanner;

  /// Karşıdaki oyuncunun kimlik plakası — üst şeridin ortasında.
  final OkeyTablePart seatAcross;

  /// Soldaki oyuncunun DİKEY levhası — sol sütunun ortasında.
  final OkeyTablePart seatLeft;

  /// Sağdaki oyuncunun DİKEY levhası — sağ sütunun ortasında.
  final OkeyTablePart seatRight;

  /// Ben — konsolun ortasındaki kimlik plakam.
  final OkeyTablePart seatMine;

  /// SOL ÜST köşe: karşımdaki oyuncunun ıskartası.
  final OkeyTablePart cornerDiscardTopLeft;

  /// SOL ALT köşe: solumdaki oyuncunun ıskartası — taşı buradan çekerim.
  final OkeyTablePart cornerDiscardBottomLeft;

  /// SAĞ ÜST köşe: sağımdaki oyuncunun ıskartası.
  final OkeyTablePart cornerDiscardTopRight;

  /// SAĞ ALT köşe: kendi ıskartam — taşı buraya atarım.
  final OkeyTablePart myDiscard;

  /// Gösterge → okey → deste sütunu (per alanının sağı).
  final OkeyTablePart island;

  /// Açılan SERİ ve GRUPLAR — geniş bölmeye serilir, ASLA kaydırılmaz.
  final OkeyTablePart melds;

  /// Açılan ÇİFTLER — bilgi sütununun sağındaki DAR bölme.
  ///
  /// Çiftler ayrı bir bölmede durur çünkü ayrı bir oyundur: çiftle açan
  /// oyuncu seri açamaz, çiftlere taş işlenmez ve ceza katsayısı farklıdır.
  /// Aynı tablaya karıştırıldıklarında masaya bakan oyuncu "şu pere şu taş
  /// gider mi" sorusunu yanıtlarken sürekli çiftleri eleme zahmetine
  /// giriyordu.
  final OkeyTablePart? pairsBoard;

  /// Hamle düğmeleri: SERİ AÇ / ÇİFT AÇ / İŞLE / TAŞI AT (konsolun solu).
  final OkeyTablePart actions;

  /// Alt şerit: ahşap ıstakam ve taşlarım.
  final OkeyTablePart rack;

  /// Istakanın SOL ucundaki dizme düğmesi (ÇİFT DİZ).
  final OkeyTablePart? rackCapStart;

  /// Istakanın SAĞ ucundaki dizme düğmesi (SERİ DİZ).
  final OkeyTablePart? rackCapEnd;

  /// Istakanın hemen ÜSTÜNDEKİ ince süre çizgisi.
  final OkeyTablePart? turnTimerBar;

  /// Mod rozetleri (Eşli / Katlamalı / Yardımlı / 3. El) — bilgi sütununun
  /// üstünde, DİKEY sıralanır.
  final Widget? modeBadges;

  /// Üst şeridin SOL ucu: altın sayacı ve bonus düğmesi.
  final Widget? topLeading;

  /// Üst şeridin SAĞ ucu: mağaza, sohbet, menü.
  final Widget? topControls;

  /// "Çifte gidiyorum" ve hazırlanan gruplar — konsolun sağ boşluğunda.
  final OkeyTablePart? bottomExtra;

  const OkeyTableScaffold({
    super.key,
    this.errorBanner,
    required this.seatAcross,
    required this.seatLeft,
    required this.seatRight,
    required this.seatMine,
    required this.cornerDiscardTopLeft,
    required this.cornerDiscardBottomLeft,
    required this.cornerDiscardTopRight,
    required this.myDiscard,
    required this.island,
    required this.melds,
    this.pairsBoard,
    required this.actions,
    required this.rack,
    this.rackCapStart,
    this.rackCapEnd,
    this.turnTimerBar,
    this.modeBadges,
    this.topLeading,
    this.topControls,
    this.bottomExtra,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final m = OkeyTableMetrics.from(constraints);

        return Stack(
          children: [
            Column(
              children: [
                SizedBox(
                  height: m.topStripHeight,
                  child: _TopStrip(metrics: m, scaffold: this),
                ),
                Expanded(
                  child: _Middle(metrics: m, scaffold: this),
                ),
                SizedBox(
                  height: m.consoleHeight,
                  child: _Console(metrics: m, scaffold: this),
                ),
                if (turnTimerBar != null)
                  Center(
                    child: SizedBox(
                      width: math.min(m.rackWidth, m.rackMaxWidth),
                      height: OkeyTableMetrics.timerBarHeight,
                      child: turnTimerBar!(context, m),
                    ),
                  )
                else
                  const SizedBox(height: OkeyTableMetrics.timerBarHeight),
                SizedBox(
                  height: m.rackHeight,
                  child: _RackStrip(metrics: m, scaffold: this),
                ),
              ],
            ),
            if (errorBanner != null)
              Positioned(top: 0, left: 0, right: 0, child: errorBanner!),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// ÜST ŞERİT
// ---------------------------------------------------------------------------

/// `[altın · bonus]  ·  [karşıdaki oyuncu]  ·  [mağaza · sohbet · menü]`
///
/// Üç bölge de esnek paylarla ölçülür (30/40/30) ve her biri kendi
/// FittedBox'ı içinde küçülür: en uzun oyuncu adı bile ortadaki payı aşamaz,
/// dolayısıyla yan gruplar hiç ezilmez.
class _TopStrip extends StatelessWidget {
  final OkeyTableMetrics metrics;
  final OkeyTableScaffold scaffold;

  const _TopStrip({required this.metrics, required this.scaffold});

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final s = scaffold;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OkeyTableMetrics.gap,
        3,
        OkeyTableMetrics.gap,
        1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 30,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: s.topLeading ?? const SizedBox.shrink(),
              ),
            ),
          ),
          Expanded(
            flex: 40,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: s.seatAcross(context, m),
              ),
            ),
          ),
          Expanded(
            flex: 30,
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: s.topControls ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ORTA BÖLGE
// ---------------------------------------------------------------------------

/// `[sol sütun] [geniş per bölmesi] [bilgi sütunu] [ek bölme] [sağ sütun]`
class _Middle extends StatelessWidget {
  final OkeyTableMetrics metrics;
  final OkeyTableScaffold scaffold;

  const _Middle({required this.metrics, required this.scaffold});

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final s = scaffold;

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        // Bölge ölçüleri GERÇEK kutudan kısılır: metrics ekranın tamamından
        // hesaplandığı için dolgu düşülünce burada birkaç piksel daha az yer
        // kalır. Kısmadan kullanılsaydı, dar ekranlarda sütunların toplamı
        // satırı aşabilirdi.
        final side = m.sidePodWidth.clamp(0.0, w * 0.16);
        final info = m.infoColumnWidth.clamp(0.0, w * 0.16);
        final mini = m.miniBayWidth.clamp(0.0, w * 0.13);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: OkeyTableMetrics.gap),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: side,
                child: _SideColumn(
                  metrics: m,
                  top: s.cornerDiscardTopLeft,
                  middle: s.seatLeft,
                  bottom: s.cornerDiscardBottomLeft,
                ),
              ),
              const SizedBox(width: OkeyTableMetrics.gap),
              Expanded(child: OkeyMeldBay(child: s.melds(context, m))),
              const SizedBox(width: OkeyTableMetrics.gap),
              SizedBox(
                width: info,
                child: _InfoColumn(metrics: m, scaffold: s),
              ),
              const SizedBox(width: OkeyTableMetrics.gap),
              SizedBox(
                width: mini,
                child: OkeyMeldBay(
                  watermark: false,
                  title: 'ÇİFTLER',
                  child: s.pairsBoard?.call(context, m) ?? const SizedBox(),
                ),
              ),
              const SizedBox(width: OkeyTableMetrics.gap),
              SizedBox(
                width: side,
                child: _SideColumn(
                  metrics: m,
                  top: s.cornerDiscardTopRight,
                  middle: s.seatRight,
                  bottom: s.myDiscard,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Bir kenar sütunu: üstte bir ıskarta, ortada dikey oyuncu levhası, altta
/// bir ıskarta.
///
/// Iskarta kutuları SABİT yükseklik alır ([OkeyTableMetrics.cornerBoxHeight]
/// karşılığı: taş yüksekliği + küçük bir pay) — böylece oyuncu levhası
/// aradaki tüm boşluğu alır ve masa yükseldikçe levha uzar, taşlar değil.
class _SideColumn extends StatelessWidget {
  final OkeyTableMetrics metrics;
  final OkeyTablePart top;
  final OkeyTablePart middle;
  final OkeyTablePart bottom;

  const _SideColumn({
    required this.metrics,
    required this.top,
    required this.middle,
    required this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final boxH = m.discardTileHeight + 6;

    return LayoutBuilder(
      builder: (context, c) {
        // Sütun çok kısaldığında (çok kısa ekran) ıskartalar sütunun en fazla
        // üçte birini alır; kalan levhanındır. Aksi halde levha sıfır
        // yüksekliğe düşüp görünmez olurdu.
        final cap = c.hasBoundedHeight && c.maxHeight.isFinite
            ? math.min(boxH, c.maxHeight * 0.36)
            : boxH;

        return Column(
          children: [
            SizedBox(
              height: cap,
              child: Align(
                alignment: Alignment.topCenter,
                child: FittedBox(fit: BoxFit.scaleDown, child: top(context, m)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: middle(context, m),
              ),
            ),
            SizedBox(
              height: cap,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: bottom(context, m),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Per alanının sağındaki bilgi sütunu: mod rozetleri (dikey) + gösterge /
/// okey / deste.
///
/// İki blok da [Flexible] + [FittedBox] ile sarılır: hangi ekranda olursak
/// olalım toplamları sütunu AŞAMAZ, yalnızca birlikte küçülürler.
class _InfoColumn extends StatelessWidget {
  final OkeyTableMetrics metrics;
  final OkeyTableScaffold scaffold;

  const _InfoColumn({required this.metrics, required this.scaffold});

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final s = scaffold;

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (s.modeBadges != null)
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: s.modeBadges!,
            ),
          ),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.bottomCenter,
            child: s.island(context, m),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// KONSOL
// ---------------------------------------------------------------------------

/// Masanın alt kenarındaki KONTROL ŞERİDİ.
///
/// `[SERİ AÇ][ÇİFT AÇ][İŞLE][TAŞI AT]  ·  ● BEN ● (skor)  ·  [ek içerik]`
///
/// Kendi ıskartam artık BURADA DEĞİL — sağ kenar sütununun dibinde, tam da
/// sağımdaki oyuncuyla aramdaki köşede (bkz. sınıf yorumu). Böylece hamle
/// düğmeleriyle bırakma hedefi arasındaki mesafe bir "güvenlik boşluğu"
/// olmaktan çıkıp masanın doğal genişliği kadar oldu: taş atarken yanlışlıkla
/// "ÇİFT AÇ"a basmak fiziksel olarak mümkün değil.
class _Console extends StatelessWidget {
  final OkeyTableMetrics metrics;
  final OkeyTableScaffold scaffold;

  const _Console({required this.metrics, required this.scaffold});

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final s = scaffold;

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final side = m.sidePodWidth.clamp(0.0, w * 0.16);

        return Padding(
          padding: const EdgeInsets.fromLTRB(
            OkeyTableMetrics.gap,
            2,
            OkeyTableMetrics.gap,
            2,
          ),
          child: Row(
            children: [
              // Kenar sütunlarıyla AYNI hizada başlar/biter: konsol masanın
              // altına çizilmiş ayrı bir şerit değil, aynı ızgaranın son
              // satırıdır.
              SizedBox(width: side),
              const SizedBox(width: OkeyTableMetrics.gap),
              Expanded(flex: 34, child: s.actions(context, m)),
              const SizedBox(width: OkeyTableMetrics.consoleGap),
              Expanded(
                flex: 30,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: s.seatMine(context, m),
                  ),
                ),
              ),
              const SizedBox(width: OkeyTableMetrics.consoleGap),
              Expanded(
                flex: 20,
                child: s.bottomExtra == null
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: s.bottomExtra!(context, m),
                        ),
                      ),
              ),
              const SizedBox(width: OkeyTableMetrics.gap),
              SizedBox(width: side),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// ISTAKA ŞERİDİ
// ---------------------------------------------------------------------------

/// `[ÇİFT DİZ] ████ ISTAKAM ████ [SERİ DİZ]`
///
/// ## Düğmeler ISTAKAYA YAPIŞIK durur (kullanıcı isteği, 2026-09-07:
/// "seri diz, çift diz takoza biraz daha yakınlaştır")
///
/// Önce düğmeler ekranın İKİ UCUNA, ıstaka ise ortaya yerleştiriliyordu.
/// Istaka gerçekte ekrandan dar olduğunda (taş satırı yükseklikten kısıldığı
/// her ekranda öyle olur) aradaki fark boşluk olarak düğmelerle ıstakanın
/// ARASINA düşüyor, "ıstakayı dizen düğme ıstakaya bitişiktir" fikri
/// bozuluyordu.
///
/// Artık ÜÇÜ BİRDEN tek bir grup olarak ortalanır: artan pay grubun dışına,
/// ekranın iki kenarına gider. Grup ekrandan geniş kalırsa (dar telefon)
/// ıstaka [rackMaxWidth] ile zaten kısılmıştır, yani taşma yapısal olarak
/// mümkün değil.
class _RackStrip extends StatelessWidget {
  final OkeyTableMetrics metrics;
  final OkeyTableScaffold scaffold;

  const _RackStrip({required this.metrics, required this.scaffold});

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final s = scaffold;
    final rackW = math.min(m.rackWidth, m.rackMaxWidth);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: m.rackCapWidth,
          child: s.rackCapStart?.call(context, m) ?? const SizedBox.shrink(),
        ),
        const SizedBox(width: OkeyTableMetrics.rackCapGap),
        SizedBox(width: rackW, child: s.rack(context, m)),
        const SizedBox(width: OkeyTableMetrics.rackCapGap),
        SizedBox(
          width: m.rackCapWidth,
          child: s.rackCapEnd?.call(context, m) ?? const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ORTAK PARÇALAR
// ---------------------------------------------------------------------------

/// Konsoldaki düğme satırları için ortak sarmalayıcı: eşit genişlikte
/// düğmeler, aralarında tek bir standart boşluk.
///
/// Ekranın kendi `Row(children: [Expanded, SizedBox, Expanded...])`
/// kalıbını tekrar tekrar yazmasını engeller — o kalıpta boşluk değerini
/// bir yerde 6, başka yerde 4 yazmak, düğmelerin farklı genişliklerde
/// çıkmasına yol açıyordu.
class OkeyButtonRow extends StatelessWidget {
  final List<Widget> children;
  final double gap;

  const OkeyButtonRow({super.key, required this.children, this.gap = 6});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

/// Masaya oturan koyu cam yüzey — oyuncu kartları, ada ve rozetler bunu
/// kullanır, böylece zeminin üstündeki her kutu aynı malzemeden görünür.
class OkeyGlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? borderColor;
  final Color? glow;

  const OkeyGlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
    this.radius = OkeyV3.radius,
    this.borderColor,
    this.glow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: OkeyV3.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? OkeyV3.border),
        boxShadow: [
          ...OkeyV3.lift,
          if (glow != null) BoxShadow(color: glow!, blurRadius: 12),
        ],
      ),
      child: child,
    );
  }
}
