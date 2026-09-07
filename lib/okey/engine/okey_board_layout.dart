import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Bir perin masadaki yerleşimi: hangi SÜTUNDA, yukarıdan aşağıya kaçıncı.
@immutable
class OkeyBoardColumn {
  /// Bu sütundaki perlerin, verilen listedeki indeksleri — yukarıdan aşağıya.
  final List<int> meldIndices;

  const OkeyBoardColumn(this.meldIndices);
}

/// Masaya açılan perlerin HESAPLANMIŞ yerleşimi.
@immutable
class OkeyBoardFit {
  final double tileWidth;
  final double tileHeight;

  /// Perler SÜTUN SÜTUN: her sütun yukarıdan aşağıya dolar, sütun dolunca
  /// bir sonrakine geçilir (bkz. [OkeyBoardLayout] sınıf yorumu).
  final List<OkeyBoardColumn> columns;

  /// Yerleşimin gerçekten kapladığı genişlik.
  final double usedWidth;

  /// Her şey sığdı mı? false ise taşlar EN KÜÇÜK ölçüye indirildiği halde
  /// alan yetmemiştir (pratikte 20+ per gerekir) — çağıran taraf bunu bir
  /// kaydırma alanıyla telafi eder.
  final bool everythingFits;

  const OkeyBoardFit({
    required this.tileWidth,
    required this.tileHeight,
    required this.columns,
    required this.usedWidth,
    required this.everythingFits,
  });

  int get columnCount => columns.length;

  /// Bir sütunda en fazla kaç per var (yerleşimin yüksekliğini belirler).
  int get tallestColumn {
    var n = 0;
    for (final c in columns) {
      if (c.meldIndices.length > n) n = c.meldIndices.length;
    }
    return n;
  }
}

/// MASAYA AÇILAN PERLERİN YERLEŞİM MOTORU — saf hesap.
///
/// ## Çözdüğü sorun
///
/// Eski tahta, taş ölçüsünü DIŞARIDAN alıyor ve sığmayanı bir
/// `SingleChildScrollView`'a atıyordu. 101 Okey'de dört oyuncu 101'er puan
/// açtığında masada 12-16 per birikir; sonuç, oyuncunun masanın yarısını
/// göremediği ve KAYDIRMAK zorunda kaldığı bir tahtaydı. Gerçek bir okey
/// masasında böyle bir şey yoktur: açılan her per ORTADA, herkesin gözü
/// önündedir.
///
/// ## AKIŞ YÖNÜ: ALT ALTA (kullanıcı isteği, 2026-09-05)
///
/// Perler sol üst köşeden başlar ve AŞAĞI doğru dizilir; bir sütun masanın
/// yüksekliğini doldurunca bir sonraki sütun sağdan başlar:
///
/// ```
///   ┌──────────────────────────────┐
///   │ 1·2·3        7·7·7           │
///   │ 4·5·6·7      9·9·9·9         │
///   │ 11·12·13     2·2·2           │
///   └──────────────────────────────┘
/// ```
///
/// Neden satır satır DEĞİL: bir per masaya konduğunda satır akışı ondan
/// SONRAKİ her peri kaydırıyordu — oyuncunun "şurada duruyordu" diye
/// baktığı per her el birkaç kez yer değiştiriyordu. Sütunlar aşağı
/// büyüdüğü için yeni per hep sıranın SONUNA eklenir, önündekiler durur.
/// Ayrıca perler doğal olarak sola hizalanmış bir liste gibi okunur.
///
/// ## Yaklaşım: taş ölçüsünü ALANA GÖRE ÇÖZ
///
/// Taş ölçüsü artık bir GİRDİ değil, bir ÇIKTIDIR. Motor, verilen alana tüm
/// perlerin sığdığı EN BÜYÜK taş ölçüsünü ikili arama ile bulur:
///
///   * ölçü büyüdükçe perler yükselir → bir sütuna daha az per sığar →
///     sütun sayısı artar; aynı anda perler genişler → toplam genişlik artar
///   * yani "sığar mı?" sorusu ölçüye göre MONOTONDUR ve ikili arama geçerlidir
///
/// 22 yineleme, piksel altı bir kesinlik verir ve per sayısı küçük olduğu
/// için (≤ ~20) maliyeti ihmal edilebilir.
///
/// ## Neden saf bir sınıf
///
/// Ne Flutter ne Supabase bilir: doğrudan test edilir. Yerleşim mantığı
/// widget'ın içinde kalsaydı, "16 per sığıyor mu" sorusunu ancak ekran
/// görüntüsüne bakarak yanıtlayabilirdik.
abstract final class OkeyBoardLayout {
  /// Taşın genişlik/yükseklik oranı — masadaki ve ıstakadaki taşla aynı.
  static const double defaultAspect = 0.74;

  /// Perin kendi oturma zemininin iç payı (her yönde).
  ///
  /// 2026-09-05'te 3 → 1'e indi (kullanıcı: "tablodaki alt alta sıralı
  /// taşların arasındaki boşluğu kapat"). Sıfır DEĞİL: zemin çukuru bir
  /// piksel de olsa görünmezse yan yana iki per tek bir taş dizisi gibi
  /// okunuyordu.
  static const double meldPadding = 1;

  /// İki per SÜTUNU arasındaki yatay boşluk.
  static const double meldGap = 5;

  /// Alt alta duran iki per arasındaki dikey boşluk.
  ///
  /// 5 → 1: bu boşluk masanın en göze batan boşluğuydu ve her perde
  /// tekrarlandığı için sekiz perlik bir masada tek başına ~35px yiyordu —
  /// o piksellerle taşlar büyüyebilirdi.
  static const double rowGap = 1;

  /// Perin oturma zemininin ALT kenar çizgisi.
  ///
  /// Bir pikselmiş gibi görünür ama hesaba KATILMAK ZORUNDADIR: satır
  /// yüksekliğine eklenmezse motor her satırı 1px eksik sanar ve altı satırlı
  /// bir masada 6px'lik bir hata birikir — tam da "sığdı sanıp taşırma"
  /// senaryosu. (Bu, testte 1.0'lık sapma olarak yakalandı.)
  static const double meldBorderWidth = 1;

  /// Okunabilirliğin dibi: bundan küçük bir taşta rakam seçilemez.
  static const double minTileWidth = 9;

  /// SON SONUÇLARIN ÖNBELLEĞİ — aynı soru, aynı cevap.
  ///
  /// [fit] 22 yinelemelik bir ikili arama koşturur ve bir `LayoutBuilder`'ın
  /// içinden çağrılır: masa her yeniden çizildiğinde (bir rakip taş attığında,
  /// bir sayaç güncellendiğinde, sürükleme sırasında her karede) girdiler
  /// BİREBİR AYNI olduğu halde arama baştan çalışıyordu. Masada iki tahta var
  /// (seri/grup ve çiftler) ve ikisi de aynı karede ölçülüyor; dört girişlik
  /// bir halka ikisini de, ekran döndüğünde bile, rahatça taşır.
  ///
  /// Sonuç nesnesi değişmezdir (`@immutable`), dolayısıyla paylaşılması
  /// güvenlidir.
  static const int _cacheSize = 4;
  static final List<int> _cacheKeys = <int>[];
  static final Map<int, OkeyBoardFit> _cache = <int, OkeyBoardFit>{};

  /// Test/hata ayıklama için önbelleği boşaltır.
  @visibleForTesting
  static void clearCache() {
    _cacheKeys.clear();
    _cache.clear();
  }

  /// Verilen alana TÜM perleri sığdıran en büyük taş ölçüsünü bulur.
  ///
  /// [maxTileWidth] üst sınırdır: masadaki taş, oyuncunun ıstakasındaki
  /// taştan büyük olmamalı (aksi halde uzaktaki masa yakındaki elden büyük
  /// görünür, derinlik hissi tersine döner).
  static OkeyBoardFit fit({
    required double width,
    required double height,
    required List<int> meldSizes,
    required double maxTileWidth,
    double aspect = defaultAspect,
  }) {
    final key = Object.hash(
      width,
      height,
      Object.hashAll(meldSizes),
      maxTileWidth,
      aspect,
    );
    final cached = _cache[key];
    if (cached != null) return cached;

    final result = _fit(
      width: width,
      height: height,
      meldSizes: meldSizes,
      maxTileWidth: maxTileWidth,
      aspect: aspect,
    );

    _cache[key] = result;
    _cacheKeys.add(key);
    if (_cacheKeys.length > _cacheSize) {
      _cache.remove(_cacheKeys.removeAt(0));
    }
    return result;
  }

  static OkeyBoardFit _fit({
    required double width,
    required double height,
    required List<int> meldSizes,
    required double maxTileWidth,
    double aspect = defaultAspect,
  }) {
    if (meldSizes.isEmpty || width <= 0 || height <= 0) {
      return OkeyBoardFit(
        tileWidth: maxTileWidth,
        tileHeight: maxTileWidth / aspect,
        columns: const [],
        usedWidth: 0,
        everythingFits: true,
      );
    }

    final maxW = math.max(maxTileWidth, minTileWidth);

    // En büyük ölçü zaten sığıyorsa arama yapma.
    final atMax = _plan(maxW, width, height, meldSizes, aspect);
    if (atMax.fits) return atMax.toFit(true);

    var lo = minTileWidth;
    var hi = maxW;
    _Plan? best;

    for (var i = 0; i < 22; i++) {
      final mid = (lo + hi) / 2;
      final plan = _plan(mid, width, height, meldSizes, aspect);
      if (plan.fits) {
        best = plan;
        lo = mid; // daha büyüğü denenebilir
      } else {
        hi = mid;
      }
    }

    if (best != null) return best.toFit(true);

    // En küçük ölçüde bile sığmıyor — yine de EN İYİ yerleşimi döndür.
    // Çağıran taraf bunu kaydırılabilir yapar; hiçbir per gizlenmez.
    return _plan(minTileWidth, width, height, meldSizes, aspect).toFit(false);
  }

  /// Belirli bir taş ölçüsü için ALT ALTA akış planı.
  ///
  /// Perler sırayla bir sütuna yığılır; sütun masanın yüksekliğini
  /// dolduramayacak hale gelince yeni bir sütun açılır. Sütun genişliği,
  /// içindeki EN GENİŞ perin genişliğidir (perler sütunda sola yaslanır).
  static _Plan _plan(
    double tileW,
    double areaW,
    double areaH,
    List<int> meldSizes,
    double aspect,
  ) {
    final tileH = tileW / aspect;
    final meldH = tileH + meldPadding * 2 + meldBorderWidth;

    // Bir sütuna kaç per sığar? İlk perden sonra her biri ayrıca rowGap yer.
    var perColumn = 0;
    if (meldH <= areaH) {
      perColumn = 1 + ((areaH - meldH) / (meldH + rowGap)).floor();
    }
    // Tek bir per bile sığmıyorsa ölçü geçersizdir; yine de yerleşimi
    // ÜRETMEK zorundayız (hiçbir per düşmemeli), o yüzden sütun başına en az
    // bir per varsayılır ve plan "sığmadı" olarak işaretlenir.
    final heightOk = perColumn >= 1;
    final capacity = heightOk ? perColumn : 1;

    final columns = <OkeyBoardColumn>[];
    var current = <int>[];
    var widthOk = true;
    var totalW = 0.0;
    var columnW = 0.0;

    void closeColumn() {
      if (current.isEmpty) return;
      columns.add(OkeyBoardColumn(current));
      totalW += (columns.length > 1 ? meldGap : 0) + columnW;
      current = <int>[];
      columnW = 0;
    }

    for (var i = 0; i < meldSizes.length; i++) {
      final meldW = meldSizes[i] * tileW + meldPadding * 2;
      // Tek başına alana sığmayan bir per varsa bu ölçü GEÇERSİZDİR:
      // o per kırpılırdı, oysa hiçbir per kırpılmamalı.
      if (meldW > areaW) widthOk = false;

      if (current.length >= capacity) closeColumn();
      current.add(i);
      if (meldW > columnW) columnW = meldW;
    }
    closeColumn();

    return _Plan(
      tileWidth: tileW,
      tileHeight: tileH,
      columns: columns,
      usedWidth: totalW,
      fits: widthOk && heightOk && totalW <= areaW,
    );
  }
}

class _Plan {
  final double tileWidth;
  final double tileHeight;
  final List<OkeyBoardColumn> columns;
  final double usedWidth;
  final bool fits;

  const _Plan({
    required this.tileWidth,
    required this.tileHeight,
    required this.columns,
    required this.usedWidth,
    required this.fits,
  });

  OkeyBoardFit toFit(bool everythingFits) => OkeyBoardFit(
    tileWidth: tileWidth,
    tileHeight: tileHeight,
    columns: columns,
    usedWidth: usedWidth,
    everythingFits: everythingFits,
  );
}
