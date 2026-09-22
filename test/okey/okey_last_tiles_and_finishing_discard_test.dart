import 'package:cizreapp/okey/engine/okey_announcements.dart';
import 'package:cizreapp/okey/engine/okey_win_detector.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-09-21 — İKİ KULLANICI İSTEĞİ
///
/// [1] "son 3 taş sesi sadece takozda (taş attıktan sonra) kaldığında
///     bildirilsin" ("takoz" = ıstaka). Anons eskiden ıstaka turun ORTASINDA
///     — taş çekilip perler indirildikten sonra, atmadan önce — 3'e düşünce
///     çalıyordu; oyuncu atınca ıstakasında 2 taş kalıyordu.
///
/// [2] "el bittiğinde yani kişi eli bitirse son taş işlekte işlek sayılmasın,
///     çünkü mecburdur ve takozda taş yok." Eli bitiren atış işlek taş cezası
///     yazmaz. Sunucu tarafı için bkz.
///     supabase/tests/manual/okey_seat_choice_and_finishing_discard_test.sql.
void main() {
  group('"Son üç taş" anonsu — yalnızca atıştan sonra, tam 3 taşta', () {
    test(
      'sırası BAŞKASINDA olan ve ıstakasında 3 taş kalan koltuk duyurulur',
      () {
        final announced = <int>{};
        final result = OkeyAnnouncements.lastThreeTiles(
          counts: {0: 21, 1: 3, 2: 21, 3: 21},
          turnSeat: 2, // 1. koltuk atışını yapmış, sıra ilerlemiş
          announced: announced,
        );
        expect(result, [1]);
        expect(announced, {1});
      },
    );

    test('TURUN ORTASINDA (sırası kendindeyken) 3 taş DUYURULMAZ', () {
      // Kullanıcının bildirdiği hata: oyuncu taş çekip perlerini indirdi,
      // ıstakasında 3 taş var ama HENÜZ ATMADI — atınca 2 kalacak.
      final announced = <int>{};
      final result = OkeyAnnouncements.lastThreeTiles(
        counts: {0: 21, 1: 3, 2: 21, 3: 21},
        turnSeat: 1,
        announced: announced,
      );
      expect(result, isEmpty);
      expect(announced, isEmpty);
    });

    test('ara duruma bakıp sonra atışla 2 kalırsa HİÇ duyurulmaz', () {
      final announced = <int>{};
      // Ara durum: sırası kendinde, 3 taş.
      expect(
        OkeyAnnouncements.lastThreeTiles(
          counts: {1: 3},
          turnSeat: 1,
          announced: announced,
        ),
        isEmpty,
      );
      // Atış yapıldı: 2 taş, sıra geçti. "Son üç taş" denmez.
      expect(
        OkeyAnnouncements.lastThreeTiles(
          counts: {1: 2},
          turnSeat: 2,
          announced: announced,
        ),
        isEmpty,
      );
    });

    test('atıştan sonra tam 3 kalınca, ara durumdan SONRA duyurulur', () {
      final announced = <int>{};
      // 4 taşlık ıstaka, sırası kendinde: çekti (5), işledi (4)… sonra attı.
      expect(
        OkeyAnnouncements.lastThreeTiles(
          counts: {1: 4},
          turnSeat: 1,
          announced: announced,
        ),
        isEmpty,
      );
      expect(
        OkeyAnnouncements.lastThreeTiles(
          counts: {1: 3},
          turnSeat: 2,
          announced: announced,
        ),
        [1],
      );
    });

    test('3 ALTINDA (2 ya da 1 taş) "üç taş" denmez', () {
      // 5'ten 1'e inen oyuncu için "üç taş" yanlış bilgi olurdu.
      for (final n in [2, 1, 0]) {
        expect(
          OkeyAnnouncements.lastThreeTiles(
            counts: {1: n},
            turnSeat: 2,
            announced: <int>{},
          ),
          isEmpty,
          reason: '$n taş',
        );
      }
    });

    test('aynı koltuk için ikinci tazelemede tekrar duyurulmaz', () {
      final announced = <int>{};
      final first = OkeyAnnouncements.lastThreeTiles(
        counts: {1: 3},
        turnSeat: 2,
        announced: announced,
      );
      final second = OkeyAnnouncements.lastThreeTiles(
        counts: {1: 3},
        turnSeat: 3,
        announced: announced,
      );
      expect(first, [1]);
      expect(second, isEmpty);
    });

    test(
      'sıra yeniden gelip taş çekince (4) işaret kalkar, tekrar 3 olursa yine duyurulur',
      () {
        final announced = <int>{};
        OkeyAnnouncements.lastThreeTiles(
          counts: {1: 3},
          turnSeat: 2,
          announced: announced,
        );
        // Sırası geldi, çekti: 4.
        OkeyAnnouncements.lastThreeTiles(
          counts: {1: 4},
          turnSeat: 1,
          announced: announced,
        );
        expect(announced, isEmpty);
        // Attı: yine 3.
        expect(
          OkeyAnnouncements.lastThreeTiles(
            counts: {1: 3},
            turnSeat: 2,
            announced: announced,
          ),
          [1],
        );
      },
    );

    test(
      'kendi turunun başında (çekmeden önce) 3 taşım varken sessiz kalır',
      () {
        // Atıştan sonra zaten duyuruldu; sıra bana geldiğinde tekrar değil.
        final announced = <int>{1};
        expect(
          OkeyAnnouncements.lastThreeTiles(
            counts: {1: 3},
            turnSeat: 1,
            announced: announced,
          ),
          isEmpty,
        );
        expect(announced, {1}, reason: 'işaret bu durumda silinmez');
      },
    );

    test(
      'iki koltuk birden 3 taşa inerse koltuk sırasıyla ikisi de duyulur',
      () {
        final result = OkeyAnnouncements.lastThreeTiles(
          counts: {3: 3, 0: 21, 1: 3, 2: 21},
          turnSeat: 0,
          announced: <int>{},
        );
        expect(result, [1, 3]);
      },
    );

    test(
      'elin ilk görüşünde 3 ve altındaki koltuklar "zaten duyuruldu" sayılır',
      () {
        expect(OkeyAnnouncements.alreadyLow({0: 21, 1: 3, 2: 2, 3: 8}), {1, 2});
      },
    );

    test('eşik 3', () => expect(OkeyAnnouncements.lastTilesCount, 3));
  });

  group('Eli bitiren atış — RULES.md §6/§7', () {
    test('elde tek taş kaldı ve el AÇIK → atış eli bitirir', () {
      expect(
        OkeyWinDetector.discardFinishesHand(handSize: 1, isOpeningDone: true),
        isTrue,
      );
    });

    test(
      'elde birden çok taş varsa atış eli bitirmez (işlek ceza geçerli)',
      () {
        for (final n in [2, 3, 10, 22]) {
          expect(
            OkeyWinDetector.discardFinishesHand(
              handSize: n,
              isOpeningDone: true,
            ),
            isFalse,
            reason: '$n taş',
          );
        }
      },
    );

    test(
      'eli AÇILMAMIŞ oyuncunun tek taşı eli bitirmez (bitiş açık el ister)',
      () {
        expect(
          OkeyWinDetector.discardFinishesHand(
            handSize: 1,
            isOpeningDone: false,
          ),
          isFalse,
        );
      },
    );

    test('boş el bir "atış" değildir', () {
      expect(
        OkeyWinDetector.discardFinishesHand(handSize: 0, isOpeningDone: true),
        isFalse,
      );
    });
  });
}
