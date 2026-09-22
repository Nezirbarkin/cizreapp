import 'package:cizreapp/okey/okey.dart';
import 'package:cizreapp/okey/widgets/okey_indicator_widget.dart';
import 'package:cizreapp/okey/widgets/okey_action_panel_widget.dart';
import 'package:cizreapp/okey/widgets/okey_board_widget.dart';
import 'package:cizreapp/okey/widgets/okey_rack_bar_widget.dart';
import 'package:cizreapp/okey/widgets/okey_corner_pile_widget.dart';
import 'package:cizreapp/okey/widgets/okey_drag_payload.dart';
import 'package:cizreapp/okey/widgets/okey_tile_widget.dart';
import 'package:cizreapp/okey/widgets/okey_action_dock.dart';
import 'package:cizreapp/okey/widgets/okey_turn_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bu dosya, oyun ekranının görsel bileşenlerini GERÇEKTEN inşa ederek
/// düzen (layout) hatalarını cihaz olmadan yakalar.
///
/// Neden var: canlı testte iki ayrı düzen hatası ancak cihazda ortaya çıktı —
///   1) "katlamalı" rafta negatif padding ('value.isNonNegative' assertion),
///   2) rakip taş rafında sınırsız/yetersiz Stack alanı (taşma).
/// Bu testler o sınıfın hatalarını derleme sonrası, cihaz gerekmeden yakalar.

/// Bir widget'ı gerçek boyutlarla kurar; herhangi bir layout assertion'ı
/// veya RenderFlex taşması testi düşürür.
Future<void> _pump(WidgetTester tester, Widget child, {Size? size}) async {
  tester.view.physicalSize = size ?? const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

OkeyRoomSeat _seat(int seatNo, {bool isBot = false, String? name}) =>
    OkeyRoomSeat(
      roomId: 'room-1',
      seatNo: seatNo,
      userId: isBot ? null : 'user-$seatNo',
      isReady: true,
      isBot: isBot,
      displayName: name,
    );

void main() {
  final okeyTile = OkeyTile.numbered(OkeyColor.red, 8);

  group('OkeyIndicatorWidget — masanın ortasındaki ada', () {
    testWidgets('gösterge → okey → deste soldan sağa dizilir', (tester) async {
      await _pump(
        tester,
        const OkeyIndicatorWidget(
          indicatorTile: OkeyTile.numbered(OkeyColor.red, 8),
          // Gösterge kırmızı 8 ise okey kırmızı 9'dur (RULES.md §1).
          okeyTile: OkeyTile.numbered(OkeyColor.red, 9),
          deckRemaining: 48,
          isMyTurn: true,
        ),
      );

      expect(find.text('48'), findsOneWidget);
      expect(find.text('GÖSTERGE'), findsOneWidget);
      // OKEY TAŞI AÇIKÇA GÖSTERİLİR: oyuncu göstergeden "bir üst rakam"
      // çevirmesini zihninden yapmak zorunda kalmasın (özellikle 13 → 1
      // sarmasında sık hata kaynağıydı).
      expect(find.text('OKEY'), findsOneWidget);
      expect(find.text('DESTE'), findsOneWidget);

      final indicator = tester.getCenter(find.text('GÖSTERGE'));
      final okey = tester.getCenter(find.text('OKEY'));
      final deckLabel = tester.getCenter(find.text('DESTE'));

      expect(
        indicator.dx,
        lessThan(okey.dx),
        reason: 'gösterge okeyin solunda değil',
      );
      expect(
        okey.dx,
        lessThan(deckLabel.dx),
        reason: 'okey destenin solunda değil',
      );

      // Kalan deste sayısı destenin İÇİNDE yazar — üstünde yüzen ayrı bir
      // etiket olsaydı ada bir satır daha uzardı ve keçenin dikey bütçesi
      // (bkz. OkeyTableMetrics.meldAreaHeight) açılan perlerden çalardı.
      final count = tester.getCenter(find.text('48'));
      final deckTile = tester.getCenter(
        find.byType(Draggable<OkeyDragPayload>),
      );
      expect(
        (count.dy - deckTile.dy).abs(),
        lessThan(8),
        reason: 'deste sayısı taşın içinde değil',
      );
    });

    testWidgets('okey verilmezse OKEY bölümü gizlenir', (tester) async {
      await _pump(
        tester,
        const OkeyIndicatorWidget(
          indicatorTile: OkeyTile.numbered(OkeyColor.red, 8),
          deckRemaining: 12,
          isMyTurn: false,
        ),
      );

      expect(find.text('GÖSTERGE'), findsOneWidget);
      expect(find.text('OKEY'), findsNothing);
    });
  });

  group('OkeyTurnRing', () {
    // Sıra sayacı artık SIRASI GELEN OYUNCUNUN AVATARINI çevreleyen bir
    // yaydır (düzen v5). Eskiden ıstakanın üstünde ayrı bir çizgiydi:
    // kimin süresi olduğunu söylemiyordu ve masadan dikey yer yiyordu.
    //
    // Bu grubun ikinci testi gerçek bir ÇÖKME regresyonunu korur: sayaç
    // saniyede bir provider.notifyListeners() ile güncellenirse tüm masa
    // (sürüklenebilir taşlar ve DragTarget'lar dahil) yeniden kurulur ve
    // aktif bir sürükleme sırasında Flutter'ın Element ağacı bozulur.
    // Bu yüzden sayaç AYRI bir ValueListenable üzerinden akar — yön
    // değişti, kural değişmedi.

    test('kalan süre azaldıkça yay kısalır', () {
      expect(OkeyTurnRing.fractionFor(20, 20), closeTo(1.0, 0.001));
      expect(OkeyTurnRing.fractionFor(5, 20), closeTo(0.25, 0.001));
      expect(OkeyTurnRing.fractionFor(0, 20), closeTo(0.0, 0.001));
      // Sunucudan gelen bozuk değerler yayı taşırmaz.
      expect(OkeyTurnRing.fractionFor(99, 20), closeTo(1.0, 0.001));
      expect(OkeyTurnRing.fractionFor(-3, 20), closeTo(0.0, 0.001));
      expect(OkeyTurnRing.fractionFor(10, 0), closeTo(0.5, 0.001));
    });

    testWidgets('sayaç güncellemesi TÜM ağacı yeniden kurmadan yansır', (
      tester,
    ) async {
      final seconds = ValueNotifier<int>(20);
      addTearDown(seconds.dispose);
      var outerBuilds = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                outerBuilds++;
                return SizedBox(
                  width: 48,
                  height: 48,
                  child: OkeyTurnRing(
                    secondsLeft: seconds,
                    totalSeconds: 20,
                    stroke: 3,
                  ),
                );
              },
            ),
          ),
        ),
      );

      final buildsAfterFirstPump = outerBuilds;

      seconds.value = 9;
      await tester.pump();
      seconds.value = 3;
      await tester.pump();

      expect(
        outerBuilds,
        buildsAfterFirstPump,
        reason:
            'sayaç, kendi dışındaki ağacı da yeniden kuruyor — '
            'bu, sürükleme sırasında çökmeye yol açan hatanın ta kendisi',
      );
    });

    testWidgets('kare avatarda da (dikey levha) sorunsuz çizilir', (
      tester,
    ) async {
      final seconds = ValueNotifier<int>(4);
      addTearDown(seconds.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 40,
                height: 40,
                // cornerRadius > 0 = yuvarlatılmış KARE yol. Yay orada elle
                // kurulan bir Path üzerinde yürür; dairede hiç çalışmayan
                // bir kod yolu olduğu için ayrıca denenmeli.
                child: OkeyTurnRing(
                  secondsLeft: seconds,
                  totalSeconds: 20,
                  stroke: 2.5,
                  cornerRadius: 5,
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('Yatay masa düzeni bileşenleri', () {
    testWidgets('ahşap ıstaka 21 taşla iki sıra halinde kurulur', (
      tester,
    ) async {
      final tiles = List<OkeyTile>.generate(
        21,
        (i) => OkeyTile.numbered(OkeyColor.values[i % 4], (i % 13) + 1),
      );
      await _pump(
        tester,
        SizedBox(
          width: 700,
          height: 108,
          child: OkeyRackBarWidget(
            slots: [...tiles, ...List<OkeyTile?>.filled(7, null)],
            selectedIndices: const {2, 5},
            onTap: (_) {},
            onMove: (_, __) {},
          ),
        ),
        size: const Size(1000, 500),
      );
      expect(find.byType(OkeyTileWidget), findsNWidgets(21));
    });

    testWidgets('ÇİFT DİZ / SERİ DİZ başlığı kurulur ve tıklanır', (
      tester,
    ) async {
      // v5: dizme araçları ıstakanın SOL başlığında alt alta durur. Başlık
      // yarı yüksekliğe indiği için kutu 54 px — düğme o boyda da kurulmalı.
      var tapped = false;
      await _pump(
        tester,
        SizedBox(
          width: 62,
          height: 54,
          child: OkeyDizCapButton.pairs(
            active: true,
            onPressed: () => tapped = true,
          ),
        ),
      );
      await tester.tap(find.byType(OkeyDizCapButton));
      expect(tapped, isTrue);
    });

    testWidgets('oyun tahtası boşken ve dolu haldeyken kurulur', (
      tester,
    ) async {
      await _pump(
        tester,
        const SizedBox(
          width: 400,
          height: 300,
          child: OkeyBoardWidget(melds: []),
        ),
        size: const Size(1000, 500),
      );
      // BOŞ TABLA SESSİZDİR (kullanıcı isteği, 2026-09-08): ipucu yazısı
      // keçedeki "CizreApp 101 OKEY" filigranının üstüne biniyordu.
      expect(find.byType(Text), findsNothing);

      await _pump(
        tester,
        SizedBox(
          width: 400,
          height: 300,
          child: OkeyBoardWidget(
            melds: [
              OkeyTableMeld(
                id: 1,
                matchId: 'm',
                laidBySeat: 0,
                meldType: 'run',
                tiles: [
                  OkeyTile.numbered(OkeyColor.blue, 5),
                  OkeyTile.numbered(OkeyColor.blue, 6),
                  OkeyTile.numbered(OkeyColor.blue, 7),
                ],
              ),
            ],
          ),
        ),
        size: const Size(1000, 500),
      );
      expect(find.byType(OkeyTileWidget), findsNWidgets(3));
    });

    testWidgets('köşe ıskarta kutusu taşı, adı ve taş sayısını gösterir', (
      tester,
    ) async {
      await _pump(
        tester,
        OkeyCornerPileWidget(
          size: 44,
          seat: _seat(1, name: 'Ali'),
          seatNo: 1,
          topDiscard: OkeyTile.numbered(OkeyColor.red, 10),
          tileCount: 21,
          score: 42,
          isCurrentTurn: true,
          isDrawSource: true,
        ),
      );
      // Iskarta taşının rakamı artık Canvas'a çiziliyor, bir Text widget
      // DEĞİL (bkz. OkeyTileWidget.debugNumberText) — ad ve sayaç hâlâ düz
      // Text olduğu için onlar aynı kaldı.
      expect(
        tester
            .widget<OkeyTileWidget>(find.byType(OkeyTileWidget))
            .debugNumberText,
        '10',
      );
      expect(find.text('Ali'), findsOneWidget);
      expect(find.text('21'), findsOneWidget);
    });

    testWidgets('dock düğmesi pasifken hamleyi DENEMEZ, sebebini sorar', (
      tester,
    ) async {
      // v5: hamleler dikey dock'ta. Kapalı düğme GÖRÜNÜR kalır ve dokunuşa
      // cevap verir — ama hamleyi değil, sebebini çalıştırır. Kaybolan ya da
      // sessiz kalan bir düğme oyuncuya hiçbir şey öğretmez.
      var pressed = 0;
      var explained = 0;

      await _pump(
        tester,
        SizedBox(
          width: 104,
          height: 160,
          child: OkeyActionDock(
            drawPhase: false,
            canOpen: false,
            openBadge: '46/101',
            onOpen: () => pressed++,
            onOpenBlocked: () => explained++,
          ),
        ),
      );

      expect(find.text('AÇ'), findsOneWidget);
      expect(find.text('46/101'), findsOneWidget);

      await tester.tap(find.text('AÇ'));
      await tester.pump();

      expect(pressed, 0, reason: 'kapalı düğme hamleyi DENEMEZ');
      expect(explained, 1, reason: 'sebep sorulmuş olmalı');
    });

    testWidgets('dar dock sütununda + uzun rozetle TAŞMAZ (regresyon)', (
      tester,
    ) async {
      // OkeyTableMetrics.actionDockWidth alt sınırı 82'dir ve dock kendi
      // dolgusunu da içeriden düşer. Dört satır düğme, "AT — BİTİR" gibi
      // uzun bir etiket ve "103/101" rozeti bu genişlikte yan yana
      // sığmalı — sığmazsa FittedBox küçültmeli, taşma OLMAMALI.
      await _pump(
        tester,
        const SizedBox(
          width: 82,
          height: 132,
          child: OkeyActionDock(
            drawPhase: false,
            canOpen: true,
            openBadge: '103/101',
            canProcess: true,
            autoProcessCount: 4,
            canDiscard: true,
            isWinningDiscard: true,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('çekme aşamasında dock TEK büyük düğmeye döner', (
      tester,
    ) async {
      // Dört sönük düğme yerine tek bir hedef: o an yapılabilecek tek şey
      // taş çekmek. Diğer üç etiket ekranda HİÇ bulunmamalı.
      await _pump(
        tester,
        SizedBox(
          width: 104,
          height: 160,
          child: OkeyActionDock(
            drawPhase: true,
            drawSubtitle: 'Desteden ya da soldan',
            onDraw: () {},
          ),
        ),
      );

      expect(find.text('TAŞ ÇEK'), findsOneWidget);
      expect(find.text('AÇ'), findsNothing);
      expect(find.text('İŞLE'), findsNothing);
      expect(find.text('TAŞI AT'), findsNothing);
    });
  });

  group('Yardımlı mod ipuçları', () {
    testWidgets('işlenebilir taş yeşil, meldable taş mavi çizgiyle kurulur', (
      tester,
    ) async {
      final tiles = List<OkeyTile>.generate(
        6,
        (i) => OkeyTile.numbered(OkeyColor.values[i % 4], (i % 13) + 1),
      );
      await _pump(
        tester,
        SizedBox(
          width: 700,
          height: 108,
          child: OkeyRackBarWidget(
            slots: [...tiles, ...List<OkeyTile?>.filled(22, null)],
            selectedIndices: const {},
            onTap: (_) {},
            onMove: (_, __) {},
            processableIndices: const {0, 1},
            meldableIndices: const {2, 3},
          ),
        ),
        size: const Size(1000, 500),
      );
      expect(find.byType(OkeyTileWidget), findsNWidgets(6));
    });

    testWidgets('ipucu olmayan raf da sorunsuz kurulur (yardımsız mod)', (
      tester,
    ) async {
      final tiles = List<OkeyTile>.generate(
        6,
        (i) => OkeyTile.numbered(OkeyColor.values[i % 4], (i % 13) + 1),
      );
      await _pump(
        tester,
        SizedBox(
          width: 700,
          height: 108,
          child: OkeyRackBarWidget(
            slots: [...tiles, ...List<OkeyTile?>.filled(22, null)],
            selectedIndices: const {},
            onTap: (_) {},
            onMove: (_, __) {},
          ),
        ),
        size: const Size(1000, 500),
      );
      expect(find.byType(OkeyTileWidget), findsNWidgets(6));
    });
  });

  group('HUD şeridi — taşma regresyonu', () {
    // TARİHÇE: mod rozetleri + gösterge + deste + skor bir ara masanın
    // ortasındaki 84px'lik dar bir SÜTUNDA alt alta duruyordu ve
    // "BOTTOM OVERFLOWED BY 122 PIXELS" veriyordu. Merkezi düzende ikisi
    // ayrıldı — rozetler üst şeritte tek satır, ada masanın ortasında — ama
    // her ikisinin de dar bir kutuda taşmaması hâlâ şart.

    testWidgets('mod rozetleri dar şeritte taşmaz', (tester) async {
      await _pump(
        tester,
        const SizedBox(
          width: 240,
          height: 26,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OkeyModeBadge(text: 'EŞLİ', color: Colors.blue),
                SizedBox(width: 5),
                OkeyModeBadge(text: 'KATLAMALI', color: Colors.red),
                SizedBox(width: 5),
                OkeyModeBadge(text: 'YARDIMLI', color: Colors.green),
                SizedBox(width: 5),
                OkeyModeBadge(text: '1. EL', color: Colors.white70),
              ],
            ),
          ),
        ),
        size: const Size(1000, 400),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('EŞLİ'), findsOneWidget);
    });

    testWidgets('ada dar ve kısa alanda taşmadan kurulur', (tester) async {
      await _pump(
        tester,
        SizedBox(
          width: 150,
          height: 70,
          child: OkeyIndicatorWidget(
            indicatorTile: okeyTile,
            okeyTile: OkeyTile.numbered(OkeyColor.red, 9),
            deckRemaining: 20,
            isMyTurn: true,
          ),
        ),
        size: const Size(1000, 400),
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'dar masada gösterge adası taştı',
      );
      expect(find.text('GÖSTERGE'), findsOneWidget);
    });
  });

  group('Okey taşı kapalı gösterimi + çift basma', () {
    // Gösterge 1 ise okey 2'dir. Aşağıda okey = Mavi 2 kabul edilir.
    testWidgets('kapalı okey arkası dönük görünür, sayısı okunmaz', (
      tester,
    ) async {
      final tiles = <OkeyTile?>[
        OkeyTile.numbered(OkeyColor.blue, 2), // okey
        OkeyTile.numbered(OkeyColor.red, 7),
        ...List<OkeyTile?>.filled(OkeyRackLayout.totalSlots - 2, null),
      ];
      await _pump(
        tester,
        SizedBox(
          width: 700,
          height: 108,
          child: OkeyRackBarWidget(
            slots: tiles,
            selectedIndices: const {},
            onTap: (_) {},
            onMove: (_, __) {},
            hiddenOkeySlots: const {0}, // 0. slot okey ve kapalı
          ),
        ),
        size: const Size(1000, 500),
      );
      // Kapalı taşın sayısı görünmemeli, açık olanınki görünmeli. Rakam
      // artık Canvas'a çiziliyor (bkz. OkeyTileWidget.debugNumberText).
      final rackTiles = tester
          .widgetList<OkeyTileWidget>(find.byType(OkeyTileWidget))
          .toList();
      final hiddenOkey = rackTiles.firstWhere(
        (w) => w.tile.color == OkeyColor.blue && w.tile.number == 2,
      );
      expect(hiddenOkey.debugNumberText, isNull, reason: 'okey kapalı olmalı');
      final visibleSeven = rackTiles.firstWhere(
        (w) => w.tile.color == OkeyColor.red && w.tile.number == 7,
      );
      expect(visibleSeven.debugNumberText, '7');
    });

    testWidgets('çift basınca onDoubleTap doğru slot ile tetiklenir', (
      tester,
    ) async {
      int? tapped;
      final tiles = <OkeyTile?>[
        OkeyTile.numbered(OkeyColor.blue, 2),
        ...List<OkeyTile?>.filled(OkeyRackLayout.totalSlots - 1, null),
      ];
      await _pump(
        tester,
        SizedBox(
          width: 700,
          height: 108,
          child: OkeyRackBarWidget(
            slots: tiles,
            selectedIndices: const {},
            onTap: (_) {},
            onMove: (_, __) {},
            hiddenOkeySlots: const {0},
            onDoubleTap: (i) => tapped = i,
          ),
        ),
        size: const Size(1000, 500),
      );
      await tester.tap(find.byType(OkeyTileWidget).first);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(OkeyTileWidget).first);
      await tester.pumpAndSettle();
      expect(tapped, 0);
    });

    testWidgets('yardımsız modda okey açık gösterilir (hiddenOkeySlots boş)', (
      tester,
    ) async {
      final tiles = <OkeyTile?>[
        OkeyTile.numbered(OkeyColor.blue, 2),
        ...List<OkeyTile?>.filled(OkeyRackLayout.totalSlots - 1, null),
      ];
      await _pump(
        tester,
        SizedBox(
          width: 700,
          height: 108,
          child: OkeyRackBarWidget(
            slots: tiles,
            selectedIndices: const {},
            onTap: (_) {},
            onMove: (_, __) {},
            hiddenOkeySlots: const {}, // yardımsız: hiçbiri gizli değil
          ),
        ),
        size: const Size(1000, 500),
      );
      final okeyTile = tester
          .widgetList<OkeyTileWidget>(find.byType(OkeyTileWidget))
          .firstWhere(
            (w) => w.tile.color == OkeyColor.blue && w.tile.number == 2,
          );
      expect(okeyTile.debugNumberText, '2', reason: 'yardımsızda okey açık');
    });
  });

  group('Lobi & bekleme odası modelleri', () {
    test('OkeyRoom doluluk hesabı doğru', () {
      final room = OkeyRoom(
        id: 'r1',
        createdBy: 'u1',
        status: 'waiting',
        isPrivate: false,
        maxScore: 101,
        turnSeconds: 20,
        gameMode: 'katlamali',
        teamMode: 'esli',
        assistMode: 'yardimli',
        entryFee: 500,
        createdAt: DateTime(2026, 1, 1),
        seatedCount: 2,
        botCount: 1,
        creatorName: 'Ali',
      );
      expect(room.occupiedSeats, 3);
      expect(room.isFull, isFalse);
    });

    test('4 koltuk dolduysa masa dolu sayılır', () {
      final room = OkeyRoom(
        id: 'r2',
        createdBy: 'u1',
        status: 'waiting',
        isPrivate: false,
        maxScore: 101,
        turnSeconds: 20,
        gameMode: 'katlamasiz',
        teamMode: 'essiz',
        assistMode: 'yardimsiz',
        createdAt: DateTime(2026, 1, 1),
        seatedCount: 3,
        botCount: 1,
      );
      expect(room.occupiedSeats, 4);
      expect(room.isFull, isTrue);
    });

    test('okey_list_open_rooms alanları modele okunur', () {
      final room = OkeyRoom.fromMap({
        'id': 'r3',
        'created_by': 'u9',
        'creator_name': 'Veli',
        'creator_avatar': null,
        'status': 'waiting',
        'is_private': false,
        'join_code': null,
        'max_score': 101,
        'turn_seconds': 20,
        'game_mode': 'katlamali',
        'team_mode': 'esli',
        'assist_mode': 'yardimsiz',
        'entry_fee': 1000,
        'current_match_id': null,
        'seated_count': 2,
        'bot_count': 0,
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(room.creatorName, 'Veli');
      expect(room.entryFee, 1000);
      expect(room.occupiedSeats, 2);
      expect(room.teamMode, 'esli');
    });
  });

  group('OkeyTileWidget', () {
    testWidgets('sayının altında aynı renkte dolu çember var', (tester) async {
      await _pump(
        tester,
        OkeyTileWidget(tile: OkeyTile.numbered(OkeyColor.black, 1)),
      );
      // Rakam VE altındaki dolu çember artık ikisi de Canvas'a, TEK
      // painter'da çiziliyor (bkz. OkeyTileWidget class dokümanı,
      // "TAŞIN YÜZÜ TEK BİR ÇİZİMDİR") — ne bir Text ne bir Container var.
      // İkisi de AYNI `color`den türediği için (bkz. _glyphFor: `pipColor:
      // color`), rengin doğruluğu ikisini birden kanıtlar.
      final w = tester.widget<OkeyTileWidget>(find.byType(OkeyTileWidget));
      expect(w.debugNumberText, '1');
      expect(
        w.debugGlyphColor,
        const Color(0xFF212121), // siyah taş rengi
        reason: 'rakam ve altındaki dolu çember aynı renkte olmalı',
      );
    });

    testWidgets('küçük (small) taşta da çember taşmadan sığar', (tester) async {
      // Istakadaki gerçek boyut: 30x40 — çember eklenince taşmamalı
      await _pump(
        tester,
        SizedBox(
          width: 40,
          height: 44,
          child: Center(
            child: OkeyTileWidget(
              tile: OkeyTile.numbered(OkeyColor.red, 13),
              small: true,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<OkeyTileWidget>(find.byType(OkeyTileWidget))
            .debugNumberText,
        '13',
      );
    });

    testWidgets('joker taşında çember yerine ikon var', (tester) async {
      await _pump(tester, const OkeyTileWidget(tile: OkeyTile.falseJoker()));
      // İkon artık `Icon` widget'ı değil, taşın diğer rakamlarıyla AYNI
      // Canvas painter'ında çiziliyor (bkz. OkeyTileWidget.debugShowsJokerIcon).
      final w = tester.widget<OkeyTileWidget>(find.byType(OkeyTileWidget));
      expect(w.debugShowsJokerIcon, isTrue);
      expect(w.debugNumberText, isNull, reason: 'joker rakam göstermemeli');
    });

    testWidgets('sayı taşı, joker ve kapalı taş hatasız kurulur', (
      tester,
    ) async {
      await _pump(
        tester,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OkeyTileWidget(tile: OkeyTile.numbered(OkeyColor.black, 13)),
            const OkeyTileWidget(tile: OkeyTile.falseJoker()),
            const OkeyTileWidget(tile: OkeyTile.falseJoker(), faceDown: true),
            OkeyTileWidget(
              tile: OkeyTile.numbered(OkeyColor.yellow, 1),
              selected: true,
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      final first = tester
          .widgetList<OkeyTileWidget>(find.byType(OkeyTileWidget))
          .first;
      expect(first.debugNumberText, '13');
    });
  });
}
