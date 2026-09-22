import 'package:cizreapp/okey/models/okey_models.dart';
import 'package:cizreapp/okey/providers/okey_room_provider.dart';
import 'package:cizreapp/okey/services/okey_room_service.dart';
import 'package:cizreapp/okey/widgets/okey_seat_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// KOLTUK SEÇİMİ — 2026-09-21
///
/// Kullanıcı isteği: "oyuncular istediği (eşli) kişinin karşısında
/// oturabilsin." Eskiden oyuncu en düşük numaralı boş koltuğa oturtuluyor ve
/// yerini değiştiremiyordu; eşli modda takımlar karşılıklı koltuklar
/// (0-2 ve 1-3) olduğundan "kimin eşi olacağım" tamamen katılma sırasına
/// bağlıydı.
///
/// Sunucu tarafı (okey_choose_seat) için bkz.
/// supabase/tests/manual/okey_seat_choice_and_finishing_discard_test.sql.
OkeyRoomSeat _seat(
  int n, {
  String? name,
  bool ready = false,
  bool bot = false,
}) => OkeyRoomSeat(
  roomId: 'r',
  seatNo: n,
  userId: bot ? null : 'u$n',
  isBot: bot,
  isReady: ready,
  displayName: name ?? 'Oyuncu$n',
);

OkeyRoomSeat _empty(int n) =>
    OkeyRoomSeat(roomId: 'r', seatNo: n, isReady: false);

Future<void> _pump(
  WidgetTester tester,
  Widget table, {
  Size size = const Size(390, 844),
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
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(14), child: table),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('Boş koltuğa geçiş', () {
    testWidgets('boş koltuk "OTUR" düğmesidir ve dokununca koltuk no döner', (
      tester,
    ) async {
      int? picked;
      await _pump(
        tester,
        OkeySeatTable(
          seats: [_seat(0), _seat(1), _seat(2), _empty(3)],
          mySeatNo: 1,
          isTeams: true,
          canPick: true,
          onPickSeat: (n) => picked = n,
        ),
      );

      expect(find.text('OTUR'), findsOneWidget);
      await tester.tap(find.text('OTUR'));
      expect(picked, 3);
    });

    testWidgets('sırayla dört koltuk da seçilebilir (yer haritası doğru)', (
      tester,
    ) async {
      final picks = <int>[];
      // Ben 0'dayım; 1, 2, 3 boş. Üç "OTUR" üç ayrı koltuk numarası döndürmeli.
      await _pump(
        tester,
        OkeySeatTable(
          seats: [_seat(0), _empty(1), _empty(2), _empty(3)],
          mySeatNo: 0,
          canPick: true,
          onPickSeat: picks.add,
        ),
      );

      final buttons = find.text('OTUR');
      expect(buttons, findsNWidgets(3));
      for (var i = 0; i < 3; i++) {
        await tester.tap(buttons.at(i));
      }
      expect(picks.toSet(), {1, 2, 3});
    });

    testWidgets('seçilemiyorsa (oda başladı / masada değilim) OTUR yok', (
      tester,
    ) async {
      var called = false;
      await _pump(
        tester,
        OkeySeatTable(
          seats: [_seat(0), _empty(1), _empty(2), _empty(3)],
          mySeatNo: 0,
          canPick: false,
          onPickSeat: (_) => called = true,
        ),
      );

      expect(find.text('OTUR'), findsNothing);
      expect(find.text('bekleniyor…'), findsNWidgets(3));
      expect(called, isFalse);
    });

    testWidgets('dolu koltuğa dokunmak profil açar, koltuk değiştirmez', (
      tester,
    ) async {
      OkeyRoomSeat? profile;
      int? picked;
      await _pump(
        tester,
        OkeySeatTable(
          seats: [
            _seat(0),
            _seat(1, name: 'Ayşe'),
            _empty(2),
            _empty(3),
          ],
          mySeatNo: 0,
          canPick: true,
          onPickSeat: (n) => picked = n,
          onSeatTap: (s) => profile = s,
        ),
      );

      await tester.tap(find.text('Ayşe'));
      expect(profile?.seatNo, 1);
      expect(picked, isNull);
    });

    testWidgets('yönlendirme yazısı: eşlide "karşındaki eşin olur"', (
      tester,
    ) async {
      await _pump(
        tester,
        OkeySeatTable(
          seats: [_seat(0), _empty(1), _empty(2), _empty(3)],
          mySeatNo: 0,
          isTeams: true,
          canPick: true,
          onPickSeat: (_) {},
        ),
      );
      expect(
        find.textContaining('Karşındaki koltuk eşin olur'),
        findsOneWidget,
      );
    });

    testWidgets(
      'eşsizde takım etiketi yok, yönlendirme yalnızca boş koltuk için',
      (tester) async {
        await _pump(
          tester,
          OkeySeatTable(
            seats: [_seat(0), _empty(1), _empty(2), _empty(3)],
            mySeatNo: 0,
            canPick: true,
            onPickSeat: (_) {},
          ),
        );
        expect(find.textContaining('Takım'), findsNothing);
        expect(find.textContaining('Eşin'), findsNothing);
        expect(find.textContaining('Boş bir koltuğa dokunup'), findsOneWidget);
      },
    );
  });

  group('Eşli masa — kimin eşi olurum', () {
    testWidgets('karşımdaki koltuk "Eşin", diğerleri takım adıyla', (
      tester,
    ) async {
      await _pump(
        tester,
        OkeySeatTable(
          seats: [_seat(0), _seat(1), _seat(2), _seat(3)],
          mySeatNo: 0,
          isTeams: true,
          canPick: true,
          onPickSeat: (_) {},
        ),
      );

      // Ben 0. koltuktayım → eşim karşımdaki 2. koltuk. Takım adı yerine
      // doğrudan "Eşin" yazar (dar ekranda "Takım 1 · Eşin" kırpılıyordu).
      expect(find.text('Eşin'), findsOneWidget);
      // Yan koltuklar (1 ve 3) RAKİP takımdır (Takım 2).
      expect(find.text('Takım 2'), findsNWidgets(2));
      // Kendim: Takım 1, "Eşin" değil.
      expect(find.text('Takım 1'), findsOneWidget);
    });

    testWidgets('boş koltuk, oraya geçersem eşimin kim olacağını söyler', (
      tester,
    ) async {
      await _pump(
        tester,
        OkeySeatTable(
          // Ben 1'deyim. 3. koltuk boş; karşısı (1) BEN'im ve oradan kalkacağım.
          // 2. koltuk dolu değil; 0. koltukta Ali var → 2'ye geçersem eşim Ali.
          seats: [
            _seat(0, name: 'Ali'),
            _seat(1),
            _empty(2),
            _empty(3),
          ],
          mySeatNo: 1,
          isTeams: true,
          canPick: true,
          onPickSeat: (_) {},
        ),
      );

      // 2. koltuk: oraya geçersem eşim, karşısındaki Ali.
      expect(find.text('Eşin: Ali'), findsOneWidget);
      // 3. koltuk ZATEN eşimin koltuğu: kartı "Eşin" der, ikinci bir
      // "Eşin: henüz yok" satırı eklenmez.
      expect(find.text('Eşin'), findsOneWidget);
      expect(find.text('Eşin: henüz yok'), findsNothing);
    });

    test('partnerHint: koltuk zaten eşimin koltuğuysa ipucu yok', () {
      // Ben 1'deyim; 3 karşımdaki koltuk. Kartı "Eşin" diyor, ipucu tekrar etmez.
      expect(
        OkeySeatTable.partnerHint(
          seatNo: 3,
          mySeatNo: 1,
          seats: [_seat(1), _empty(3)],
        ),
        isNull,
      );
    });

    test('partnerHint: karşıda biri oturuyorsa adı yazar', () {
      expect(
        OkeySeatTable.partnerHint(
          seatNo: 3,
          mySeatNo: 0,
          seats: [
            _seat(0),
            _seat(1, name: 'Ada'),
            _empty(3),
          ],
        ),
        'Eşin: Ada',
      );
    });

    test('partnerHint: karşı koltuk boşsa "henüz yok"', () {
      expect(
        OkeySeatTable.partnerHint(
          seatNo: 2,
          mySeatNo: 1,
          seats: [_empty(0), _seat(1)],
        ),
        'Eşin: henüz yok',
      );
    });

    test('takım kimliği karşılıklı koltuklardan türer (0-2 / 1-3)', () {
      expect(OkeyTeamStyle.labelOf(0), OkeyTeamStyle.labelOf(2));
      expect(OkeyTeamStyle.labelOf(1), OkeyTeamStyle.labelOf(3));
      expect(OkeyTeamStyle.labelOf(0), isNot(OkeyTeamStyle.labelOf(1)));
      expect(OkeyTeamStyle.colorOf(0), OkeyTeamStyle.colorOf(2));
      expect(OkeyTeamStyle.colorOf(1), OkeyTeamStyle.colorOf(3));
      expect(OkeyTeamStyle.colorOf(0), isNot(OkeyTeamStyle.colorOf(1)));
    });
  });

  group('Katılım sesi — koltuk değiştirmek katılım DEĞİLDİR', () {
    test('oyuncu boş koltuğa geçince ses yok', () {
      // u1, 1. koltuktan 3. koltuğa geçti; masaya yeni biri gelmedi. Koltuk
      // 3 boşken doluyor ama OTURANLAR KÜMESİ değişmedi.
      expect(
        OkeyRoomProvider.seatJoined(
          before: [_seat(0), _seat(1), _empty(2), _empty(3)],
          after: [
            _seat(0),
            _empty(1),
            _empty(2),
            OkeyRoomSeat(roomId: 'r', seatNo: 3, userId: 'u1', isReady: false),
          ],
        ),
        isFalse,
      );
    });

    test('geçişle birlikte MASAYA yeni biri de gelirse ses çalar', () {
      expect(
        OkeyRoomProvider.seatJoined(
          before: [_seat(0), _seat(1), _empty(2), _empty(3)],
          after: [
            _seat(0),
            _empty(1),
            _seat(2, name: 'Yeni'), // yeni kimlik u2
            OkeyRoomSeat(roomId: 'r', seatNo: 3, userId: 'u1', isReady: false),
          ],
        ),
        isTrue,
      );
    });
  });

  group('Hata cümleleri', () {
    test('koltuk dolmuşsa oyuncuya yeniden seçmesini söyler', () {
      expect(
        OkeyRoomService.chooseSeatError('PostgrestException(APP:seat_taken)'),
        contains('az önce doldu'),
      );
    });

    test('oyun başlamışsa nedenini söyler', () {
      expect(
        OkeyRoomService.chooseSeatError('APP:room_not_waiting'),
        contains('Oyun başladığı için'),
      );
    });

    test('bilinmeyen hata ham metni sızdırmaz', () {
      final msg = OkeyRoomService.chooseSeatError('SocketException: boom');
      expect(msg, isNot(contains('SocketException')));
      expect(msg, isNotEmpty);
    });
  });

  group('Masa hiçbir boyutta taşmaz', () {
    const sizes = <String, Size>{
      'küçük telefon 320x568': Size(320, 568),
      'dar telefon 360x640': Size(360, 640),
      'yaygın telefon 411x731': Size(411, 731),
      'yatay telefon 731x411': Size(731, 411),
      'tablet 768x1024': Size(768, 1024),
    };
    const longName = 'ÇokUzunOyuncuAdıTaşmaTestiİçin';

    for (final entry in sizes.entries) {
      for (final scale in const [1.0, 1.5]) {
        testWidgets('${entry.key} · yazı x$scale — eşli, dolu masa', (
          tester,
        ) async {
          await _pump(
            tester,
            OkeySeatTable(
              seats: [
                _seat(0, name: longName, ready: true),
                _seat(1, name: longName),
                _seat(2, name: longName, ready: true),
                _seat(3, name: longName),
              ],
              mySeatNo: 0,
              isTeams: true,
              canPick: true,
              onPickSeat: (_) {},
            ),
            size: entry.value,
            textScale: scale,
          );
          expect(tester.takeException(), isNull);
        });

        testWidgets('${entry.key} · yazı x$scale — eşli, boş koltuklu masa', (
          tester,
        ) async {
          await _pump(
            tester,
            OkeySeatTable(
              seats: [
                _seat(0, name: longName),
                _seat(1, name: longName),
              ],
              mySeatNo: 0,
              isTeams: true,
              canPick: true,
              onPickSeat: (_) {},
            ),
            size: entry.value,
            textScale: scale,
          );
          expect(tester.takeException(), isNull);
        });

        testWidgets('${entry.key} · yazı x$scale — eşsiz, hiç oturan yok', (
          tester,
        ) async {
          await _pump(
            tester,
            const OkeySeatTable(seats: [], mySeatNo: null),
            size: entry.value,
            textScale: scale,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
