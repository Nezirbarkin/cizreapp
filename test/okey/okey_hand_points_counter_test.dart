import 'package:cizreapp/okey/engine/okey_hand_partition.dart';
import 'package:cizreapp/okey/engine/okey_meld_validator.dart';
import 'package:cizreapp/okey/engine/okey_tile.dart';
import 'package:cizreapp/okey/widgets/okey_table_metrics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// ELDEKİ ANLIK PUAN SAYACI (2026-09-05, kullanıcı bildirimi)
///
/// > "mevcut puan gösterilmiyor, mesela 1·2·3 + 2·2·2 varsa puan 12 yazması
/// > lazım ama yazılmıyor"
///
/// Sayacın beslendiği hesap buydu: ıstakadaki bitişik öbeklerden geçerli
/// perleri çıkarmak. Eskiden bir öbek ancak TAMAMI tek bir per ise sayılıyordu;
/// araya boşluk konmamış dizilimler 0 puan görünüyordu.

OkeyTile _t(OkeyColor c, int n) => OkeyTile.numbered(c, n);

/// Gösterge mavi 7 → okey mavi 8. Testteki hiçbir taş mavi değil, yani
/// hiçbiri joker sayılmaz.
const _okey = OkeyTile.numbered(OkeyColor.blue, 8);

void main() {
  group('Istaka öbeklerinden per çıkarma', () {
    // Kullanıcının örneği: kırmızı 1·2·3 (=6) ve üç renkten 2·2·2 (=6).
    final block = <OkeyTile>[
      _t(OkeyColor.red, 1),
      _t(OkeyColor.red, 2),
      _t(OkeyColor.red, 3),
      _t(OkeyColor.red, 2),
      _t(OkeyColor.black, 2),
      _t(OkeyColor.yellow, 2),
    ];

    test('boşluksuz dizilen 1·2·3 + 2·2·2 = 12 puan', () {
      final melds = OkeyHandPartitioner.fromRackGroups([block], _okey);
      expect(melds.length, 2, reason: 'öbekten iki per çıkmalı');
      expect(OkeyHandPartitioner.pointsOf(melds, _okey), 12);
    });

    test('ESKİ davranış: öbeğin tamamı geçerli per değil (0 puan sebebi)', () {
      // Bu satır regresyonun kendisini belgeliyor: sayaç eskiden yalnızca
      // buna bakıyordu ve false döndüğü için puanı 0 yazıyordu.
      expect(OkeyMeldValidator.isValidMeld(block, _okey), isFalse);
    });

    test('öbek tek başına geçerli perse AYNEN korunur', () {
      final run = <OkeyTile>[
        _t(OkeyColor.black, 4),
        _t(OkeyColor.black, 5),
        _t(OkeyColor.black, 6),
      ];
      final melds = OkeyHandPartitioner.fromRackGroups([run], _okey);
      expect(melds.length, 1);
      expect(melds.first, same(run), reason: 'oyuncunun dizilimi bozulmamalı');
      expect(OkeyHandPartitioner.pointsOf(melds, _okey), 15);
    });

    test('üçten kısa öbekler ve peri olmayan öbekler puan getirmez', () {
      final melds = OkeyHandPartitioner.fromRackGroups([
        [_t(OkeyColor.red, 5), _t(OkeyColor.red, 6)],
        [
          _t(OkeyColor.red, 1),
          _t(OkeyColor.black, 7),
          _t(OkeyColor.yellow, 12),
        ],
      ], _okey);
      expect(melds, isEmpty);
      expect(OkeyHandPartitioner.pointsOf(melds, _okey), 0);
    });

    test('101 barajını geçen dizilim doğru toplanır', () {
      // 11·12·13 üç renkten = 36 × 3 = 108
      final melds = OkeyHandPartitioner.fromRackGroups([
        [
          _t(OkeyColor.red, 11),
          _t(OkeyColor.red, 12),
          _t(OkeyColor.red, 13),
          _t(OkeyColor.black, 11),
          _t(OkeyColor.black, 12),
          _t(OkeyColor.black, 13),
        ],
        [
          _t(OkeyColor.yellow, 11),
          _t(OkeyColor.yellow, 12),
          _t(OkeyColor.yellow, 13),
        ],
      ], _okey);
      expect(OkeyHandPartitioner.pointsOf(melds, _okey), 108);
    });
  });

  group('Elin tamamı — dizilimden bağımsız puan', () {
    test('taşlar rastgele sırada olsa da 12 puan bulunur', () {
      final hand = <OkeyTile>[
        _t(OkeyColor.black, 2),
        _t(OkeyColor.red, 3),
        _t(OkeyColor.yellow, 2),
        _t(OkeyColor.red, 1),
        _t(OkeyColor.red, 2),
        _t(OkeyColor.red, 2),
      ];
      expect(OkeyHandPartitioner.best(hand, _okey).points, 12);
    });
  });

  group('Masadaki per taşı küçüldü', () {
    test('üst sınır 26px ve ıstaka taşının yarısı kadar', () {
      for (final size in const [
        Size(892, 412), // telefon, yatay
        Size(740, 360), // küçük telefon
        Size(1280, 800), // tablet
      ]) {
        final m = OkeyTableMetrics.from(BoxConstraints.tight(size));
        expect(
          m.meldTileWidth,
          lessThanOrEqualTo(26.0),
          reason: '$size: masadaki taş tavanı aşmış',
        );
        expect(
          m.meldTileWidth,
          lessThanOrEqualTo(m.rackTileWidth * 0.55),
          reason: '$size: masadaki taş ıstaka taşına göre büyük kalmış',
        );
      }
    });
  });
}
