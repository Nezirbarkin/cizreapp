import 'dart:math';

import 'package:cizreapp/okey/engine/okey_hand_hints.dart';
import 'package:cizreapp/okey/engine/okey_meld_validator.dart';
import 'package:cizreapp/okey/engine/okey_tile.dart';
import 'package:flutter_test/flutter_test.dart';

/// KABA KUVVET REFERANSI — provider'da eskiden çalışan taramanın birebir
/// kopyası. Hızlı motorun (OkeyHandHints) çıktısı bununla AYNI olmalıdır;
/// aksi halde ıstakadaki mavi ipucu çizgileri sessizce değişmiş olurdu.
bool _anyOrderIsRun(List<OkeyTile> trio, OkeyTile okeyTile) {
  const orders = [
    [0, 1, 2],
    [0, 2, 1],
    [1, 0, 2],
    [1, 2, 0],
    [2, 0, 1],
    [2, 1, 0],
  ];
  for (final o in orders) {
    if (OkeyMeldValidator.isValidRun([
      trio[o[0]],
      trio[o[1]],
      trio[o[2]],
    ], okeyTile)) {
      return true;
    }
  }
  return false;
}

Set<int> _bruteForce(List<OkeyTile?> slots, OkeyTile okeyTile) {
  final idx = <int>[];
  for (var i = 0; i < slots.length; i++) {
    if (slots[i] != null) idx.add(i);
  }
  OkeyTile at(int i) => slots[i]!;
  final result = <int>{};
  for (var x = 0; x < idx.length; x++) {
    final a = idx[x];
    for (var y = x + 1; y < idx.length; y++) {
      final b = idx[y];
      if (OkeyMeldValidator.isValidPair([at(a), at(b)], okeyTile)) {
        result.add(a);
        result.add(b);
      }
      for (var z = y + 1; z < idx.length; z++) {
        final c = idx[z];
        final trio = [at(a), at(b), at(c)];
        if (OkeyMeldValidator.isValidSet(trio, okeyTile) ||
            _anyOrderIsRun(trio, okeyTile)) {
          result.addAll([a, b, c]);
        }
      }
    }
  }
  return result;
}

List<OkeyTile> _fullDeck() {
  final deck = <OkeyTile>[];
  for (var copy = 0; copy < 2; copy++) {
    for (final color in OkeyColor.values) {
      for (var n = 1; n <= 13; n++) {
        deck.add(OkeyTile.numbered(color, n));
      }
    }
  }
  deck.add(const OkeyTile.falseJoker());
  deck.add(const OkeyTile.falseJoker());
  return deck;
}

void main() {
  group('OkeyHandHints.meldableSlots', () {
    test('rastgele 3000 rafta kaba kuvvetle BİREBİR aynı sonucu verir', () {
      final rnd = Random(20260908);
      final deck = _fullDeck();
      for (var trial = 0; trial < 3000; trial++) {
        deck.shuffle(rnd);
        final okey = deck.lastWhere((t) => !t.isFalseJoker);
        final handSize = 1 + rnd.nextInt(22);
        // Taşlar rastgele slotlara serpilir: boşluklar da denenmeli.
        final slots = List<OkeyTile?>.filled(32, null);
        final free = List<int>.generate(32, (i) => i)..shuffle(rnd);
        for (var i = 0; i < handSize; i++) {
          slots[free[i]] = deck[i];
        }
        expect(
          OkeyHandHints.meldableSlots(slots, okey),
          _bruteForce(slots, okey),
          reason: 'raf: $slots  okey: $okey',
        );
      }
    });

    test('boş ve tek taşlı rafta hiçbir ipucu yok', () {
      const okey = OkeyTile.numbered(OkeyColor.red, 5);
      expect(OkeyHandHints.meldableSlots(List.filled(16, null), okey), isEmpty);
      final one = List<OkeyTile?>.filled(16, null);
      one[3] = const OkeyTile.numbered(OkeyColor.blue, 7);
      expect(OkeyHandHints.meldableSlots(one, okey), isEmpty);
    });

    test('13-1 sarması seri saymaz (RULES.md §2)', () {
      const okey = OkeyTile.numbered(OkeyColor.red, 5);
      final slots = <OkeyTile?>[
        const OkeyTile.numbered(OkeyColor.blue, 12),
        const OkeyTile.numbered(OkeyColor.blue, 13),
        const OkeyTile.numbered(OkeyColor.blue, 1),
      ];
      expect(OkeyHandHints.meldableSlots(slots, okey), isEmpty);
    });

    test('okey (joker) rafta ise tüm taşlar işaretlenir', () {
      const okey = OkeyTile.numbered(OkeyColor.red, 5);
      final slots = <OkeyTile?>[
        const OkeyTile.numbered(OkeyColor.red, 5), // okey = joker
        const OkeyTile.numbered(OkeyColor.blue, 9),
        null,
        const OkeyTile.numbered(OkeyColor.black, 2),
      ];
      expect(OkeyHandHints.meldableSlots(slots, okey), {0, 1, 3});
    });

    test('sahte okey JOKER DEĞİL: okey taşının kimliğiyle oynar', () {
      const okey = OkeyTile.numbered(OkeyColor.red, 5);
      final slots = <OkeyTile?>[
        const OkeyTile.falseJoker(), // kırmızı 5 gibi
        const OkeyTile.numbered(OkeyColor.blue, 9),
      ];
      // Kırmızı 5 ile mavi 9 ne çift ne per — sahte okey joker olsaydı çift
      // sayılırdı.
      expect(OkeyHandHints.meldableSlots(slots, okey), isEmpty);

      final pair = <OkeyTile?>[
        const OkeyTile.falseJoker(),
        const OkeyTile.numbered(OkeyColor.red, 5),
      ];
      expect(OkeyHandHints.meldableSlots(pair, okey), {0, 1});
    });
  });
}
