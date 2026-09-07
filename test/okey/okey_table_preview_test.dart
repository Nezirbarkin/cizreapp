// MASA ÖNİZLEMESİ — gerçek yerleşimin PNG'sini üretir (tasarım incelemesi için)
//
//   flutter test test/okey/okey_table_preview_test.dart --update-goldens
//
// KARŞILAŞTIRMA YAPMAZ, YALNIZCA ÜRETİR. `flutter test` ile çalıştırıldığında
// hiçbir şey yapmadan geçer (bkz. autoUpdateGoldenFiles kontrolü).
//
// NEDEN KARŞILAŞTIRMIYOR: golden karşılaştırması yazı tipi biçimlendirme,
// kenar yumuşatma ve GPU farklarına duyarlıdır — aynı kod başka bir makinede
// (ya da CI'da) piksel piksel aynı çıkmaz. Bu dosyanın amacı regresyon
// yakalamak değil, tasarımı GÖZLE görebilmek; o yüzden asla kırmız yanmaz.
// Gerçek taşma/yerleşim regresyonları okey_table_layout_test.dart'ta ölçülür.
@Tags(['preview'])
library;

import 'package:cizreapp/okey/engine/okey_rack_layout.dart';
import 'package:cizreapp/okey/engine/okey_tile.dart';
import 'package:cizreapp/okey/models/okey_models.dart';
import 'package:cizreapp/okey/theme/okey_theme.dart';
import 'package:cizreapp/okey/widgets/okey_action_panel_widget.dart';
import 'package:cizreapp/okey/widgets/okey_board_widget.dart';
import 'package:cizreapp/okey/widgets/okey_corner_pile_widget.dart';
import 'package:cizreapp/okey/widgets/okey_hud_chrome.dart';
import 'package:cizreapp/okey/widgets/okey_indicator_widget.dart';
import 'package:cizreapp/okey/widgets/okey_rack_bar_widget.dart';
import 'package:cizreapp/okey/widgets/okey_room_backdrop.dart';
import 'package:cizreapp/okey/widgets/okey_table_metrics.dart';
import 'package:cizreapp/okey/widgets/okey_table_scaffold.dart';
import 'package:cizreapp/okey/widgets/okey_turn_timer_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

OkeyTile _t(OkeyColor c, int n) => OkeyTile.numbered(c, n);

OkeyRoomSeat _seat(int n, String name) => OkeyRoomSeat(
  roomId: 'r',
  seatNo: n,
  userId: 'u$n',
  isReady: true,
  displayName: name,
);

List<OkeyTableMeld> _melds() {
  var id = 0;
  OkeyTableMeld run(OkeyColor c, int base, int len) => OkeyTableMeld(
    id: ++id,
    matchId: 'm',
    laidBySeat: 0,
    meldType: 'run',
    tiles: [for (var i = 0; i < len; i++) _t(c, base + i)],
  );
  OkeyTableMeld set(int n) => OkeyTableMeld(
    id: ++id,
    matchId: 'm',
    laidBySeat: 1,
    meldType: 'set',
    tiles: [
      _t(OkeyColor.red, n),
      _t(OkeyColor.black, n),
      _t(OkeyColor.blue, n),
    ],
  );
  OkeyTableMeld pair(OkeyColor c, int n) => OkeyTableMeld(
    id: ++id,
    matchId: 'm',
    laidBySeat: 2,
    meldType: 'pair',
    tiles: [_t(c, n), _t(c, n)],
  );
  // EN YOĞUN SENARYO: dört oyuncu da açtı ve işledi — 16 per.
  // Yeni tahta bunların HEPSİNİ sığdırmalı (bkz. OkeyBoardLayout).
  return [
    run(OkeyColor.red, 1, 3),
    run(OkeyColor.yellow, 7, 5),
    set(10),
    run(OkeyColor.blue, 7, 4),
    set(13),
    pair(OkeyColor.red, 9),
    run(OkeyColor.black, 4, 3),
    pair(OkeyColor.blue, 5),
    run(OkeyColor.yellow, 2, 4),
    set(6),
    run(OkeyColor.black, 9, 4),
    set(4),
    run(OkeyColor.red, 5, 3),
    pair(OkeyColor.yellow, 12),
    run(OkeyColor.blue, 1, 5),
    set(8),
  ];
}

List<OkeyTile?> _rack() {
  final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
  const tiles = [
    [OkeyColor.blue, 1],
    [OkeyColor.blue, 2],
    [OkeyColor.blue, 3],
    [OkeyColor.red, 5],
    [OkeyColor.yellow, 3],
    [OkeyColor.yellow, 4],
    [OkeyColor.yellow, 5],
    [OkeyColor.black, 11],
    [OkeyColor.black, 12],
    [OkeyColor.black, 13],
    [OkeyColor.red, 8],
    [OkeyColor.blue, 8],
    [OkeyColor.yellow, 8],
  ];
  var i = 0;
  for (final t in tiles) {
    if (i % 6 == 5) i++;
    slots[i++] = OkeyTile.numbered(t[0] as OkeyColor, t[1] as int);
  }
  return slots;
}

void main() {
  final seconds = ValueNotifier<int>(14);

  for (final entry in const {
    'preview_masa.png': Size(892, 412),
    'preview_masa_kucuk.png': Size(640, 320),
    'preview_masa_tablet.png': Size(1280, 800),
  }.entries) {
    testWidgets('masa önizlemesi ${entry.key}', (tester) async {
      // Yalnızca --update-goldens ile çalışır (bkz. dosya başındaki gerekçe).
      if (!autoUpdateGoldenFiles) return;

      OkeyRoomBackdrop.debugSetCachedUrl(null); // fotoğrafsız (vektörel zemin)
      // devicePixelRatio 1.0: physicalSize doğrudan MANTIKSAL ölçü olsun.
      // 2.0 verilseydi mantıksal alan yarıya inerdi — test ettiğimiz ekran
      // değil, onun yarısı.
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: OkeyColors.tableBackground,
            body: Stack(
              children: [
                const Positioned.fill(
                  child: IgnorePointer(child: OkeyRoomBackdrop()),
                ),
                OkeyTableScaffold(
                  seatAcross: (c, m) => OkeyCornerPileWidget(
                    size: m.discardTileWidth,
                    avatarSize: m.avatarSize,
                    side: OkeySeatSide.top,
                    parts: OkeySeatParts.identity,
                    seat: _seat(2, 'Oyuncu 2'),
                    seatNo: 2,
                    tileCount: 14,
                    score: 116,
                    isCurrentTurn: false,
                  ),
                  seatLeft: (c, m) => OkeyCornerPileWidget(
                    size: m.discardTileWidth,
                    side: OkeySeatSide.left,
                    parts: OkeySeatParts.identity,
                    seat: _seat(3, 'Oyuncu 3'),
                    seatNo: 3,
                    tileCount: 15,
                    score: 23,
                    isCurrentTurn: false,
                  ),
                  seatRight: (c, m) => OkeyCornerPileWidget(
                    size: m.discardTileWidth,
                    side: OkeySeatSide.right,
                    parts: OkeySeatParts.identity,
                    seat: _seat(1, 'Oyuncu 1'),
                    seatNo: 1,
                    tileCount: 13,
                    score: 5,
                    isCurrentTurn: true,
                  ),
                  seatMine: (c, m) => Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OkeyCornerPileWidget(
                        size: m.discardTileWidth,
                        avatarSize: m.avatarSize,
                        side: OkeySeatSide.bottom,
                        parts: OkeySeatParts.identity,
                        seat: _seat(0, 'SM-S9..'),
                        seatNo: 0,
                        tileCount: 13,
                        score: 115,
                        isMe: true,
                        isCurrentTurn: false,
                      ),
                      const SizedBox(width: 6),
                      OkeyScoreBubble(
                        score: 115,
                        height: (m.consoleHeight * 0.52).clamp(16.0, 28.0),
                      ),
                    ],
                  ),
                  cornerDiscardTopLeft: (c, m) => OkeyCornerPileWidget(
                    size: m.discardTileWidth,
                    side: OkeySeatSide.left,
                    parts: OkeySeatParts.discard,
                    seat: _seat(2, 'Oyuncu 2'),
                    seatNo: 2,
                    topDiscard: _t(OkeyColor.black, 1),
                    tileCount: 14,
                    isCurrentTurn: false,
                  ),
                  cornerDiscardBottomLeft: (c, m) => OkeyCornerPileWidget(
                    size: m.discardTileWidth,
                    side: OkeySeatSide.left,
                    parts: OkeySeatParts.discard,
                    seat: _seat(3, 'Oyuncu 3'),
                    seatNo: 3,
                    topDiscard: _t(OkeyColor.red, 4),
                    tileCount: 15,
                    isCurrentTurn: false,
                    isDrawSource: true,
                  ),
                  cornerDiscardTopRight: (c, m) => OkeyCornerPileWidget(
                    size: m.discardTileWidth,
                    side: OkeySeatSide.right,
                    parts: OkeySeatParts.discard,
                    seat: _seat(1, 'Oyuncu 1'),
                    seatNo: 1,
                    topDiscard: _t(OkeyColor.yellow, 5),
                    tileCount: 13,
                    isCurrentTurn: false,
                  ),
                  myDiscard: (c, m) => OkeyCornerPileWidget(
                    size: m.discardTileWidth,
                    side: OkeySeatSide.right,
                    parts: OkeySeatParts.discard,
                    seat: _seat(0, 'SM-S9..'),
                    seatNo: 0,
                    tileCount: 13,
                    score: 115,
                    isMe: true,
                    isCurrentTurn: false,
                    isDiscardTarget: true,
                  ),
                  island: (c, m) => OkeyIndicatorWidget(
                    vertical: true,
                    indicatorTile: _t(OkeyColor.red, 11),
                    okeyTile: _t(OkeyColor.red, 12),
                    deckRemaining: 18,
                    isMyTurn: true,
                    canDragFromDeck: true,
                    tileWidth: m.islandTileWidth,
                  ),
                  melds: (c, m) => OkeyBoardWidget(
                    melds: _melds(),
                    okeyTile: _t(OkeyColor.yellow, 13),
                    tileWidth: m.meldTileWidth,
                    tileHeight: m.meldTileHeight,
                  ),
                  pairsBoard: (c, m) => OkeyBoardWidget(
                    emptyHint: '',
                    okeyTile: _t(OkeyColor.yellow, 13),
                    melds: [
                      OkeyTableMeld(
                        id: 90,
                        matchId: 'm',
                        laidBySeat: 1,
                        meldType: 'pair',
                        tiles: [_t(OkeyColor.blue, 6), _t(OkeyColor.blue, 6)],
                      ),
                      OkeyTableMeld(
                        id: 91,
                        matchId: 'm',
                        laidBySeat: 1,
                        meldType: 'pair',
                        tiles: [_t(OkeyColor.black, 9), _t(OkeyColor.black, 9)],
                      ),
                    ],
                    tileWidth: m.meldTileWidth,
                    tileHeight: m.meldTileHeight,
                  ),
                  rackCapStart: (c, m) =>
                      OkeyDizCapButton.pairs(active: false, onPressed: _noop),
                  rackCapEnd: (c, m) =>
                      OkeyDizCapButton.series(active: true, onPressed: _noop),
                  // onPressed VERİLİR: buton "etkin" görünümünü ancak geri
                  // çağrısı olduğunda alır. Önizlemede boş bırakılınca dört
                  // düğme de kapalı çiziliyor ve tasarımın asıl mesajı (altın
                  // = şu an yapılabilir) hiç görünmüyordu.
                  actions: (c, m) => const OkeyButtonRow(
                    children: [
                      OkeyActionButton(
                        title: 'SERİ AÇ',
                        icon: Icons.view_week,
                        badge: '108/101',
                        tone: OkeyActionTone.ready,
                        onPressed: _noop,
                      ),
                      OkeyActionButton(
                        title: 'ÇİFT AÇ',
                        icon: Icons.filter_2,
                        badge: '2/5',
                        enabled: false,
                        onPressed: _noop,
                      ),
                      OkeyActionButton(
                        title: 'İŞLE',
                        icon: Icons.playlist_add,
                        badge: '2',
                        onPressed: _noop,
                      ),
                      OkeyActionButton(
                        title: 'TAŞI AT',
                        icon: Icons.arrow_downward,
                        onPressed: _noop,
                      ),
                    ],
                  ),
                  modeBadges: const OkeyModeBadgeStack(
                    items: [
                      ('Eşsiz', Colors.lightBlueAccent),
                      ('Yardımlı', Colors.lightGreenAccent),
                      ('Katlamasız', Colors.redAccent),
                      ('3. EL', Colors.white70),
                    ],
                  ),
                  topLeading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const OkeyCoinPill(amount: 4500, height: 26),
                      const SizedBox(width: 6),
                      // MASA PUANI (2026-09-05): 3 el × 500 = 1.500
                      const OkeyStakePill(
                        stake: 1500,
                        perHand: 500,
                        hands: 3,
                        height: 26,
                      ),
                      const SizedBox(width: 6),
                      OkeyHudActionButton.bonus(
                        label: 'BONUS AL',
                        height: 26,
                        enabled: true,
                        onTap: _noop,
                      ),
                    ],
                  ),
                  topControls: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const OkeyRoundIconButton(
                        size: 26,
                        icon: Icons.volume_up,
                        tooltip: 'Ses',
                        onTap: _noop,
                      ),
                      const SizedBox(width: 5),
                      const OkeyRoundIconButton(
                        size: 26,
                        icon: Icons.keyboard_arrow_down,
                        tooltip: 'Menü',
                        onTap: _noop,
                      ),
                    ],
                  ),
                  turnTimerBar: (c, m) => OkeyTurnTimerBar(
                    secondsLeftListenable: seconds,
                    totalSeconds: 20,
                    isMyTurn: true,
                    height: OkeyTableMetrics.timerBarHeight,
                  ),
                  rack: (c, m) => OkeyRackPanel(
                    rack: OkeyRackBarWidget(
                      slots: _rack(),
                      selectedIndices: const {},
                      onTap: (_) {},
                      onMove: (_, _) {},
                      metrics: m,
                      showChrome: false,
                      groupEndSlots: const {2, 6, 9},
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(OkeyTableScaffold),
        matchesGoldenFile(entry.key),
      );
    });
  }
}

void _noop() {}
