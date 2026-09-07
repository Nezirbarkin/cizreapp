import 'okey_meld_validator.dart';
import 'okey_tile.dart';

/// Bir elin per/grup ayrışımı: masaya konabilecek geçerli gruplar ve
/// hiçbirine girmeyen artık taşlar.
class OkeyHandPartition {
  /// Geçerli per (seri) ve gruplar — her biri 3+ taş.
  final List<List<OkeyTile>> melds;

  /// Hiçbir gruba girmeyen taşlar.
  final List<OkeyTile> leftovers;

  /// [melds] toplam açılış puanı.
  final int points;

  /// Arama bütçesi tükendiği için sonuç KESİN EN İYİ olmayabilir.
  final bool approximate;

  const OkeyHandPartition({
    required this.melds,
    required this.leftovers,
    required this.points,
    this.approximate = false,
  });
}

/// Elden EN YÜKSEK PUANLI per/grup ayrışımını çıkaran arama.
///
/// ## Neden gerekliydi
///
/// SERİ DİZ eskiden yalnızca "aynı renk ardışık taşlar" arıyordu. Yani
/// elinde `Kırmızı 3 · Siyah 3 · Mavi 3` varken bunlar üç ayrı tekil taş
/// olarak diziliyor, oyuncu 9 puanlık hazır bir GRUBU gözüyle aramak
/// zorunda kalıyordu. Oysa 101 Okey'de bir per iki biçimde olur:
///
///   * **seri** — aynı renk, ardışık (`1·2·3`)
///   * **grup** — aynı rakam, FARKLI renkler (`3·3·3`)
///
/// İkisi de geçerli, ikisi de puan getirir ve bir taş yalnızca BİRİNE
/// girebilir. Dolayısıyla "en iyi dizilim" bir tercih değil, bir OPTİMİZASYON
/// problemidir: aynı taş bir seriye mi yoksa bir gruba mı gitsin?
///
/// ## Arama nasıl sınırlı kalıyor
///
/// Kaba kuvvet, 22 taşın tüm alt kümelerini denemek olurdu (4 milyon+).
/// Bunun yerine standart "en küçük taşı KAPSA" dallanması kullanılır:
///
///   1. Kullanılmamış EN KÜÇÜK normal taş seçilir (pivot).
///   2. O taş ya artık olarak bırakılır ya da onu İÇEREN bir gruba girer.
///   3. Pivot her dalda kesin olarak tükendiği için ağaç hızla daralır.
///
/// Pivot elin en küçüğü olduğundan, onu içeren bir seri ondan BAŞLAMAK
/// zorundadır (daha küçüğü kalmadı) — tek istisna, seriye baştan joker
/// eklemektir ve o da joker sayısı kadar (en fazla 2) denenir.
///
/// Aynı taş kümesi farklı sıralarla tekrar tekrar çözülmesin diye sonuçlar
/// kullanılmış-taş maskesine göre önbelleklenir.
///
/// ## Neden bir düğüm bütçesi var
///
/// Bu kod her SERİ DİZ dokunuşunda ANA İZLEKTE çalışır. Patolojik bir el
/// (ör. dört renkten 1..13'ün tamamı) aramayı büyütebilir; bütçe dolarsa
/// arama durur ve o ana kadarki en iyi sonuç [OkeyHandPartition.approximate]
/// işaretiyle döner. Oyuncu ASLA donmuş bir ekranla karşılaşmaz.
abstract final class OkeyHandPartitioner {
  /// Varsayılan düğüm (özyineleme) bütçesi.
  ///
  /// Gerçek ellerde (21-22 taş) tipik maliyet birkaç yüz düğümdür; bu tavan
  /// yalnızca patolojik ellerde devreye girer.
  static const int defaultNodeBudget = 40000;

  /// Bir serinin/grubun en az taş sayısı.
  static const int _minMeldSize = 3;

  static OkeyHandPartition best(
    List<OkeyTile> tiles,
    OkeyTile okeyTile, {
    int nodeBudget = defaultNodeBudget,
  }) {
    if (tiles.length < _minMeldSize) {
      return OkeyHandPartition(
        melds: const [],
        leftovers: List<OkeyTile>.from(tiles),
        points: 0,
      );
    }
    return _Search(tiles, okeyTile, nodeBudget).run();
  }

  /// ISTAKA DİZİLİMİNDEN perleri çıkarır: [blocks], boşluklarla ayrılmış
  /// bitişik taş öbekleridir (bkz. `OkeyRackLayout.contiguousGroups`).
  ///
  /// Öbek TEK BAŞINA geçerli bir per/grupsa aynen alınır — oyuncu onu bilerek
  /// öyle dizmiştir. Değilse öbeğin İÇİNDEKİ geçerli perler aranır.
  ///
  /// ## Neden ikinci adım gerekli
  ///
  /// Eskiden yalnızca birinci adım vardı ve "öbek geçerli değilse puan yok"
  /// deniyordu. Oyuncu `1·2·3` ile `2·2·2` taşlarını aralarına boşluk
  /// koymadan yan yana dizdiğinde bu, altı taşlık TEK bir öbek sayılıyor,
  /// geçerli bir per olmadığı için elin puanı **0** görünüyordu (kullanıcı
  /// bildirimi, 2026-09-05). Oysa o dizilimde masaya konabilecek 12 puan
  /// vardır; oyuncuyu önce "SERİ DİZ"e basmaya zorlamanın bir sebebi yok.
  static List<List<OkeyTile>> fromRackGroups(
    Iterable<List<OkeyTile>> blocks,
    OkeyTile okeyTile, {
    int nodeBudget = 4000,
  }) {
    final result = <List<OkeyTile>>[];
    for (final block in blocks) {
      if (block.length < _minMeldSize) continue;
      if (OkeyMeldValidator.isValidMeld(block, okeyTile)) {
        result.add(block);
        continue;
      }
      result.addAll(best(block, okeyTile, nodeBudget: nodeBudget).melds);
    }
    return result;
  }

  /// [melds] listesinin toplam açılış puanı.
  static int pointsOf(Iterable<List<OkeyTile>> melds, OkeyTile okeyTile) {
    var total = 0;
    for (final m in melds) {
      total += OkeyMeldValidator.meldPoints(m, okeyTile);
    }
    return total;
  }
}

/// Tek bir arama koşusu. Durumu (önbellek, sayaç) örnek alanlarında tutar;
/// böylece özyinelemeli fonksiyonlara sekiz parametre taşımak gerekmez.
class _Search {
  final OkeyTile okeyTile;
  final int budget;

  /// Taşlar KANONİK sırada: önce normal taşlar (renk, sayı), sonra jokerler.
  ///
  /// Sıra keyfi değil, ARAMANIN DOĞRULUĞU buna bağlı: "pivot elin en
  /// küçüğüdür, dolayısıyla onu içeren seri ondan başlar" çıkarımı ancak
  /// taşlar bu sırada olduğunda geçerlidir.
  late final List<OkeyTile> _tiles;
  late final List<bool> _isWild;
  late final List<int> _colorIndex;
  late final List<int> _number;

  /// (renk, sayı) → o taşa sahip indeksler.
  final Map<int, List<int>> _byKey = {};

  /// Joker (okey) taşlarının indeksleri.
  final List<int> _wilds = [];

  final Map<int, _Result> _memo = {};
  int _nodes = 0;
  bool _aborted = false;

  _Search(List<OkeyTile> source, this.okeyTile, this.budget) {
    final sorted = List<OkeyTile>.from(source);
    sorted.sort((a, b) {
      final aw = a.isJokerFor(okeyTile);
      final bw = b.isJokerFor(okeyTile);
      if (aw != bw) return aw ? 1 : -1;
      if (aw) return 0;
      final ac = a.resolvedColor(okeyTile)!.index;
      final bc = b.resolvedColor(okeyTile)!.index;
      if (ac != bc) return ac.compareTo(bc);
      return a.resolvedNumber(okeyTile)!.compareTo(b.resolvedNumber(okeyTile)!);
    });

    _tiles = sorted;
    _isWild = List<bool>.filled(sorted.length, false);
    _colorIndex = List<int>.filled(sorted.length, -1);
    _number = List<int>.filled(sorted.length, -1);

    for (var i = 0; i < sorted.length; i++) {
      final t = sorted[i];
      if (t.isJokerFor(okeyTile)) {
        _isWild[i] = true;
        _wilds.add(i);
        continue;
      }
      // SAHTE OKEY normal bir taştır ve okey taşının KİMLİĞİYLE oynar
      // (RULES.md §1) — bu yüzden resolved* kullanılır, color/number değil.
      final c = t.resolvedColor(okeyTile)!.index;
      final n = t.resolvedNumber(okeyTile)!;
      _colorIndex[i] = c;
      _number[i] = n;
      (_byKey[_key(c, n)] ??= []).add(i);
    }
  }

  static int _key(int color, int number) => color * 16 + number;

  OkeyHandPartition run() {
    // 22 taş 22 bite sığar; web'deki 53 bitlik güvenli tamsayı sınırının
    // çok altında, dolayısıyla maske aritmetiği her platformda kesindir.
    final result = _solve(0);
    final melds = <List<OkeyTile>>[];
    var usedMask = 0;
    for (final c in result.melds) {
      melds.add([for (final i in c.indices) _tiles[i]]);
      usedMask |= c.mask;
    }
    final leftovers = <OkeyTile>[];
    for (var i = 0; i < _tiles.length; i++) {
      if ((usedMask >> i) & 1 == 0) leftovers.add(_tiles[i]);
    }
    return OkeyHandPartition(
      melds: melds,
      leftovers: leftovers,
      points: result.score,
      approximate: _aborted,
    );
  }

  _Result _solve(int mask) {
    final cached = _memo[mask];
    if (cached != null) return cached;

    if (_nodes++ > budget) {
      _aborted = true;
      return _Result.empty;
    }

    // Kullanılmamış EN KÜÇÜK normal taş. Jokerler atlanır: tek başına bir
    // joker grubu olmaz, gruplara ancak başka bir taşın yanında girer.
    var pivot = -1;
    for (var i = 0; i < _tiles.length; i++) {
      if ((mask >> i) & 1 == 1) continue;
      if (_isWild[i]) continue;
      pivot = i;
      break;
    }
    if (pivot < 0) return _Result.empty;

    // A) Pivot'u ARTIK bırak.
    var best = _solve(mask | (1 << pivot));

    // B) Pivot'u içeren her aday grubu dene.
    for (final cand in _candidates(mask, pivot)) {
      final sub = _solve(mask | cand.mask);
      final score = cand.points + sub.score;
      if (score > best.score) {
        best = _Result(score, [cand, ...sub.melds]);
      }
    }

    _memo[mask] = best;
    return best;
  }

  /// [pivot]'u içeren geçerli per/grup adayları.
  List<_Candidate> _candidates(int mask, int pivot) {
    final out = <_Candidate>[];
    final color = _colorIndex[pivot];
    final number = _number[pivot];
    final freeWilds = [
      for (final w in _wilds)
        if ((mask >> w) & 1 == 0) w,
    ];

    // ---- SERİ (aynı renk, ardışık) --------------------------------------
    //
    // Pivot elin kullanılmamış EN KÜÇÜĞÜ olduğu için seri normalde ondan
    // başlar. TEK İSTİSNA: serinin başına joker konabilir (7·8·9 elde varken
    // joker'i 6 yerine kullanmak seriyi 30 puana çıkarır). O yüzden
    // başlangıç, eldeki joker sayısı kadar aşağıya da denenir.
    for (var lead = 0; lead <= freeWilds.length; lead++) {
      final start = number - lead;
      if (start < 1) break;

      final used = <int>[];
      var wildCursor = 0;
      for (var k = 0; k < lead; k++) {
        used.add(freeWilds[wildCursor++]);
      }
      used.add(pivot);
      _emit(out, used);

      var next = number + 1;
      while (next <= 13) {
        final real = _firstFree(_byKey[_key(color, next)], mask, used);
        if (real != null) {
          used.add(real);
        } else if (wildCursor < freeWilds.length) {
          // Joker, GERÇEK taş yokken kullanılır. Gerçek taş varken joker
          // tercih etmek asla daha iyi olamaz: aynı puanı verir ama jokeri
          // başka bir grupta kullanma şansını yakar.
          used.add(freeWilds[wildCursor++]);
        } else {
          break;
        }
        _emit(out, used);
        next++;
      }
    }

    // ---- GRUP (aynı rakam, farklı renkler) ------------------------------
    final pool = <int>[];
    for (var c = 0; c < OkeyColor.values.length; c++) {
      if (c == color) continue;
      final idx = _firstFree(_byKey[_key(c, number)], mask, const []);
      if (idx != null) pool.add(idx);
    }
    pool.addAll(freeWilds);

    // Renk başına en fazla bir taş alındığı için "farklı renk" koşulu
    // kurulum gereği sağlanır; 3'lü ve 4'lü gruplar denenir.
    for (var size = 2; size <= 3; size++) {
      _combinations(pool, size, (combo) {
        _emit(out, [pivot, ...combo]);
      });
    }

    return out;
  }

  /// Adayı doğrular ve puanlar; geçersizse sessizce atılır.
  void _emit(List<_Candidate> out, List<int> indices) {
    if (indices.length < OkeyHandPartitioner._minMeldSize) return;
    final tiles = [for (final i in indices) _tiles[i]];
    if (!OkeyMeldValidator.isValidMeld(tiles, okeyTile)) return;
    var mask = 0;
    for (final i in indices) {
      mask |= 1 << i;
    }
    out.add(
      _Candidate(
        indices: List<int>.from(indices),
        mask: mask,
        points: OkeyMeldValidator.meldPoints(tiles, okeyTile),
      ),
    );
  }

  int? _firstFree(List<int>? candidates, int mask, List<int> taken) {
    if (candidates == null) return null;
    for (final i in candidates) {
      if ((mask >> i) & 1 == 1) continue;
      if (taken.contains(i)) continue;
      return i;
    }
    return null;
  }

  static void _combinations(
    List<int> pool,
    int size,
    void Function(List<int>) onCombo,
  ) {
    if (size > pool.length) return;
    final chosen = <int>[];
    void walk(int start) {
      if (chosen.length == size) {
        onCombo(List<int>.from(chosen));
        return;
      }
      for (var i = start; i < pool.length; i++) {
        chosen.add(pool[i]);
        walk(i + 1);
        chosen.removeLast();
      }
    }

    walk(0);
  }
}

/// Bir arama dalının sonucu: toplam puan ve onu veren gruplar.
class _Result {
  final int score;
  final List<_Candidate> melds;

  const _Result(this.score, this.melds);

  static const empty = _Result(0, []);
}

/// Tek bir aday grup.
class _Candidate {
  final List<int> indices;
  final int mask;
  final int points;

  const _Candidate({
    required this.indices,
    required this.mask,
    required this.points,
  });
}
