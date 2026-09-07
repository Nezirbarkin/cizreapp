import 'package:cizreapp/okey/okey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  falseJokerTests();

  gostergePairTests();

  stealJokerTests();

  countValidPairsTests();

  // Gösterge: 7 Kırmızı -> okey taşı: 8 Kırmızı.
  final okeyTile = OkeyTile.numbered(OkeyColor.red, 8);

  OkeyTile t(OkeyColor c, int n) => OkeyTile.numbered(c, n);

  // SERBEST JOKER = OKEY TAŞININ KENDİSİ (kırmızı 8).
  //
  // Bu fixture önce OkeyTile.falseJoker() idi ve testler sahte okeyin her
  // yere girebildiğini varsayıyordu. Oysa RULES.md §1: sahte okey, okey
  // taşının SAYI DEĞERİYLE geçer — serbest joker DEĞİLDİR. Jokerlik testleri
  // artık gerçek okey taşıyla yapılır (bkz. falseJokerTests()).
  final joker = OkeyTile.numbered(OkeyColor.red, 8);

  group('isValidRun — RULES.md §2', () {
    test('ardışık aynı renk 3 taş geçerli', () {
      expect(
        OkeyMeldValidator.isValidRun([
          t(OkeyColor.blue, 5),
          t(OkeyColor.blue, 6),
          t(OkeyColor.blue, 7),
        ], okeyTile),
        isTrue,
      );
    });

    test('12-13-1 GEÇERSİZ — seri 13te biter, sarma yok', () {
      // KURAL DEĞİŞİKLİĞİ: Önce 12-13-1 geçerliydi. Kullanıcı "11-12-13'ten
      // sonra sayı gelmez" diyerek sarmayı kaldırdı.
      expect(
        OkeyMeldValidator.isValidRun([
          t(OkeyColor.blue, 12),
          t(OkeyColor.blue, 13),
          t(OkeyColor.blue, 1),
        ], okeyTile),
        isFalse,
        reason: '13ten sonra 1 bağlanamaz',
      );
    });

    test('11-12-13 GEÇERLİ — 13te biten seri', () {
      expect(
        OkeyMeldValidator.isValidRun([
          t(OkeyColor.blue, 11),
          t(OkeyColor.blue, 12),
          t(OkeyColor.blue, 13),
        ], okeyTile),
        isTrue,
      );
    });

    test('1-2-3 GEÇERLİ — seri 1den başlayabilir', () {
      expect(
        OkeyMeldValidator.isValidRun([
          t(OkeyColor.blue, 1),
          t(OkeyColor.blue, 2),
          t(OkeyColor.blue, 3),
        ], okeyTile),
        isTrue,
      );
    });

    test('11-12-13-1 GEÇERSİZ — 13ten sonra sayı gelmez', () {
      expect(
        OkeyMeldValidator.isValidRun([
          t(OkeyColor.blue, 11),
          t(OkeyColor.blue, 12),
          t(OkeyColor.blue, 13),
          t(OkeyColor.blue, 1),
        ], okeyTile),
        isFalse,
        reason: 'kullanıcının bildirdiği kural: 11-12-13ten sonra sayı gelmez',
      );
    });

    test('13-1-2 GEÇERSİZ (1den sonra 2 gelemez)', () {
      expect(
        OkeyMeldValidator.isValidRun([
          t(OkeyColor.blue, 13),
          t(OkeyColor.blue, 1),
          t(OkeyColor.blue, 2),
        ], okeyTile),
        isFalse,
      );
    });

    test('joker eksik numarayı doldurur', () {
      expect(
        OkeyMeldValidator.isValidRun([
          t(OkeyColor.blue, 5),
          joker,
          t(OkeyColor.blue, 7),
        ], okeyTile),
        isTrue,
      );
    });

    test('farklı renk geçersiz', () {
      expect(
        OkeyMeldValidator.isValidRun([
          t(OkeyColor.blue, 5),
          t(OkeyColor.black, 6),
          t(OkeyColor.blue, 7),
        ], okeyTile),
        isFalse,
      );
    });

    test('ardışık olmayan geçersiz', () {
      expect(
        OkeyMeldValidator.isValidRun([
          t(OkeyColor.blue, 5),
          t(OkeyColor.blue, 6),
          t(OkeyColor.blue, 9),
        ], okeyTile),
        isFalse,
      );
    });

    test('2 taş çok kısa', () {
      expect(
        OkeyMeldValidator.isValidRun([
          t(OkeyColor.blue, 5),
          t(OkeyColor.blue, 6),
        ], okeyTile),
        isFalse,
      );
    });
  });

  group('isValidSet — RULES.md §2', () {
    test('aynı rakam farklı renk 3 taş geçerli', () {
      expect(
        OkeyMeldValidator.isValidSet([
          t(OkeyColor.blue, 5),
          t(OkeyColor.black, 5),
          t(OkeyColor.yellow, 5),
        ], okeyTile),
        isTrue,
      );
    });

    test('4 taş geçerli', () {
      expect(
        OkeyMeldValidator.isValidSet([
          t(OkeyColor.blue, 5),
          t(OkeyColor.black, 5),
          t(OkeyColor.yellow, 5),
          t(OkeyColor.red, 5),
        ], okeyTile),
        isTrue,
      );
    });

    test('aynı renk tekrarı geçersiz', () {
      expect(
        OkeyMeldValidator.isValidSet([
          t(OkeyColor.blue, 5),
          t(OkeyColor.blue, 5),
          t(OkeyColor.yellow, 5),
        ], okeyTile),
        isFalse,
      );
    });

    test('farklı numara geçersiz', () {
      expect(
        OkeyMeldValidator.isValidSet([
          t(OkeyColor.blue, 5),
          t(OkeyColor.black, 5),
          t(OkeyColor.yellow, 6),
        ], okeyTile),
        isFalse,
      );
    });
  });

  group('isValidPair — RULES.md §2', () {
    test('aynı renk + aynı rakam geçerli', () {
      expect(
        OkeyMeldValidator.isValidPair([
          t(OkeyColor.red, 5),
          t(OkeyColor.red, 5),
        ], okeyTile),
        isTrue,
      );
    });

    test('farklı renk aynı rakam GEÇERSİZ', () {
      expect(
        OkeyMeldValidator.isValidPair([
          t(OkeyColor.red, 5),
          t(OkeyColor.blue, 5),
        ], okeyTile),
        isFalse,
      );
    });

    test('joker herhangi bir taşla çift olur', () {
      expect(
        OkeyMeldValidator.isValidPair([joker, t(OkeyColor.red, 5)], okeyTile),
        isTrue,
      );
    });

    test('3 taş çift değildir', () {
      expect(
        OkeyMeldValidator.isValidPair([
          t(OkeyColor.red, 5),
          t(OkeyColor.red, 5),
          t(OkeyColor.red, 5),
        ], okeyTile),
        isFalse,
      );
    });
  });

  group('meldPoints — RULES.md §3', () {
    test('per puanı taşların toplamı', () {
      expect(
        OkeyMeldValidator.meldPoints([
          t(OkeyColor.blue, 5),
          t(OkeyColor.blue, 6),
          t(OkeyColor.blue, 7),
        ], okeyTile),
        18,
      );
    });

    test('11-12-13 puanı 36 — seri 13te biter', () {
      // Önce 12-13-1 (sarma) puanı test ediliyordu; sarma kaldırıldığı için
      // geçerli en yüksek seri 11-12-13'tür.
      expect(
        OkeyMeldValidator.meldPoints([
          t(OkeyColor.blue, 11),
          t(OkeyColor.blue, 12),
          t(OkeyColor.blue, 13),
        ], okeyTile),
        36,
      );
    });

    test('sarmalı seri artık puan üretmez (geçersiz)', () {
      expect(
        OkeyMeldValidator.isValidRun([
          t(OkeyColor.blue, 12),
          t(OkeyColor.blue, 13),
          t(OkeyColor.blue, 1),
        ], okeyTile),
        isFalse,
      );
    });

    test('grup puanı numara x taş sayısı', () {
      expect(
        OkeyMeldValidator.meldPoints([
          t(OkeyColor.blue, 9),
          t(OkeyColor.black, 9),
          t(OkeyColor.yellow, 9),
        ], okeyTile),
        27,
      );
    });

    test('jokerli per puanı jokerin temsil ettiği taşı sayar', () {
      expect(
        OkeyMeldValidator.meldPoints([
          t(OkeyColor.blue, 5),
          joker,
          t(OkeyColor.blue, 7),
        ], okeyTile),
        18,
      );
    });

    test('totalOpeningPoints 101 barajını doğru hesaplar', () {
      final groups = [
        [
          t(OkeyColor.red, 10),
          t(OkeyColor.red, 11),
          t(OkeyColor.red, 12),
          t(OkeyColor.red, 13),
        ], // 46
        [
          t(OkeyColor.blue, 13),
          t(OkeyColor.black, 13),
          t(OkeyColor.yellow, 13),
        ], // 39
        [
          t(OkeyColor.blue, 5),
          t(OkeyColor.blue, 6),
          t(OkeyColor.blue, 7),
        ], // 18
      ];
      expect(OkeyMeldValidator.totalOpeningPoints(groups, okeyTile), 103);
    });
  });

  group('countValidPairs — RULES.md §3', () {
    test('5 geçerli çift sayılır', () {
      final groups = [
        [t(OkeyColor.red, 1), t(OkeyColor.red, 1)],
        [t(OkeyColor.blue, 2), t(OkeyColor.blue, 2)],
        [t(OkeyColor.black, 3), t(OkeyColor.black, 3)],
        [t(OkeyColor.yellow, 4), t(OkeyColor.yellow, 4)],
        [t(OkeyColor.red, 5), t(OkeyColor.red, 5)],
      ];
      expect(OkeyMeldValidator.countValidPairs(groups, okeyTile), 5);
    });

    test('geçersiz çift varsa -1 döner', () {
      final groups = [
        [t(OkeyColor.red, 1), t(OkeyColor.red, 1)],
        [t(OkeyColor.blue, 2), t(OkeyColor.black, 2)], // farklı renk
      ];
      expect(OkeyMeldValidator.countValidPairs(groups, okeyTile), -1);
    });
  });
}

/// GÖSTERGE ÇİFTİ — gerçek 101 Okey Plus kuralı.
///
/// Göstergenin bir kopyası ortada açık durduğu için oyunda yalnızca bir
/// kopyası kalır; gerçek çiftini yapmak imkânsızdır. Bu yüzden o TEK taş
/// başlı başına bir çift sayılır. Örnek: 4 gerçek çifti olan oyuncu
/// göstergeyle 5 çift açabilir.
void gostergePairTests() {
  group('Gösterge çifti', () {
    final gosterge = OkeyTile.numbered(OkeyColor.blue, 7);
    final okey = OkeyTile.numbered(OkeyColor.blue, 8); // göstergenin üstü

    test('göstergeyle aynı TEK taş çift sayılır', () {
      expect(OkeyMeldValidator.isGostergePair([gosterge], gosterge), isTrue);
    });

    test('gösterge OLMAYAN tek taş çift sayılmaz', () {
      expect(
        OkeyMeldValidator.isGostergePair([
          OkeyTile.numbered(OkeyColor.red, 5),
        ], gosterge),
        isFalse,
        reason: 'her tek taş çift sayılırsa herkes bedavaya açar',
      );
    });

    test('iki taşlık gösterge grubu tek-taş kuralına GİRMEZ', () {
      expect(
        OkeyMeldValidator.isGostergePair([gosterge, gosterge], gosterge),
        isFalse,
      );
    });

    test('gösterge bilinmiyorsa tek taş çift sayılmaz', () {
      expect(OkeyMeldValidator.isGostergePair([gosterge], null), isFalse);
    });

    test('isValidPairEx hem normal çifti hem gösterge çiftini kabul eder', () {
      // Normal çift
      final five = OkeyTile.numbered(OkeyColor.red, 5);
      expect(
        OkeyMeldValidator.isValidPairEx([five, five], okey, gosterge),
        isTrue,
      );
      // Gösterge çifti
      expect(
        OkeyMeldValidator.isValidPairEx([gosterge], okey, gosterge),
        isTrue,
      );
      // Alakasız tek taş
      expect(OkeyMeldValidator.isValidPairEx([five], okey, gosterge), isFalse);
    });

    test('4 gerçek çift + gösterge = 5 çift', () {
      final groups = <List<OkeyTile>>[
        [
          OkeyTile.numbered(OkeyColor.red, 2),
          OkeyTile.numbered(OkeyColor.red, 2),
        ],
        [
          OkeyTile.numbered(OkeyColor.black, 4),
          OkeyTile.numbered(OkeyColor.black, 4),
        ],
        [
          OkeyTile.numbered(OkeyColor.yellow, 6),
          OkeyTile.numbered(OkeyColor.yellow, 6),
        ],
        [
          OkeyTile.numbered(OkeyColor.red, 9),
          OkeyTile.numbered(OkeyColor.red, 9),
        ],
        [gosterge], // gösterge çifti
      ];

      final validCount = groups
          .where((g) => OkeyMeldValidator.isValidPairEx(g, okey, gosterge))
          .length;

      expect(
        validCount,
        5,
        reason: 'gösterge çifti sayılmazsa oyuncu 4 çiftte kalır ve açamaz',
      );
    });
  });
}

/// SAHTE OKEY SERBEST JOKER DEĞİLDİR
///
/// BULUNAN HATA: Kod, sahte okeyi HER TAŞIN yerine geçebilen serbest bir
/// joker olarak işliyordu — istenen her pere sokulabiliyordu. Oysa RULES.md
/// §1 zaten şunu yazıyordu: "Sahte okey taşları, okey taşının yerine NORMAL
/// SAYI DEĞERİYLE geçer". Yani kod, onaylanmış kuralla çelişiyordu.
///
/// Kullanıcının örneği: sahte okey 11 ise, aynı renk 10-11-12 serisine ya da
/// farklı renklerden 11-11-11 grubuna girer — BAŞKA YERE DEĞİL.
void falseJokerTests() {
  group('Sahte okey (serbest joker DEĞİL)', () {
    // Gösterge kırmızı 10 -> okey kırmızı 11. Sahte okey de kırmızı 11 sayılır.
    final okey = OkeyTile.numbered(OkeyColor.red, 11);
    const fake = OkeyTile.falseJoker();

    OkeyTile t(OkeyColor c, int n) => OkeyTile.numbered(c, n);

    test('sahte okey JOKER SAYILMAZ', () {
      expect(
        fake.isJokerFor(okey),
        isFalse,
        reason: 'sahte okey serbest joker olursa her yere konabilir',
      );
      // Gerçek okey taşı JOKERDİR
      expect(t(OkeyColor.red, 11).isJokerFor(okey), isTrue);
    });

    test('sahte okey, OKEY taşının kimliğini alır', () {
      expect(fake.resolvedColor(okey), OkeyColor.red);
      expect(fake.resolvedNumber(okey), 11);
    });

    test(
      'KULLANICI ÖRNEĞİ: sahte okey 11, aynı renk 10-11-12 serisine girer',
      () {
        final run = [t(OkeyColor.red, 10), fake, t(OkeyColor.red, 12)];
        expect(
          OkeyMeldValidator.isValidRun(run, okey),
          isTrue,
          reason: 'sahte okey kendi rengindeki seriye girmeli',
        );
      },
    );

    test('KULLANICI ÖRNEĞİ: sahte okey 11, 11-11-11 grubuna girer', () {
      final set = [t(OkeyColor.blue, 11), t(OkeyColor.black, 11), fake];
      expect(
        OkeyMeldValidator.isValidSet(set, okey),
        isTrue,
        reason: 'sahte okey kendi sayısındaki gruba girmeli',
      );
    });

    test('sahte okey BAŞKA RENKTEKİ seriye GİREMEZ', () {
      // Sahte okey kırmızı 11 sayılır; mavi bir seriye giremez
      final run = [t(OkeyColor.blue, 10), fake, t(OkeyColor.blue, 12)];
      expect(
        OkeyMeldValidator.isValidRun(run, okey),
        isFalse,
        reason:
            'sahte okey serbest joker gibi davranıyor — '
            'istenen her yere konabiliyor',
      );
    });

    test('sahte okey BAŞKA SAYIDAKİ seriye GİREMEZ', () {
      // 3-4-5 serisine kırmızı 11 giremez
      final run = [t(OkeyColor.red, 3), t(OkeyColor.red, 4), fake];
      expect(OkeyMeldValidator.isValidRun(run, okey), isFalse);
    });

    test('sahte okey BAŞKA SAYIDAKİ gruba GİREMEZ', () {
      // 5-5-5 grubuna kırmızı 11 giremez
      final set = [t(OkeyColor.blue, 5), t(OkeyColor.black, 5), fake];
      expect(
        OkeyMeldValidator.isValidSet(set, okey),
        isFalse,
        reason: 'sahte okey her gruba giriyor — kural ihlali',
      );
    });

    test('aynı renkte İKİ sahte okey grupta çakışır', () {
      // İkisi de kırmızı 11 sayılır -> aynı renk tekrarı, grup geçersiz
      final set = [t(OkeyColor.blue, 11), fake, fake];
      expect(
        OkeyMeldValidator.isValidSet(set, okey),
        isFalse,
        reason: 'aynı renkten iki taş bir grupta olamaz',
      );
    });

    test('GERÇEK okey serbest jokerdir — her yere girer', () {
      final realOkey = t(OkeyColor.red, 11);
      // Mavi 3-4-5 serisinde 5in yerine geçebilir
      final run = [t(OkeyColor.blue, 3), t(OkeyColor.blue, 4), realOkey];
      expect(
        OkeyMeldValidator.isValidRun(run, okey),
        isTrue,
        reason: 'gerçek okey joker olmalı',
      );
    });

    test('sahte okey ile ÇİFT yalnızca okey taşıyla olur', () {
      expect(
        OkeyMeldValidator.isValidPair([fake, t(OkeyColor.red, 11)], okey),
        isTrue,
        reason: 'sahte okey kırmızı 11 ile çift yapmalı',
      );
      expect(
        OkeyMeldValidator.isValidPair([fake, t(OkeyColor.blue, 5)], okey),
        isFalse,
        reason: 'sahte okey her taşla çift yapamaz',
      );
    });
  });
}

/// OKEY ÇALMA — RULES.md §4
///
/// Sunucudaki okey_steal_joker ile aynı mantık: masadaki perde JOKER olarak
/// duran okeyin yerine, onun yerine geçen gerçek taş konur.
void stealJokerTests() {
  // Gösterge: kırmızı 10 -> okey taşı: kırmızı 11
  final okey = OkeyTile.numbered(OkeyColor.red, 11);
  OkeyTile t(OkeyColor c, int n) => OkeyTile.numbered(c, n);

  group('stealableJokerIndex — RULES.md §4 okey çalma', () {
    test('serideki okeyin yerine geçen taş, okeyin indeksini döner', () {
      // Mavi 3-4-OKEY  ==  3-4-5  →  elimdeki mavi 5 okeyi çalar
      final meld = [t(OkeyColor.blue, 3), t(OkeyColor.blue, 4), okey];
      expect(
        OkeyMeldValidator.stealableJokerIndex(meld, t(OkeyColor.blue, 5), okey),
        2,
      );
    });

    test('grup içindeki okeyin yerine eksik renk konabilir', () {
      // 8 kırmızı - 8 siyah - OKEY  →  8 mavi okeyi çalar
      final meld = [t(OkeyColor.red, 8), t(OkeyColor.black, 8), okey];
      expect(
        OkeyMeldValidator.stealableJokerIndex(meld, t(OkeyColor.blue, 8), okey),
        2,
      );
    });

    test('uymayan taş çalamaz', () {
      final meld = [t(OkeyColor.blue, 3), t(OkeyColor.blue, 4), okey];
      expect(
        OkeyMeldValidator.stealableJokerIndex(meld, t(OkeyColor.red, 9), okey),
        isNull,
      );
    });

    test('jokersiz perden çalınamaz', () {
      final meld = [
        t(OkeyColor.blue, 3),
        t(OkeyColor.blue, 4),
        t(OkeyColor.blue, 5),
      ];
      expect(
        OkeyMeldValidator.stealableJokerIndex(meld, t(OkeyColor.blue, 6), okey),
        isNull,
      );
    });

    test('SAHTE OKEY çalınamaz — perde normal bir taştır', () {
      // Sahte okey kırmızı 11 sayılır: 9-10-SAHTE == 9-10-11 geçerli bir seri.
      // Ama sahte okey JOKER DEĞİLDİR, dolayısıyla "yerine geçilecek" bir okey
      // de değildir (RULES.md §1).
      final meld = [
        t(OkeyColor.red, 9),
        t(OkeyColor.red, 10),
        const OkeyTile.falseJoker(),
      ];
      expect(
        OkeyMeldValidator.stealableJokerIndex(meld, t(OkeyColor.red, 11), okey),
        isNull,
      );
    });
  });
}

/// countValidPairs, sunucudaki okey_is_valid_pair_ex ile AYNI şeyi saymalı:
/// gösterge çifti (tek taş) de bir çifttir (RULES.md §8).
void countValidPairsTests() {
  final okey = OkeyTile.numbered(OkeyColor.red, 11);
  final gosterge = OkeyTile.numbered(OkeyColor.red, 10);
  OkeyTile t(OkeyColor c, int n) => OkeyTile.numbered(c, n);

  group('countValidPairs — gösterge çifti paritesi', () {
    final groups = [
      [t(OkeyColor.blue, 2), t(OkeyColor.blue, 2)],
      [t(OkeyColor.black, 4), t(OkeyColor.black, 4)],
      [gosterge], // gösterge çifti: TEK taş
    ];

    test('gösterge verilmezse tek taşlı grup geçersiz sayılır', () {
      expect(OkeyMeldValidator.countValidPairs(groups, okey), -1);
    });

    test('gösterge verilirse tek taş da çift sayılır', () {
      expect(OkeyMeldValidator.countValidPairs(groups, okey, gosterge), 3);
    });

    test('win detector aynı sonucu vermeli', () {
      final r = OkeyWinDetector.validatePairsOpening(
        groups: groups,
        okeyTile: okey,
        requiredMinPairs: 3,
        indicatorTile: gosterge,
      );
      expect(r.isValid, isTrue);
      expect(r.pairCount, 3);
    });
  });
}
