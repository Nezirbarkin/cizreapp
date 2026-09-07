import 'okey_tile.dart';

/// Bir oyuncunun el sonundaki durumu — RULES.md §7 ceza tablosunun girdisi.
enum OkeyEndState {
  /// Eli bitiren oyuncu → -101
  winner,

  /// Seri/grup ile el açmış ama bitirememiş → elde kalanların toplamı
  openedWithSeries,

  /// Çift ile el açmış ama bitirememiş → elde kalanların toplamının 2 katı
  openedWithPairs,

  /// Hiç el açamamış → 202
  neverOpened,

  /// Çifte gitmiş ama el açamamış → 404
  pairsAttemptFailed,
}

/// Bir bitişin türü — RULES.md §6 / §7 çarpan tablosu.
class OkeyFinishType {
  final bool withOkey; // son atılan taş okey
  final bool elden; // hiç açmadan tek turda bitiş
  final bool withPairs; // çift açarak bitiş

  const OkeyFinishType({
    this.withOkey = false,
    this.elden = false,
    this.withPairs = false,
  });

  /// RULES.md §7: çarpanlar birleşince ÇARPILARAK uygulanır
  /// (elden ×2 ve okey ×2 → ×4).
  int get multiplier {
    var m = 1;
    if (withOkey) m *= 2;
    if (elden) m *= 2;
    if (withPairs) m *= 2;
    return m;
  }

  /// Veritabanına/görüntülemeye giden etiket.
  String get label {
    if (elden && withOkey) return 'elden_okey';
    if (elden) return 'elden';
    if (withOkey) return 'okey';
    if (withPairs) return 'cift';
    return 'normal';
  }
}

/// RULES.md §7 puanlama motoru.
class OkeyScoring {
  const OkeyScoring._();

  /// Biten oyuncunun sabit puanı.
  static const int winnerScore = -101;

  /// Hiç el açamayanın cezası.
  static const int neverOpenedPenalty = 202;

  /// Çifte gidip açamayanın cezası (202'nin 2 katı).
  static const int pairsAttemptFailedPenalty = 404;

  /// Kural dışı hamle cezası.
  static const int invalidMovePenalty = 101;

  /// Tek bir taşın ceza puanı: sayı taşları basılı numarası kadar; sahte okey
  /// o elin okey taşının numarası kadar sayılır.
  static int tilePenaltyValue(OkeyTile tile, OkeyTile okeyTile) {
    if (tile.isFalseJoker) return okeyTile.number!;
    return tile.number!;
  }

  static int handPenaltyValue(List<OkeyTile> tiles, OkeyTile okeyTile) =>
      tiles.fold(0, (sum, t) => sum + tilePenaltyValue(t, okeyTile));

  /// Bitiş çarpanı uygulanmadan ÖNCEKİ ham ceza.
  static int basePenalty({
    required OkeyEndState state,
    required List<OkeyTile> remainingTiles,
    required OkeyTile okeyTile,
  }) {
    switch (state) {
      case OkeyEndState.winner:
        return winnerScore;
      case OkeyEndState.neverOpened:
        return neverOpenedPenalty;
      case OkeyEndState.pairsAttemptFailed:
        return pairsAttemptFailedPenalty;
      case OkeyEndState.openedWithSeries:
        return handPenaltyValue(remainingTiles, okeyTile);
      case OkeyEndState.openedWithPairs:
        return handPenaltyValue(remainingTiles, okeyTile) * 2;
    }
  }

  /// El sonu puan dağılımı. Çarpan yalnızca KAYBEDENLERE uygulanır;
  /// kazanan her zaman [winnerScore] alır (RULES.md §7).
  static Map<int, int> computeHandScores({
    required int winnerSeat,
    required Map<int, OkeyEndState> seatStates,
    required Map<int, List<OkeyTile>> remainingTiles,
    required OkeyTile okeyTile,
    required OkeyFinishType finish,
  }) {
    final multiplier = finish.multiplier;
    final scores = <int, int>{};

    seatStates.forEach((seat, state) {
      if (seat == winnerSeat || state == OkeyEndState.winner) {
        scores[seat] = winnerScore;
        return;
      }
      final base = basePenalty(
        state: state,
        remainingTiles: remainingTiles[seat] ?? const [],
        okeyTile: okeyTile,
      );
      scores[seat] = base * multiplier;
    });

    return scores;
  }
}
