import 'package:cizreapp/okey/okey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  drawPlacementTests();

  // Gösterge: 7 Kırmızı -> okey taşı: 8 Kırmızı
  final okeyTile = OkeyTile.numbered(OkeyColor.red, 8);
  OkeyTile t(OkeyColor c, int n) => OkeyTile.numbered(c, n);

  /// Slotları okunur bir dizeye çevirir: taş -> "1b", boşluk -> "_"
  String render(List<OkeyTile?> slots) {
    final buf = <String>[];
    for (final s in slots) {
      if (s == null) {
        buf.add('_');
      } else if (s.isFalseJoker) {
        buf.add('J');
      } else {
        buf.add('${s.number}${s.color!.name[0]}');
      }
    }
    // Sondaki boşlukları kırp
    while (buf.isNotEmpty && buf.last == '_') {
      buf.removeLast();
    }
    return buf.join(' ');
  }

  _autoMeldTests();

  group('SERİ DİZ — gruplar arasına boşluk', () {
    test('aynı renk ardışık taşlar bir grup, aralarında boşluk kalır', () {
      // Mavi 1-2-3-4 ve Kırmızı 11-11-11 değil; seri için: Siyah 7-8-9
      final tiles = [
        t(OkeyColor.blue, 3),
        t(OkeyColor.black, 8),
        t(OkeyColor.blue, 1),
        t(OkeyColor.black, 7),
        t(OkeyColor.blue, 4),
        t(OkeyColor.black, 9),
        t(OkeyColor.blue, 2),
      ];
      final slots = OkeyRackLayout.buildSorted(tiles, okeyTile, byPairs: false);

      // Beklenen: 1b 2b 3b 4b _ 7bl 8bl 9bl  (renk sırası: black=2, blue=3)
      final out = render(slots);
      expect(out, contains('_'), reason: 'gruplar arasında boşluk olmalı');

      // İki grup da bitişik olmalı ve aralarında tam bir boşluk bulunmalı
      final parts = out.split(' _ ');
      expect(parts.length, 2);
      expect(parts[0].split(' ').length, 3); // siyah 7-8-9
      expect(parts[1].split(' ').length, 4); // mavi 1-2-3-4
    });

    test('tek başına kalan taş da kendi grubu olur', () {
      final tiles = [
        t(OkeyColor.blue, 1),
        t(OkeyColor.blue, 2),
        t(OkeyColor.blue, 3),
        t(OkeyColor.red, 12), // tek başına
      ];
      final slots = OkeyRackLayout.buildSorted(tiles, okeyTile, byPairs: false);
      final out = render(slots);
      expect(out.split(' _ ').length, 2);
    });

    test('tüm taşlar korunur (hiçbiri kaybolmaz)', () {
      final tiles = List<OkeyTile>.generate(
        21,
        (i) => t(OkeyColor.values[i % 4], (i % 13) + 1),
      );
      final slots = OkeyRackLayout.buildSorted(tiles, okeyTile, byPairs: false);
      expect(OkeyRackLayout.tilesOf(slots).length, 21);
    });

    test('elde SAHTE OKEY varken çökmez (regresyon: null check operator)', () {
      // Sahte okeyin color/number'ı null'dur — groupBySeries onu "normal"
      // (color!/number! ile sıralanan) kümeden ayırmazsa sort() çöker.
      final tiles = [
        t(OkeyColor.blue, 1),
        t(OkeyColor.blue, 2),
        t(OkeyColor.blue, 3),
        const OkeyTile.falseJoker(),
      ];
      final slots = OkeyRackLayout.buildSorted(tiles, okeyTile, byPairs: false);
      expect(OkeyRackLayout.tilesOf(slots).length, 4);
      expect(render(slots), contains('J'));
    });

    test('ÇOK SAYIDA küçük grup 32 slotu aşınca gruplar birbirine KARIŞMAZ '
        '(regresyon: "perler şaçmalıyor")', () {
      // Kasıtlı olarak: 2 gerçek per (kırmızı 1-2-3, mavi 1-2-3) + 14 tekil
      // grup (sarı/siyah, aralarında hep 2 rakam boşluk — asla ardışık/eş
      // olmasınlar diye). 16 grup × (taş + ayırıcı) toplamı 32 slotu aşar
      // — eski koddaki "ilk boş slota at" güvenlik ağı taşan taşları
      // ÖNCEKİ gruplardan birinin ayırıcı boşluğuna düşürüp o grubu
      // bölüyordu. Artık her grup, boşluk feda edilse bile, KENDİ İÇİNDE
      // bitişik ve BAŞKA taş sızmamış olarak kalmalı.
      final tiles = [
        t(OkeyColor.red, 1),
        t(OkeyColor.red, 2),
        t(OkeyColor.red, 3),
        t(OkeyColor.blue, 1),
        t(OkeyColor.blue, 2),
        t(OkeyColor.blue, 3),
        for (final n in [1, 3, 5, 7, 9, 11, 13]) t(OkeyColor.yellow, n),
        for (final n in [1, 3, 5, 7, 9, 11, 13]) t(OkeyColor.black, n),
      ];
      final expectedGroups = OkeyRackLayout.groupBySeries(tiles, okeyTile);
      final slots = OkeyRackLayout.buildSorted(tiles, okeyTile, byPairs: false);

      // Hiçbir taş kaybolmadı
      expect(OkeyRackLayout.tilesOf(slots).length, tiles.length);

      // Her grup, yerleştiği slotlarda BİTİŞİK duruyor ve arasına BAŞKA
      // bir taş sızmamış (o aralıktaki her slot ya bu grubun bir taşı ya
      // da boş olmalı — asla farklı bir grubun taşı olmamalı).
      for (final group in expectedGroups) {
        final indices = group.map((tile) => slots.indexOf(tile)).toList()
          ..sort();
        expect(
          indices,
          everyElement(greaterThanOrEqualTo(0)),
          reason: 'grup $group tamamen yerleştirilmedi',
        );
        final span = slots.sublist(indices.first, indices.last + 1);
        final foreign = span.where((s) => s != null && !group.contains(s));
        expect(
          foreign,
          isEmpty,
          reason:
              'grup $group\'in arasına başka bir taş sızdı: $foreign — '
              'gruplar birbirine karışıyor',
        );
      }
    });
  });

  group('ÇİFT DİZ — çiftler gruplanır, aralarında boşluk', () {
    test('aynı renk+rakam ikilileri yan yana, aralarında boşluk', () {
      final tiles = [
        t(OkeyColor.red, 5),
        t(OkeyColor.blue, 9),
        t(OkeyColor.red, 5),
        t(OkeyColor.blue, 9),
      ];
      final slots = OkeyRackLayout.buildSorted(tiles, okeyTile, byPairs: true);
      final out = render(slots);
      final parts = out.split(' _ ');
      expect(parts.length, 2);
      expect(parts[0], '5r 5r');
      expect(parts[1], '9b 9b');
    });

    test('eşi olmayan taşlar ayrı bir grupta toplanır', () {
      final tiles = [
        t(OkeyColor.red, 5),
        t(OkeyColor.red, 5),
        t(OkeyColor.blue, 9), // eşi yok
      ];
      final slots = OkeyRackLayout.buildSorted(tiles, okeyTile, byPairs: true);
      final parts = render(slots).split(' _ ');
      expect(parts.first, '5r 5r');
      expect(parts.last, '9b');
    });

    test('elde SAHTE OKEY varken çökmez (regresyon: null check operator)', () {
      final tiles = [
        t(OkeyColor.red, 5),
        t(OkeyColor.red, 5),
        const OkeyTile.falseJoker(),
      ];
      final slots = OkeyRackLayout.buildSorted(tiles, okeyTile, byPairs: true);
      expect(OkeyRackLayout.tilesOf(slots).length, 3);
      expect(render(slots), contains('J'));
    });
  });

  group('Sürükleme (moveTile)', () {
    test('taş boş slota taşınır', () {
      final slots = <OkeyTile?>[t(OkeyColor.red, 5), null, null];
      final moved = OkeyRackLayout.moveTile(slots, 0, 2);
      expect(moved[0], isNull);
      expect(moved[2], t(OkeyColor.red, 5));
    });

    test('hedef doluysa aradaki taşlar KAYAR (yer değiştirmez)', () {
      // 1·2·3·5 dizisinde 4'ü 5'in üstüne bırakınca 5 SAĞA kaymalı ve
      // sonuç 1·2·3·4·5 olmalı. Eski davranış (yer değiştirme) 5'i elin
      // öbür ucuna atıyor, dizmeye çalıştığın peri bozuyordu.
      final one = t(OkeyColor.blue, 1);
      final two = t(OkeyColor.blue, 2);
      final three = t(OkeyColor.blue, 3);
      final four = t(OkeyColor.blue, 4);
      final five = t(OkeyColor.blue, 5);

      final slots = <OkeyTile?>[one, two, three, five, null, four];
      final moved = OkeyRackLayout.moveTile(slots, 5, 3);

      expect(moved.sublist(0, 5), [one, two, three, four, five]);
      expect(moved[5], isNull);
    });

    test('kayma EN YAKIN boşluğa doğru olur (dizilim az bozulur)', () {
      final a = t(OkeyColor.red, 1);
      final b = t(OkeyColor.red, 2);
      final c = t(OkeyColor.red, 3);
      final x = t(OkeyColor.blue, 9);

      // Boşluk hedefin HEMEN SOLUNDA (indeks 0); taş sağdan geliyor.
      // Sadece 'a' bir sola kaymalı, b ve c yerinde kalmalı.
      final slots = <OkeyTile?>[null, a, b, c, x];
      final moved = OkeyRackLayout.moveTile(slots, 4, 1);

      expect(moved, [a, x, b, c, null]);
    });

    test('iki taşlık raftaki hareket taşı kaybetmez', () {
      final a = t(OkeyColor.red, 5);
      final b = t(OkeyColor.blue, 9);
      final moved = OkeyRackLayout.moveTile(<OkeyTile?>[a, b], 0, 1);
      expect(moved.whereType<OkeyTile>().toSet(), {a, b});
      expect(moved[1], a, reason: 'taşınan taş hedefte olmalı');
    });

    test('boş slottan taşıma yerleşimi bozmaz', () {
      final slots = <OkeyTile?>[null, t(OkeyColor.red, 5)];
      expect(OkeyRackLayout.moveTile(slots, 0, 1), slots);
    });

    test('geçersiz indeks yerleşimi bozmaz', () {
      final slots = <OkeyTile?>[t(OkeyColor.red, 5), null];
      expect(OkeyRackLayout.moveTile(slots, 0, 99), slots);
      expect(OkeyRackLayout.moveTile(slots, -1, 1), slots);
      expect(OkeyRackLayout.moveTile(slots, 1, 1), slots);
    });
  });

  group('mergeWithHand — elle dizilim korunur', () {
    test('atılan taş slottan kalkar, dizilim bozulmaz', () {
      final a = t(OkeyColor.red, 5);
      final b = t(OkeyColor.blue, 9);
      final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
      slots[3] = a;
      slots[7] = b;

      final merged = OkeyRackLayout.mergeWithHand(slots, [b]); // a atıldı
      expect(merged[3], isNull);
      expect(merged[7], b, reason: 'kalan taş yerinde durmalı');
    });

    test('çekilen yeni taş ilk boş slota gelir', () {
      final a = t(OkeyColor.red, 5);
      final yeni = t(OkeyColor.black, 12);
      final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
      slots[2] = a;

      final merged = OkeyRackLayout.mergeWithHand(slots, [a, yeni]);
      expect(merged[2], a, reason: 'mevcut taş yerinde kalmalı');
      expect(merged[0], yeni, reason: 'yeni taş ilk boş slota konmalı');
    });

    test('aynı taştan iki kopya varsa ikisi de korunur', () {
      final a = t(OkeyColor.red, 5);
      final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
      slots[1] = a;
      slots[9] = a;

      final merged = OkeyRackLayout.mergeWithHand(slots, [a, a]);
      expect(OkeyRackLayout.tilesOf(merged).length, 2);
      expect(merged[1], a);
      expect(merged[9], a);
    });

    test('elden çıkan kopya sayısı kadar slot boşalır', () {
      final a = t(OkeyColor.red, 5);
      final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
      slots[1] = a;
      slots[9] = a;

      final merged = OkeyRackLayout.mergeWithHand(slots, [a]); // biri gitti
      expect(OkeyRackLayout.tilesOf(merged).length, 1);
    });
  });
}

/// Otomatik per sayımı: ıstakada boşlukla ayrılmış bitişik öbekler
void _autoMeldTests() {
  final okeyTile = OkeyTile.numbered(OkeyColor.red, 8);
  OkeyTile t(OkeyColor c, int n) => OkeyTile.numbered(c, n);

  group('Otomatik per sayımı (contiguousGroups)', () {
    test('boşlukla ayrılmış öbekler doğru bölünür', () {
      final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
      // 1 2 3 4 _ 9 9 9
      slots[0] = t(OkeyColor.blue, 1);
      slots[1] = t(OkeyColor.blue, 2);
      slots[2] = t(OkeyColor.blue, 3);
      slots[3] = t(OkeyColor.blue, 4);
      // slots[4] boş
      slots[5] = t(OkeyColor.red, 9);
      slots[6] = t(OkeyColor.black, 9);
      slots[7] = t(OkeyColor.blue, 9);

      final groups = OkeyRackLayout.contiguousGroups(slots);
      expect(groups.length, 2);
      expect(groups[0].tiles.length, 4);
      expect(groups[1].tiles.length, 3);
    });

    test('aynı renk 1-2-3-4-5 seri olarak geçerli sayılır', () {
      final tiles = [
        t(OkeyColor.blue, 1),
        t(OkeyColor.blue, 2),
        t(OkeyColor.blue, 3),
        t(OkeyColor.blue, 4),
        t(OkeyColor.blue, 5),
      ];
      expect(OkeyMeldValidator.isValidRun(tiles, okeyTile), isTrue);
    });

    test('farklı renk 2-2-2 grup olarak geçerli sayılır', () {
      final tiles = [
        t(OkeyColor.blue, 2),
        t(OkeyColor.red, 2),
        t(OkeyColor.black, 2),
      ];
      expect(OkeyMeldValidator.isValidSet(tiles, okeyTile), isTrue);
    });

    test('satır sonu öbeği böler (görsel olarak ayrı satırlar)', () {
      final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
      final last = OkeyRackLayout.slotsPerRow - 1;
      slots[last] = t(OkeyColor.blue, 5);
      slots[last + 1] = t(OkeyColor.blue, 6); // ikinci satırın başı
      final groups = OkeyRackLayout.contiguousGroups(slots);
      expect(groups.length, 2, reason: 'satır sınırı öbeği bölmeli');
    });

    test('boş ıstakada öbek yok', () {
      final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
      expect(OkeyRackLayout.contiguousGroups(slots), isEmpty);
    });
  });
}

/// ÇEKİLEN TAŞ, BIRAKILDIĞI SLOTA GİDER
///
/// GEÇMİŞ: `mergeWithHand` yeni taşları "ilk boş slota" koyuyordu. Oyuncu
/// desteden çektiği taşı ıstakada istediği yere bıraksa bile taş bambaşka
/// bir yere gidiyordu — kullanıcı bunu "rastgele bir yere gidiyor" diye
/// bildirdi. Artık bırakılan slot tercih edilir.
void drawPlacementTests() {
  group('Çekilen taşın yerleşimi', () {
    OkeyTile t(OkeyColor c, int n) => OkeyTile.numbered(c, n);

    test('yeni taş BIRAKILAN slota yerleşir', () {
      final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
      slots[0] = t(OkeyColor.red, 1);
      slots[1] = t(OkeyColor.red, 2);

      final drawn = t(OkeyColor.blue, 9);
      final hand = [slots[0]!, slots[1]!, drawn];

      final result = OkeyRackLayout.mergeWithHand(
        slots,
        hand,
        preferredSlot: 10,
      );

      expect(
        result[10],
        drawn,
        reason:
            'taş bırakılan slota gitmedi — kullanıcı rastgele bir yere '
            'gittiğini bildirmişti',
      );
      // Mevcut dizilim bozulmamalı
      expect(result[0], t(OkeyColor.red, 1));
      expect(result[1], t(OkeyColor.red, 2));
    });

    test('tercih edilen slot DOLUYSA taş ilk boş slota gider', () {
      final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
      slots[5] = t(OkeyColor.black, 7);

      final drawn = t(OkeyColor.blue, 9);
      final hand = [slots[5]!, drawn];

      final result = OkeyRackLayout.mergeWithHand(
        slots,
        hand,
        preferredSlot: 5,
      );

      // Dolu slottaki taş korunur, yeni taş başka yere konur
      expect(result[5], t(OkeyColor.black, 7));
      expect(result.contains(drawn), isTrue, reason: 'taş kayboldu');
    });

    test('tercih verilmezse eski davranış korunur (ilk boş slot)', () {
      final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
      final drawn = t(OkeyColor.yellow, 4);

      final result = OkeyRackLayout.mergeWithHand(slots, [drawn]);
      expect(result[0], drawn);
    });

    test('geçersiz slot indeksi güvenle yok sayılır', () {
      final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
      final drawn = t(OkeyColor.yellow, 4);

      for (final bad in [-1, 999]) {
        final result = OkeyRackLayout.mergeWithHand(slots, [
          drawn,
        ], preferredSlot: bad);
        expect(
          result.contains(drawn),
          isTrue,
          reason: 'geçersiz indekste taş kayboldu ($bad)',
        );
      }
    });

    test('birden çok yeni taşta YALNIZCA ilki tercih edilen slota gider', () {
      final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
      final a = t(OkeyColor.red, 3);
      final b = t(OkeyColor.blue, 8);

      final result = OkeyRackLayout.mergeWithHand(slots, [
        a,
        b,
      ], preferredSlot: 7);

      final atPreferred = result[7];
      expect(atPreferred, isNotNull);
      expect(
        result.whereType<OkeyTile>().length,
        2,
        reason: 'taş sayısı değişti',
      );
    });
  });
}
