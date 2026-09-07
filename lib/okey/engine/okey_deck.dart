import 'dart:math';

import 'okey_tile.dart';

/// 101 Okey destesi: 4 renk × 1-13 × 2 kopya + 2 sahte okey = 106 taş.
/// Gerçek dağıtım/karıştırma her zaman sunucuda (Postgres RPC) yapılır —
/// bu sınıf yalnızca istemci ipuçları ve testler için kullanılır, asla
/// gerçek bir eli oluşturmak için güvenilmez.
class OkeyDeck {
  static List<OkeyTile> buildFullDeck() {
    final tiles = <OkeyTile>[];
    for (final color in OkeyColor.values) {
      for (var number = 1; number <= 13; number++) {
        tiles.add(OkeyTile.numbered(color, number));
        tiles.add(OkeyTile.numbered(color, number));
      }
    }
    tiles.add(const OkeyTile.falseJoker());
    tiles.add(const OkeyTile.falseJoker());
    return tiles;
  }

  static List<OkeyTile> shuffled([Random? random]) {
    final tiles = buildFullDeck();
    tiles.shuffle(random ?? Random());
    return tiles;
  }

  /// Gösterge taşından o elin okey (joker) taşını türetir: aynı renk,
  /// numara +1 (13'ten sonra 1'e döner).
  static OkeyTile deriveOkeyTile(OkeyTile indicator) {
    final nextNumber = indicator.number! == 13 ? 1 : indicator.number! + 1;
    return OkeyTile.numbered(indicator.color!, nextNumber);
  }
}
