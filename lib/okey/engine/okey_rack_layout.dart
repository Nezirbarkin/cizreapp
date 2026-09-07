import 'okey_hand_partition.dart';
import 'okey_meld_validator.dart';
import 'okey_tile.dart';

/// Istakanın (rafın) görsel yerleşimi: sabit sayıda "slot"tan oluşur.
/// Bir slot ya bir taş tutar ya da boştur (null) — boş slotlar gruplar
/// arasındaki ayırıcı boşluklardır (ör. `1 2 3 4 _ 11 11 11`).
class OkeyRackLayout {
  /// Her satırdaki slot sayısı (2 satır → 32 slot; 22 taş + boşluklar sığar).
  static const int slotsPerRow = 16;
  static const int rowCount = 2;
  static const int totalSlots = slotsPerRow * rowCount;

  /// SERİ DİZ: eli EN YÜKSEK PUANI veren biçimde gruplar.
  ///
  /// ## Ne değişti ve NEDEN
  ///
  /// Eskiden yalnızca "aynı renk ardışık taşlar" bir grup sayılıyordu. Yani
  /// elinde `Kırmızı 3 · Siyah 3 · Mavi 3` varken bunlar ÜÇ AYRI tekil taş
  /// olarak diziliyordu — oysa bu, masaya konabilecek 9 puanlık hazır bir
  /// GRUPTUR. 101 Okey'de per iki biçimde olur ve ikisi de puan getirir:
  ///
  ///   * **seri** — aynı renk, ardışık (`1·2·3`)
  ///   * **grup** — aynı rakam, farklı renkler (`3·3·3`)
  ///
  /// Bir taş yalnızca birine girebildiği için hangi taşın nereye gideceği
  /// bir tercih değil, bir optimizasyon problemidir. Onu
  /// [OkeyHandPartitioner] çözer: elden en yüksek puanlı per/grup kümesini
  /// çıkarır.
  ///
  /// Geriye kalan taşlar ATILMAZ: eski "aynı renk ardışık" mantığıyla
  /// gruplanıp perlerin ARDINA dizilir. Böylece oyuncu `5·6·_·8` gibi
  /// yarım kalmış serileri de gözüyle görmeye devam eder — yalnızca tam
  /// perler öne alınmış olur.
  static List<List<OkeyTile>> groupBySeries(
    List<OkeyTile> tiles,
    OkeyTile okeyTile,
  ) {
    final partition = OkeyHandPartitioner.best(tiles, okeyTile);

    // Perler önce SERİLER sonra GRUPLAR olarak okunur; seriler kendi
    // içinde renge, gruplar rakama göre sıralanır. Puana göre sıralamak
    // matematiksel olarak "daha doğru" olurdu ama masada renkleri rastgele
    // sıçrayan bir ıstaka bırakırdı.
    final melds = List<List<OkeyTile>>.from(partition.melds)
      ..sort((a, b) {
        final ar = OkeyMeldValidator.findRunStart(a, okeyTile);
        final br = OkeyMeldValidator.findRunStart(b, okeyTile);
        if ((ar != null) != (br != null)) return ar != null ? -1 : 1;
        return _sortKey(a, okeyTile).compareTo(_sortKey(b, okeyTile));
      });

    return [...melds, ..._legacyGroupBySeries(partition.leftovers, okeyTile)];
  }

  /// Bir perin sıralama anahtarı: seriler renge, gruplar rakama göre.
  static int _sortKey(List<OkeyTile> meld, OkeyTile okeyTile) {
    for (final t in meld) {
      if (t.isJokerFor(okeyTile)) continue;
      final c = t.resolvedColor(okeyTile)!.index;
      final n = t.resolvedNumber(okeyTile)!;
      return c * 16 + n;
    }
    return 999;
  }

  /// Taşları "aynı renk ardışık" mantığıyla gruplar — perlere girmeyen
  /// ARTIK taşlar için. (2026-09'a kadar SERİ DİZ'in tamamı buydu.)
  static List<List<OkeyTile>> _legacyGroupBySeries(
    List<OkeyTile> tiles,
    OkeyTile okeyTile,
  ) {
    // SAHTE OKEY (isFalseJoker) burada da AYRILMALI: isJokerFor() onu
    // KASITLI OLARAK joker saymaz (bkz. o metottaki not — sahte okey normal
    // bir taş gibi oynar), ama color/number'ı null'dur. Ayrılmazsa aşağıdaki
    // sort() içinde `a.color!` çöker ("Null check operator used on a null
    // value") — bu tam olarak SERİ DİZ tıklanınca elde sahte okey varken
    // oluşan çökme.
    final jokers = tiles
        .where((t) => t.isJokerFor(okeyTile) || t.isFalseJoker)
        .toList();
    final normal =
        tiles.where((t) => !t.isJokerFor(okeyTile) && !t.isFalseJoker).toList()
          ..sort((a, b) {
            final c = a.color!.index.compareTo(b.color!.index);
            if (c != 0) return c;
            return a.number!.compareTo(b.number!);
          });

    final groups = <List<OkeyTile>>[];
    List<OkeyTile> current = [];
    for (final tile in normal) {
      if (current.isEmpty) {
        current = [tile];
        continue;
      }
      final prev = current.last;
      final sameColor = prev.color == tile.color;
      final consecutive = tile.number == prev.number! + 1;
      final duplicate = tile.number == prev.number;
      if (sameColor && (consecutive || duplicate)) {
        // Aynı taşın ikinci kopyası seriyi bölmemeli; ayrı grup olarak başlat
        if (duplicate) {
          groups.add(current);
          current = [tile];
        } else {
          current.add(tile);
        }
      } else {
        groups.add(current);
        current = [tile];
      }
    }
    if (current.isNotEmpty) groups.add(current);
    if (jokers.isNotEmpty) groups.add(jokers);
    return groups;
  }

  /// Taşları "çift" mantığıyla gruplar: aynı renk+rakam ikilileri bir grup,
  /// eşi olmayanlar tek başına.
  ///
  /// ## Bir grup ÇİFT SAYILMAK İÇİN tek başına durmalı
  ///
  /// Perlerin otomatik sayımı [contiguousGroups] üzerine kurulu: bir öbek
  /// ancak iki yanında boşluk (ya da satır sınırı) varsa "bir per/çift"
  /// sayılır. Dolayısıyla burada AYRI bir grup olarak dönmeyen hiçbir şey
  /// masada çift olarak sayılamaz — bu yüzden aşağıdaki üç ayrım
  /// kozmetik değil, oynanabilirliğin ta kendisidir.
  ///
  /// ### 1) GÖSTERGE ÇİFTİ tek başına bir gruptur (RULES.md §8)
  ///
  /// Göstergenin bir kopyası ortada açık durduğu için oyunda tek kopyası
  /// kalır; gerçek çiftini yapmak imkânsızdır ve kural o TEK taşı başlı
  /// başına bir çift sayar. [indicatorTile] verilmezse bu ayrım yapılamaz
  /// ve taş "eşi olmayanlar" yığınına gömülür — 4 gerçek çifti olan bir
  /// oyuncu göstergeyle 5. çifti ASLA göremezdi. ÇİFT DİZ'in gerçek
  /// hâliyle çiftle açmayı imkânsız kıldığı hata tam olarak buydu.
  ///
  /// ### 2) JOKERLER İKİŞER İKİŞER ayrılır
  ///
  /// Okey taşının iki kopyası geçerli bir çifttir; sahte okeyler de öyle
  /// (ikisi de okey taşının kimliğine çözülür, bkz.
  /// [OkeyMeldValidator.isValidPair]). Hepsi TEK bir yığın olarak
  /// döndüğünde elinde üç ya da dört joker olan oyuncu hiçbirini çift
  /// olarak sayamıyordu: üç taşlık bir öbek çift değildir.
  ///
  /// ### 3) EŞSİZ taşlar tek yığında kalır
  ///
  /// Onlar zaten çift değil; ayrı ayrı dizmek 22 taşlık eli 32 slota
  /// sığdıramaz ve ıstakayı okunmaz hale getirirdi.
  static List<List<OkeyTile>> groupByPairs(
    List<OkeyTile> tiles,
    OkeyTile okeyTile, {
    OkeyTile? indicatorTile,
  }) {
    // Bkz. groupBySeries'teki aynı notla: sahte okey (isFalseJoker) burada da
    // "normal" (color/number ile sıralanan) kümeden AYRI tutulmalı, yoksa
    // aşağıdaki sort() `a.number!`/`a.color!` ile çöker (ÇİFT DİZ tıklanınca).
    final jokers = tiles
        .where((t) => t.isJokerFor(okeyTile) || t.isFalseJoker)
        .toList();
    final normal =
        tiles.where((t) => !t.isJokerFor(okeyTile) && !t.isFalseJoker).toList()
          ..sort((a, b) {
            final n = a.number!.compareTo(b.number!);
            if (n != 0) return n;
            return a.color!.index.compareTo(b.color!.index);
          });

    final groups = <List<OkeyTile>>[];
    final singles = <OkeyTile>[];
    var i = 0;
    while (i < normal.length) {
      if (i + 1 < normal.length && normal[i] == normal[i + 1]) {
        groups.add([normal[i], normal[i + 1]]);
        i += 2;
      } else {
        singles.add(normal[i]);
        i += 1;
      }
    }

    // JOKERLER: ikişerli çiftler + (tek kalırsa) artan bir taş.
    for (var j = 0; j + 1 < jokers.length; j += 2) {
      groups.add([jokers[j], jokers[j + 1]]);
    }
    if (jokers.length.isOdd) singles.add(jokers.last);

    // GÖSTERGE ÇİFTİ: eşsizler arasından çekilip KENDİ grubuna alınır.
    //
    // Elde birden fazla kopya kalmışsa (kuralda olmaması gereken ama
    // savunma amaçlı düşünülen durum) zaten yukarıda normal bir çift
    // olarak eşleşmiştir; buraya yalnızca TEK kopya düşer.
    if (indicatorTile != null) {
      final at = singles.indexOf(indicatorTile);
      if (at >= 0) groups.add([singles.removeAt(at)]);
    }

    if (singles.isNotEmpty) groups.add(singles);
    return groups;
  }

  /// Grupları slotlara yerleştirir: her grubun ardına, YER VARSA, bir boş
  /// slot (ayırıcı) konur. Bir grup satırın kalanına sığmıyorsa (ve tek
  /// başına bir satıra sığacak kadar küçükse) grup bir sonraki satıra taşınır
  /// — grup ikiye bölünmez.
  ///
  /// DÜZELTME (regresyon: "SERİ DİZ'e basınca perler şaçmalıyor"): eski
  /// sürüm her grup arasına KOŞULSUZ bir boşluk ekliyordu, sonra toplam
  /// (taş + boşluk) 32 slotu AŞARSA taşan taşları `slots.indexOf(null)` ile
  /// "ilk boş slota" atıyordu. İlk boş slot genelde ÖNCEKİ, zaten yerleşmiş
  /// bir grubun kendi ayırıcı boşluğuydu — yani taşan taş o grubun TAM
  /// ORTASINA/YANINA sızıyor, iki alakasız grup birbirine karışmış gibi
  /// görünüyordu. Elde çok sayıda küçük/tekil grup olması (ör. henüz per
  /// toplayamamış bir el) NADİR değil, sık karşılaşılan bir durumdu.
  ///
  /// Artık ayırıcı boşluk yalnızca SONRAKİ tüm gruplar için hâlâ yeterli yer
  /// kalıyorsa eklenir; aksi halde ATLANIR (gruplar bitişik kalır) ama HİÇBİR
  /// taş başka bir grubun içine sızmaz. Taşlar yine ASLA kaybolmaz (22 taş
  /// her zaman 32 slota sığar) — güvenlik ağı olarak `index` sınırı aşarsa
  /// son slota sıkıştırılır (pratikte hiç tetiklenmez).
  static List<OkeyTile?> layoutGroups(List<List<OkeyTile>> groups) {
    final slots = List<OkeyTile?>.filled(totalSlots, null);
    var index = 0;

    // tilesAfter[g] = groups[g], groups[g+1], ... içindeki TOPLAM taş sayısı.
    // Bir ayırıcı eklemenin güvenli olup olmadığını (kalan taşlar için hâlâ
    // yer var mı) önceden bilmek için kullanılır.
    final tilesAfter = List<int>.filled(groups.length + 1, 0);
    for (var g = groups.length - 1; g >= 0; g--) {
      tilesAfter[g] = tilesAfter[g + 1] + groups[g].length;
    }

    for (var g = 0; g < groups.length; g++) {
      final group = groups[g];
      if (group.isEmpty) continue;

      final rowStart = (index ~/ slotsPerRow) * slotsPerRow;
      final usedInRow = index - rowStart;
      final freeInRow = slotsPerRow - usedInRow;
      final nextRowStart = rowStart + slotsPerRow;

      // Grup bu satıra sığmıyorsa VE bir sonraki satıra tamamen sığacaksa
      // oraya geç. Sığmayacaksa (satır kalmadıysa) burada kalıp taşar —
      // aşağıdaki güvenlik ağı yine de her taşı bir slota yerleştirir.
      if (group.length > freeInRow &&
          group.length <= slotsPerRow &&
          nextRowStart + group.length <= totalSlots) {
        index = nextRowStart;
      }

      for (final tile in group) {
        final at = index < totalSlots ? index++ : totalSlots - 1;
        slots[at] = tile;
      }

      // AYIRICI BOŞLUK: yalnızca kalan TÜM gruplar için hâlâ kesinlikle
      // yeterli yer varsa eklenir — böylece bir sonraki grubun taşları asla
      // bu boşluğa (ya da başka bir grubun boşluğuna) sızamaz.
      if (index < totalSlots && (totalSlots - index) > tilesAfter[g + 1]) {
        index++;
      }
    }

    return slots;
  }

  /// Sunucudan gelen yeni el ile mevcut yerleşimi birleştirir:
  /// - Elde olmayan taşlar slotlardan kaldırılır
  /// - Elde olup yerleşimde bulunmayan (yeni çekilen) taşlar ilk boş slota konur
  /// Böylece oyuncunun elle yaptığı dizilim korunur.
  /// [preferredSlot] verilirse, yerleşimde olmayan İLK yeni taş oraya konur.
  ///
  /// NEDEN: Desteden çekilen taş "ilk boş slota" yerleştiriliyordu; oyuncu
  /// taşı ıstakada istediği yere bıraksa bile taş bambaşka bir yere
  /// gidiyordu. Artık bırakılan slot tercih edilir.
  static List<OkeyTile?> mergeWithHand(
    List<OkeyTile?> currentSlots,
    List<OkeyTile> hand, {
    int? preferredSlot,
  }) {
    final slots = List<OkeyTile?>.from(currentSlots);
    if (slots.length != totalSlots) {
      slots
        ..clear()
        ..addAll(List<OkeyTile?>.filled(totalSlots, null));
    }

    // Kalan el taşlarının çoklu-kümesi
    final remaining = <OkeyTile, int>{};
    for (final t in hand) {
      remaining[t] = (remaining[t] ?? 0) + 1;
    }

    // Elde olmayan taşları temizle
    for (var i = 0; i < slots.length; i++) {
      final t = slots[i];
      if (t == null) continue;
      final left = remaining[t] ?? 0;
      if (left == 0) {
        slots[i] = null;
      } else {
        remaining[t] = left - 1;
      }
    }

    // Yerleşimde olmayan yeni taşlar
    final pref = preferredSlot;
    var usePreferred = pref != null && pref >= 0 && pref < slots.length;

    for (final entry in remaining.entries) {
      for (var n = 0; n < entry.value; n++) {
        // İLK yeni taş, oyuncunun bıraktığı slota konur (boşsa)
        if (usePreferred && pref != null && slots[pref] == null) {
          slots[pref] = entry.key;
          usePreferred = false;
          continue;
        }
        final free = slots.indexOf(null);
        if (free == -1) break;
        slots[free] = entry.key;
      }
    }
    return slots;
  }

  /// Slotlardaki taşları düz liste olarak döndürür (boşluklar atılır).
  static List<OkeyTile> tilesOf(List<OkeyTile?> slots) =>
      slots.whereType<OkeyTile>().toList();

  /// Bir slottaki taşı başka bir slota taşır.
  ///
  /// ## Davranış: YER DEĞİŞTİRME değil, ARAYA SOKMA
  ///
  /// Eskiden hedef doluysa iki taş YER DEĞİŞTİRİYORDU. Oyuncunun niyeti
  /// neredeyse hiç bu değildir: `1·2·3·5` dizisinde 4'ü 5'in soluna
  /// bırakmak isteyen oyuncu, 5'in kalkıp elin öbür ucuna gitmesini
  /// beklemez — 5'in bir yana KAYMASINI bekler. Yer değiştirme, dizmeye
  /// çalıştığın perin iki taşını birbirinden koparıyordu.
  ///
  /// Artık taş hedefe SOKULUR ve arada kalanlar bir slot kayar:
  ///
  /// ```
  ///   önce:  1 2 3 5 _ 9      (4'ü 5'in yerine bırak)
  ///   sonra: 1 2 3 4 5 9      ← 5 sağa kaydı, boşluk kapandı
  /// ```
  ///
  /// Kayma yönü, hedefe EN YAKIN boşluğa doğrudur; böylece dizilimin geri
  /// kalanı olabildiğince az bozulur. Taş kaldırıldığı an kendi slotu
  /// boşaldığı için en az bir boşluk HER ZAMAN vardır — yani bu işlem
  /// hiçbir koşulda taş kaybetmez.
  ///
  /// Hedef BOŞSA taş oraya olduğu gibi konur: oyuncu taşı ıstakanın
  /// ortasındaki boşluğa bıraktığında orada DURUR, bir kenara toplanmaz.
  static List<OkeyTile?> moveTile(List<OkeyTile?> slots, int from, int to) {
    if (from == to || from < 0 || to < 0) return slots;
    if (from >= slots.length || to >= slots.length) return slots;

    final tile = slots[from];
    if (tile == null) return slots;

    final next = List<OkeyTile?>.from(slots);
    next[from] = null;

    // Hedef boşsa iş bitti — taş bırakıldığı yerde durur.
    if (next[to] == null) {
      next[to] = tile;
      return next;
    }

    // Hedefe EN YAKIN boşluk hangi yönde? (from her zaman bir aday, çünkü
    // az önce boşaldı — dolayısıyla arama daima bir sonuç bulur.)
    var gap = -1;
    for (var d = 1; d < next.length; d++) {
      if (to - d >= 0 && next[to - d] == null) {
        gap = to - d;
        break;
      }
      if (to + d < next.length && next[to + d] == null) {
        gap = to + d;
        break;
      }
    }
    if (gap < 0) {
      // Ulaşılamaz: en az bir boşluk (from) var. Yine de sessizce yer
      // değiştirmeye düş — taş asla kaybolmasın.
      next[from] = next[to];
      next[to] = tile;
      return next;
    }

    // Aradaki taşları boşluğa doğru bir slot kaydır.
    if (gap > to) {
      for (var i = gap; i > to; i--) {
        next[i] = next[i - 1];
      }
    } else {
      for (var i = gap; i < to; i++) {
        next[i] = next[i + 1];
      }
    }
    next[to] = tile;
    return next;
  }

  /// Seçili sıralama moduna göre yerleşimi baştan kurar.
  /// [indicatorTile] yalnızca ÇİFT DİZ'de anlamlıdır: gösterge çiftinin
  /// (RULES.md §8) kendi grubuna ayrılabilmesi için gerekir. Verilmezse o
  /// taş eşsizler yığınında kalır ve çift olarak sayılamaz.
  static List<OkeyTile?> buildSorted(
    List<OkeyTile> tiles,
    OkeyTile okeyTile, {
    required bool byPairs,
    OkeyTile? indicatorTile,
  }) {
    final groups = byPairs
        ? groupByPairs(tiles, okeyTile, indicatorTile: indicatorTile)
        : groupBySeries(tiles, okeyTile);
    return layoutGroups(groups);
  }

  /// Istakada BOŞLUKLA ayrılmış bitişik taş öbeklerini döndürür.
  /// Her öbek `(slotIndeksleri, taşlar)` çiftidir. Satır sonu da öbeği böler.
  ///
  /// Perlerin OTOMATİK sayılması bunun üzerine kuruludur: oyuncunun ıstakada
  /// yan yana dizdiği taşlar zaten bir grup adayıdır; ayrıca "grup yap"
  /// demesine gerek yoktur.
  static List<({List<int> slots, List<OkeyTile> tiles})> contiguousGroups(
    List<OkeyTile?> slots,
  ) {
    final groups = <({List<int> slots, List<OkeyTile> tiles})>[];
    var currentSlots = <int>[];
    var currentTiles = <OkeyTile>[];

    void flush() {
      if (currentTiles.isNotEmpty) {
        groups.add((slots: currentSlots, tiles: currentTiles));
      }
      currentSlots = <int>[];
      currentTiles = <OkeyTile>[];
    }

    for (var i = 0; i < slots.length; i++) {
      // Satır başında öbeği kes (satırlar görsel olarak ayrıdır)
      if (i % slotsPerRow == 0) flush();
      final tile = slots[i];
      if (tile == null) {
        flush();
      } else {
        currentSlots.add(i);
        currentTiles.add(tile);
      }
    }
    flush();
    return groups;
  }

  /// Bir perin/grubun SON slotu olan indeksler — YALNIZCA hemen ardından
  /// başka bir taş geliyorsa.
  ///
  /// Istakada iki öbek bitişik durabilir (dizme motoru yer kalmadığında
  /// ayırıcı boşluğu atlar). O zaman perlerin nerede bitip nerede başladığı
  /// ancak SON TAŞIN sağında açılan küçük bir payla görülür — ve o pay taşın
  /// GENİŞLİĞİNDEN kısılır (bkz. OkeyRackBarWidget'taki `groupGap`).
  ///
  /// ## Neden "yalnızca ardından taş varsa" (kullanıcı: "takozda taş
  /// dizilirken sondaki taş boyut olarak zayıf oluyor", 2026-09-05)
  ///
  /// Öbek satırın sonunda bitiyorsa ya da ardında zaten BOŞ bir slot varsa
  /// ayrılacak bir komşu yoktur: kısma hiçbir işe yaramaz, sadece o taşı
  /// diğerlerinden ~5px dar — gözle "cılız" — bırakır. Istakadaki en son taş
  /// neredeyse HER ZAMAN bu duruma düşüyordu, çünkü [layoutGroups] son
  /// öbeğin ardına da bir ayırıcı boşluk koyuyor.
  static Set<int> groupEndSlots(List<OkeyTile?> slots) {
    final result = <int>{};
    for (final g in contiguousGroups(slots)) {
      if (g.slots.length < 2) continue; // tek taş "per" sayılmaz
      final last = g.slots.last;
      final next = last + 1;
      if (next % slotsPerRow == 0) continue; // satır sonu: komşu yok
      if (next >= slots.length || slots[next] == null) continue; // boşluk var
      result.add(last);
    }
    return result;
  }

  /// Bir grubun geçerli bir per/grup/çift olup olmadığı (görsel vurgulama için).
  static bool isCompleteMeld(List<OkeyTile> group, OkeyTile okeyTile) {
    if (group.length == 2) {
      return OkeyMeldValidator.isValidPair(group, okeyTile);
    }
    return OkeyMeldValidator.isValidMeld(group, okeyTile);
  }
}
