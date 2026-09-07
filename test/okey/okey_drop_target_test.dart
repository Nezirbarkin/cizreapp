import 'package:cizreapp/okey/engine/okey_rack_layout.dart';
import 'package:cizreapp/okey/engine/okey_tile.dart';
import 'package:cizreapp/okey/models/okey_models.dart';
import 'package:cizreapp/okey/widgets/okey_board_widget.dart';
import 'package:cizreapp/okey/widgets/okey_drag_payload.dart';
import 'package:cizreapp/okey/widgets/okey_indicator_widget.dart';
import 'package:cizreapp/okey/widgets/okey_rack_bar_widget.dart';
import 'package:cizreapp/okey/widgets/okey_corner_pile_widget.dart';
import 'package:cizreapp/okey/widgets/okey_table_metrics.dart';
import 'package:cizreapp/okey/widgets/okey_table_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// GERÇEK SÜRÜKLE-BIRAK TESTLERİ
///
/// NEDEN VAR: Mevcut sürükleme testleri widget'ları yalnızca KURUYORDU
/// (çökmüyor mu diye). Gerçekten parmakla sürükleyip bırakma yapmadıkları
/// için, bırakmanın hiç gerçekleşmediği bir hatayı kaçırdılar:
/// kullanıcı desteden çektiği taşı ıstakaya bırakamıyor, elindeki taşı da
/// ıskartaya atamıyordu.
///
/// Bu testler tam olarak o iki hareketi yapar ve geri çağrının ÇALIŞTIĞINI
/// doğrular. Yerleşim, ekranın gerçekte kullandığı [OkeyTableScaffold]
/// içinde kurulur — çünkü hatanın yerleşim sarmalayıcılarından kaynaklanma
/// ihtimali vardı ve sadeleştirilmiş bir kurulum onu gizlerdi.

OkeyRoomSeat _seat(int n) => OkeyRoomSeat(
  roomId: 'r',
  seatNo: n,
  userId: 'u$n',
  isReady: true,
  isBot: false,
  displayName: 'Oyuncu $n',
);

List<OkeyTile?> _rackWithTiles() {
  final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
  slots[0] = OkeyTile.numbered(OkeyColor.red, 5);
  slots[1] = OkeyTile.numbered(OkeyColor.blue, 6);
  return slots;
}

/// Gerçek cihaz boyutları. Sürükle-bırak HER BOYUTTA çalışmak zorunda:
/// ıskartaya atma ve desteden çekme oyunun temel hareketleridir, küçük
/// ekranda kaybolurlarsa oyun oynanamaz hale gelir.
const _sizes = <String, Size>{
  'küçük telefon 640x360': Size(640, 360),
  'yaygın telefon 800x360': Size(800, 360),
  'orta telefon 892x412': Size(892, 412),
  'büyük telefon 1000x480': Size(1000, 480),
  'tablet 1280x800': Size(1280, 800),
};

/// Masayı, ekranın gerçekte kurduğu düzenle kurar.
Future<void> _pumpForSize(
  WidgetTester tester, {
  required void Function(OkeyDragSource) onDrawDropped,
  required void Function(int fromSlot) onDiscardDropped,
  void Function(int from, int to)? onMove,
  Size size = const Size(1000, 480),
  bool canDraw = true,
  bool canDiscard = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: OkeyTableScaffold(
            seatAcross: (c, m) => OkeyCornerPileWidget(
              size: m.discardTileWidth,
              side: OkeySeatSide.top,
              parts: OkeySeatParts.identity,
              seat: _seat(2),
              seatNo: 2,
              tileCount: 21,
              isCurrentTurn: false,
            ),
            seatLeft: (c, m) => OkeyCornerPileWidget(
              size: m.discardTileWidth,
              side: OkeySeatSide.left,
              parts: OkeySeatParts.identity,
              seat: _seat(1),
              seatNo: 1,
              tileCount: 21,
              isCurrentTurn: false,
            ),
            seatRight: (c, m) => OkeyCornerPileWidget(
              size: m.discardTileWidth,
              side: OkeySeatSide.right,
              parts: OkeySeatParts.identity,
              seat: _seat(3),
              seatNo: 3,
              tileCount: 21,
              isCurrentTurn: false,
            ),
            seatMine: (c, m) => OkeyCornerPileWidget(
              size: m.discardTileWidth,
              side: OkeySeatSide.bottom,
              parts: OkeySeatParts.identity,
              seat: _seat(0),
              seatNo: 0,
              tileCount: 21,
              isCurrentTurn: true,
              isMe: true,
            ),
            // SOL ÜST köşe: karşımdakinin ıskartası.
            cornerDiscardTopLeft: (c, m) => OkeyCornerPileWidget(
              size: m.discardTileWidth,
              side: OkeySeatSide.left,
              parts: OkeySeatParts.discard,
              seat: _seat(2),
              seatNo: 2,
              tileCount: 21,
              isCurrentTurn: false,
            ),
            // SOL ALT köşe: solumdakinin ıskartası — taş BURADAN çekilir.
            cornerDiscardBottomLeft: (c, m) => OkeyCornerPileWidget(
              size: m.discardTileWidth,
              side: OkeySeatSide.left,
              parts: OkeySeatParts.discard,
              seat: _seat(1),
              seatNo: 1,
              topDiscard: OkeyTile.numbered(OkeyColor.black, 3),
              tileCount: 21,
              isCurrentTurn: false,
              isDrawSource: canDraw,
            ),
            // SAĞ ÜST köşe: sağımdakinin ıskartası.
            cornerDiscardTopRight: (c, m) => OkeyCornerPileWidget(
              size: m.discardTileWidth,
              side: OkeySeatSide.right,
              parts: OkeySeatParts.discard,
              seat: _seat(3),
              seatNo: 3,
              tileCount: 21,
              isCurrentTurn: false,
            ),
            // SAĞ ALT köşe: KENDİ ıskartam — taş buraya bırakılarak atılır.
            // Attığım taşı sağdaki oyuncu alır.
            myDiscard: (c, m) => OkeyCornerPileWidget(
              size: m.discardTileWidth,
              side: OkeySeatSide.right,
              parts: OkeySeatParts.discard,
              seat: _seat(0),
              seatNo: 0,
              tileCount: 21,
              isCurrentTurn: true,
              isMe: true,
              isDiscardTarget: canDiscard,
              onTileDropped: onDiscardDropped,
            ),
            melds: (c, m) => const OkeyBoardWidget(melds: []),
            // Deste, per alanının sağındaki bilgi sütunundadır
            // (gösterge → okey → deste).
            island: (c, m) => OkeyIndicatorWidget(
              vertical: true,
              indicatorTile: OkeyTile.numbered(OkeyColor.red, 10),
              okeyTile: OkeyTile.numbered(OkeyColor.red, 11),
              deckRemaining: 20,
              isMyTurn: true,
              canDragFromDeck: canDraw,
              tileWidth: m.islandTileWidth,
            ),
            actions: (c, m) => const SizedBox.shrink(),
            rack: (c, m) => OkeyRackBarWidget(
              metrics: m,
              slots: _rackWithTiles(),
              selectedIndices: const {},
              onTap: (_) {},
              onMove: onMove ?? (_, __) {},
              onDrawDropped: (src, _) => onDrawDropped(src),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  _sizeIndependenceGroup();
  _realisticGestureGroup();

  testWidgets('desteden çekilen taş ISTAKAYA bırakılabilir', (tester) async {
    OkeyDragSource? dropped;
    await _pumpForSize(
      tester,
      onDrawDropped: (s) => dropped = s,
      onDiscardDropped: (_) {},
      onMove: (_, __) {},
    );

    // Deste, masanın ortasındaki gösterge şeridindeki KAPALI taştır
    final deck = find.descendant(
      of: find.byType(OkeyIndicatorWidget),
      matching: find.byType(Draggable<OkeyDragPayload>),
    );
    expect(deck, findsOneWidget, reason: 'destede sürüklenebilir taş yok');

    // Istakadaki GERÇEK bir taşın üzerine bırak.
    // (Istakanın geometrik merkezi iki taş satırı ARASINDAKİ boşluğa denk
    // gelir; oraya bırakmak gerçek kullanımı temsil etmez.)
    final target = tester.getCenter(
      find
          .descendant(
            of: find.byType(OkeyRackBarWidget),
            matching: find.byType(Draggable<OkeyDragPayload>),
          )
          .first,
    );

    final gesture = await tester.startGesture(tester.getCenter(deck));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(target);
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      dropped,
      OkeyDragSource.deck,
      reason: 'desteden çekilen taş ıstakaya BIRAKILAMADI',
    );
  });

  testWidgets('elimdeki taş KENDİ ıskartama bırakılarak atılabilir', (
    tester,
  ) async {
    int? discardedSlot;
    await _pumpForSize(
      tester,
      onDrawDropped: (_) {},
      onDiscardDropped: (slot) => discardedSlot = slot,
      onMove: (_, __) {},
    );

    // Istakadaki ilk taşı tut
    final rackTiles = find.descendant(
      of: find.byType(OkeyRackBarWidget),
      matching: find.byType(Draggable<OkeyDragPayload>),
    );
    expect(rackTiles, findsWidgets);

    // KENDİ ISKARTAM — kimlik kartımdan AYRI bir widget'tır ve masanın SAĞ
    // alt köşesinde durur (attığım taşı sağdaki oyuncu alır). Bu yüzden
    // yalnızca `isMe` aramak yetmez: kimlik kartı da isMe'dir, iki eşleşme
    // döner. Bırakma hedefi olan parça açıkça seçilir.
    final myPileBox = find.byWidgetPredicate(
      (w) =>
          w is OkeyCornerPileWidget &&
          w.isMe &&
          w.parts == OkeySeatParts.discard,
    );
    expect(
      myPileBox,
      findsOneWidget,
      reason: 'kendi ıskarta kutum ekranda YOK',
    );

    final myPile = find.descendant(
      of: myPileBox,
      matching: find.byType(DragTarget<OkeyDragPayload>),
    );
    expect(myPile, findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(rackTiles.first),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(tester.getCenter(myPile));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      discardedSlot,
      isNotNull,
      reason: 'taş kendi ıskartama BIRAKILAMADI (atılamadı)',
    );
  });

  testWidgets('soldaki oyuncunun ıskartasından çekip ıstakaya bırakabilirim', (
    tester,
  ) async {
    OkeyDragSource? dropped;
    await _pumpForSize(
      tester,
      onDrawDropped: (s) => dropped = s,
      onDiscardDropped: (_) {},
      onMove: (_, __) {},
    );

    final leftSeat = find.byWidgetPredicate(
      (w) => w is OkeyCornerPileWidget && w.isDrawSource,
    );
    expect(leftSeat, findsOneWidget);

    final leftPile = find.descendant(
      of: leftSeat,
      matching: find.byType(Draggable<OkeyDragPayload>),
    );
    expect(
      leftPile,
      findsOneWidget,
      reason: 'soldaki oyuncunun ıskarta kutusu ekranda YOK',
    );

    final gesture = await tester.startGesture(tester.getCenter(leftPile));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(
      tester.getCenter(
        find
            .descendant(
              of: find.byType(OkeyRackBarWidget),
              matching: find.byType(Draggable<OkeyDragPayload>),
            )
            .first,
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      dropped,
      OkeyDragSource.discard,
      reason: 'ıskartadan çekilen taş ıstakaya bırakılamadı',
    );
  });

  testWidgets('ıstaka içinde taş başka slota taşınabilir', (tester) async {
    int? from;
    int? to;
    await _pumpForSize(
      tester,
      onDrawDropped: (_) {},
      onDiscardDropped: (_) {},
      onMove: (f, t) {
        from = f;
        to = t;
      },
    );

    final rackTiles = find.descendant(
      of: find.byType(OkeyRackBarWidget),
      matching: find.byType(Draggable<OkeyDragPayload>),
    );

    // İlk taşı al, birkaç slot sağa taşı
    final start = tester.getCenter(rackTiles.first);
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(start + const Offset(140, 0));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(from, isNotNull, reason: 'ıstaka içinde taşıma çalışmıyor');
    expect(to, isNot(from));
  });
}

/// EKRAN BOYUTUNDAN BAĞIMSIZLIK
///
/// Yerleşim, dar ekranlarda yer kazanmak için koltuk kartındaki bazı öğeleri
/// gizleyebiliyor. Bu tehlikeli: gizlenen öğelerden biri ıskarta kutusuysa,
/// o kutu aynı zamanda TAŞ ATMA hedefi olduğu için oyun küçük ekranda
/// oynanamaz hale gelir. Aşağıdaki testler tam olarak bunu kovalar.
void _sizeIndependenceGroup() {
  group('Sürükle-bırak her ekran boyutunda çalışır', () {
    _sizes.forEach((label, size) {
      testWidgets('$label — kendi ıskartama taş atabilirim', (tester) async {
        int? discarded;
        await _pumpForSize(
          tester,
          size: size,
          onDiscardDropped: (s) => discarded = s,
          onDrawDropped: (_) {},
        );

        final mySeat = find.byWidgetPredicate(
          (w) => w is OkeyCornerPileWidget && w.isMe,
        );
        final myPile = find.descendant(
          of: mySeat,
          matching: find.byType(DragTarget<OkeyDragPayload>),
        );
        expect(
          myPile,
          findsOneWidget,
          reason: '$label: ıskarta kutusu (atma hedefi) ekranda YOK',
        );

        final rackTile = find
            .descendant(
              of: find.byType(OkeyRackBarWidget),
              matching: find.byType(Draggable<OkeyDragPayload>),
            )
            .first;

        final g = await tester.startGesture(tester.getCenter(rackTile));
        await tester.pump(const Duration(milliseconds: 20));
        await g.moveTo(tester.getCenter(myPile));
        await tester.pump(const Duration(milliseconds: 20));
        await g.up();
        await tester.pumpAndSettle();

        expect(discarded, isNotNull, reason: '$label: taş atılamadı');
      });

      testWidgets('$label — desteden çekip ıstakaya bırakabilirim', (
        tester,
      ) async {
        OkeyDragSource? dropped;
        await _pumpForSize(
          tester,
          size: size,
          onDiscardDropped: (_) {},
          onDrawDropped: (s) => dropped = s,
        );

        final deck = find.descendant(
          of: find.byType(OkeyIndicatorWidget),
          matching: find.byType(Draggable<OkeyDragPayload>),
        );
        expect(deck, findsOneWidget, reason: '$label: deste ekranda YOK');

        final rackTile = find
            .descendant(
              of: find.byType(OkeyRackBarWidget),
              matching: find.byType(Draggable<OkeyDragPayload>),
            )
            .first;

        final g = await tester.startGesture(tester.getCenter(deck));
        await tester.pump(const Duration(milliseconds: 20));
        await g.moveTo(tester.getCenter(rackTile));
        await tester.pump(const Duration(milliseconds: 20));
        await g.up();
        await tester.pumpAndSettle();

        expect(
          dropped,
          OkeyDragSource.deck,
          reason: '$label: desteden çekilen taş ıstakaya bırakılamadı',
        );
      });
    });
  });
}

/// GERÇEKÇİ PARMAK HAREKETİ
///
/// Yukarıdaki testler hedefe TEK HAMLEDE sıçrıyor. Gerçek bir parmak ise
/// küçük adımlarla ilerler ve bu, Flutter'ın "jest arenası"nda farklı
/// sonuçlanabilir: ıstaka satırları yatay kaydırılabilir olduğu için
/// kaydırma jesti sürükleme jestini yenip taşı hiç kaldırmayabilir.
/// Kullanıcının bildirdiği "taş bırakılmıyor" hatası tam olarak bu sınıfa
/// giriyor, bu yüzden ayrıca kademeli hareketle test edilir.
void _realisticGestureGroup() {
  group('Gerçekçi (kademeli) parmak hareketi', () {
    testWidgets('ıstakadan taşı YAVAŞÇA sürükleyip ıskartaya atabilirim', (
      tester,
    ) async {
      int? discarded;
      await _pumpForSize(
        tester,
        size: const Size(800, 360),
        onDiscardDropped: (s) => discarded = s,
        onDrawDropped: (_) {},
      );

      final mySeat = find.byWidgetPredicate(
        (w) => w is OkeyCornerPileWidget && w.isMe,
      );
      final myPile = find.descendant(
        of: mySeat,
        matching: find.byType(DragTarget<OkeyDragPayload>),
      );
      final rackTile = find
          .descendant(
            of: find.byType(OkeyRackBarWidget),
            matching: find.byType(Draggable<OkeyDragPayload>),
          )
          .first;

      final start = tester.getCenter(rackTile);
      final end = tester.getCenter(myPile);

      final g = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 16));
      // 20 küçük adımda ilerle — gerçek bir parmak gibi
      for (var i = 1; i <= 20; i++) {
        await g.moveTo(Offset.lerp(start, end, i / 20)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();

      expect(
        discarded,
        isNotNull,
        reason:
            'yavaş sürüklemede taş atılamadı — '
            'muhtemelen yatay kaydırma jesti sürüklemeyi yeniyor',
      );
    });

    testWidgets('desteden taşı YAVAŞÇA sürükleyip ıstakaya bırakabilirim', (
      tester,
    ) async {
      OkeyDragSource? dropped;
      await _pumpForSize(
        tester,
        size: const Size(800, 360),
        onDiscardDropped: (_) {},
        onDrawDropped: (s) => dropped = s,
      );

      final deck = find.descendant(
        of: find.byType(OkeyIndicatorWidget),
        matching: find.byType(Draggable<OkeyDragPayload>),
      );
      final rackTile = find
          .descendant(
            of: find.byType(OkeyRackBarWidget),
            matching: find.byType(Draggable<OkeyDragPayload>),
          )
          .first;

      final start = tester.getCenter(deck);
      final end = tester.getCenter(rackTile);

      final g = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 16));
      for (var i = 1; i <= 20; i++) {
        await g.moveTo(Offset.lerp(start, end, i / 20)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();

      expect(
        dropped,
        OkeyDragSource.deck,
        reason: 'yavaş sürüklemede desteden çekilen taş bırakılamadı',
      );
    });
  });
}
