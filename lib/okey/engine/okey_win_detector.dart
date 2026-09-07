import 'okey_meld_validator.dart';
import 'okey_scoring.dart';
import 'okey_tile.dart';

/// El açma (oyuna girme) denemesinin sonucu — RULES.md §3.
class OkeyOpeningResult {
  final bool isValid;

  /// Seri ile açılışta toplam puan; çift açılışında 0.
  final int points;

  /// Çift ile açılışta çift sayısı; seri açılışında 0.
  final int pairCount;

  final bool isPairsOpening;
  final String? invalidReason;

  const OkeyOpeningResult._({
    required this.isValid,
    this.points = 0,
    this.pairCount = 0,
    this.isPairsOpening = false,
    this.invalidReason,
  });

  factory OkeyOpeningResult.invalid(String reason) =>
      OkeyOpeningResult._(isValid: false, invalidReason: reason);

  factory OkeyOpeningResult.series(int points) =>
      OkeyOpeningResult._(isValid: true, points: points);

  factory OkeyOpeningResult.pairs(int pairCount) => OkeyOpeningResult._(
    isValid: true,
    pairCount: pairCount,
    isPairsOpening: true,
  );
}

/// El açma doğrulaması ve bitiş türü tespiti.
///
/// NOT: Artık ayrı bir "kazandım" beyanı yoktur. RULES.md §6'ya göre kazanma,
/// tüm taşları per/işleme olarak yere açıp **son taşı atmakla** gerçekleşir;
/// bunu sunucu her atma sonrası elin boşalıp boşalmadığına bakarak tespit eder.
class OkeyWinDetector {
  const OkeyWinDetector._();

  /// Seri/grup ile açılış — RULES.md §3.
  /// [requiredMinPoints] katlamasız modda 101, katlamalı modda masadaki en
  /// yüksek açılıştan 1 fazladır. Eşli modda eşi açmışsa 0 geçilebilir.
  static OkeyOpeningResult validateSeriesOpening({
    required List<List<OkeyTile>> groups,
    required OkeyTile okeyTile,
    required int requiredMinPoints,
  }) {
    if (groups.isEmpty) {
      return OkeyOpeningResult.invalid('En az bir per/grup açmalısın.');
    }
    for (final group in groups) {
      if (!OkeyMeldValidator.isValidMeld(group, okeyTile)) {
        return OkeyOpeningResult.invalid(
          'Geçersiz per/grup: ${group.map((t) => t.toString()).join(', ')}',
        );
      }
    }
    final points = OkeyMeldValidator.totalOpeningPoints(groups, okeyTile);
    if (points < requiredMinPoints) {
      return OkeyOpeningResult.invalid(
        'El açmak için en az $requiredMinPoints puan gerekli (senin toplamın: $points).',
      );
    }
    return OkeyOpeningResult.series(points);
  }

  /// Çift ile açılış — RULES.md §3 (en az 5 çift; katlamalı modda daha fazla).
  ///
  /// [indicatorTile] verilirse GÖSTERGE ÇİFTİ de sayılır (RULES.md §8):
  /// göstergenin tek kopyası başlı başına bir çifttir. Sunucu bunu her zaman
  /// sayar; parametre geçilmezse istemci ipucu sunucudan DAHA KATI olur.
  static OkeyOpeningResult validatePairsOpening({
    required List<List<OkeyTile>> groups,
    required OkeyTile okeyTile,
    required int requiredMinPairs,
    OkeyTile? indicatorTile,
  }) {
    final count = OkeyMeldValidator.countValidPairs(
      groups,
      okeyTile,
      indicatorTile,
    );
    if (count < 0) {
      return OkeyOpeningResult.invalid(
        'Gruplardan biri geçerli bir çift değil.',
      );
    }
    if (count < requiredMinPairs) {
      return OkeyOpeningResult.invalid(
        'Çift ile açmak için en az $requiredMinPairs çift gerekli (senin çiftin: $count).',
      );
    }
    return OkeyOpeningResult.pairs(count);
  }

  /// Bitiş türü — RULES.md §6/§7.
  ///
  /// [lastDiscardedTile] son atılan taş, [openedThisTurnOnly] oyuncunun hiç
  /// açmamışken tek turda tüm taşlarını sermesi (elden bitiş),
  /// [openedWithPairs] çift açarak oynuyor olması.
  static OkeyFinishType detectFinishType({
    required OkeyTile lastDiscardedTile,
    required OkeyTile okeyTile,
    required bool openedThisTurnOnly,
    required bool openedWithPairs,
  }) {
    return OkeyFinishType(
      withOkey: lastDiscardedTile.isJokerFor(okeyTile),
      elden: openedThisTurnOnly,
      withPairs: openedWithPairs,
    );
  }

  static int countJokersHeld(List<OkeyTile> tiles, OkeyTile okeyTile) =>
      tiles.where((t) => t.isJokerFor(okeyTile)).length;
}
