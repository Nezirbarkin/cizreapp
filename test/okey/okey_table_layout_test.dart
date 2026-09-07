import 'package:cizreapp/okey/engine/okey_board_layout.dart';
import 'package:cizreapp/okey/engine/okey_rack_layout.dart';
import 'package:cizreapp/okey/engine/okey_seating.dart';
import 'package:cizreapp/okey/engine/okey_tile.dart';
import 'package:cizreapp/okey/models/okey_models.dart';
import 'package:cizreapp/okey/widgets/okey_action_panel_widget.dart';
import 'package:cizreapp/okey/widgets/okey_board_grid.dart';
import 'package:cizreapp/okey/widgets/okey_turn_timer_bar.dart';
import 'package:cizreapp/okey/widgets/okey_board_widget.dart';
import 'package:cizreapp/okey/widgets/okey_drag_payload.dart';
import 'package:cizreapp/okey/widgets/okey_hud_chrome.dart';
import 'package:cizreapp/okey/widgets/okey_indicator_widget.dart';
import 'package:cizreapp/okey/widgets/okey_rack_bar_widget.dart';
import 'package:cizreapp/okey/widgets/okey_tile_widget.dart';
import 'package:cizreapp/okey/widgets/okey_corner_pile_widget.dart';
import 'package:cizreapp/okey/widgets/okey_table_metrics.dart';
import 'package:cizreapp/okey/widgets/okey_table_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// MASA EKRANI — TAŞMA VE OTURMA DÜZENİ REGRESYON TESTLERİ
///
/// GEÇMİŞ HATALAR (hepsi gerçek cihazda kullanıcı tarafından bulundu):
///  1) Sabit piksel ölçüleri → kısa yatay ekranlarda taşma.
///  2) Ölçüler ekranın TAMAMINDAN hesaplanıyor, üstteki bantlar için sabit
///     18px pay bırakılıyordu. Sıra bandı + hata bandı bundan fazla yer
///     kaplayınca "overflowed by 41 pixels".
///  3) Oturma düzeni TERSTİ — ıskartasını aldığım oyuncu sağa çiziliyordu,
///     oyun ters yönde dönüyormuş gibi görünüyordu.
///
/// (2) NUMARALI HATAYI ÖNCEKİ TEST NEDEN KAÇIRDI:
/// Test, ekranın yerleşimini elle "taklit" ediyordu ve bantları hiç
/// içermiyordu. Yani gerçek bileşim değil, onun iyimser bir kopyası test
/// ediliyordu. Bu yüzden yerleşim artık [OkeyTableScaffold] içinde saf bir
/// widget olarak duruyor ve buradaki testler EKRANIN KULLANDIĞI DÜZENİN TA
/// KENDİSİNİ, bantlar dahil kuruyor.

/// Gerçek cihazlarda karşılaşılan yatay ekran boyutları (mantıksal piksel).
const _screens = <String, Size>{
  'çok kısa 640x320': Size(640, 320),
  'küçük telefon 640x360': Size(640, 360),
  'yaygın telefon 800x360': Size(800, 360),
  'uzun telefon 892x412': Size(892, 412),
  'büyük telefon 1067x480': Size(1067, 480),
  'tablet 1280x800': Size(1280, 800),
};

OkeyRoomSeat _seat(int seatNo) => OkeyRoomSeat(
  roomId: 'room-1',
  seatNo: seatNo,
  userId: 'user-$seatNo',
  isReady: true,
  isBot: false,
  // Uzun ad: taşırmaya en yatkın içerik
  displayName: 'ÇokUzunOyuncuAdıTaşmaTesti',
);

List<OkeyTile?> _fullRack() {
  final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
  var placed = 0;
  for (var i = 0; i < slots.length && placed < 21; i++) {
    if (i % 6 == 5) continue; // grup arası boşluk
    slots[i] = OkeyTile.numbered(
      OkeyColor.values[placed % 4],
      (placed % 13) + 1,
    );
    placed++;
  }
  return slots;
}

/// Süre çizgisinin beslendiği sayaç. Test genelinde tek bir örnek kullanılır
/// (her _table() çağrısında yenisini yaratıp dispose edememek sızıntı olurdu).
final _testSeconds = ValueNotifier<int>(12);

/// Üç taşlık bir seri (per) — tahta testlerinin ortak yapı taşı.
OkeyTableMeld _run(int id, OkeyColor color, int base) => OkeyTableMeld(
  id: id,
  matchId: 'm',
  laidBySeat: 0,
  meldType: 'run',
  tiles: [
    OkeyTile.numbered(color, base),
    OkeyTile.numbered(color, base + 1),
    OkeyTile.numbered(color, base + 2),
  ],
);

List<OkeyTableMeld> _sampleMelds() => [
  for (var i = 0; i < 5; i++)
    OkeyTableMeld(
      id: i,
      matchId: 'm',
      laidBySeat: i % 4,
      meldType: 'run',
      tiles: [
        OkeyTile.numbered(OkeyColor.values[i % 4], 3),
        OkeyTile.numbered(OkeyColor.values[i % 4], 4),
        OkeyTile.numbered(OkeyColor.values[i % 4], 5),
      ],
    ),
];

/// Ekranın gerçekte kurduğu masayı, aynı parçalarla inşa eder.
///
/// [withError] true ise hata bandı da eklenir — 41 piksellik taşmayı ortaya
/// çıkaran senaryo tam olarak buydu (iki bant birden).
///
/// GERÇEK üretim yerleşimini birebir yansıtır: mod rozetleri, HUD düğmeleri,
/// gösterge adası, iki per bölümü, 2x2 aksiyon ızgarası, "çifte gidiyorum"
/// çipi, süre çizgisi ve DİZ düğmeli ıstaka — hepsi ekrandaki gibi. İyimser
/// bir kopya değil: geçmişte bantları içermeyen bir taklit yüzünden 41
/// piksellik taşma bu testlerden kaçmıştı.
Widget _table({required bool withError}) {
  Widget seat(
    BuildContext context,
    OkeyTableMetrics m,
    int n,
    OkeySeatSide side, {
    bool isMe = false,
    OkeySeatParts parts = OkeySeatParts.both,
  }) => OkeyCornerPileWidget(
    size: m.discardTileWidth,
    avatarSize: m.avatarSize,
    side: side,
    parts: parts,
    maxWidth:
        (parts != OkeySeatParts.identity &&
            (side == OkeySeatSide.left || side == OkeySeatSide.right))
        ? m.sidePodWidth
        : null,
    seat: _seat(n),
    seatNo: n,
    topDiscard: OkeyTile.numbered(OkeyColor.red, 13),
    tileCount: 21,
    score: 202,
    isCurrentTurn: n == 1,
    isMe: isMe,
    isOpened: true,
    isDrawSource: n == 1 && parts == OkeySeatParts.discard,
    isDiscardTarget: isMe && parts == OkeySeatParts.discard,
  );

  return OkeyTableScaffold(
    errorBanner: withError
        ? Container(
            width: double.infinity,
            color: Colors.red,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: const Text(
              'Sunucu hatası: işlem tamamlanamadı, lütfen tekrar deneyin',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white, fontSize: 11),
            ),
          )
        : null,
    seatAcross: (c, m) =>
        seat(c, m, 2, OkeySeatSide.top, parts: OkeySeatParts.identity),
    seatLeft: (c, m) =>
        seat(c, m, 1, OkeySeatSide.left, parts: OkeySeatParts.identity),
    seatRight: (c, m) =>
        seat(c, m, 3, OkeySeatSide.right, parts: OkeySeatParts.identity),
    seatMine: (c, m) => Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        seat(
          c,
          m,
          0,
          OkeySeatSide.bottom,
          isMe: true,
          parts: OkeySeatParts.identity,
        ),
        const SizedBox(width: 6),
        OkeyScoreBubble(
          score: 202,
          height: (m.consoleHeight * 0.52).clamp(16.0, 28.0),
        ),
      ],
    ),
    // DÖRT KÖŞE = DÖRT ISKARTA (bkz. OkeyTableScaffold).
    cornerDiscardTopLeft: (c, m) =>
        seat(c, m, 2, OkeySeatSide.left, parts: OkeySeatParts.discard),
    cornerDiscardBottomLeft: (c, m) =>
        seat(c, m, 1, OkeySeatSide.left, parts: OkeySeatParts.discard),
    cornerDiscardTopRight: (c, m) =>
        seat(c, m, 3, OkeySeatSide.right, parts: OkeySeatParts.discard),
    myDiscard: (c, m) => seat(
      c,
      m,
      0,
      OkeySeatSide.right,
      isMe: true,
      parts: OkeySeatParts.discard,
    ),
    island: (c, m) => OkeyIndicatorWidget(
      vertical: true,
      indicatorTile: OkeyTile.numbered(OkeyColor.blue, 7),
      okeyTile: OkeyTile.numbered(OkeyColor.blue, 8),
      deckRemaining: 20,
      isMyTurn: true,
      canDragFromDeck: true,
      tileWidth: m.islandTileWidth,
    ),
    // AÇILAN PERLER TEK ALANDA (2026-09): ayrı "çiftler" bölmesi kaldırıldı,
    // perler keçenin tüm genişliğine serilir (bkz. OkeyTableScaffold.melds).
    melds: (c, m) => OkeyBoardWidget(
      melds: _sampleMelds(),
      tileWidth: m.meldTileWidth,
      tileHeight: m.meldTileHeight,
    ),
    modeBadges: const OkeyModeBadgeStack(
      items: [
        ('EŞLİ', Colors.lightBlueAccent),
        ('YARDIMLI', Colors.lightGreenAccent),
        ('KATLAMALI', Colors.redAccent),
        ('12. EL', Colors.white70),
      ],
    ),
    // ÜST ŞERİDİN İKİ UCU — gerçek ekrandaki en uzun içerikle kurulur:
    // altın sayacı beş haneli, bonus düğmesi geri sayım yazıyor.
    topLeading: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const OkeyCoinPill(amount: 128450, height: 26),
        const SizedBox(width: 6),
        // MASA PUANI çipi de üst şeritte durur (2026-09-05) ve en uzun
        // hâliyle kurulur: 10 el × 5000 = 50.000.
        const OkeyStakePill(stake: 50000, perHand: 5000, hands: 10, height: 26),
        const SizedBox(width: 6),
        OkeyHudActionButton.bonus(
          label: '59:12',
          height: 26,
          enabled: false,
          onTap: () {},
        ),
      ],
    ),
    topControls: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OkeyRoundIconButton(
          size: 26,
          icon: Icons.volume_up,
          tooltip: 'ses',
          onTap: () {},
        ),
        const SizedBox(width: 5),
        OkeyRoundIconButton(
          size: 26,
          icon: Icons.music_note,
          tooltip: 'müzik',
          onTap: () {},
        ),
        const SizedBox(width: 5),
        OkeyRoundIconButton(
          size: 26,
          icon: Icons.keyboard_arrow_down,
          tooltip: 'menü',
          onTap: () {},
        ),
      ],
    ),
    bottomExtra: (c, m) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      color: Colors.white10,
      child: const Text(
        'Çifte gidiyorum',
        style: TextStyle(fontSize: 10, color: Colors.white70),
      ),
    ),
    turnTimerBar: (c, m) => OkeyTurnTimerBar(
      secondsLeftListenable: _testSeconds,
      totalSeconds: 20,
      isMyTurn: true,
      height: OkeyTableMetrics.timerBarHeight,
    ),
    // KONSOLUN HAMLE SATIRI — gerçek ekrandaki en UZUN metinlerle, çünkü
    // taşma riski tam olarak orada.
    actions: (c, m) => const OkeyButtonRow(
      children: [
        OkeyActionButton(
          title: 'SERİ AÇ',
          icon: Icons.view_week,
          badge: '103/101',
          tone: OkeyActionTone.ready,
        ),
        OkeyActionButton(title: 'ÇİFT AÇ', icon: Icons.filter_2, badge: '3/5'),
        OkeyActionButton(title: 'İŞLE', icon: Icons.playlist_add, badge: '4'),
        OkeyActionButton(
          title: 'AT — BİTİR',
          icon: Icons.emoji_events,
          tone: OkeyActionTone.winning,
        ),
      ],
    ),
    // GERÇEK üretim yerleşimini birebir yansıtır: OkeyGameScreen'in rack
    // builder'ı iki ÇİFT/SERİ DİZ düğmesini ve ortalanmış genişlik sınırını
    // (rackMaxWidth) da içerir. Önceden burada yalnızca OkeyRackBarWidget
    // tek başına kuruluyordu — bu yüzden DizButton'ın kısa ekranlarda
    // taştığı gerçek bir regresyon (RenderFlex overflowed by 6.0 pixels)
    // bu test dosyası hiç yakalamadan üretime gitmişti.
    rack: (c, m) => OkeyRackPanel(
      rack: OkeyRackBarWidget(
        metrics: m,
        showChrome: false,
        slots: _fullRack(),
        selectedIndices: const {3},
        processableIndices: const {1, 2},
        completeMeldSlots: const {0, 1, 2},
        hiddenOkeySlots: const {6},
        onTap: (_) {},
        onMove: (_, _) {},
      ),
    ),
    // ÇİFT DİZ / SERİ DİZ artık ıstakanın İKİ UCUNDA. Üretimdeki yerleşimin
    // birebir aynısı kurulur: bu düğmeler kısa ekranlarda bir kez taşmıştı
    // (RenderFlex overflowed by 6.0 pixels) ve o regresyon ancak GERÇEK
    // bileşim test edildiğinde yakalanır.
    rackCapStart: (c, m) =>
        OkeyDizCapButton.pairs(active: true, onPressed: () {}),
    rackCapEnd: (c, m) =>
        OkeyDizCapButton.series(active: false, onPressed: () {}),
  );
}

Future<void> _pumpTable(
  WidgetTester tester,
  Size size, {
  required bool withError,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MaterialApp(
          home: Scaffold(
            backgroundColor: const Color(0xFF10495F),
            body: SafeArea(child: _table(withError: withError)),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('OkeySeating — sıra yönü ile görsel yön aynı olmalı', () {
    test('soldaki oyuncu sırada benden ÖNCEKİdir', () {
      for (var mySeat = 0; mySeat < 4; mySeat++) {
        final s = OkeySeating(mySeat);
        // Soldakinden sonra sıra BANA gelmeli
        expect(
          s.nextSeatAfter(s.leftSeat),
          mySeat,
          reason: 'koltuk $mySeat: soldaki, sırada benden önceki değil',
        );
      }
    });

    test('sağdaki oyuncu sırada benden SONRAKİdir', () {
      for (var mySeat = 0; mySeat < 4; mySeat++) {
        final s = OkeySeating(mySeat);
        expect(
          s.nextSeatAfter(mySeat),
          s.rightSeat,
          reason: 'koltuk $mySeat: sağdaki, sırada benden sonraki değil',
        );
      }
    });

    test('taş SOLDAKİ oyuncunun ıskartasından çekilir', () {
      for (var mySeat = 0; mySeat < 4; mySeat++) {
        final s = OkeySeating(mySeat);
        expect(s.drawSeat, s.leftSeat);
        // Ters yön hatasının kesin imzası: çekilen koltuk sağdaki OLMAMALI
        expect(
          s.drawSeat,
          isNot(s.rightSeat),
          reason: 'koltuk $mySeat: oyun ters yönde dönüyor',
        );
      }
    });

    test('dört koltuk birbirinden farklıdır ve hepsi kullanılır', () {
      for (var mySeat = 0; mySeat < 4; mySeat++) {
        final s = OkeySeating(mySeat);
        expect(
          {mySeat, s.leftSeat, s.acrossSeat, s.rightSeat},
          hasLength(4),
          reason: 'koltuk $mySeat: aynı oyuncu iki yere çiziliyor',
        );
      }
    });

    test('karşımdaki, iki hamle sonrakidir (eşli modda eşim)', () {
      for (var mySeat = 0; mySeat < 4; mySeat++) {
        final s = OkeySeating(mySeat);
        expect(s.nextSeatAfter(s.nextSeatAfter(mySeat)), s.acrossSeat);
      }
    });
  });

  group('OkeyTableMetrics — masa alanı aritmetiği', () {
    _screens.forEach((label, size) {
      test('$label — dikey bütçe kapalıdır', () {
        final m = OkeyTableMetrics.from(BoxConstraints.tight(size));

        expect(m.rackHeight, lessThanOrEqualTo(size.height));
        // Istaka alanın yarısından fazlasını asla almaz — masaya yer kalır
        expect(m.rackHeight, lessThanOrEqualTo(size.height * 0.5 + 0.01));
        // İki taş satırı + iç süsleme ıstakanın İÇİNE sığmalı
        expect(
          m.rackRowHeight * 2 + OkeyTableMetrics.rackChrome,
          lessThanOrEqualTo(m.rackHeight + 0.01),
          reason: '$label: ıstaka kendi içinde taşıyor',
        );
        // masa + süre çizgisi + ıstaka = ekran (tanım gereği)
        expect(
          m.boardAreaHeight + OkeyTableMetrics.timerBarHeight + m.rackHeight,
          closeTo(size.height, 0.01),
          reason: '$label: dikey bütçe kapanmıyor',
        );
        // Açılan perlere gerçekten yer kalmalı — üst/alt şeritler keçeyi
        // tamamen yiyip bitirirse masa oynanamaz hale gelir.
        expect(
          m.meldAreaHeight,
          greaterThan(m.meldTileHeight),
          reason: '$label: açılan perlere tek satır bile yer kalmıyor',
        );
        // Kenar oyuncuları ortadaki per alanını ezmemeli
        expect(m.sidePodWidth * 2, lessThan(size.width * 0.4));
        expect(m.rackHeight, greaterThan(0));
        expect(m.discardTileWidth, greaterThan(0));
      });

      // ---- ASIL DÜZELTİLEN HATA -------------------------------------------
      // Eski hesap ıstaka YÜKSEKLİĞİNİ ekrandan, taş GENİŞLİĞİNİ ise ondan
      // bağımsız türetiyordu. 892x412'de sonuç 34x24'lük taşlardı: eninden
      // yatık, gerçek bir okey taşına hiç benzemeyen dikdörtgenler.
      test('$label — taşlar YATIK olmaz, oran korunur', () {
        final m = OkeyTableMetrics.from(BoxConstraints.tight(size));

        expect(
          m.rackTileHeight,
          greaterThan(m.rackTileWidth),
          reason:
              '$label: ıstaka taşı eninden yatık '
              '(${m.rackTileWidth.toStringAsFixed(1)}x'
              '${m.rackTileHeight.toStringAsFixed(1)})',
        );
        for (final entry in {
          'ıstaka': [m.rackTileWidth, m.rackTileHeight],
          'ıskarta': [m.discardTileWidth, m.discardTileHeight],
          'masadaki per': [m.meldTileWidth, m.meldTileHeight],
          'ada': [m.islandTileWidth, m.islandTileWidth / 0.74],
        }.entries) {
          expect(
            entry.value[0] / entry.value[1],
            closeTo(OkeyTableMetrics.tileAspect, 0.02),
            reason: '$label: ${entry.key} taşının oranı bozuk',
          );
        }
      });

      test('$label — ıstaka azami genişliği aşmaz', () {
        final m = OkeyTableMetrics.from(BoxConstraints.tight(size));
        expect(
          m.rackWidth,
          lessThanOrEqualTo(m.rackMaxWidth + 0.01),
          reason: '$label: ıstaka ekrandan taşıyor',
        );
      });

      /// DİZME DÜĞMELERİ ISTAKAYA BİTİŞİK (kullanıcı isteği, 2026-09-07:
      /// "seri diz, çift diz takoza biraz daha yakınlaştır").
      ///
      /// Düğmeler ekranın iki UCUNA, ıstaka ise ortaya yerleştirildiğinde
      /// aradaki fark boşluk olarak düğmeyle ıstakanın arasına düşüyordu:
      /// 1280x800'de her yanda 90 pikselden fazla. Artık üçü tek grup olarak
      /// ortalanır ve mesafe hangi ekranda olursak olalım sabittir.
      testWidgets('$label — DİZ düğmeleri ıstakaya bitişik', (tester) async {
        await _pumpTable(tester, size, withError: false);

        final rack = tester.getRect(find.byType(OkeyRackPanel));
        final caps = find.byType(OkeyDizCapButton);
        expect(caps, findsNWidgets(2));

        final left = tester.getRect(caps.at(0));
        final right = tester.getRect(caps.at(1));
        // Sol düğme ıstakanın SOLUNDA, sağdaki SAĞINDA durmalı.
        expect(left.right, lessThanOrEqualTo(rack.left + 0.01));
        expect(right.left, greaterThanOrEqualTo(rack.right - 0.01));

        const tolerance = OkeyTableMetrics.rackCapGap + 0.5;
        expect(
          rack.left - left.right,
          lessThanOrEqualTo(tolerance),
          reason: '$label: ÇİFT DİZ ıstakadan uzak',
        );
        expect(
          right.left - rack.right,
          lessThanOrEqualTo(tolerance),
          reason: '$label: SERİ DİZ ıstakadan uzak',
        );
      });
    });

    test('sınırsız/bozuk kısıtta makul varsayılana düşer', () {
      final m = OkeyTableMetrics.from(const BoxConstraints());
      expect(m.rackHeight, greaterThan(0));
      expect(m.discardTileWidth, greaterThan(0));
      expect(m.width, greaterThan(0));
      expect(m.rackTileHeight, greaterThan(m.rackTileWidth));
    });
  });

  _visualsGroup();

  group('Oyunun yönü masada görünür', () {
    // Okey saat yönünün TERSİNE döner: soldakinin attığını alırsın, attığını
    // sağdaki alır. Masa bu yönü yansıtmalı — ıskartam kimlik kartımın
    // yanında (solda) dururken "sağa atma" hareketinin görsel karşılığı
    // yoktu.
    testWidgets('kendi ıskartam masanın SAĞ alt köşesindedir', (tester) async {
      const size = Size(892, 412);
      await _pumpTable(tester, size, withError: false);

      final myIdentity = find.byWidgetPredicate(
        (w) =>
            w is OkeyCornerPileWidget &&
            w.isMe &&
            w.parts == OkeySeatParts.identity,
      );
      final myDiscard = find.byWidgetPredicate(
        (w) =>
            w is OkeyCornerPileWidget &&
            w.isMe &&
            w.parts == OkeySeatParts.discard,
      );
      expect(myIdentity, findsOneWidget);
      expect(myDiscard, findsOneWidget);

      final identityRect = tester.getRect(myIdentity);
      final discardRect = tester.getRect(myDiscard);

      expect(
        discardRect.center.dx,
        greaterThan(identityRect.center.dx),
        reason: 'ıskartam kimlik kartımın solunda kalmış',
      );

      // Iskartam masanın SAĞ kenarında ve aksiyon butonlarına BİTİŞİK
      // DEĞİL. Aradaki boşluk kozmetik değil, hata önleme: ıskarta bir
      // bırakma hedefidir; taşı oraya sürüklerken parmak son anda kayarsa,
      // bitişikteki "ÇİFT AÇ"a basmak eli açma gibi geri alınamaz bir hamleyi
      // tetikleyebilir.
      var rightmostButton = double.negativeInfinity;
      for (
        var i = 0;
        i < find.byType(OkeyActionButton).evaluate().length;
        i++
      ) {
        final r = tester.getRect(find.byType(OkeyActionButton).at(i));
        if (r.right > rightmostButton) rightmostButton = r.right;
      }
      expect(
        discardRect.left - rightmostButton,
        greaterThan(24),
        reason:
            'ıskarta ile aksiyon butonları arasında yeterli boşluk yok '
            '(${(discardRect.left - rightmostButton).toStringAsFixed(1)}px) — '
            'taş atarken yanlışlıkla butona basılabilir',
      );

      // Ve taş ÇEKTİĞİM ıskartanın (solumdaki oyuncunun) sağında.
      final drawPile = find.byWidgetPredicate(
        (w) => w is OkeyCornerPileWidget && w.isDrawSource,
      );
      expect(drawPile, findsOneWidget);
      expect(
        discardRect.center.dx,
        greaterThan(tester.getRect(drawPile).center.dx),
        reason: 'çekme ve atma aynı tarafta — oyunun yönü okunmuyor',
      );

      // ÇEKME kutusu masanın SOL ALT, ATMA kutusu SAĞ ALT köşesinde: ikisi
      // de masanın ALT yarısında durur, çünkü ikisi de BENİMLE komşularım
      // arasındaki köşelerdir.
      final drawRect = tester.getRect(drawPile);
      expect(
        drawRect.center.dy,
        greaterThan(size.height * 0.35),
        reason: 'çekme kutusu masanın alt yarısında değil',
      );
      expect(
        discardRect.center.dy,
        greaterThan(size.height * 0.35),
        reason: 'atma kutusu masanın alt yarısında değil',
      );
    });
  });

  group('GERÇEK masa yerleşimi hiçbir boyutta taşmaz', () {
    _screens.forEach((label, size) {
      testWidgets('$label — yalnızca sıra bandı', (tester) async {
        await _pumpTable(tester, size, withError: false);
        expect(tester.takeException(), isNull, reason: '$label taştı');
      });

      // 41 PİKSELLİK HATANIN TAM SENARYOSU: iki bant birden
      testWidgets('$label — sıra bandı + hata bandı', (tester) async {
        await _pumpTable(tester, size, withError: true);
        expect(
          tester.takeException(),
          isNull,
          reason: '$label: iki bantla birlikte taştı',
        );
      });

      // Sistem yazı tipi büyütmesi — bantlar daha da uzar
      testWidgets('$label — büyük yazı tipi (1.5x) + iki bant', (tester) async {
        await _pumpTable(tester, size, withError: true, textScale: 1.5);
        expect(
          tester.takeException(),
          isNull,
          reason: '$label: büyük yazı tipinde taştı',
        );
      });
    });
  });
}

/// Bu grup, kullanıcının istediği GÖRSEL değişiklikleri sabitler.
/// Amaç güzellik yargısı değil, davranışın kazara geri alınmaması:
/// özellikle "boş slotta iz olmasın" isteği, slotun sürükle-bırak hedefi
/// olma özelliğini yanlışlıkla öldürebilirdi (görünmez kutular hit-test
/// almaz). Bu yüzden burada hem görünüm hem de İŞLEVSELLİK doğrulanır.
void _visualsGroup() {
  group('Masa görünümü', () {
    testWidgets('kapalı taş (deste/gizli okey) BEYAZ gövdelidir', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: OkeyTileWidget(
                tile: OkeyTile.falseJoker(),
                faceDown: true,
              ),
            ),
          ),
        ),
      );

      // GÖVDE RENGİNİ TAŞIYICI WIDGET'TAN DEĞİL, ÇİZİMDEN OKU.
      //
      // Gövde kutusu artık her zaman AnimatedContainer değil: seçim geçişi
      // yalnızca ıstakadaki taşlarda açık (bkz. OkeyTileWidget
      // .animateSelection — masadaki ~40 taş için her build'de bir State +
      // AnimationController kurup sökmek performans maliyetiydi). Kapalı bir
      // taş düz bir Container ile çizilir.
      //
      // Bu testin derdi ANİMASYON DEĞİL, RENK. İkisi de aynı DecoratedBox'ı
      // üretir (Container/AnimatedContainer gövdeyi onunla boyar), o yüzden
      // ölçüm oradan yapılır — böylece test, sunum katmanının hangi kutuyu
      // seçtiğinden bağımsız kalır.
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(OkeyTileWidget),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final decoration = box.decoration as BoxDecoration;
      final gradient = decoration.gradient! as LinearGradient;

      // Eski hali koyu gri/lacivertti (0xFF37474F). Artık açık taşlarla
      // aynı fildişi/beyaz gövde kullanılır.
      for (final c in gradient.colors) {
        expect(
          c.computeLuminance(),
          greaterThan(0.7),
          reason: 'kapalı taş beyaz değil: $c',
        );
      }
    });

    testWidgets('ıstakadaki taşlar BİTİŞİK durur (aralarında boşluk yok)', (
      tester,
    ) async {
      // Yan yana beş taş: kenarları birbirine DEĞMELİ.
      //
      // NEDEN ÖLÇÜYORUZ: taşın yan boşluğunu (margin) sıfırlamak yetmiyordu.
      // Asıl boşluk, her slotun Expanded ile eşit genişlik alması ama taşın
      // SABİT 30px kalmasından geliyordu — taş slotun ortasında yüzüyor,
      // aradaki fark boşluk olarak görünüyordu. Bu test o farkı yakalar.
      final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
      for (var i = 0; i < 5; i++) {
        slots[i] = OkeyTile.numbered(OkeyColor.values[i % 4], i + 1);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 90,
              child: OkeyRackBarWidget(
                slots: slots,
                selectedIndices: const {},
                onTap: (_) {},
                onMove: (_, __) {},
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      final tiles = find.byType(OkeyTileWidget);
      expect(tiles, findsWidgets);

      // İlk beş taşın kutularını soldan sağa sırala
      final rects = <Rect>[];
      for (var i = 0; i < 5; i++) {
        rects.add(tester.getRect(tiles.at(i)));
      }
      rects.sort((a, b) => a.left.compareTo(b.left));

      for (var i = 1; i < rects.length; i++) {
        final gap = rects[i].left - rects[i - 1].right;
        expect(
          gap.abs(),
          lessThan(0.6),
          reason:
              '$i. taş ile öncekinin arasında ${gap.toStringAsFixed(1)}px '
              'boşluk var — ıstakada taşlar bitişik olmalı',
        );
      }
    });

    testWidgets('ıstaka taşları slot genişliğini TAMAMEN doldurur', (
      tester,
    ) async {
      final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
      slots[0] = OkeyTile.numbered(OkeyColor.red, 7);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 90,
              child: OkeyRackBarWidget(
                slots: slots,
                selectedIndices: const {},
                onTap: (_) {},
                onMove: (_, __) {},
              ),
            ),
          ),
        ),
      );

      // 16 slot, yatay iç padding 8 -> slot ~39.5px.
      // Taş sabit 30px kalsaydı her slotta ~9px boşluk olurdu.
      final tileW = tester.getSize(find.byType(OkeyTileWidget).first).width;
      const expected = (640 - 8) / OkeyRackLayout.slotsPerRow;
      expect(
        tileW,
        closeTo(expected, 1.5),
        reason:
            'taş slot genişliğini doldurmuyor '
            '(taş: $tileW, slot: $expected) — aralarında boşluk kalır',
      );
    });

    testWidgets('perin SON taşından sonra boşluk bırakılır', (tester) async {
      // Tüm boşluklar kapatılınca perlerin nerede başlayıp bittiği
      // anlaşılmıyordu. Artık bir perin son taşının sağında küçük bir pay
      // kalır — taşlar per İÇİNDE bitişik, perler ARASINDA ayrık.
      final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
      for (var i = 0; i < 6; i++) {
        slots[i] = OkeyTile.numbered(OkeyColor.values[i % 4], i + 1);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 90,
              child: OkeyRackBarWidget(
                slots: slots,
                selectedIndices: const {},
                // 0-1-2 bir per, 3-4-5 başka bir per
                groupEndSlots: const {2},
                onTap: (_) {},
                onMove: (_, __) {},
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      final tiles = find.byType(OkeyTileWidget);
      final rects = <Rect>[];
      for (var i = 0; i < 6; i++) {
        rects.add(tester.getRect(tiles.at(i)));
      }
      rects.sort((a, b) => a.left.compareTo(b.left));

      // Per İÇİNDE bitişik (0-1 ve 1-2)
      expect(
        (rects[1].left - rects[0].right).abs(),
        lessThan(0.6),
        reason: 'aynı perin taşları ayrıldı',
      );
      expect(
        (rects[2].left - rects[1].right).abs(),
        lessThan(0.6),
        reason: 'aynı perin taşları ayrıldı',
      );

      // Perler ARASINDA boşluk (2 -> 3)
      final gap = rects[3].left - rects[2].right;
      expect(
        gap,
        greaterThan(2.0),
        reason:
            'perler arasında boşluk yok — hangi taşın hangi pere ait '
            'olduğu ayırt edilemiyor',
      );
    });

    testWidgets('grup sınırı YOKSA taşlar tamamen bitişik kalır', (
      tester,
    ) async {
      final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
      for (var i = 0; i < 4; i++) {
        slots[i] = OkeyTile.numbered(OkeyColor.values[i % 4], i + 1);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 90,
              child: OkeyRackBarWidget(
                slots: slots,
                selectedIndices: const {},
                onTap: (_) {},
                onMove: (_, __) {},
              ),
            ),
          ),
        ),
      );

      final tiles = find.byType(OkeyTileWidget);
      final rects = <Rect>[];
      for (var i = 0; i < 4; i++) {
        rects.add(tester.getRect(tiles.at(i)));
      }
      rects.sort((a, b) => a.left.compareTo(b.left));

      for (var i = 1; i < rects.length; i++) {
        expect(
          (rects[i].left - rects[i - 1].right).abs(),
          lessThan(0.6),
          reason: 'grup sınırı yokken boşluk oluştu',
        );
      }
    });

    testWidgets('bir perin taşları HÜCRE ölçüsünde ve BİTİŞİK dizilir', (
      tester,
    ) async {
      // Bir perin İÇİNDEKİ taşlar hücre adımıyla yan yana durur — böylece
      // 5-6-7 tek bir bütün gibi okunur, taşlar arasında kayma olmaz.
      //
      // TARİHÇE: bu test eskiden taşların GLOBAL bir ızgara başlangıcına
      // (okeyBoardGridKey) göre hizalandığını ölçüyordu. O ölçüt artık
      // geçersiz: (1) ızgara hiç çizilmiyor — taşlar düz keçeye yatıyor,
      // (2) perler sarmalı aktığı için satırdaki ikinci per, önceki perin
      // genişliğine bağlı bir noktada başlar. Anlamlı olan garanti, perin
      // KENDİ İÇİNDEKİ hizalamadır.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: OkeyBoardWidget(melds: [_run(1, OkeyColor.red, 2)]),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      final tiles = find.byType(OkeyTileWidget);
      expect(tiles, findsNWidgets(3));

      final rects = [for (var i = 0; i < 3; i++) tester.getRect(tiles.at(i))]
        ..sort((a, b) => a.left.compareTo(b.left));

      // TAŞ ÖLÇÜSÜ ARTIK SABİT DEĞİL: tahta, tüm perlerin sığacağı en büyük
      // ölçüyü kendi hesaplıyor (bkz. OkeyBoardLayout). Bu yüzden test bir
      // sabitle değil, perin KENDİ İÇİNDEKİ tutarlılıkla ölçülür:
      // taşlar eşit ölçüde, bitişik ve aynı satırda olmalı.
      for (var i = 0; i < 3; i++) {
        expect(
          rects[i].width,
          closeTo(rects[0].width, 0.5),
          reason: '$i. taş diğerlerinden farklı genişlikte',
        );
        expect(
          rects[i].height,
          closeTo(rects[0].height, 0.5),
          reason: '$i. taş diğerlerinden farklı yükseklikte',
        );
        // Oran korunmalı: taşlar yatık dikdörtgene dönmemeli.
        expect(
          rects[i].width / rects[i].height,
          closeTo(0.74, 0.03),
          reason: '$i. taşın oranı bozuk',
        );
        if (i > 0) {
          expect(
            (rects[i].left - rects[i - 1].right).abs(),
            lessThan(0.6),
            reason: 'per içindeki taşlar bitişik değil',
          );
          expect(
            (rects[i].top - rects[i - 1].top).abs(),
            lessThan(0.5),
            reason: 'per içindeki taşlar aynı satırda değil',
          );
        }
      }
    });

    testWidgets('bir per tam bir HÜCRE SATIRI kaplar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: OkeyBoardWidget(
                melds: [_run(1, OkeyColor.blue, 2), _run(2, OkeyColor.blue, 6)],
              ),
            ),
          ),
        ),
      );

      final melds = find.byType(DragTarget<OkeyDragPayload>);
      final tileH = tester.getRect(find.byType(OkeyTileWidget).first).height;
      // Per yüksekliği = taş + oturma zemininin iki yandan dolgusu.
      final expected =
          tileH +
          OkeyBoardLayout.meldPadding * 2 +
          OkeyBoardLayout.meldBorderWidth;
      for (var i = 0; i < 2; i++) {
        expect(
          tester.getRect(melds.at(i)).height,
          closeTo(expected, 0.6),
          reason: '$i. perin yüksekliği taş + dolgu değil',
        );
      }
    });

    testWidgets('açılan perler ALT ALTA dizilir (sütun dolunca sağa)', (
      tester,
    ) async {
      // KULLANICI KARARI (2026-09-05): "açılan perler alt alta dizilsin."
      //
      // TARİHÇE: bir ara alt alta, sonra SARMALI (soldan sağa akıp alt
      // satıra geçen) bir yerleşim vardı. Sarmalı akışın sorunu şuydu: masaya
      // her yeni per konduğunda ondan SONRAKİ perlerin hepsi kayıyor,
      // oyuncunun "şurada duruyordu" diye baktığı per el içinde birkaç kez
      // yer değiştiriyordu. Sütun aşağı büyüdüğü için yeni per hep sıranın
      // SONUNA eklenir, önündekiler yerinde kalır.
      //
      // "Alt alta dizmek kaydırma demekti" endişesi geçerli değil: sütun
      // dolunca SAĞDAN yeni bir sütun açılıyor (bkz. OkeyBoardLayout), yani
      // genişlik yine kullanılıyor ve kaydırma hiç yok.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 400,
              child: OkeyBoardWidget(
                melds: [_run(1, OkeyColor.red, 2), _run(2, OkeyColor.red, 6)],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      final melds = find.byType(DragTarget<OkeyDragPayload>);
      expect(melds, findsNWidgets(2));

      final first = tester.getRect(melds.at(0));
      final second = tester.getRect(melds.at(1));

      // İkisi de 400px yüksekliğe RAHATÇA sığar → alt alta durmalılar.
      expect(
        second.top,
        greaterThanOrEqualTo(first.bottom - 1),
        reason: 'perler alt alta dizilmiyor',
      );
      expect(
        (second.left - first.left).abs(),
        lessThan(1),
        reason: 'aynı sütundaki perler aynı hizada başlamalı',
      );
    });

    testWidgets('12 per birden MASAYA SIĞAR — hiçbiri gizlenmez', (
      tester,
    ) async {
      // YENİ SÖZLEŞME (2026-09).
      //
      // Eskiden tahta, taş ölçüsünü dışarıdan alıp sığmayanı bir kaydırma
      // alanına atıyordu; test de "yarım taş görünmesin" diye kaydırma
      // alanının satır adımının tam katı olmasını ölçüyordu. O sözleşme
      // KALDIRILDI: 101 Okey'de dört oyuncu açtığında masada 12-16 per
      // birikir ve oyuncunun masanın yarısını görmek için kaydırması,
      // gerçek bir okey masasında karşılığı olmayan bir davranıştı.
      //
      // Artık taş ölçüsü ALANA GÖRE ÇÖZÜLÜR (bkz. OkeyBoardLayout): perler
      // küçülür ama HEPSİ görünür. Ölçülen garanti de bu:
      //   1. kaydırma alanı HİÇ YOK (her şey sığdı)
      //   2. her per, tahtanın sınırlarının TAMAMEN içinde
      const area = Size(200, 300);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: area.width,
                height: area.height,
                child: OkeyBoardWidget(
                  melds: [
                    for (var i = 1; i <= 12; i++) _run(i, OkeyColor.red, 2),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      expect(
        find.byType(SingleChildScrollView),
        findsNothing,
        reason:
            '12 per sığmalıydı — kaydırma alanı oluştuysa taşlar yeterince '
            'küçültülmemiş demektir',
      );

      final boardRect = tester.getRect(find.byType(OkeyBoardWidget));
      final melds = find.byType(DragTarget<OkeyDragPayload>);
      expect(melds, findsNWidgets(12), reason: 'bazı perler hiç çizilmemiş');

      for (var i = 0; i < 12; i++) {
        final r = tester.getRect(melds.at(i));
        expect(
          r.bottom,
          lessThanOrEqualTo(boardRect.bottom + 0.5),
          reason: '$i. per tahtanın altından taşıyor',
        );
        expect(
          r.right,
          lessThanOrEqualTo(boardRect.right + 0.5),
          reason: '$i. per tahtanın sağından taşıyor',
        );
      }
    });

    testWidgets('dar alanda perler ALT SATIRA kırılır', (tester) async {
      // Bir satıra iki per sığmayacak kadar dar: ikincisi alta inmeli,
      // taşmamalı.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 130,
              height: 300,
              child: OkeyBoardWidget(
                melds: [_run(1, OkeyColor.red, 2), _run(2, OkeyColor.red, 6)],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      final melds = find.byType(DragTarget<OkeyDragPayload>);
      final first = tester.getRect(melds.at(0));
      final second = tester.getRect(melds.at(1));

      expect(
        second.top,
        greaterThanOrEqualTo(first.bottom - 1),
        reason: 'dar alanda ikinci per alt satıra inmedi',
      );
    });

    testWidgets('boş ıstaka slotu görünür bir iz BIRAKMAZ', (tester) async {
      final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
      slots[0] = OkeyTile.numbered(OkeyColor.red, 5);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 100,
              child: OkeyRackBarWidget(
                slots: slots,
                selectedIndices: const {},
                onTap: (_) {},
                onMove: (_, __) {},
              ),
            ),
          ),
        ),
      );

      // Boş slotların hiçbiri görünür bir dolgu/kenarlık çizmemeli.
      final painted = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) {
            final d = c.decoration;
            if (d is! BoxDecoration) return false;
            final fill = d.color;
            return fill != null && fill.a > 0 && fill != Colors.transparent;
          });
      // Yalnızca ıstakanın kendi ahşap gövdesi + taşın kendisi boyanabilir;
      // 30 boş slot için 30 koyu kutu OLMAMALI.
      expect(
        painted.length,
        lessThan(5),
        reason: 'boş slotlar hâlâ kart izi çiziyor',
      );
    });

    testWidgets('boş slot GÖRÜNMEZ ama sürükle-bırak hedefi olarak yaşar', (
      tester,
    ) async {
      final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
      slots[0] = OkeyTile.numbered(OkeyColor.red, 5);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 100,
              child: OkeyRackBarWidget(
                slots: slots,
                selectedIndices: const {},
                onTap: (_) {},
                onMove: (_, __) {},
              ),
            ),
          ),
        ),
      );

      // Boş slotların DragTarget'ları hâlâ ağaçta olmalı — görünmez bir
      // SizedBox kullanılsaydı hit-test alamaz, taş boşluğa bırakılamazdı.
      expect(find.byType(DragTarget<OkeyDragPayload>), findsWidgets);

      // Şeffaf ama BOYANAN kutular hit-test alır: slot sayısı kadar olmalı
      final hitTestable = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.color == Colors.transparent);
      expect(
        hitTestable.length,
        greaterThan(20),
        reason: 'boş slotlar hit-test alamıyor, taş bırakılamaz',
      );
    });

    testWidgets('masa ortasındaki ada gösterge, okey ve desteyi gösterir', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: OkeyIndicatorWidget(
                indicatorTile: OkeyTile.numbered(OkeyColor.red, 5),
                okeyTile: OkeyTile.numbered(OkeyColor.red, 6),
                deckRemaining: 20,
                isMyTurn: true,
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(OkeyIndicatorWidget), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
      expect(find.text('GÖSTERGE'), findsOneWidget);
      expect(find.text('OKEY'), findsOneWidget);

      // Desteden sürükleyerek çekme her zaman mümkün olmalı
      expect(
        find.descendant(
          of: find.byType(OkeyIndicatorWidget),
          matching: find.byType(Draggable<OkeyDragPayload>),
        ),
        findsOneWidget,
      );
    });

    testWidgets('dar alanda ada taşmaz', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 150,
              height: 80,
              child: OkeyIndicatorWidget(
                indicatorTile: OkeyTile.numbered(OkeyColor.blue, 12),
                okeyTile: OkeyTile.numbered(OkeyColor.blue, 13),
                deckRemaining: 7,
                isMyTurn: true,
              ),
            ),
          ),
        ),
      );

      expect(
        tester.takeException(),
        isNull,
        reason: 'dar masada gösterge adası taştı',
      );
    });
  });
}
