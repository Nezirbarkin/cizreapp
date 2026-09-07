import 'package:cizreapp/okey/engine/okey_board_layout.dart';
import 'package:flutter_test/flutter_test.dart';

/// MASA YERLEŞİM MOTORU — "her per masada görünür" garantisinin kendisi.
///
/// Widget testleri yerleşimi EKRANDA doğrular; burada aynı garanti SAF HESAP
/// olarak doğrulanır. İkisi birlikte olmalı: widget testi bir boyutta
/// bakabilir, motor testi onlarca senaryoyu milisaniyede tarar.
void main() {
  /// Bir yerleşimin gerçekten alana sığıp sığmadığını BAĞIMSIZ olarak ölçer.
  ///
  /// Motorun kendi `everythingFits` bayrağına GÜVENMEZ — onu doğrular:
  /// satır yükseklikleri ve per genişlikleri baştan yeniden hesaplanır.
  void expectFitsWithin(
    OkeyBoardFit fit,
    List<int> meldSizes,
    double width,
    double height,
  ) {
    final meldH =
        fit.tileHeight +
        OkeyBoardLayout.meldPadding * 2 +
        OkeyBoardLayout.meldBorderWidth;

    // EN UZUN SÜTUN alana sığmalı — yerleşimin yüksekliği odur.
    final totalH =
        fit.tallestColumn * meldH +
        (fit.tallestColumn - 1) * OkeyBoardLayout.rowGap;
    expect(
      totalH,
      lessThanOrEqualTo(height + 0.01),
      reason: 'sütun ${totalH.toStringAsFixed(1)}px, alan $height px',
    );

    // Sütun genişliklerinin TOPLAMI alana sığmalı.
    var totalW = 0.0;
    for (var c = 0; c < fit.columns.length; c++) {
      if (c > 0) totalW += OkeyBoardLayout.meldGap;
      var columnW = 0.0;
      for (final i in fit.columns[c].meldIndices) {
        final w =
            meldSizes[i] * fit.tileWidth + OkeyBoardLayout.meldPadding * 2;
        if (w > columnW) columnW = w;
      }
      totalW += columnW;
    }
    expect(
      totalW,
      lessThanOrEqualTo(width + 0.01),
      reason: 'yerleşim ${totalW.toStringAsFixed(1)}px, alan $width px',
    );

    // HİÇBİR PER KAYBOLMAZ: her indeks tam olarak bir kez yerleşmeli.
    final placed = <int>[];
    for (final column in fit.columns) {
      placed.addAll(column.meldIndices);
    }
    placed.sort();
    expect(
      placed,
      List.generate(meldSizes.length, (i) => i),
      reason: 'bazı perler yerleşimden düştü',
    );
  }

  group('OkeyBoardLayout — tüm perler alana sığar', () {
    // Gerçek masa alanları (keçenin orta bandı, yatay telefon/tablet).
    const areas = [
      (w: 300.0, h: 120.0), // çok kısa yatay telefon
      (w: 430.0, h: 160.0),
      (w: 620.0, h: 200.0),
      (w: 900.0, h: 320.0), // tablet
    ];

    // 101 Okey'de gerçekçi per dağılımları.
    const scenarios = <String, List<int>>{
      'tek per': [3],
      'iki oyuncu açtı': [3, 4, 3, 5],
      'üç oyuncu açtı': [3, 4, 3, 5, 3, 3, 4],
      'dört oyuncu + işlemeler': [3, 4, 5, 3, 6, 3, 4, 3, 5, 4, 3, 7],
      'çiftle açılış (5 çift + gösterge)': [2, 2, 2, 2, 2, 1],
      'aşırı yük — 18 per': [
        3,
        3,
        3,
        3,
        3,
        3,
        3,
        3,
        3,
        3,
        3,
        3,
        3,
        3,
        3,
        3,
        3,
        3,
      ],
    };

    for (final area in areas) {
      scenarios.forEach((name, sizes) {
        test('$name · ${area.w.toInt()}x${area.h.toInt()}', () {
          final fit = OkeyBoardLayout.fit(
            width: area.w,
            height: area.h,
            meldSizes: sizes,
            maxTileWidth: 34,
          );

          expect(
            fit.everythingFits,
            isTrue,
            reason:
                '$name bu alana sığmadı — taşlar yeterince küçültülmemiş '
                '(taş ${fit.tileWidth.toStringAsFixed(1)}px, '
                '${fit.columnCount} sütun)',
          );
          expectFitsWithin(fit, sizes, area.w, area.h);
        });
      });
    }
  });

  group('OkeyBoardLayout — ölçü kuralları', () {
    test('bol alanda taş ÜST SINIRDA kalır, büyümez', () {
      // Masadaki taş, elimdeki taştan büyük olmamalı: uzaktaki masa
      // yakındaki elden büyük görünürse derinlik hissi tersine döner.
      final fit = OkeyBoardLayout.fit(
        width: 1200,
        height: 600,
        meldSizes: const [3],
        maxTileWidth: 28,
      );
      expect(fit.tileWidth, 28);
    });

    test('per sayısı arttıkça taş küçülür', () {
      double tileFor(int meldCount) => OkeyBoardLayout.fit(
        width: 420,
        height: 150,
        meldSizes: List.filled(meldCount, 3),
        maxTileWidth: 34,
      ).tileWidth;

      final az = tileFor(2);
      final orta = tileFor(8);
      final cok = tileFor(16);

      expect(orta, lessThanOrEqualTo(az));
      expect(cok, lessThan(orta));
      expect(
        cok,
        greaterThanOrEqualTo(OkeyBoardLayout.minTileWidth),
        reason: 'taş okunamayacak kadar küçüldü',
      );
    });

    test('taş oranı her ölçekte korunur', () {
      for (final n in [1, 5, 12, 20]) {
        final fit = OkeyBoardLayout.fit(
          width: 400,
          height: 140,
          meldSizes: List.filled(n, 3),
          maxTileWidth: 34,
        );
        expect(
          fit.tileWidth / fit.tileHeight,
          closeTo(OkeyBoardLayout.defaultAspect, 0.001),
          reason: '$n perde taş oranı bozuldu',
        );
      }
    });

    test('boş masa hesap yapmadan döner', () {
      final fit = OkeyBoardLayout.fit(
        width: 400,
        height: 200,
        meldSizes: const [],
        maxTileWidth: 30,
      );
      expect(fit.columns, isEmpty);
      expect(fit.usedWidth, 0);
      expect(fit.everythingFits, isTrue);
    });

    test('sıfır/negatif alan çökmez', () {
      for (final a in const [(0.0, 100.0), (100.0, 0.0), (-5.0, -5.0)]) {
        final fit = OkeyBoardLayout.fit(
          width: a.$1,
          height: a.$2,
          meldSizes: const [3, 3],
          maxTileWidth: 30,
        );
        expect(fit.tileWidth, greaterThan(0));
      }
    });

    test('imkânsız dar alanda bile HİÇBİR per düşmez', () {
      // 14 uzun per, tek satırlık yüksekliğe: sığmayacağı için
      // everythingFits false olmalı AMA perlerin hepsi yerleşimde durmalı —
      // çağıran taraf bunu kaydırılabilir yapar, gizlemez.
      const sizes = [7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7];
      final fit = OkeyBoardLayout.fit(
        width: 120,
        height: 40,
        meldSizes: sizes,
        maxTileWidth: 30,
      );
      expect(fit.everythingFits, isFalse);

      final placed = <int>[];
      for (final column in fit.columns) {
        placed.addAll(column.meldIndices);
      }
      expect(placed.length, sizes.length, reason: 'per kayboldu');
    });

    test('perler ALT ALTA, sırayla yerleşir', () {
      final fit = OkeyBoardLayout.fit(
        width: 420,
        height: 300,
        meldSizes: const [3, 3, 3, 3, 3, 3],
        maxTileWidth: 30,
      );
      final placed = <int>[];
      for (final column in fit.columns) {
        placed.addAll(column.meldIndices);
      }
      expect(
        placed,
        List.generate(6, (i) => i),
        reason: 'perlerin sırası bozuldu — masada yerleri sürekli değişirdi',
      );
    });

    test('bol yükseklikte perlerin HEPSİ TEK SÜTUNDA, alt alta durur', () {
      // KULLANICI İSTEĞİ (2026-09-05): "açılan perler alt alta dizilsin."
      // Sığdığı sürece ikinci bir sütun AÇILMAZ.
      final fit = OkeyBoardLayout.fit(
        width: 900,
        height: 600,
        meldSizes: const [3, 4, 3, 5, 3],
        maxTileWidth: 30,
      );
      expect(fit.columnCount, 1);
      expect(fit.columns.first.meldIndices, [0, 1, 2, 3, 4]);
    });

    test('sütun dolunca SAĞDAN yeni sütun açılır', () {
      // Yükseklik iki pere yetiyor: altı per → üç sütun.
      final fit = OkeyBoardLayout.fit(
        width: 900,
        height: 92,
        meldSizes: List.filled(6, 3),
        maxTileWidth: 30,
      );
      expect(fit.columnCount, greaterThan(1));
      expect(fit.tallestColumn, lessThanOrEqualTo(3));

      // Sıra korunur: ilk sütun ilk perleri taşır.
      expect(fit.columns.first.meldIndices.first, 0);
    });
  });
}
