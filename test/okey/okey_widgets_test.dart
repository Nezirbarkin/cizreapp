import 'package:cizreapp/okey/okey.dart';
import 'package:cizreapp/okey/widgets/okey_indicator_widget.dart';
import 'package:cizreapp/okey/widgets/okey_action_panel_widget.dart';
import 'package:cizreapp/okey/widgets/okey_board_widget.dart';
import 'package:cizreapp/okey/widgets/okey_rack_bar_widget.dart';
import 'package:cizreapp/okey/widgets/okey_corner_pile_widget.dart';
import 'package:cizreapp/okey/widgets/okey_drag_payload.dart';
import 'package:cizreapp/okey/widgets/okey_tile_widget.dart';
import 'package:cizreapp/okey/widgets/okey_turn_timer_bar.dart';
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

  group('OkeyTurnTimerBar', () {
    // Sıra sayacı artık ıstakanın üstündeki AZALAN ÇİZGİDİR.
    //
    // Bu grubun ikinci testi gerçek bir ÇÖKME regresyonunu korur: sayaç
    // saniyede bir provider.notifyListeners() ile güncellenirse tüm masa
    // (sürüklenebilir taşlar ve DragTarget'lar dahil) yeniden kurulur ve
    // aktif bir sürükleme sırasında Flutter'ın Element ağacı bozulur.
    // Bu yüzden sayaç AYRI bir ValueListenable üzerinden akar.

    testWidgets('kalan süre azaldıkça çizgi kısalır', (tester) async {
      final seconds = ValueNotifier<int>(20);
      addTearDown(seconds.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: OkeyTurnTimerBar(
                secondsLeftListenable: seconds,
                totalSeconds: 20,
                isMyTurn: true,
              ),
            ),
          ),
        ),
      );

      double factor() => tester
          .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
          .widthFactor!;

      expect(factor(), closeTo(1.0, 0.001));

      seconds.value = 5;
      await tester.pump();
      expect(
        factor(),
        closeTo(0.25, 0.001),
        reason: 'süre azaldığında çizgi kısalmadı',
      );

      seconds.value = 0;
      await tester.pump();
      expect(factor(), closeTo(0.0, 0.001));
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
                  width: 400,
                  child: OkeyTurnTimerBar(
                    secondsLeftListenable: seconds,
                    totalSeconds: 20,
                    isMyTurn: true,
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

    testWidgets('sıra bende değilken soluk kalır', (tester) async {
      final seconds = ValueNotifier<int>(10);
      addTearDown(seconds.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: OkeyTurnTimerBar(
                secondsLeftListenable: seconds,
                totalSeconds: 20,
                isMyTurn: false,
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

    testWidgets('ÇİFT DİZ / SERİ DİZ butonları kurulur ve tıklanır', (
      tester,
    ) async {
      var tapped = false;
      await _pump(
        tester,
        SizedBox(
          height: 108,
          child: OkeyDizButton(
            title: 'ÇİFT DİZ',
            icon: Icons.filter_2,
            active: true,
            onPressed: () => tapped = true,
          ),
        ),
      );
      await tester.tap(find.byType(OkeyDizButton));
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
      expect(
        find.textContaining('perler masaya buraya serilir'),
        findsOneWidget,
      );

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
      expect(find.text('10'), findsOneWidget);
      expect(find.text('Ali'), findsOneWidget);
      expect(find.text('21'), findsOneWidget);
    });

    testWidgets('aksiyon butonu pasifken tıklanmaz', (tester) async {
      var tapped = false;
      await _pump(
        tester,
        SizedBox(
          width: 168,
          child: OkeyActionButton(
            title: 'SERİ AÇ',
            icon: Icons.view_week,
            badge: '46/101',
            enabled: false,
            onPressed: () => tapped = true,
          ),
        ),
      );
      expect(find.text('SERİ AÇ'), findsOneWidget);
      expect(find.text('46/101'), findsOneWidget);
      await tester.tap(find.byType(OkeyActionButton), warnIfMissed: false);
      expect(tapped, isFalse);
    });

    testWidgets('dar aksiyon sütununda + uzun rozetle TAŞMAZ (regresyon)', (
      tester,
    ) async {
      // OkeyTableMetrics.actionWidth alt sınırı 96'dır; buton kendi
      // Padding'leriyle (dış 4+4, iç 8+8) bu kadar dar bir gerçek genişlik
      // görebilir. Rozet ÖNCE sınırsız genişlikteydi — uzun bir rozet
      // ("103/101" gibi) bu genişlikte "RenderFlex overflowed" veriyordu.
      await _pump(
        tester,
        const SizedBox(
          width: 68,
          child: OkeyActionButton(
            title: 'SERİ AÇ',
            icon: Icons.view_week,
            badge: '103/101',
            onPressed: null,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
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
      // Kapalı taşın sayısı görünmemeli, açık olanınki görünmeli
      expect(find.text('2'), findsNothing, reason: 'okey kapalı olmalı');
      expect(find.text('7'), findsOneWidget);
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
      expect(find.text('2'), findsOneWidget, reason: 'yardımsızda okey açık');
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
      expect(find.text('1'), findsOneWidget);

      // Sayının ALTINDA, taşın rengiyle aynı renkte dolu bir çember olmalı
      final circle = tester.widgetList<Container>(find.byType(Container)).where(
        (c) {
          final d = c.decoration;
          return d is BoxDecoration &&
              d.shape == BoxShape.circle &&
              d.color == const Color(0xFF212121); // siyah taş rengi
        },
      );
      expect(
        circle.length,
        1,
        reason: 'aynı renkte tek bir dolu çember olmalı',
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
      expect(find.text('13'), findsOneWidget);
    });

    testWidgets('joker taşında çember yerine ikon var', (tester) async {
      await _pump(tester, const OkeyTileWidget(tile: OkeyTile.falseJoker()));
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
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
      expect(find.text('13'), findsOneWidget);
    });
  });
}
