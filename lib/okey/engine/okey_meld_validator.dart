import 'okey_tile.dart';

/// Tek bir per (seri), grup veya çift doğrulaması — RULES.md §2/§3.
///
/// Tasarım kararı: motor, oyuncunun elini otomatik olarak tüm olası
/// kombinasyonlara göre TARAMAZ. Oyuncu (raf arayüzünde taşları gruplayıp)
/// her zaman açık bir grup listesi gönderir; sunucu yalnızca bu listenin
/// gerçekten geçerli olduğunu doğrular. Bu, okey taşının belirsiz yerleşimi
/// sorununu oyuncunun kendi dizilimi çözdüğü için ortadan kaldırır.
class OkeyMeldValidator {
  const OkeyMeldValidator._();

  /// Bir seride [start] ile başlayıp [index]. sıradaki taşın olması gereken
  /// numarası. RULES.md §2: 13'ten sonra bir kez 1'e sarılabilir (12-13-1
  /// geçerli) ama 1'den sonra devam edilemez (13-1-2 geçersiz).
  /// Serinin [index]. sırasında beklenen sayı; seri biterse null.
  ///
  /// SERİ 13'TE BİTER — 13'ten sonra 1'e SARMA YOKTUR.
  /// (Önceki kural 12-13-1'i geçerli sayıyordu; kullanıcı bunu değiştirdi.)
  static int? expectedRunNumber(int start, int index) {
    final raw = start + index;
    return raw <= 13 ? raw : null;
  }

  static bool _matchesRunFrom(
    List<OkeyTile> tiles,
    OkeyTile okeyTile,
    int start,
  ) {
    for (var i = 0; i < tiles.length; i++) {
      final expected = expectedRunNumber(start, i);
      if (expected == null) return false;
      final tile = tiles[i];
      if (tile.isJokerFor(okeyTile)) continue;
      // Sahte okey ATLANMAZ: okey taşının SAYISIYLA karşılaştırılır.
      if (tile.resolvedNumber(okeyTile) != expected) return false;
    }
    return true;
  }

  /// Serinin başlangıç numarası (geçerli değilse null).
  static int? findRunStart(List<OkeyTile> tiles, OkeyTile okeyTile) {
    if (tiles.length < 3 || tiles.length > 14) return null;

    OkeyColor? color;
    for (final t in tiles) {
      if (t.isJokerFor(okeyTile)) continue;
      // Sahte okey, okey taşının RENGİYLE karşılaştırılır.
      final c = t.resolvedColor(okeyTile);
      if (color == null) {
        color = c;
      } else if (c != color) {
        return null; // seri tek renk olmalı
      }
    }

    for (var start = 1; start <= 13; start++) {
      if (_matchesRunFrom(tiles, okeyTile, start)) return start;
    }
    return null;
  }

  /// [tiles] geçerli bir seri (per) mi?
  static bool isValidRun(List<OkeyTile> tiles, OkeyTile okeyTile) =>
      findRunStart(tiles, okeyTile) != null;

  /// [tiles] geçerli bir grup mu? (aynı rakam, farklı renkler, 3 veya 4 taş)
  static bool isValidSet(List<OkeyTile> tiles, OkeyTile okeyTile) {
    if (tiles.length != 3 && tiles.length != 4) return false;

    int? targetNumber;
    final usedColors = <OkeyColor>{};

    for (final tile in tiles) {
      if (tile.isJokerFor(okeyTile)) continue;
      // Sahte okey burada da NORMAL taş gibi davranır.
      final n = tile.resolvedNumber(okeyTile);
      final c = tile.resolvedColor(okeyTile);
      targetNumber ??= n;
      if (n != targetNumber) return false;
      if (c == null || !usedColors.add(c)) return false; // aynı renk tekrarı
    }
    return true;
  }

  /// [tiles] geçerli bir çift mi? (aynı renk + aynı rakam, 2 taş)
  /// Joker herhangi bir taşla çift oluşturabilir.
  static bool isValidPair(List<OkeyTile> tiles, OkeyTile okeyTile) {
    if (tiles.length != 2) return false;
    final a = tiles[0];
    final b = tiles[1];
    if (a.isJokerFor(okeyTile) || b.isJokerFor(okeyTile)) return true;
    // Sahte okey yalnızca OKEY taşıyla eşleşir — her taşla değil.
    return a.resolvedColor(okeyTile) == b.resolvedColor(okeyTile) &&
        a.resolvedNumber(okeyTile) == b.resolvedNumber(okeyTile);
  }

  /// GÖSTERGE ÇİFTİ — göstergeyle aynı TEK taş, başlı başına bir çifttir.
  ///
  /// Göstergenin bir kopyası ortada açık durduğu için oyunda yalnızca bir
  /// kopyası kalır; gerçek çiftini yapmak imkânsızdır. Bu yüzden o tek taş
  /// çift sayılır (ör. 4 gerçek çifti olan oyuncu göstergeyle 5 çift açar).
  static bool isGostergePair(List<OkeyTile> tiles, OkeyTile? indicatorTile) {
    if (indicatorTile == null) return false;
    return tiles.length == 1 && tiles.first == indicatorTile;
  }

  /// Normal çift VEYA gösterge çifti.
  static bool isValidPairEx(
    List<OkeyTile> tiles,
    OkeyTile okeyTile,
    OkeyTile? indicatorTile,
  ) => isGostergePair(tiles, indicatorTile) || isValidPair(tiles, okeyTile);

  /// Seri veya grup (çift HARİÇ — çift ayrı bir açılış türüdür).
  static bool isValidMeld(List<OkeyTile> tiles, OkeyTile okeyTile) =>
      isValidRun(tiles, okeyTile) || isValidSet(tiles, okeyTile);

  /// [tile], [meldTiles] listesine eklendiğinde hâlâ geçerli bir per/grup
  /// oluşturuyor mu? Hem SONA hem ÖNE eklemeyi dener ve geçerliyse DOĞRU
  /// SIRADAKİ yeni listeyi döner; ikisi de geçersizse null.
  ///
  /// NEDEN İKİSİ BİRDEN: [isValidRun] pozisyon tabanlıdır — bir seriyi
  /// SADECE en yüksek uçtan (sona ekleyerek) uzatmak "4-5-6" + "7" gibi
  /// otomatik çalışır, ama en düşük uçtan uzatmak "4-5-6" + "3" (gerçekte
  /// "3-4-5-6" olması gereken) sona eklenirse "4-5-6-3" olur ve sıra
  /// bozulduğu için geçersiz sayılırdı — oysa gerçek Okey'de bir seri her
  /// iki uçtan da uzatılabilir. Grup (set) türünde sıra zaten önemsizdir,
  /// bu yüzden bu ayrım yalnızca serileri etkiler.
  static List<OkeyTile>? extendMeld(
    List<OkeyTile> meldTiles,
    OkeyTile tile,
    OkeyTile okeyTile,
  ) {
    final appended = [...meldTiles, tile];
    if (isValidMeld(appended, okeyTile)) return appended;

    final prepended = [tile, ...meldTiles];
    if (isValidMeld(prepended, okeyTile)) return prepended;

    return null;
  }

  /// El açma (≥101) hesabı için bir meld'in puanı — RULES.md §3.
  /// 13-1 kombinasyonunda 1 sayısı **1 puan** sayılır (12-13-1 = 26).
  /// Joker, yerine geçtiği taşın değeri kadar sayılır.
  ///
  /// Not: tamamı jokerden oluşan bir seride başlangıç belirsizdir; bu durumda
  /// 1..13 arasında bulunan ilk geçerli başlangıç kullanılır (pratikte çok
  /// nadir bir köşe durumu — en fazla 4 joker vardır).
  static int meldPoints(List<OkeyTile> tiles, OkeyTile okeyTile) {
    final runStart = findRunStart(tiles, okeyTile);
    if (runStart != null) {
      var sum = 0;
      for (var i = 0; i < tiles.length; i++) {
        sum += expectedRunNumber(runStart, i)!;
      }
      return sum;
    }
    if (isValidSet(tiles, okeyTile)) {
      int? sharedNumber;
      for (final tile in tiles) {
        if (!tile.isJokerFor(okeyTile)) {
          sharedNumber = tile.number;
          break;
        }
      }
      sharedNumber ??= okeyTile.number;
      return sharedNumber! * tiles.length;
    }
    throw ArgumentError('meldPoints: tiles geçerli bir per/grup değil');
  }

  /// Seri/grup ile açılışta toplam puan (baraj kontrolü için).
  static int totalOpeningPoints(
    List<List<OkeyTile>> groups,
    OkeyTile okeyTile,
  ) {
    return groups.fold(0, (sum, g) => sum + meldPoints(g, okeyTile));
  }

  /// Çift ile açılışta geçerli çift sayısı (baraj: en az 5 çift).
  ///
  /// [indicatorTile] verilirse GÖSTERGE ÇİFTİ (tek taş) de sayılır — sunucu
  /// (okey_lay_meld → okey_is_valid_pair_ex) tam olarak bunu yapar, bu yüzden
  /// istemci ipucunun da aynı şeyi sayması gerekir.
  static int countValidPairs(
    List<List<OkeyTile>> groups,
    OkeyTile okeyTile, [
    OkeyTile? indicatorTile,
  ]) {
    var count = 0;
    for (final g in groups) {
      if (!isValidPairEx(g, okeyTile, indicatorTile)) {
        return -1; // geçersiz grup varsa -1
      }
      count++;
    }
    return count;
  }

  /// OKEY ÇALMA (RULES.md §4) — [tile], [meldTiles] içinde JOKER olarak duran
  /// bir okeyin yerine geçebilir mi? Geçebiliyorsa o okeyin indeksini,
  /// geçemiyorsa null döner.
  ///
  /// Sunucudaki okey_steal_joker ile AYNI mantık: joker konumuna taş konur ve
  /// per hâlâ geçerli mi diye bakılır. Sahte okey burada joker sayılmadığı
  /// için (bkz. [OkeyTile.isJokerFor]) çalınamaz — perde normal bir taştır.
  static int? stealableJokerIndex(
    List<OkeyTile> meldTiles,
    OkeyTile tile,
    OkeyTile okeyTile,
  ) {
    for (var i = 0; i < meldTiles.length; i++) {
      if (!meldTiles[i].isJokerFor(okeyTile)) continue;
      final candidate = [...meldTiles];
      candidate[i] = tile;
      if (isValidMeld(candidate, okeyTile)) return i;
    }
    return null;
  }
}
