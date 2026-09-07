import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../engine/okey_seating.dart';
import '../models/okey_models.dart';
import 'okey_lobby_screen.dart';
import 'okey_match_result_screen.dart';
import 'okey_room_screen.dart';
import 'okey_points_screen.dart';
import '../providers/okey_game_provider.dart';
import '../providers/okey_points_provider.dart';
import '../widgets/okey_action_panel_widget.dart';
import '../widgets/okey_announcement_banner.dart';
import '../widgets/okey_baraj_badge.dart';
import '../widgets/okey_board_widget.dart';
import '../widgets/okey_drag_payload.dart';
import '../widgets/okey_gift_badge.dart';
import '../widgets/okey_gift_sheet.dart';
import '../widgets/okey_hud_chrome.dart';
import '../widgets/okey_indicator_widget.dart';
import '../widgets/okey_move_flight.dart';
import '../widgets/okey_profile_sheet.dart';
import '../widgets/okey_rack_bar_widget.dart';
import '../widgets/okey_corner_pile_widget.dart';
import '../widgets/okey_room_backdrop.dart';
import '../widgets/okey_table_metrics.dart';
import '../widgets/okey_table_scaffold.dart';
import '../widgets/okey_table_settings_dialog.dart';
import '../widgets/okey_turn_timer_bar.dart';
import '../widgets/okey_tile_widget.dart';
import '../theme/okey_theme.dart';
import '../theme/okey_ui.dart';

/// 101 Okey oyun masası — yatay (landscape) düzen.
class OkeyGameScreen extends StatefulWidget {
  final String matchId;

  /// Masaya İZLEYİCİ olarak girildi mi (koltuk yok, hamle yok).
  final bool spectator;

  const OkeyGameScreen({
    super.key,
    required this.matchId,
    this.spectator = false,
  });

  @override
  State<OkeyGameScreen> createState() => _OkeyGameScreenState();
}

class _OkeyGameScreenState extends State<OkeyGameScreen> {
  @override
  void initState() {
    super.initState();
    // Masa yatay ekranda oynanır (gerçek 101 Okey uygulamalarındaki gibi).
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // CÜZDAN da masaya gelir: üst şeritteki altın sayacı ve "BONUS AL"
    // düğmesi onu okur. Masaya özel bir kopya yaratılır (lobideki
    // OkeyPointsProvider'dan bağımsız) çünkü masa uzun süre açık kalır ve
    // lobiye dönerken cüzdanın yeniden okunması istenir.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) =>
              OkeyGameProvider(widget.matchId, spectator: widget.spectator),
        ),
        ChangeNotifierProvider(create: (_) => OkeyPointsProvider()),
      ],
      child: const _OkeyGameView(),
    );
  }
}

class _OkeyGameView extends StatefulWidget {
  const _OkeyGameView();

  @override
  State<_OkeyGameView> createState() => _OkeyGameViewState();
}

class _OkeyGameViewState extends State<_OkeyGameView>
    with WidgetsBindingObserver {
  // Aynı bitmiş el için diyalog yalnızca BİR KEZ açılır. Karar build()
  // içinde SENKRON olarak işaretlenir; aksi halde art arda showDialog
  // çağrıları Element ağacını bozuyordu.
  bool _dialogPending = false;
  String? _lastHandledFinishKey;

  /// UÇAN TAŞIN ÇAPALARI — hamlenin nereden nereye gittiğini ölçmek için.
  ///
  /// Koordinatlar sabit sayılarla tahmin EDİLMEZ: masa yerleşimi ekran
  /// ölçüsüne göre çözülüyor (bkz. OkeyTableMetrics), yani "deste şuradadır"
  /// demek her cihazda başka bir yere işaret ederdi. Gerçek RenderBox'lar
  /// okunur.
  final GlobalKey _deckKey = GlobalKey();
  final GlobalKey _meldsKey = GlobalKey();
  final List<GlobalKey> _discardKeys = [
    for (var i = 0; i < 4; i++) GlobalKey(),
  ];
  final List<GlobalKey> _seatKeys = [for (var i = 0; i < 4; i++) GlobalKey()];

  /// Uçuş katmanının kendi kutusu — çapa dikdörtgenleri ona göre çözülür.
  final GlobalKey _tableKey = GlobalKey();

  /// Bir çapanın, masa katmanına göre dikdörtgeni.
  Rect? _anchorRect(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    final table = _tableKey.currentContext?.findRenderObject();
    if (box is! RenderBox || table is! RenderBox) return null;
    if (!box.hasSize || !table.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero, ancestor: table);
    return origin & box.size;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Uygulama arka plandan döndüğünde (veya bağlantı kopup geldiğinde)
    // durum TAMAMEN veritabanından yeniden okunur — kaçırılan realtime
    // olaylarına güvenilmez. Böylece oyuna kaldığı yerden devam edilir.
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<OkeyGameProvider>().reconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OkeyGameProvider>();
    final match = provider.match;

    final finishKey = (match != null && match.status == 'finished')
        ? '${match.id}#${match.handNo}'
        : null;

    if (!_dialogPending &&
        finishKey != null &&
        finishKey != _lastHandledFinishKey) {
      _dialogPending = true;
      _lastHandledFinishKey = finishKey;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!context.mounted) return;
        await _showHandResultDialog(context, provider);
        if (!context.mounted) return;
        await _advanceToNextHandOrLeave(context, provider);
        _dialogPending = false;
      });
    }

    if (provider.isLoading && match == null) {
      return const Scaffold(
        backgroundColor: OkeyColors.tableBackground,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (match == null) {
      return Scaffold(
        backgroundColor: OkeyColors.tableBackground,
        body: Center(
          child: Text(
            provider.error ?? 'Maç bulunamadı',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final mySeat = provider.mySeatNo ?? 0;

    // Oturma düzeni saf bir hesaptır (bkz. OkeySeating): soldaki oyuncudan
    // taş alınır, sağdakine atılır. Bu eşleme daha önce ters olduğu için
    // oyun görsel olarak ters yönde dönüyormuş gibi görünüyordu.
    final seating = OkeySeating(mySeat);
    final leftSeat = seating.leftSeat;
    final acrossSeat = seating.acrossSeat;
    final rightSeat = seating.rightSeat;
    final drawSeat = seating.drawSeat;

    OkeyRoomSeat? seatAt(int n) {
      for (final s in provider.seats) {
        if (s.seatNo == n) return s;
      }
      return null;
    }

    Widget seatBox(
      int seatNo,
      OkeyTableMetrics m, {
      bool isMe = false,
      required OkeySeatSide side,
      OkeySeatParts parts = OkeySeatParts.both,
    }) {
      final pile = match.discardPiles[seatNo] ?? const [];
      final vertical = side == OkeySeatSide.left || side == OkeySeatSide.right;
      // DÖRT ISKARTA DA AYNI ÖLÇÜDE. v3'te kendi ıskartam konsolun içine
      // sıkıştığı için küçültülüyordu; artık o da diğer üçü gibi masanın bir
      // köşesinde duruyor, dolayısıyla küçültmeye gerek yok — üstelik en çok
      // kullanılan bırakma hedefinin en küçüğü olması baştan yanlıştı.
      return OkeyCornerPileWidget(
        size: m.discardTileWidth,
        avatarSize: m.avatarSize,
        side: side,
        parts: parts,
        // Kenar sütunları dar: kart oraya SIĞMALI, taşmamalı. Dikey KİMLİK
        // levhası ise sütunu doldurur (kendi kutusunu bilir), ona sınır
        // verilmez.
        maxWidth: (vertical && parts != OkeySeatParts.identity)
            ? m.sidePodWidth
            : null,
        seat: seatAt(seatNo),
        seatNo: seatNo,
        topDiscard: pile.isEmpty ? null : pile.last,
        tileCount: provider.opponentTileCounts[seatNo] ?? 0,
        score: match.scores[seatNo] ?? 0,
        // ANLIK PER PUANI — masaya açtığı/işlediği taşların toplamı.
        openPoints: provider.openPointsOf(seatNo),
        isCurrentTurn: match.turnSeat == seatNo,
        isMe: isMe,
        isOpened: isMe && provider.isOpeningDone,
        isDrawSource: seatNo == drawSeat && provider.canDraw,
        // Kendi ıskartam: sıra bendeyse ve taş çektiysem her zaman hedef
        isDiscardTarget: isMe && provider.canActOnHand,
        // BEKLEME NABZI HERKES İÇİN. Yalnızca botlarda yansaydı, üç nokta
        // "bu bir bot" demenin en açık yolu olurdu (bkz. isThinking).
        isThinking: !isMe && match.turnSeat == seatNo,
        onDragStart: provider.beginDrag,
        onDragEnd: provider.endDrag,
        onTileDropped: isMe ? provider.discardTileAtSlot : null,
        // KİMLİK levhasına dokununca profil kartı açılır. Iskarta kutusunun
        // dokunuşu (taş çek / at) bundan AYRI kalır.
        onProfileTap: parts == OkeySeatParts.identity
            ? () {
                final s = seatAt(seatNo);
                if (s == null) return;
                OkeyProfileSheet.show(
                  context,
                  userId: s.userId,
                  botProfileId: s.botProfileId,
                  name: s.displayLabel,
                  avatarUrl: s.avatarUrl,
                );
              }
            : null,
        onTap: () {
          if (seatNo == drawSeat && provider.canDraw) {
            provider.drawFromDiscard();
          } else if (isMe && provider.canDiscardSelected) {
            provider.discardSelectedTile();
          }
        },
      );
    }

    // HEDİYE ROZETİ — kimlik levhasının YANINDA belirir (kullanıcı isteği,
    // 2026-09-05: "iconlar okey masasında profillerin yanında belirsin").
    //
    // Levhanın İÇİNE konmadı: levha zaten ad, avatar, sayaç ve sıra vurgusu
    // taşıyor; oraya bir şey daha sıkıştırmak hepsini küçültürdü. Rozet
    // levhanın üst köşesinden TAŞAR (Stack + Clip.none) ve yalnızca hediye
    // geldiği birkaç saniye boyunca yer kaplar.
    Widget withSeatBadges(
      Widget plate,
      int seatNo,
      OkeyTableMetrics m, {
      required OkeySeatSide side,
    }) {
      final size = (m.avatarSize * 0.60).clamp(15.0, 28.0).toDouble();
      final badge = OkeySeatGiftBadge(
        seatNo: seatNo,
        gifts: provider.seatGifts,
        size: size,
      );
      final baraj = OkeyBarajKind.parse(provider.barajKindOf(seatNo));

      // ROZETİN YERİ — ne ekranın dışına, ne de PERLERİN ÜSTÜNE.
      //
      //   üstteki oyuncu → levhanın ALTINA (üstünde ekran kenarı var)
      //   bendeki levha  → ÜSTÜNE (altında süre çizgisi ve ıstaka var)
      //   yandakiler     → levhanın DİBİNE, ortalanmış
      //
      // Yandakiler neden yana değil ALTA: perler artık masanın sol üstünden
      // AŞAĞI doğru diziliyor (bkz. OkeyBoardLayout), yani kenar sütununun
      // sağındaki ilk şey bir perin ilk taşı. Yana taşan bir rozet tam
      // oraya, oyunun en çok bakılan noktasına otururdu. Levhanın dibinde
      // ise iki ıskarta kutusunun arasındaki boşluğa denk gelir.
      //
      // Yandaki rozet sütun genişliğinden biraz taşabilir ama SINIRLIDIR:
      // sığmayan gönderen adı kısalır (bkz. OkeySeatGiftBadge).
      final Positioned placed = switch (side) {
        OkeySeatSide.top => Positioned(
          bottom: -size * 0.55,
          right: -size * 0.30,
          child: badge,
        ),
        OkeySeatSide.bottom => Positioned(
          top: -size * 0.55,
          right: -size * 0.30,
          child: badge,
        ),
        OkeySeatSide.left || OkeySeatSide.right => Positioned(
          bottom: 2,
          left: -size * 0.6,
          right: -size * 0.6,
          child: Center(child: badge),
        ),
      };

      // ÇAPA: uçan taş, rakibin "eli" olarak bu levhayı hedefler
      // (bkz. OkeyMoveFlightOverlay). Anahtar rozetin değil LEVHANIN
      // kutusunu ölçmeli, o yüzden Stack'in kendisine değil plakaya konur.
      // BARAJ ROZETİ hediyenin TERS TARAFINA konur: ikisi de levhanın
      // dışına taşıyor ve aynı köşede buluşsalardı üst üste binerlerdi.
      // Hediye üst/alt koltukta SAĞDAN, yandakilerde ALTTAN taşıyor; baraj
      // bu yüzden sırasıyla SOLDAN ve ÜSTTEN taşar.
      final Positioned? barajChip = baraj == null
          ? null
          : switch (side) {
              OkeySeatSide.top => Positioned(
                bottom: -size * 0.55,
                left: -size * 0.30,
                child: OkeyBarajBadge(kind: baraj, size: size),
              ),
              OkeySeatSide.bottom => Positioned(
                top: -size * 0.55,
                left: -size * 0.30,
                child: OkeyBarajBadge(kind: baraj, size: size),
              ),
              OkeySeatSide.left || OkeySeatSide.right => Positioned(
                top: -size * 0.55,
                left: -size * 0.6,
                right: -size * 0.6,
                child: Center(
                  child: OkeyBarajBadge(kind: baraj, size: size),
                ),
              ),
            };

      return Stack(
        clipBehavior: Clip.none,
        children: [
          KeyedSubtree(key: _seatKeys[seatNo], child: plate),
          placed,
          // Rozet dokunmayı yutmasın: levhaya dokunup profil açmak
          // engellenmemeli.
          if (barajChip != null) IgnorePointer(child: barajChip),
        ],
      );
    }

    return Scaffold(
      backgroundColor: OkeyColors.tableBackground,
      body: Stack(
        children: [
          // Sıcak "oda" hissi — saf dekor, dokunma olaylarını hiç yutmaz.
          const Positioned.fill(
            child: IgnorePointer(child: OkeyRoomBackdrop()),
          ),
          SafeArea(
            key: _tableKey,
            // Yerleşimin TAMAMI OkeyTableScaffold'a aittir (saf, test edilebilir).
            // Ölçüler oradaki iç LayoutBuilder ile, bantların ALTINDA kalan
            // gerçek alandan hesaplanır; bant yüksekliği hakkında tahmin yapılmaz.
            child: OkeyTableScaffold(
              // HATA BANDI — lobideki/oda ekranındaki hata kartıyla AYNI dil.
              // Eskiden düz kırmızı bir şeritti; masaya ait olmayan, sistem
              // uyarısı gibi duran tek öğeydi.
              errorBanner: provider.error == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xE68E2430),
                          borderRadius: BorderRadius.circular(OkeyUI.radiusSm),
                          border: Border.all(color: const Color(0x8AFF8A9B)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x73000000),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 15,
                              color: Color(0xFFFFD9DE),
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                provider.error!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFFFECEF),
                                  fontSize: 11,
                                  height: 1.25,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              // DÖRT OYUNCU MASANIN DÖRT KENARINDA: karşıdaki üstte, soldaki
              // solda (ıskartasından taş çekilen oyuncu), sağdaki sağda, ben
              // altta. Yön, OkeySeating'in hesabıyla birebir aynı — masa
              // görsel olarak da oyunun döndüğü yönde döner.
              seatAcross: (context, m) => withSeatBadges(
                seatBox(
                  acrossSeat,
                  m,
                  side: OkeySeatSide.top,
                  parts: OkeySeatParts.identity,
                ),
                acrossSeat,
                m,
                side: OkeySeatSide.top,
              ),
              seatLeft: (context, m) => withSeatBadges(
                seatBox(
                  leftSeat,
                  m,
                  side: OkeySeatSide.left,
                  parts: OkeySeatParts.identity,
                ),
                leftSeat,
                m,
                side: OkeySeatSide.left,
              ),
              seatRight: (context, m) => withSeatBadges(
                seatBox(
                  rightSeat,
                  m,
                  side: OkeySeatSide.right,
                  parts: OkeySeatParts.identity,
                ),
                rightSeat,
                m,
                side: OkeySeatSide.right,
              ),
              seatMine: (context, m) => Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  withSeatBadges(
                    seatBox(
                      mySeat,
                      m,
                      isMe: true,
                      side: OkeySeatSide.bottom,
                      parts: OkeySeatParts.identity,
                    ),
                    mySeat,
                    m,
                    side: OkeySeatSide.bottom,
                  ),
                  const SizedBox(width: 6),
                  // CEZA PUANIM — plakanın yanında, ucu plakaya bakan bir
                  // balon. Skor plakanın İÇİNDEyken masadaki dört sayaçtan
                  // biri gibi okunuyordu; oysa bu sayı elin sonunu belirler.
                  OkeyScoreBubble(
                    score: match.scores[mySeat] ?? 0,
                    // İŞLEK TAŞ ATMA / OKEY ATMA / KULLANILMAYAN YANDAN
                    // ÇEKME cezası anında burada belirir (kullanıcı isteği:
                    // "oyuncu işlek attığında puanına göster"). Kırmızı
                    // yanıp sönme (bkz. _MistakeFlash) hatayı DUYURUR, bu
                    // sayı ise bedelini yazar.
                    pendingPenalty: provider.myPenaltyPoints,
                    height: (m.consoleHeight * 0.52).clamp(16.0, 28.0),
                  ),
                  const SizedBox(width: 5),
                  // AÇIK PUANIM — barajı geçtim mi sorusunun cevabı.
                  //
                  // Cezanın YANINDA ama ayrı bir rozette duruyor: ikisi de
                  // "puan" ama zıt yönde okunur (ceza düşük iyidir, açık puan
                  // yüksek). Aynı balonun içine iki sayı koymak, elin
                  // ortasında hangi sayının hangisi olduğunu düşündürürdü.
                  _MyOpenPoints(
                    // AÇILMADAN ÖNCE: ELİMDEKİ puan (ıstakada duran perlerin
                    // toplamı). AÇILDIKTAN SONRA: MASAYA koyduğum puan.
                    //
                    // Eskiden ikisinde de masa puanı yazıyordu; el açılmadan
                    // masada hiçbir şeyim olmadığı için rozet elin başından
                    // sonuna "0/101" gösteriyordu. Kullanıcının "mevcut puan
                    // gösterilmiyor" dediği tam olarak buydu: barajın
                    // neresinde olduğumu söylemesi gereken sayı, hep sıfırdı.
                    points: provider.isOpeningDone
                        ? provider.openPointsOf(mySeat)
                        : provider.openingCandidatePoints,
                    required: provider.requiredMinPoints,
                    isOpen: provider.isOpeningDone,
                    height: (m.consoleHeight * 0.52).clamp(16.0, 28.0),
                  ),
                ],
              ),
              // MASANIN DÖRT KÖŞESİ = DÖRT ISKARTA. Her ıskarta, onu ATAN ile
              // onu ALAN oyuncunun ARASINDAKİ köşede durur:
              //   sol alt  → solumdakinin attığı  (BEN çekerim, yeşil)
              //   sağ alt  → benim attığım        (sağımdaki çeker, mavi)
              //   sağ üst  → sağımdakinin attığı
              //   sol üst  → karşımdakinin attığı
              // Yerleşimin kendisi oyunun yönünü anlatır.
              cornerDiscardTopLeft: (context, m) => KeyedSubtree(
                key: _discardKeys[acrossSeat],
                child: seatBox(
                  acrossSeat,
                  m,
                  side: OkeySeatSide.left,
                  parts: OkeySeatParts.discard,
                ),
              ),
              cornerDiscardBottomLeft: (context, m) => KeyedSubtree(
                key: _discardKeys[leftSeat],
                child: seatBox(
                  leftSeat,
                  m,
                  side: OkeySeatSide.left,
                  parts: OkeySeatParts.discard,
                ),
              ),
              cornerDiscardTopRight: (context, m) => KeyedSubtree(
                key: _discardKeys[rightSeat],
                child: seatBox(
                  rightSeat,
                  m,
                  side: OkeySeatSide.right,
                  parts: OkeySeatParts.discard,
                ),
              ),
              myDiscard: (context, m) => KeyedSubtree(
                key: _discardKeys[mySeat],
                child: seatBox(
                  mySeat,
                  m,
                  isMe: true,
                  side: OkeySeatSide.right,
                  parts: OkeySeatParts.discard,
                ),
              ),
              // BİLGİ SÜTUNU: gösterge → okey → deste (dikey).
              // ÇAPA SÜTUNA DEĞİL DESTEYE: uçan taş destenin kendisinden
              // çıksın (bkz. OkeyIndicatorWidget.deckKey).
              island: (context, m) => OkeyIndicatorWidget(
                deckKey: _deckKey,
                vertical: true,
                indicatorTile: match.indicatorTile,
                // Okey taşı sunucudan geliyor; oyuncu göstergeden zihninden
                // türetmek zorunda kalmasın diye açıkça gösterilir
                // (özellikle 13 → 1 sarmasında sık hata kaynağıydı).
                okeyTile: match.okeyTile,
                deckRemaining: match.deckRemaining,
                isMyTurn: provider.isMyTurn,
                onTapDeck: provider.canDraw ? provider.drawFromDeck : null,
                canDragFromDeck: provider.canDraw,
                tileWidth: m.islandTileWidth,
              ),
              // AÇILAN PERLER — TEK ALAN, keçenin tüm genişliği. Ayrı bir
              // "çiftler" bölmesi yok: boş dururken bile yer tutuyordu ve
              // gerçek bir masada öyle bir bölge bulunmaz
              // (bkz. OkeyTableScaffold.melds).
              // SERİ ve GRUPLAR geniş tablaya, ÇİFTLER dar tablaya gider.
              // Ayrım kozmetik değil: çiftlere taş İŞLENEMEZ, dolayısıyla
              // aynı tablada dururken oyuncu her taş için "bu çift miydi"
              // diye eleme yapmak zorunda kalıyordu.
              melds: (context, m) => KeyedSubtree(
                key: _meldsKey,
                child: OkeyBoardWidget(
                  melds: provider.seriesMelds,
                  okeyTile: match.okeyTile,
                  canTapMelds: provider.canAddSelectedToMeld,
                  onTapMeld: provider.addSelectedTileToMeld,
                  onTileDroppedOnMeld: provider.canActOnHand
                      ? provider.addSlotTileToMeld
                      : null,
                  onDragEnd: provider.endDrag,
                  emptyHint: 'Açılan perler masaya buraya serilir',
                  tileWidth: m.meldTileWidth,
                  tileHeight: m.meldTileHeight,
                ),
              ),
              pairsBoard: (context, m) => OkeyBoardWidget(
                melds: provider.pairMelds,
                okeyTile: match.okeyTile,
                emptyHint: '',
                tileWidth: m.meldTileWidth,
                tileHeight: m.meldTileHeight,
              ),
              actions: (context, m) => provider.isSpectating
                  ? const SizedBox.shrink()
                  : _ActionRow(provider: provider),
              bottomExtra: (context, m) => provider.isSpectating
                  ? const SizedBox.shrink()
                  : _BottomExtra(provider: provider),
              modeBadges: _ModeBadges(provider: provider, match: match),
              topLeading: const _TopLeading(),
              topControls: _TopRightControls(provider: provider),
              // SÜRE ÇİZGİSİ — ıstakanın hemen üstünde, azalarak kısalır.
              // Toplam süre odadan gelir; admin panelinden ayarlanabilir.
              turnTimerBar: (context, m) => OkeyTurnTimerBar(
                secondsLeftListenable: provider.secondsLeftNotifier,
                totalSeconds: provider.room?.turnSeconds ?? 20,
                isMyTurn: provider.isMyTurn,
                height: OkeyTableMetrics.timerBarHeight,
              ),
              // DİZME ARAÇLARI — ISTAKANIN İKİ UCUNDA. Düzenledikleri nesneye
              // bitişik dururlar; üstlerindeki minik taşlar (5·5 / 1·2·3)
              // etiketten önce okunur.
              rackCapStart: provider.isSpectating
                  ? null
                  : (context, m) => OkeyDizCapButton.pairs(
                      active: provider.sortMode == OkeyRackSortMode.pairs,
                      onPressed: () =>
                          provider.setSortMode(OkeyRackSortMode.pairs),
                    ),
              rackCapEnd: provider.isSpectating
                  ? null
                  : (context, m) => OkeyDizCapButton.series(
                      active: provider.sortMode == OkeyRackSortMode.series,
                      onPressed: () =>
                          provider.setSortMode(OkeyRackSortMode.series),
                    ),
              // ISTAKA — iki dizme düğmesinin arasındaki tüm genişlik.
              // Genişlik ve ortalama artık OkeyTableScaffold'un işi; burada
              // yalnızca ahşap gövde ile taş satırları kurulur.
              rack: (context, m) => provider.isSpectating
                  ? _SpectatorBar(provider: provider)
                  : OkeyRackPanel(
                      rack: OkeyRackBarWidget(
                        metrics: m,
                        showChrome: false,
                        slots: provider.rackSlots,
                        selectedIndices: provider.selectedIndices,
                        canSelect: provider.canActOnHand,
                        onTap: provider.toggleTileSelection,
                        onMove: provider.moveTileToSlot,
                        onDragStart: provider.beginDrag,
                        onDragEnd: provider.endDrag,
                        onDrawDropped: (source, toSlot) =>
                            source == OkeyDragSource.deck
                            ? provider.drawFromDeck(toSlot: toSlot)
                            : provider.drawFromDiscard(toSlot: toSlot),
                        processableIndices: provider.processableTileIndices,
                        meldableIndices: provider.meldableTileIndices,
                        riskyIndices: provider.riskyDiscardIndices,
                        completeMeldSlots: provider.completeMeldSlots,
                        // Perlerin son taşından sonra boşluk bırakılır ki hangi
                        // taşların aynı pere ait olduğu gözle ayırt edilsin.
                        groupEndSlots: provider.groupEndSlots,
                        hiddenOkeySlots: provider.hiddenOkeySlots,
                        onDoubleTap: provider.toggleOkeyReveal,
                      ),
                    ),
            ),
          ),
          // HATA UYARISI: işlek bir taş yanlışlıkla ıskartaya atıldığında
          // kısa bir kırmızı yanıp-sönme. En üstte durur ama dokunma
          // olaylarını hiç yutmaz.
          Positioned.fill(
            child: IgnorePointer(
              child: _MistakeFlash(tick: provider.discardMistakeTick),
            ),
          ),
          // ANONS BANDI: "Seri açıldı" / "Çift açıldı" / "… son üç taş".
          // Anons SESLİ okunur (bkz. OkeySoundService.speak); bu bant onun
          // yazılı eşi — ses kapalıyken ya da cihazda Türkçe konuşma motoru
          // yokken bilgi kaybolmasın diye.
          Positioned.fill(
            child: IgnorePointer(
              child: OkeyAnnouncementBanner(listenable: provider.announcement),
            ),
          ),
          // UÇAN TAŞ — hangi taşın nereden nereye gittiğini GÖSTERİR
          // (kullanıcı isteği, 2026-09-06). Masanın ÜSTÜNDE ama dokunmayı
          // yutmayan bir katman; çapaları gerçek RenderBox'lardan okur.
          Positioned.fill(
            child: OkeyMoveFlightOverlay(
              move: provider.lastMove,
              mySeatNo: provider.mySeatNo,
              tileWidth: OkeyTableMetrics.from(
                BoxConstraints.tight(MediaQuery.sizeOf(context)),
              ).discardTileWidth,
              resolve: (anchor, seatNo) => switch (anchor) {
                OkeyAnchor.deck => _anchorRect(_deckKey),
                OkeyAnchor.melds => _anchorRect(_meldsKey),
                OkeyAnchor.discard => _anchorRect(_discardKeys[seatNo]),
                OkeyAnchor.seat => _anchorRect(_seatKeys[seatNo]),
              },
            ),
          ),
        ],
      ),
    );
  }

  /// El bitince gösterilen MODERN sonuç kartı.
  ///
  /// Eski hali düz bir AlertDialog'du: "Kazanan koltuk: 2" ve alt alta
  /// "Koltuk 1: 44" satırları — kimin kazandığı isim/profil olarak
  /// görünmüyordu. Artık kazanan vurgulanır, her oyuncu adı ve avatarıyla
  /// sıralanır.
  Future<void> _showHandResultDialog(
    BuildContext context,
    OkeyGameProvider provider,
  ) {
    final match = provider.match;
    final mySeat = provider.mySeatNo ?? 0;
    final iWon = match?.winnerSeat == mySeat;

    OkeyRoomSeat? seatOf(int n) {
      for (final s in provider.seats) {
        if (s.seatNo == n) return s;
      }
      return null;
    }

    String nameOf(int n) {
      final s = seatOf(n);
      if (s == null) return 'Boş';
      // Bot olup olmadığını ELE VERMEZ (bkz. OkeyRoomSeat.displayLabel).
      return s.displayLabel;
    }

    // Skorlar CEZADIR: düşük olan öndedir.
    final ranked = [
      0,
      1,
      2,
      3,
    ]..sort((a, b) => (match?.scores[a] ?? 0).compareTo(match?.scores[b] ?? 0));

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: OkeyColors.screenBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // BAŞLIK
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: iWon
                          ? [const Color(0xFFFFB300), const Color(0xFFFF8F00)]
                          : [
                              const Color(0xFF16556E),
                              OkeyColors.screenBackground,
                            ],
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(18),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        iWon ? Icons.emoji_events : Icons.flag,
                        size: 34,
                        color: iWon ? Colors.black87 : Colors.white70,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        iWon ? 'ELİ SEN KAZANDIN' : 'El Bitti',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                          color: iWon ? Colors.black87 : Colors.white,
                        ),
                      ),
                      if (match != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            match.winnerSeat == null
                                ? 'Deste bitti — kazanan yok'
                                : '${nameOf(match.winnerSeat!)} · ${_winTypeLabel(match.winType)}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: iWon ? Colors.black54 : Colors.white60,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // SKOR LİSTESİ
                if (match == null)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Sonuç alınamadı.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: Column(
                      children: List.generate(ranked.length, (i) {
                        final seatNo = ranked[i];
                        final s = seatOf(seatNo);
                        final isMe = seatNo == mySeat;
                        final isWinner = match.winnerSeat == seatNo;
                        // SATIRA DOKUNUNCA PROFİL — masadaki levhalarla aynı
                        // davranış (kullanıcı: "diğer kişilerin profiline
                        // tıklamasına izin verilsin"). El sonu kartı, bir
                        // rakibin kim olduğunu merak etmek için masadan bile
                        // daha doğal bir an.
                        final row = Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isMe
                                ? Colors.amber.withValues(alpha: 0.14)
                                : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isWinner
                                  ? Colors.amber
                                  : (isMe
                                        ? Colors.amber.withValues(alpha: 0.4)
                                        : Colors.white12),
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 8),
                              CircleAvatar(
                                radius: 15,
                                backgroundColor: Colors.white12,
                                // Botun fotoğrafı da çizilir ve fotoğrafsız
                                // bot robot ikonuyla değil, herkesle aynı
                                // kişi ikonuyla görünür.
                                backgroundImage: s?.avatarUrl == null
                                    ? null
                                    : NetworkImage(s!.avatarUrl!),
                                child: (s == null)
                                    ? const Icon(
                                        Icons.person_off,
                                        size: 14,
                                        color: Colors.white38,
                                      )
                                    : (s.avatarUrl == null
                                          ? const Icon(
                                              Icons.person,
                                              size: 14,
                                              color: Colors.white70,
                                            )
                                          : null),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  isMe
                                      ? '${nameOf(seatNo)} (Sen)'
                                      : nameOf(seatNo),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isWinner
                                        ? Colors.amber
                                        : Colors.white,
                                    fontWeight: isMe
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              if (isWinner)
                                const Padding(
                                  padding: EdgeInsets.only(right: 6),
                                  child: Icon(
                                    Icons.emoji_events,
                                    size: 15,
                                    color: Colors.amber,
                                  ),
                                ),
                              Text(
                                '${match.scores[seatNo] ?? 0}',
                                style: TextStyle(
                                  color: isWinner
                                      ? Colors.amber
                                      : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        );

                        if (s == null) return row;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => OkeyProfileSheet.show(
                            dialogContext,
                            userId: s.userId,
                            botProfileId: s.botProfileId,
                            name: s.displayLabel,
                            avatarUrl: s.avatarUrl,
                          ),
                          child: row,
                        );
                      }),
                    ),
                  ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'Düşük puan iyidir — skorlar cezadır.',
                    style: TextStyle(color: Colors.white30, fontSize: 10),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text(
                        'Devam Et',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _winTypeLabel(String? t) {
    switch (t) {
      case 'okey':
        return 'Okey ile bitiş (×2)';
      case 'elden':
        return 'Elden bitiş (×2)';
      case 'cift':
        return 'Çiftten bitiş (×2)';
      case 'elden_okey':
        return 'Elden + Okey (×4)';
      case 'normal':
        return 'Normal bitiş';
      default:
        return '-';
    }
  }

  /// Yeni el başladıysa ona geç, maç bittiyse lobiye dön.
  Future<void> _advanceToNextHandOrLeave(
    BuildContext context,
    OkeyGameProvider provider,
  ) async {
    String? next;
    try {
      next = await provider.checkForNextMatchId();
    } catch (_) {
      next = null;
    }
    if (!context.mounted) return;

    if (next != null) {
      // MAÇ SÜRÜYOR: sıradaki ele AYNI EKRANDA geçilir.
      //
      // Burada eskiden `pushReplacement(OkeyGameScreen(matchId: next))` vardı
      // ve kullanıcının bildirdiği hata tam olarak buydu: "2. el, 3. el
      // bittiğinde devam edilmiyor, tekrar yeni masa açmış gibi oluyor".
      // Ekran baştan kuruluyor, ekran yönü sıfırlanıp yeniden yatay yapılıyor,
      // masa boş bir yükleniyor çarkına düşüyor ve oyuncu kendini yeni bir
      // masaya oturmuş gibi hissediyordu. Provider artık maç kimliğini kendi
      // taşıyor: masa yerinde kalır, yalnızca el değişir.
      await provider.switchToMatch(next);
      return;
    }

    // MAÇ BİTTİ. Oyuncuyu uygulamanın en başına FIRLATMA — skor tablosunu
    // göster, nereye gideceğine kendisi karar versin.
    // (Eskiden burada popUntil(isFirst) vardı ve oyundan atılmış gibi
    // hissettiriyordu.)
    final match = provider.match;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        // DİKKAT: burada YENİ ROTANIN context'i kullanılmalı.
        //
        // Önce `builder: (_)` yazılıp onLeave, OYUN EKRANININ context'ini
        // yakalıyordu. pushReplacement oyun ekranını ağaçtan kaldırdığı için
        // o context ölüyor ve "Lobiye Dön" düğmesi hiçbir şey yapmıyordu.
        builder: (resultContext) => OkeyMatchResultScreen(
          seats: List<OkeyRoomSeat?>.generate(
            4,
            (i) => provider.seats.where((s) => s.seatNo == i).firstOrNull,
          ),
          // Ödeme özeti ("kim ne kazandı") oda üzerinden okunur; maç kaydı
          // değil, ODA potu dağıtır.
          roomId: provider.room?.id,
          scores: match?.scores ?? const {},
          mySeat: provider.mySeatNo ?? 0,
          teamMode: provider.teamModeRaw,
          handsPlayed: match?.handNo ?? 0,
          // "LOBİYE DÖN" GERÇEKTEN LOBİYE DÖNER (kullanıcı isteği,
          // 2026-09-05: "lobiye dön bastığında odaya atılsın").
          //
          // Eskiden `popUntil(isFirst)` vardı: bu, yığındaki HER ŞEYİ —
          // aradaki okey lobisi dahil — atıp oyuncuyu uygulamanın en başına
          // fırlatıyordu. Yani düğme "lobiye dön" yazdığı hâlde oyuncuyu
          // okeyden tamamen çıkarıyor, yeni bir masaya oturmak için okeyi
          // baştan açmak gerekiyordu.
          //
          // Neden ODAYA değil LOBİYE: maç bitince odanın kendisi de
          // kapanıyor (okey_rooms.status = 'finished'), yani o odaya dönmek
          // ölü bir ekran demek. Yeni masa da, aynı kişilerle yeniden oyun
          // da lobiden kuruluyor.
          //
          // pushAndRemoveUntil + isFirst: yığın her koşulda
          // [uygulama kökü, lobi] olur. Oyuncu masaya nereden gelirse gelsin
          // (lobi, davet bağlantısı, doğrudan oda) sonuç aynı ve geri tuşu
          // öngörülebilir kalır.
          // AYNI MASAYLA YENİDEN OYNA — kurulan/katılınan odanın bekleme
          // ekranına gider. Yığın [uygulama kökü, oda] olur: oyuncu oradan
          // geri basınca biten maçın sonucuna değil, uygulamaya döner.
          // Gezinme, SONUÇ EKRANININ KENDİ context'iyle yapılır — yakalanan
          // bir context'le değil. (Aynı hata bu dosyada bir kez yaşandı:
          // yakalanan context ölünce düğme sessizce hiçbir şey yapmıyordu.)
          onRematch: (ctx, newRoomId) => Navigator.of(ctx).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => OkeyRoomScreen(roomId: newRoomId),
            ),
            (r) => r.isFirst,
          ),
          onLeave: () => Navigator.of(resultContext).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const OkeyLobbyScreen()),
            (r) => r.isFirst,
          ),
        ),
      ),
    );
  }
}

/// KONSOLDAKİ AÇIK PUANIM — masaya serdiğim perlerin ve işlediğim taşların
/// toplamı.
///
/// ## Neden barajı da yazıyor
///
/// El açılmadan önce bu sayının tek bir anlamı var: baraja ne kadar kaldı.
/// "48" tek başına iyi mi kötü mü belli değil; "48 / 101" bir hedef koyar.
/// El açıldıktan sonra baraj anlamını yitirir ve yalnızca toplam kalır.
class _MyOpenPoints extends StatelessWidget {
  final int points;
  final int required;
  final bool isOpen;
  final double height;

  const _MyOpenPoints({
    required this.points,
    required this.required,
    required this.isOpen,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final reached = isOpen || points >= required;

    return MediaQuery.withNoTextScaling(
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: height * 0.32),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xF00A2733),
          borderRadius: BorderRadius.circular(height * 0.42),
          border: Border.all(
            color: reached
                ? OkeyColors.accentGold
                : OkeyColors.accentGold.withValues(alpha: 0.35),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.layers,
              size: height * 0.5,
              color: OkeyColors.accentGold,
            ),
            SizedBox(width: height * 0.18),
            OkeyOpenPointsText(
              points: points,
              fontSize: height * 0.5,
              color: OkeyColors.accentGold,
            ),
            if (!isOpen)
              Text(
                '/$required',
                maxLines: 1,
                style: TextStyle(
                  fontSize: height * 0.38,
                  height: 1.0,
                  fontWeight: FontWeight.w700,
                  color: const Color(0x8AFFFFFF),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Mod rozetleri + gösterge taşı + kalan deste + süre.
/// Keçenin SOL ÜSTÜNDEKİ mod rozetleri: Eşli / Katlamalı / Yardımlı / N. El.
///
/// Eskiden bunlar masanın ortasındaki dar "bilgi şeridi" panelinde, gösterge
/// ve deste ile alt alta duruyordu — dört rozet + gösterge + deste + skor bir
/// arada dar bir sütuna sığmayıp taşıyordu ("BOTTOM OVERFLOWED BY 122
/// PIXELS"). Artık tur boyunca değişmeyen referans bilgi (modlar) ile her
/// hamlede değişen bilgi (gösterge, deste) AYRILDI: modlar üst şeritte tek
/// satır, gösterge/deste masanın ortasında.
class _ModeBadges extends StatelessWidget {
  final OkeyGameProvider provider;
  final OkeyMatch match;

  const _ModeBadges({required this.provider, required this.match});

  @override
  Widget build(BuildContext context) {
    // SIRA REFERANSTAKİYLE AYNI ve keyfi değil: masaya OTURURKEN seçilenden
    // (eşli/eşsiz) el sırasında değişene (kaçıncı el) doğru gider.
    return OkeyModeBadgeStack(
      items: [
        (provider.teamModeLabel, Colors.lightBlueAccent),
        (provider.assistModeLabel, Colors.lightGreenAccent),
        (provider.gameModeLabel, Colors.redAccent),
        ('${match.handNo}. EL', Colors.white70),
      ],
    );
  }
}

/// İZLEYİCİ ŞERİDİ — ıstakanın yerine geçer.
///
/// ## Neden ıstakanın YERİNE, üstüne değil
///
/// İzleyicinin taşı yoktur; ıstakayı boş çizmek ekranın üçte birini
/// anlamsız bir tahtaya harcardı. Aynı yeri, izleyicinin gerçekten
/// ihtiyaç duyduğu üç şey doldurur: burada olduğunun teyidi, kaç kişinin
/// birlikte izlediği ve çıkış.
class _SpectatorBar extends StatelessWidget {
  final OkeyGameProvider provider;

  const _SpectatorBar({required this.provider});

  @override
  Widget build(BuildContext context) {
    final count = provider.spectators.length;

    return MediaQuery.withNoTextScaling(
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xF0123A4C), Color(0xF00A2130)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.visibility,
                  size: 20,
                  color: Color(0xFF9BE87C),
                ),
                const SizedBox(width: 8),
                const Text(
                  'MASAYI İZLİYORSUN',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.0,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                    color: Color(0xFFEAF6FA),
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  count <= 1 ? 'tek izleyici sensin' : '$count izleyici',
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.0,
                    color: Color(0x99FFFFFF),
                  ),
                ),
                const SizedBox(width: 16),
                // İZLEYİCİ DE HEDİYE GÖNDERİR (kullanıcı isteği: "seyirci ya
                // da normal oyuncu"). İzleyicinin masada yapabileceği tek
                // eylem bu olduğu için düğme burada, en görünür yerde durur.
                SizedBox(
                  height: 30,
                  child: OkeyButton(
                    label: 'HEDİYE',
                    icon: Icons.card_giftcard,
                    onPressed: () => showOkeyGiftSheet(context, provider),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 30,
                  child: OkeyButton(
                    label: 'AYRIL',
                    tone: OkeyButtonTone.ghost,
                    onPressed: () =>
                        Navigator.of(context).popUntil((r) => r.isFirst),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// HEDİYE SAYFASINI AÇAR — masadaki dört giriş noktası (oyuncu düğmesi,
/// izleyici şeridi ve ileride eklenecekler) aynı akışı kullansın diye tek
/// yerde durur.
void showOkeyGiftSheet(BuildContext context, OkeyGameProvider provider) {
  // CÜZDAN, üst şeritteki altın sayacını besliyor. Hediye bedeli sunucuda
  // düşüldüğü için sayaç kendiliğinden değişmez: gönderim biter bitmez
  // tazelenmezse oyuncu 100 puan harcayıp aynı sayıyı görmeye devam eder ve
  // hediyenin gerçekten gidip gitmediğinden emin olamaz.
  final points = context.read<OkeyPointsProvider>();

  OkeyGiftSheet.show(
    context,
    seats: provider.seats,
    mySeatNo: provider.mySeatNo,
    loadCatalog: provider.giftCatalog,
    onSend: (seatNo, giftCode) async {
      await provider.sendGift(seatNo, giftCode);
      // Cüzdan tazelemesi hediyeyi BEKLETMEZ: hata olursa hediye yine
      // gitmiştir, sayaç bir sonraki tazelemede düzelir.
      unawaited(points.refresh());
    },
  );
}

/// İZLEYİCİ SAYACI — masadaki oyuncular da izleyenleri görür.
///
/// Kullanıcı isteği: "masacılar izleyenleri görsün". Sayının kendisi yetmez;
/// dokununca KİMLER olduğu listelenir, çünkü tanımadığın birinin masanı
/// izlemesi ile arkadaşının izlemesi aynı şey değildir.
class _SpectatorChip extends StatelessWidget {
  final OkeyGameProvider provider;
  final double size;

  const _SpectatorChip({required this.provider, required this.size});

  @override
  Widget build(BuildContext context) {
    final list = provider.spectators;
    if (list.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showSpectators(context, list),
        child: MediaQuery.withNoTextScaling(
          child: Container(
            height: size,
            padding: EdgeInsets.symmetric(horizontal: size * 0.26),
            decoration: BoxDecoration(
              color: const Color(0xF00A2733),
              borderRadius: BorderRadius.circular(size * 0.30),
              border: Border.all(color: const Color(0x59FFFFFF), width: 1.1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.visibility,
                  size: size * 0.50,
                  color: const Color(0xFF9BE87C),
                ),
                SizedBox(width: size * 0.16),
                Text(
                  '${list.length}',
                  style: TextStyle(
                    fontSize: size * 0.42,
                    height: 1.0,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFFEAF6FA),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSpectators(BuildContext context, List<OkeySpectator> list) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OkeyUI.cardFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OkeyUI.radius),
          side: const BorderSide(color: OkeyUI.cardBorder),
        ),
        title: Text('Masayı izleyenler (${list.length})', style: OkeyUI.title),
        content: SizedBox(
          width: 320,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: list.length,
            itemBuilder: (_, i) {
              final s = list[i];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 15,
                  backgroundColor: Colors.white12,
                  backgroundImage: s.avatarUrl == null
                      ? null
                      : NetworkImage(s.avatarUrl!),
                  child: s.avatarUrl != null
                      ? null
                      : Icon(
                          s.isGuest ? Icons.person_outline : Icons.person,
                          size: 15,
                          color: Colors.white54,
                        ),
                ),
                title: Text(s.displayName, style: OkeyUI.body),
                subtitle: s.isGuest
                    ? const Text('Misafir', style: OkeyUI.caption)
                    : null,
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }
}

/// Üst şeridin SOL ucu: altın sayacı + MASA PUANI + saatlik bonus düğmesi.
///
/// Cüzdanı [OkeyPointsProvider]'dan okur. Bonus hazır değilse düğme sönük
/// kalır ve kalan süreyi yazar — kaybolmaz. "Yapılamaz" ile "yok" farklı
/// şeylerdir: kaybolan bir düğme, oyuncuya bir daha ne zaman geleceğini
/// söylemez.
///
/// ## Masa puanı neden BURADA (kullanıcı isteği: "masa puanı üstte gösterilsin")
///
/// Cüzdanın hemen yanında duruyor çünkü ikisi aynı para birimidir ve oyuncu
/// masaya oturmadan önce sorduğu tek soruyu ("bu masa bana kaça mal oluyor")
/// masanın içindeyken de sorabilmeli. Masanın ortasına ya da bir menüye
/// konsaydı, el sürerken bakılmayan bir bilgi olurdu.
class _TopLeading extends StatelessWidget {
  const _TopLeading();

  @override
  Widget build(BuildContext context) {
    final points = context.watch<OkeyPointsProvider>();
    final room = context.watch<OkeyGameProvider>().room;
    final m = OkeyTableMetrics.from(
      BoxConstraints.tight(MediaQuery.sizeOf(context)),
    );
    final h = (m.topStripHeight - 8).clamp(20.0, 40.0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OkeyCoinPill(
          amount: points.points,
          height: h,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const OkeyPointsScreen()),
          ),
        ),
        // Ücretsiz masa artık kurulamıyor ama eski/bozuk bir oda satırı 0
        // taşıyabilir; o zaman çip hiç çizilmez ("0 puanlık masa" yanlış
        // bir bilgidir).
        if (room != null && room.tableStake > 0) ...[
          const SizedBox(width: 6),
          OkeyStakePill(
            stake: room.tableStake,
            perHand: room.entryFee,
            hands: room.totalHands,
            height: h,
          ),
        ],
        const SizedBox(width: 6),
        OkeyHudActionButton.bonus(
          label: points.canClaimGift ? 'BONUS AL' : points.giftCountdownText,
          height: h,
          enabled: points.canClaimGift && !points.isBusy,
          onTap: points.claimHourlyGift,
        ),
      ],
    );
  }
}

/// Konsolun HAMLE düğmeleri: SERİ AÇ / ÇİFT AÇ / İŞLE / TAŞI AT.
///
/// ## Ne değişti (v3)
///
/// Eski hali sağ alt köşede 2x2'lik bir IZGARAYDI: dört düğme 104-190px
/// genişliğinde bir sütunu paylaşıyor, her biri ~90x30px'e sıkışıyordu.
/// 10px'lik etiket + rozet aynı satırda yarışınca "SERİ AÇ" çoğu telefonda
/// "SERİ..." diye kırpılıyordu.
///
/// Artık dördü de konsolun tek satırında, eşit genişlikte ve ~112x45px:
/// ikon üstte, etiket altta, sayaç rozeti ikonun yanında. Sıra da rastgele
/// değil, oyunun akışıyla aynı: önce AÇ (eli masaya koy), sonra İŞLE
/// (masadakini büyüt), en sonda AT (turu bitir).
class _ActionRow extends StatelessWidget {
  final OkeyGameProvider provider;

  const _ActionRow({required this.provider});

  @override
  Widget build(BuildContext context) {
    final p = provider;

    // "Açma" hamleleri nadirdir ve eli baştan aşağı değiştirir: barajı
    // geçtiğin an altın yanarlar. İşle/at ise her turun rutini — sakin kalır.
    final seriesReady = p.canLaySeries;
    final pairsReady = p.canLayPairs;

    // Seçim ŞART DEĞİL: hiçbir taş seçili değilse işlenebilen tüm taşlar
    // otomatik işlenir.
    final autoProcessable =
        p.selectedIndices.isEmpty && p.processableTiles.isNotEmpty;

    return OkeyButtonRow(
      children: [
        // GERİ KOY — yalnızca yandan alınan taş hâlâ geri konabilirken.
        //
        // Koşullu olarak eklenir çünkü hamlelerin rutini değil, bir KAÇIŞ
        // yoludur: yanlışlıkla alınan taşı geri koymanın tek alternatifi onu
        // atmaktı, o da +101 ceza demekti (kullanıcı isteği, 2026-09-05:
        // "yandan taş aldım, vazgeçtim; taşı geri yerine bırakayım, desteden
        // çekeyim"). Hep görünseydi dört rutin düğmenin arasında beşinci bir
        // seçenek olarak okunur, sıra her geldiğinde göz onu da tarardı.
        if (p.canUndoSideDraw)
          OkeyActionButton(
            title: 'GERİ KOY',
            icon: Icons.undo,
            tone: OkeyActionTone.ready,
            enabled: true,
            onPressed: p.undoSideDraw,
          ),
        OkeyActionButton(
          title: 'SERİ AÇ',
          icon: Icons.view_week,
          tone: seriesReady ? OkeyActionTone.ready : OkeyActionTone.normal,
          badge: p.isOpeningDone
              ? '${p.detectedSeriesGroups.length} per'
              : '${p.openingCandidatePoints}/${p.requiredMinPoints}',
          enabled: seriesReady,
          onPressed: seriesReady ? p.laySeries : null,
          // KAPALIYKEN SEBEBİNİ SÖYLER. Rozette "103/101" yazıp düğmenin
          // sönük kalması, oyuncunun kendi başına çözemeyeceği bir kilit.
          onBlockedTap: () => _explainBlocked(p, p.seriesBlockedReason),
        ),
        OkeyActionButton(
          title: 'ÇİFT AÇ',
          icon: Icons.filter_2,
          tone: pairsReady ? OkeyActionTone.ready : OkeyActionTone.normal,
          // Seri ile açan oyuncunun rozeti BU TURKİ hakkını gösterir
          // (RULES.md §3: tur başına en çok 3 çift): elindeki çift sayısını
          // göstermek, düğme hak dolduğu için kapalıyken yanıltıcı olurdu.
          badge: p.isOpeningDone
              ? (p.openedWithPairs
                    ? '${p.detectedPairCount} çift'
                    : '${p.seriesPairsThisTurn}'
                          '/${OkeyGameProvider.seriesPairsLimit}')
              : '${p.detectedPairCount}/${p.requiredMinPairs}',
          enabled: pairsReady,
          onPressed: pairsReady ? p.layPairs : null,
          onBlockedTap: () => _explainBlocked(p, p.pairsBlockedReason),
        ),
        OkeyActionButton(
          title: 'İŞLE',
          icon: Icons.playlist_add,
          badge: autoProcessable ? '${p.processableTiles.length}' : null,
          badgeColor: const Color(0xFF9BE87C),
          enabled:
              p.isOpeningDone &&
              p.canActOnHand &&
              (p.selectedIndices.isNotEmpty || p.processableTiles.isNotEmpty),
          onPressed: p.processSelectedTiles,
          onBlockedTap: () => _explainBlocked(p, p.processBlockedReason),
        ),
        OkeyActionButton(
          title: p.isOneTileFromWinning ? 'AT — BİTİR' : 'TAŞI AT',
          icon: p.isOneTileFromWinning
              ? Icons.emoji_events
              : Icons.arrow_downward,
          tone: p.isOneTileFromWinning
              ? OkeyActionTone.winning
              : OkeyActionTone.normal,
          enabled: p.canDiscardSelected,
          onPressed: p.canDiscardSelected ? p.discardSelectedTile : null,
          onBlockedTap: () => _explainBlocked(p, p.discardBlockedReason),
        ),
      ],
    );
  }
}

/// Kapalı bir düğmeye dokunulduğunda sebebini hata şeridine yazar.
///
/// Sebep hesaplanamıyorsa (mantıken olmamalı) genel bir cümle döner —
/// dokunuşun HİÇBİR ŞEY yapmaması, düğmenin bozuk olduğu izlenimini verirdi.
void _explainBlocked(OkeyGameProvider p, String? reason) {
  p.explain(reason ?? 'Bu hamle şu an yapılamıyor.');
}

/// Alt şeritte kartımın yanındaki ek içerik: "Çifte gidiyorum" işareti ve
/// henüz masaya konmamış hazırlanan gruplar.
class _BottomExtra extends StatelessWidget {
  final OkeyGameProvider provider;

  const _BottomExtra({required this.provider});

  @override
  Widget build(BuildContext context) {
    final p = provider;
    final children = <Widget>[];

    // BEYAN KUTUSU SIRA BEKLEMEZ.
    //
    // Eskiden yalnızca `canActOnHand` (kendi turumun ATMA aşaması) iken
    // görünüyordu; yani oyuncu çifte gitmeye ancak taş çektikten SONRA,
    // saniyeler içinde karar verebiliyordu. Sunucu böyle bir kısıt koymuyor
    // (bkz. okey_set_went_for_pairs: yalnızca el açılmamış olmalı) ve bot da
    // beyanı turun BAŞINDA, çekmeden önce veriyor. Kutuyu turlar boyunca
    // açık tutmak hem kuralla hem botla aynı hizaya getirir: oyuncu
    // rakipleri oynarken elini düşünüp karar verebilir.
    if (!p.isOpeningDone) {
      // Beyan GERİ ALINAMAZ (RULES.md §7): çiftle açmanın ön koşuludur ama
      // açamazsan ceza 202 yerine 404 olur. Bu yüzden tek dokunuşla değil,
      // ne olduğunu anlatan bir onayla verilir.
      //
      // Yeterli çifti olup HENÜZ BEYAN ETMEMİŞ oyuncuda kutu altın rengine
      // döner: "ÇİFT AÇ" butonu beyan olmadan açılmayacağı için, oyuncunun
      // neyin eksik olduğunu görmesi gerekir.
      final needsNudge =
          !p.wentForPairs && p.detectedPairCount >= p.requiredMinPairs;
      final accent = p.wentForPairs || needsNudge
          ? OkeyColors.accentGold
          : OkeyColors.hudTextDim;

      children.add(
        GestureDetector(
          onTap: p.wentForPairs
              ? null
              : () => _confirmGoingForPairs(context, p),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0x42000000),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: needsNudge ? accent : OkeyColors.hudBorder,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  p.wentForPairs ? Icons.lock : Icons.check_box_outline_blank,
                  size: 14,
                  color: accent,
                ),
                const SizedBox(width: 5),
                Text(
                  p.wentForPairs ? 'Çifte gidiyorum ✓' : 'Çifte gidiyorum',
                  style: TextStyle(
                    color: p.wentForPairs ? accent : OkeyColors.hudTextDim,
                    fontSize: 10,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Hazırlanan gruplar (henüz masaya konmadı) — dokununca geri alınır.
    for (var i = 0; i < p.stagedGroups.length; i++) {
      final g = p.stagedGroups[i];
      children.add(
        GestureDetector(
          onTap: () => p.unstageGroup(i),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: OkeyColors.accentGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: OkeyColors.accentGold),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: g
                  .map((t) => OkeyTileWidget(tile: t, small: true))
                  .toList(),
            ),
          ),
        ),
      );
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return MediaQuery.withNoTextScaling(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            children[i],
          ],
        ],
      ),
    );
  }

  /// "Çifte gidiyorum" onayı — beyan geri alınamadığı için ne kazanıp ne
  /// kaybettiği açıkça söylenir (RULES.md §7).
  Future<void> _confirmGoingForPairs(
    BuildContext context,
    OkeyGameProvider p,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      // Masadaki diyaloglar da modülün geri kalanıyla aynı dilde: koyu kart,
      // altın birincil aksiyon. Varsayılan AlertDialog açık temalıydı ve
      // masanın üstünde yabancı bir kutu gibi duruyordu.
      builder: (ctx) => AlertDialog(
        backgroundColor: OkeyUI.cardFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OkeyUI.radius),
          side: const BorderSide(color: OkeyUI.cardBorder),
        ),
        title: const Text('Çifte gidiyorum', style: OkeyUI.title),
        content: Text(
          'Bu karar bu el için GERİ ALINAMAZ.\n\n'
          '• ${p.requiredMinPairs} çift toplarsan çiftle açabilirsin.\n'
          '• Hiç açamazsan ceza 202 yerine 404 olur.',
          style: OkeyUI.body,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        actions: [
          SizedBox(
            width: 104,
            child: OkeyButton(
              label: 'Vazgeç',
              tone: OkeyButtonTone.ghost,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
          ),
          SizedBox(
            width: 152,
            child: OkeyButton(
              label: 'Çifte gidiyorum',
              tone: OkeyButtonTone.primary,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ),
        ],
      ),
    );
    if (ok == true) await p.declareGoingForPairs();
  }
}

/// Sağ ÜST köşedeki kontroller: ses efektleri, müzik ve ayarlar.
///
/// Yerleşimden bağımsız bir KATMAN olarak durur (bkz. OkeyTableScaffold),
/// yani masanın alanını hiç küçültmez.
class _TopRightControls extends StatelessWidget {
  final OkeyGameProvider provider;

  const _TopRightControls({required this.provider});

  @override
  Widget build(BuildContext context) {
    final m = OkeyTableMetrics.from(
      BoxConstraints.tight(MediaQuery.sizeOf(context)),
    );
    final h = (m.topStripHeight - 8).clamp(20.0, 40.0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SpectatorChip(provider: provider, size: h),
        // HEDİYE — masadaki bir oyuncuya çay/kahve gönder. Ses ve müzik
        // düğmelerinin YANINDA duruyor çünkü üçü de masanın "hamle olmayan"
        // eylemleri; hamle düğmeleriyle karışsaydı sıra bendeyken yanlışlıkla
        // basılan bir düğme olurdu.
        OkeyRoundIconButton(
          size: h,
          icon: Icons.card_giftcard,
          tooltip: 'Hediye gönder',
          accent: const Color(0xFFFFD54F),
          onTap: () => showOkeyGiftSheet(context, provider),
        ),
        const SizedBox(width: 5),
        OkeyRoundIconButton(
          size: h,
          icon: provider.isSoundOn ? Icons.volume_up : Icons.volume_off,
          tooltip: provider.isSoundOn ? 'Sesi kapat' : 'Sesi aç',
          accent: provider.isSoundOn ? null : const Color(0xFFFFB4A2),
          onTap: provider.toggleSound,
        ),
        const SizedBox(width: 5),
        OkeyRoundIconButton(
          size: h,
          icon: provider.isMusicOn ? Icons.music_note : Icons.music_off,
          tooltip: provider.isMusicOn ? 'Müziği kapat' : 'Müziği aç',
          onTap: provider.toggleMusic,
        ),
        const SizedBox(width: 5),
        // Referanstaki aşağı bakan ok: masanın MENÜSÜ. Ayrı bir dişli
        // ikonundan farkı yok, ama "burada bir çekmece var" demesi
        // öğrenilmesi gereken bir simgeden daha hızlı okunur.
        OkeyRoundIconButton(
          size: h,
          icon: Icons.keyboard_arrow_down,
          tooltip: 'Masa menüsü',
          onTap: () => _showSettings(context),
        ),
      ],
    );
  }

  void _showSettings(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => OkeyTableSettingsDialog(
        // Değerler GETTER olarak veriliyor: diyalog anahtarı çevirdikten
        // sonra provider'ın güncel halini okumalı, kurulduğu andaki
        // fotoğrafını değil.
        isSoundOn: () => provider.isSoundOn,
        isVoiceOn: () => provider.isVoiceOn,
        isMusicOn: () => provider.isMusicOn,
        onToggleSound: provider.toggleSound,
        onToggleVoice: provider.toggleVoice,
        onToggleMusic: provider.toggleMusic,
        // MASADAN AYRILMA, DİYALOĞUN DEĞİL MASANIN context'iyle yapılır:
        // diyalog kapandığı anda kendi context'i ölür ve gezinme sessizce
        // hiçbir şey yapmaz (aynı hata bu dosyada bir kez yaşandı).
        //
        // Hedef LOBİ — maç sonucu ekranındaki "ayrıl" ile aynı davranış.
        // Eskiden `popUntil((r) => r.isFirst)` çağrılıyordu; o, oyuncuyu
        // Okey'in tamamen dışına, uygulamanın ilk ekranına atıyordu.
        onLeaveTable: () => Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const OkeyLobbyScreen()),
          (r) => r.isFirst,
        ),
      ),
    );
  }
}

/// İşlek bir taş yanlışlıkla ıskartaya atıldığında kısa bir kırmızı
/// yanıp-sönme. [tick] her arttığında animasyon baştan oynar — saf Flutter
/// AnimationController kullanır (bkz. OkeyCornerPileWidget'taki _Pulse notu:
/// flutter_animate'in iç Timer'ı widget testlerinde "Timer is still
/// pending" hatasına yol açıyordu).
class _MistakeFlash extends StatefulWidget {
  final ValueListenable<int> tick;

  const _MistakeFlash({required this.tick});

  @override
  State<_MistakeFlash> createState() => _MistakeFlashState();
}

class _MistakeFlashState extends State<_MistakeFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final Animation<double> _opacity = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.0,
        end: 0.4,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 15,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.4,
        end: 0.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 85,
    ),
  ]).animate(_controller);

  @override
  void initState() {
    super.initState();
    widget.tick.addListener(_onTick);
  }

  void _onTick() {
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    widget.tick.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // KIRMIZI PERDE + AÇIK CÜMLE.
    //
    // Önce yalnızca perde vardı ve kullanıcı bunu "sanki normal taş atmış
    // gibi" diye bildirdi: ekranın kısa bir an kızarması, taşın işlenebilir
    // olduğunu ve BU YÜZDEN +101 yazıldığını söylemiyordu. Ceza sunucuda
    // zaten işliyordu (bkz. mistake_discard_penalty) — eksik olan, hatanın
    // ADIYLA duyurulmasıydı.
    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, _) {
        final t = _opacity.value;
        if (t <= 0) return const SizedBox.shrink();
        return Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: Colors.red.withValues(alpha: t)),
            ),
            Align(
              alignment: const Alignment(0, -0.35),
              child: Opacity(
                // Perde 0,4'te doyuyor; yazı onun iki buçuk katıyla okunur
                // kalsın diye ayrı ölçeklenir.
                opacity: (t / 0.4).clamp(0.0, 1.0),
                child: MediaQuery.withNoTextScaling(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xF2A31220),
                      borderRadius: BorderRadius.circular(OkeyUI.radiusSm),
                      border: Border.all(color: const Color(0xFFFFB3BD)),
                    ),
                    // Ceza MİKTARI burada yazılmaz: mistake_discard_penalty
                    // admin panelinden değiştirilebilir ve istemci onu
                    // okumaz. Bedeli, gerçek rakamı taşıyan skor balonu
                    // yazar (bkz. OkeyScoreBubble.pendingPenalty); buranın
                    // işi hatayı ADIYLA duyurmak.
                    child: const Text(
                      'İŞLEK TAŞ ATTIN — CEZA YAZILDI',
                      style: TextStyle(
                        color: Color(0xFFFFECEF),
                        fontSize: 15,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
