import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cizreapp/sehirici/models/sehirici_models.dart';
import 'package:cizreapp/sehirici/services/sehirici_line_service.dart';

/// `SehiriciLineService.computeStopsSignature` RPC tarafıyla birebir aynı
/// hesaplamayı yapıyor mu? RPC:
///   md5(string_agg(ls.stop_id::text, ',' ORDER BY ls.stop_order))
///
/// Bu test Dart tarafını bu beklentiyle karşılaştırır — hatalı sıralama,
/// boşluk ekleme veya join karakteri farkı ileride RPC'nin "Durak imzası
/// uyuşmuyor" hatası vermesine yol açar; bu yüzden burada sabitliyoruz.
void main() {
  group('computeStopsSignature', () {
    test('boş liste → md5 boş string', () {
      // md5("") = "d41d8cd98f00b204e9800998ecf8427e"
      const empty = <SehiriciLineStop>[];
      expect(
        SehiriciLineService.computeStopsSignature(empty),
        'd41d8cd98f00b204e9800998ecf8427e',
      );
    });

    test('tekil durak → md5(tek id)', () {
      final s = _stop('a');
      final expected = md5.convert(utf8.encode('a')).toString();
      expect(SehiriciLineService.computeStopsSignature([s]), expected);
    });

    test('sıra önemli: a,b,c ≠ b,a,c', () {
      final abc = [_stop('a'), _stop('b'), _stop('c')];
      final bac = [_stop('b'), _stop('a'), _stop('c')];
      expect(
        SehiriciLineService.computeStopsSignature(abc),
        isNot(equals(SehiriciLineService.computeStopsSignature(bac))),
      );
    });

    test('RPC ile aynı imza üretir (bilinen örnek)', () {
      // md5("a,b,c") = "a44c56c8177e32d3613988f4dba7962e"
      const stops = ['a', 'b', 'c'];
      final list = stops.map(_stop).toList();
      expect(
        SehiriciLineService.computeStopsSignature(list),
        'a44c56c8177e32d3613988f4dba7962e',
      );
    });

    test('UUID benzeri karmaşık stop_id de doğru', () {
      final list = [
        _stop('11111111-1111-1111-1111-111111111111'),
        _stop('22222222-2222-2222-2222-222222222222'),
      ];
      final expected = md5
          .convert(
            utf8.encode(
              '11111111-1111-1111-1111-111111111111,22222222-2222-2222-2222-222222222222',
            ),
          )
          .toString();
      expect(SehiriciLineService.computeStopsSignature(list), expected);
    });
  });
}

SehiriciLineStop _stop(String id) => SehiriciLineStop(
  stopId: id,
  stopOrder: 0,
  minutesFromStart: 0,
  distanceKm: 0,
  name: 's-$id',
  lat: 0,
  lng: 0,
);
