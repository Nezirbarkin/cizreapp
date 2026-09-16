// Arama metninin PostgREST filtrelerine güvenle gömülmesini doğrular.
//
// Bu testler, "kırmızı, mavi" gibi tamamen normal bir aramanın filtreyi
// bozup 400 döndürdüğü gerçek hatayı (bkz. product_service.dart:105) kilitler.

import 'package:flutter_test/flutter_test.dart';

import 'package:cizreapp/core/utils/search_query.dart';

void main() {
  group('escapeLikeWildcards', () {
    test('yüzde işaretini kaçırır — kullanıcı "%" yazınca her şey eşleşmemeli', () {
      expect(escapeLikeWildcards('50%'), r'50\%');
    });

    test('alt çizgiyi kaçırır (tek karakter jokeri)', () {
      expect(escapeLikeWildcards('a_b'), r'a\_b');
    });

    test('ters bölüyü önce kaçırır, aksi halde çift kaçış bozulur', () {
      expect(escapeLikeWildcards(r'a\b'), r'a\\b');
    });

    test('sıradan metni değiştirmez', () {
      expect(escapeLikeWildcards('kırmızı ayakkabı'), 'kırmızı ayakkabı');
    });
  });

  group('quotePostgrestValue', () {
    test('değeri çift tırnağa alır', () {
      expect(quotePostgrestValue('abc'), '"abc"');
    });

    test('içerideki çift tırnağı kaçırır', () {
      expect(quotePostgrestValue('a"b'), r'"a\"b"');
    });

    test('içerideki ters bölüyü kaçırır', () {
      expect(quotePostgrestValue(r'a\b'), r'"a\\b"');
    });
  });

  group('ilikeContainsPattern', () {
    test('her iki uca joker ekler ve tırnaklar', () {
      expect(ilikeContainsPattern('kalem'), '"%kalem%"');
    });

    test('baştaki/sondaki boşluğu kırpar', () {
      expect(ilikeContainsPattern('  kalem  '), '"%kalem%"');
    });

    test('virgül filtreyi bozmaz — tırnak içinde kalır', () {
      expect(ilikeContainsPattern('kırmızı, mavi'), '"%kırmızı, mavi%"');
    });

    test('parantez filtreyi bozmaz', () {
      expect(ilikeContainsPattern('kalem (mavi)'), '"%kalem (mavi)%"');
    });

    test('LIKE jokeri önce, PostgREST kaçışı sonra uygulanır', () {
      // Kullanici "50%" yaziyor.
      //   1) LIKE kacisi   -> 50\%
      //   2) joker sarma   -> %50\%%
      //   3) PostgREST     -> "%50\\%%"
      // PostgREST tirnagi cozunce Postgres'e %50\%% gider: literal "50%".
      expect(ilikeContainsPattern('50%'), r'"%50\\%%"');
    });
  });

  group('buildIlikeOrFilter', () {
    test('sütunları virgülle birleştirir', () {
      expect(
        buildIlikeOrFilter(const ['name', 'description'], 'kalem'),
        'name.ilike."%kalem%",description.ilike."%kalem%"',
      );
    });

    test('tek sütunla da çalışır', () {
      expect(buildIlikeOrFilter(const ['name'], 'kalem'),
          'name.ilike."%kalem%"');
    });

    test('virgüllü aramada sütun ayracı ile değer virgülü karışmaz', () {
      final filter = buildIlikeOrFilter(const ['name', 'description'], 'a,b');
      // Yapisal virguller tirnak DISINDA, kullanici virgulu tirnak ICINDE.
      expect(filter, 'name.ilike."%a,b%",description.ilike."%a,b%"');
    });
  });
}
