import 'package:cizreapp/okey/engine/okey_tile.dart';
import 'package:cizreapp/okey/widgets/okey_move_flight.dart';
import 'package:cizreapp/okey/widgets/okey_tile_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// UÇAN TAŞ — kullanıcı istekleri, 2026-09-06:
///  * "taş atma veya taş çekme, taş işletme vs ekranda taş belli olsun,
///     kaydığını"
///  * "benim taş çekmede uçan taş olmasın ama karşı tarafta öyle görsün,
///     tümüne öyle yap"
///
/// Testin üç derdi var:
///  1. başkasının hamlesi gerçekten uçuyor mu,
///  2. KENDİ hamlem uçmuyor mu (her hamle türü için),
///  3. uçarken gizli bilgi sızdırıyor mu.

/// Sahte masa: her çapa sabit bir dikdörtgen.
const _deck = Rect.fromLTWH(400, 20, 40, 56);
const _melds = Rect.fromLTWH(150, 100, 200, 120);
final _discards = <int, Rect>{
  0: const Rect.fromLTWH(620, 260, 40, 56),
  1: const Rect.fromLTWH(20, 240, 40, 56),
  2: const Rect.fromLTWH(20, 30, 40, 56),
  3: const Rect.fromLTWH(620, 30, 40, 56),
};
final _seats = <int, Rect>{
  0: const Rect.fromLTWH(300, 300, 120, 40),
  1: const Rect.fromLTWH(10, 120, 60, 140),
  2: const Rect.fromLTWH(300, 10, 120, 40),
  3: const Rect.fromLTWH(700, 120, 60, 140),
};

Rect? _resolve(OkeyAnchor a, int seat) => switch (a) {
  OkeyAnchor.deck => _deck,
  OkeyAnchor.melds => _melds,
  OkeyAnchor.discard => _discards[seat],
  OkeyAnchor.seat => _seats[seat],
};

Widget _overlay(ValueNotifier<OkeyMoveFlash?> move, {int? mySeat = 0}) =>
    MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: OkeyMoveFlightOverlay(
                move: move,
                resolve: _resolve,
                mySeatNo: mySeat,
              ),
            ),
          ],
        ),
      ),
    );

OkeyMoveFlash _flash(
  int id,
  String action, {
  required int seatNo,
  OkeyTile? tile,
}) => OkeyMoveFlash(
  id: id,
  seatNo: seatNo,
  action: action,
  tile: tile ?? OkeyTile.numbered(OkeyColor.red, 7),
);

/// Uçan taşın o andaki merkezi.
Offset _tileCenter(WidgetTester tester) =>
    tester.getRect(find.byType(OkeyTileWidget)).center;

/// Bildirimci, DİNLEYEN widget ağaçtan kalktıktan SONRA kapatılır.
Future<void> _teardown(
  WidgetTester tester,
  ValueNotifier<OkeyMoveFlash?> move,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  move.dispose();
}

void main() {
  group('Kendi hamlem UÇMAZ', () {
    // Kendi hamlemi zaten ben yaptım: desteye ben dokundum, taşı ben
    // sürükledim. Üstüne animasyon oynatmak bilgi vermez, elimin önünü kapatır.
    const actions = [
      'draw_deck',
      'draw_discard',
      'discard',
      'timeout_auto_discard',
      'lay_meld',
      'add_to_meld',
      'steal_okey',
    ];

    for (final action in actions) {
      testWidgets('$action — kendi koltuğumda uçan taş yok', (tester) async {
        final move = ValueNotifier<OkeyMoveFlash?>(null);
        await tester.pumpWidget(_overlay(move, mySeat: 1));

        move.value = _flash(1, action, seatNo: 1);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));

        expect(
          find.byType(OkeyTileWidget),
          findsNothing,
          reason: '$action kendi hamlemde uçtu',
        );

        await _teardown(tester, move);
      });
    }

    testWidgets('AYNI hamle türü BAŞKASININ koltuğunda UÇAR', (tester) async {
      // Kuralın asimetrisi kasıtlı: aynı hamle, kimin yaptığına göre uçar ya
      // da uçmaz. Bu test ikisini yan yana koyar.
      final move = ValueNotifier<OkeyMoveFlash?>(null);
      await tester.pumpWidget(_overlay(move, mySeat: 1));

      move.value = _flash(1, 'discard', seatNo: 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(OkeyTileWidget), findsNothing);

      move.value = _flash(2, 'discard', seatNo: 3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(OkeyTileWidget), findsOneWidget);

      await tester.pump(OkeyMoveFlightOverlay.duration);
      await _teardown(tester, move);
    });

    testWidgets('İZLEYİCİ dört koltuğu da uçarken görür', (tester) async {
      // Masada oturmayan biri için her hamle "başkasının" hamlesidir.
      final move = ValueNotifier<OkeyMoveFlash?>(null);
      await tester.pumpWidget(_overlay(move, mySeat: null));

      for (var seat = 0; seat < 4; seat++) {
        move.value = _flash(10 + seat, 'discard', seatNo: seat);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        expect(
          find.byType(OkeyTileWidget),
          findsOneWidget,
          reason: '$seat. koltuk izleyicide uçmadı',
        );
        await tester.pump(OkeyMoveFlightOverlay.duration);
      }

      await _teardown(tester, move);
    });
  });

  group('Uçuş yolu', () {
    testWidgets('ATILAN taş levhadan ıskartaya KAYAR', (tester) async {
      final move = ValueNotifier<OkeyMoveFlash?>(null);
      await tester.pumpWidget(_overlay(move, mySeat: 0));

      expect(find.byType(OkeyTileWidget), findsNothing);

      move.value = _flash(1, 'discard', seatNo: 2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.byType(OkeyTileWidget), findsOneWidget);
      final early = _tileCenter(tester);

      await tester.pump(const Duration(milliseconds: 200));
      final later = _tileCenter(tester);

      // GERÇEKTEN KAYIYOR: iki kare arasında yer değiştirdi ve HEDEFE
      // yaklaştı. Yalnızca "göründü mü" diye bakmak, sabit duran bir taşı da
      // geçerdi.
      expect(early, isNot(later));
      final target = _discards[2]!.center;
      expect(
        (later - target).distance,
        lessThan((early - target).distance),
        reason: 'taş hedefe yaklaşmıyor',
      );

      // Kendiliğinden biter — masada asılı bir taş bırakmaz.
      await tester.pump(OkeyMoveFlightOverlay.duration);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(OkeyTileWidget), findsNothing);

      await _teardown(tester, move);
    });

    testWidgets('DESTEDEN çekme destenin üstünden başlar', (tester) async {
      // "Uçan taş desteden aldığı gibi de olsun" — çekiş, destenin durduğu
      // yerden başlamalı, yoksa taşın nereden geldiği yine belirsiz kalır.
      final move = ValueNotifier<OkeyMoveFlash?>(null);
      await tester.pumpWidget(_overlay(move, mySeat: 0));

      move.value = _flash(2, 'draw_deck', seatNo: 2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      final start = _tileCenter(tester);
      expect(
        (start - _deck.center).distance,
        lessThan((start - _seats[2]!.center).distance),
        reason: 'deste çekişi destenin yanından başlamıyor',
      );

      await tester.pump(OkeyMoveFlightOverlay.duration);
      await _teardown(tester, move);
    });

    testWidgets('YANDAN çekme, SOLDAKİNİN ıskartasından gelir', (tester) async {
      final move = ValueNotifier<OkeyMoveFlash?>(null);
      await tester.pumpWidget(_overlay(move, mySeat: 0));

      // 2. koltuk yandan çekiyor → kaynak 1. koltuğun ıskartası.
      move.value = _flash(
        3,
        'draw_discard',
        seatNo: 2,
        tile: OkeyTile.numbered(OkeyColor.blue, 4),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      final start = _tileCenter(tester);
      expect(
        (start - _discards[1]!.center).distance,
        lessThan((start - _discards[3]!.center).distance),
        reason: 'yandan çekme yanlış ıskartadan başlıyor',
      );

      await tester.pump(OkeyMoveFlightOverlay.duration);
      await _teardown(tester, move);
    });

    testWidgets('İŞLEME masaya doğru, OKEY ÇALMA masadan geri akar', (
      tester,
    ) async {
      final move = ValueNotifier<OkeyMoveFlash?>(null);
      await tester.pumpWidget(_overlay(move, mySeat: 0));

      move.value = _flash(
        4,
        'add_to_meld',
        seatNo: 2,
        tile: OkeyTile.numbered(OkeyColor.black, 5),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      final processStart = _tileCenter(tester);
      await tester.pump(OkeyMoveFlightOverlay.duration);

      move.value = _flash(
        5,
        'steal_okey',
        seatNo: 2,
        tile: OkeyTile.numbered(OkeyColor.black, 5),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      final stealStart = _tileCenter(tester);

      // İşleme LEVHADAN başlar, çalma MASADAN: yönler ters olmalı.
      expect(
        (processStart - _seats[2]!.center).distance,
        lessThan((processStart - _melds.center).distance),
      );
      expect(
        (stealStart - _melds.center).distance,
        lessThan((stealStart - _seats[2]!.center).distance),
      );

      await tester.pump(OkeyMoveFlightOverlay.duration);
      await _teardown(tester, move);
    });
  });

  group('Gizlilik', () {
    testWidgets('DESTEDEN çekilen taş KAPALI uçar', (tester) async {
      // Buraya yalnızca BAŞKASININ hamlesi geliyor (kendi hamlem hiç uçmaz),
      // dolayısıyla her deste çekişi gizlidir. Animasyon hiçbir koşulda bir
      // bilgi sızıntısı kanalı olamaz.
      final move = ValueNotifier<OkeyMoveFlash?>(null);
      await tester.pumpWidget(_overlay(move, mySeat: 0));

      move.value = _flash(
        6,
        'draw_deck',
        seatNo: 2,
        tile: OkeyTile.numbered(OkeyColor.yellow, 13),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));

      final tile = tester.widget<OkeyTileWidget>(find.byType(OkeyTileWidget));
      expect(
        tile.faceDown,
        isTrue,
        reason: 'rakibin çektiği taş açık uçtu — bilgi sızıntısı',
      );
      expect(find.text('13'), findsNothing);

      await tester.pump(OkeyMoveFlightOverlay.duration);
      await _teardown(tester, move);
    });

    testWidgets('ATILAN taş AÇIK uçar — zaten herkesin gözü önünde', (
      tester,
    ) async {
      final move = ValueNotifier<OkeyMoveFlash?>(null);
      await tester.pumpWidget(_overlay(move, mySeat: 0));

      move.value = _flash(
        7,
        'discard',
        seatNo: 3,
        tile: OkeyTile.numbered(OkeyColor.yellow, 13),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));

      final tile = tester.widget<OkeyTileWidget>(find.byType(OkeyTileWidget));
      expect(tile.faceDown, isFalse);

      await tester.pump(OkeyMoveFlightOverlay.duration);
      await _teardown(tester, move);
    });
  });

  /// PEŞ PEŞE UÇUŞ — kullanıcı isteği, 2026-09-07: "desteden taş çektiğinde
  /// uçan taş kullanıcılar görsün çektiğini".
  ///
  /// Bot bir turun tamamını (çek → at) tek RPC'de bitiriyor, yani istemciye
  /// iki hamle BİRDEN geliyor. Provider bunları kuyruğa alıp tek tek yayar
  /// (bkz. OkeyGameProvider._queueFlight); bu test katmanın karşı tarafını
  /// doğrular: art arda gelen İKİ hamlenin İKİSİ de uçar ve ikincisi
  /// birincinin yolunu değil KENDİ yolunu izler.
  testWidgets('art arda iki hamle: çekme de atma da uçar', (tester) async {
    final move = ValueNotifier<OkeyMoveFlash?>(null);
    await tester.pumpWidget(_overlay(move, mySeat: 0));

    // 1) Rakip DESTEDEN çekti — taş desteden onun levhasına gider.
    move.value = _flash(1, 'draw_deck', seatNo: 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byType(OkeyTileWidget), findsOneWidget);
    final drawStart = _tileCenter(tester);
    expect(
      (drawStart - _deck.center).distance,
      lessThan((drawStart - _seats[2]!.center).distance),
      reason: 'çekme uçuşu desteden başlamalı',
    );

    // Uçuş bitsin.
    await tester.pump(OkeyMoveFlightOverlay.duration);
    await tester.pump(const Duration(milliseconds: 40));

    // 2) Aynı rakip taşı attı — bu kez levhadan ıskartaya.
    move.value = _flash(2, 'discard', seatNo: 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byType(OkeyTileWidget), findsOneWidget);
    final discardStart = _tileCenter(tester);
    expect(
      (discardStart - _seats[2]!.center).distance,
      lessThan((discardStart - _discards[2]!.center).distance),
      reason: 'atma uçuşu oyuncunun levhasından başlamalı',
    );
    expect(
      (discardStart - drawStart).distance,
      greaterThan(1),
      reason: 'ikinci uçuş birincinin yolunu tekrarlamış',
    );

    await tester.pump(OkeyMoveFlightOverlay.duration);
    await _teardown(tester, move);
  });

  testWidgets('dokunma olaylarını YUTMAZ', (tester) async {
    final move = ValueNotifier<OkeyMoveFlash?>(null);
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => tapped = true,
                ),
              ),
              Positioned.fill(
                child: OkeyMoveFlightOverlay(
                  move: move,
                  resolve: _resolve,
                  mySeatNo: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Uçuş SÜRERKEN dokun: katman ekranın tamamını kaplıyor, taş da yolun
    // ortasında.
    move.value = _flash(8, 'discard', seatNo: 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(OkeyTileWidget), findsOneWidget);

    await tester.tapAt(const Offset(300, 200));
    await tester.pump();
    expect(tapped, isTrue, reason: 'uçan taş hamleyi yuttu');

    await tester.pump(OkeyMoveFlightOverlay.duration);
    await _teardown(tester, move);
  });
}
