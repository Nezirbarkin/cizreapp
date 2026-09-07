import 'package:cizreapp/okey/engine/okey_hand_partition.dart';
import 'package:cizreapp/okey/engine/okey_meld_validator.dart';
import 'package:cizreapp/okey/engine/okey_rack_layout.dart';
import 'package:cizreapp/okey/engine/okey_tile.dart';
import 'package:flutter_test/flutter_test.dart';

/// SERİ DİZ — "EN YÜKSEK NASILSA ÖYLE DİZ"
///
/// Kullanıcı isteği (2026-09): dizim yalnızca aynı renk ardışık taşları
/// değil, aynı rakamın farklı renklerini de (3·3·3) görmeli ve HANGİSİ DAHA
/// ÇOK PUAN getiriyorsa onu seçmeli.
///
/// Buradaki testler o kararın kendisini ölçer: aynı taş kümesi için motorun
/// bulduğu ayrışımın puanı, elle kurulmuş makul alternatiflerden düşük
/// OLMAMALI.

OkeyTile t(OkeyColor c, int n) => OkeyTile.numbered(c, n);

/// Bu testlerde okey taşı Sarı 13'tür — hiçbir senaryoda kullanılmayan,
/// dolayısıyla yanlışlıkla joker yaratmayan bir taş.
final okeyTile = t(OkeyColor.yellow, 13);

int pointsOf(List<List<OkeyTile>> melds) =>
    melds.fold(0, (s, m) => s + OkeyMeldValidator.meldPoints(m, okeyTile));

void main() {
  group('OkeyHandPartitioner — en yüksek puanlı ayrışım', () {
    test('aynı rakamın farklı renkleri GRUP olarak bulunur (3·3·3)', () {
      final tiles = [
        t(OkeyColor.red, 3),
        t(OkeyColor.black, 3),
        t(OkeyColor.blue, 3),
      ];
      final p = OkeyHandPartitioner.best(tiles, okeyTile);

      expect(p.melds, hasLength(1));
      expect(p.melds.first, hasLength(3));
      expect(p.points, 9);
      expect(p.leftovers, isEmpty);
    });

    test('aynı renk ardışık taşlar SERİ olarak bulunur (1·2·3)', () {
      final tiles = [
        t(OkeyColor.blue, 1),
        t(OkeyColor.blue, 2),
        t(OkeyColor.blue, 3),
      ];
      final p = OkeyHandPartitioner.best(tiles, okeyTile);

      expect(p.melds, hasLength(1));
      expect(p.points, 6);
    });

    test('SERİ ile GRUP yarışınca daha ÇOK PUAN getiren seçilir', () {
      // Kırmızı 1·2·3 (6 puan) ile üç renkli 3 grubu (9 puan) aynı Kırmızı
      // 3 taşını istiyor. İkisi birden olamaz; motor 9 puanlı olanı almalı.
      final tiles = [
        t(OkeyColor.red, 1),
        t(OkeyColor.red, 2),
        t(OkeyColor.red, 3),
        t(OkeyColor.black, 3),
        t(OkeyColor.blue, 3),
      ];
      final p = OkeyHandPartitioner.best(tiles, okeyTile);

      expect(
        p.points,
        9,
        reason: '9 puanlık grup yerine 6 puanlık seri seçilmiş',
      );
      expect(p.leftovers, hasLength(2)); // kırmızı 1 ve 2 artar
    });

    test('iki per birden çıkarılır ve hiçbir taş iki kez kullanılmaz', () {
      final tiles = [
        t(OkeyColor.blue, 5),
        t(OkeyColor.blue, 6),
        t(OkeyColor.blue, 7),
        t(OkeyColor.red, 11),
        t(OkeyColor.black, 11),
        t(OkeyColor.blue, 11),
        t(OkeyColor.yellow, 2), // artık
      ];
      final p = OkeyHandPartitioner.best(tiles, okeyTile);

      expect(p.melds, hasLength(2));
      expect(p.points, 18 + 33);

      // Taş muhasebesi: perler + artıklar = elin TAMAMI, fazlası yok.
      final used = [for (final m in p.melds) ...m, ...p.leftovers];
      expect(used, hasLength(tiles.length));
      for (final tile in tiles) {
        expect(
          used.where((x) => x == tile).length,
          tiles.where((x) => x == tile).length,
          reason: '$tile sayısı değişmiş',
        );
      }
    });

    test('okey taşı seriyi UZATIR — ve hangi uçtan uzatacağını seçer', () {
      // Elde Siyah 7·8·9 ve bir okey var. Okey iki uca da konabilir:
      //   6·7·8·9 = 30   ya da   7·8·9·10 = 34
      // Motor puanı büyüten UCU seçmeli. (Bu test bir kez 30 bekleyerek
      // yazılmıştı; motorun 34 bulması hatası değil, tam olarak istenen
      // davranıştı — beklenti düzeltildi.)
      final tiles = [
        t(OkeyColor.black, 7),
        t(OkeyColor.black, 8),
        t(OkeyColor.black, 9),
        okeyTile, // joker
      ];
      final p = OkeyHandPartitioner.best(tiles, okeyTile);

      expect(p.melds, hasLength(1));
      expect(p.melds.first, hasLength(4));
      expect(p.points, 34, reason: 'okey seriyi en kârlı uçtan uzatmamış');
    });

    test('per çıkmayan elde hiçbir grup uydurulmaz', () {
      final tiles = [
        t(OkeyColor.red, 1),
        t(OkeyColor.blue, 5),
        t(OkeyColor.black, 9),
      ];
      final p = OkeyHandPartitioner.best(tiles, okeyTile);

      expect(p.melds, isEmpty);
      expect(p.points, 0);
      expect(p.leftovers, hasLength(3));
    });

    test('SAHTE OKEY normal bir taş gibi (okeyin kimliğiyle) oynar', () {
      // Okey Sarı 13 olduğuna göre sahte okey Sarı 13 sayılır ve
      // Sarı 11·12 ile bir seri tamamlar.
      final tiles = [
        t(OkeyColor.yellow, 11),
        t(OkeyColor.yellow, 12),
        const OkeyTile.falseJoker(),
      ];
      final p = OkeyHandPartitioner.best(tiles, okeyTile);

      expect(p.melds, hasLength(1));
      expect(p.points, 36); // 11 + 12 + 13
    });

    test('21 taşlık dolu bir el makul sürede ve tutarlı çözülür', () {
      final tiles = <OkeyTile>[
        for (final c in OkeyColor.values)
          for (var n = 1; n <= 5; n++) t(c, n),
        t(OkeyColor.red, 7),
      ];

      final sw = Stopwatch()..start();
      final p = OkeyHandPartitioner.best(tiles, okeyTile);
      sw.stop();

      // ANA İZLEKTE çalışıyor: SERİ DİZ'e basınca ekran donmamalı.
      expect(
        sw.elapsedMilliseconds,
        lessThan(1500),
        reason: 'ayrışım çok uzun sürdü (${sw.elapsedMilliseconds} ms)',
      );

      final used = [for (final m in p.melds) ...m, ...p.leftovers];
      expect(used, hasLength(tiles.length));
      for (final m in p.melds) {
        expect(OkeyMeldValidator.isValidMeld(m, okeyTile), isTrue);
      }
      // Dört renkte 1..5 varken en az birkaç grup/seri çıkmalı.
      expect(p.points, greaterThan(0));
    });
  });

  group('SERİ DİZ ıstakaya yansır', () {
    test(
      'gruplar ve seriler ıstakada BİTİŞİK, aralarında boşluk ile durur',
      () {
        final tiles = [
          t(OkeyColor.red, 3),
          t(OkeyColor.black, 3),
          t(OkeyColor.blue, 3),
          t(OkeyColor.blue, 7),
          t(OkeyColor.blue, 8),
          t(OkeyColor.blue, 9),
        ];
        final groups = OkeyRackLayout.groupBySeries(tiles, okeyTile);

        // İki per de bulunmuş olmalı (9 + 24 puan).
        expect(groups.where((g) => g.length == 3), hasLength(2));
        expect(pointsOf(groups.where((g) => g.length == 3).toList()), 9 + 24);

        final slots = OkeyRackLayout.buildSorted(
          tiles,
          okeyTile,
          byPairs: false,
        );
        expect(OkeyRackLayout.tilesOf(slots), hasLength(tiles.length));

        // Her grup ıstakada bitişik ve arasına başka taş sızmamış.
        for (final g in groups) {
          final idx = g.map(slots.indexOf).toList()..sort();
          final span = slots.sublist(idx.first, idx.last + 1);
          expect(span.where((s) => s != null && !g.contains(s)), isEmpty);
        }
      },
    );

    test('perlere girmeyen taşlar KAYBOLMAZ, arkaya dizilir', () {
      final tiles = [
        t(OkeyColor.blue, 1),
        t(OkeyColor.blue, 2),
        t(OkeyColor.blue, 3),
        t(OkeyColor.red, 6),
        t(OkeyColor.red, 7), // yarım seri — per değil ama görünmeli
      ];
      final slots = OkeyRackLayout.buildSorted(tiles, okeyTile, byPairs: false);
      expect(OkeyRackLayout.tilesOf(slots), hasLength(5));
      expect(slots.contains(t(OkeyColor.red, 6)), isTrue);
      expect(slots.contains(t(OkeyColor.red, 7)), isTrue);
    });
  });
}
