import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/20260817000031_avatar_photo_overlay_effects.sql',
    ).readAsStringSync();
  });

  test('bu migration şema değiştirmez, sadece katalog satırı ekler', () {
    expect(sql, isNot(contains('alter table')));
    expect(sql, isNot(contains('alter type')));
  });

  test(
    '3 fotoğraf-üstü efekt avatar_effect kind ile eklenir (kapak değil)',
    () {
      for (final rendererKey in [
        'photo_lightning_strike',
        'photo_rain_overlay',
        'photo_old_tv',
      ]) {
        expect(sql, contains("'$rendererKey'"));
      }
      expect(sql, contains("'avatar_effect',"));
      expect(sql, isNot(contains("'cover_effect',")));
    },
  );

  test(
    'renderer_key her zaman photo_ öneki taşır (Flutter tarafı bununla tanır)',
    () {
      final matches = RegExp(
        r"\('(photo_[a-z_]+)',",
      ).allMatches(sql).map((m) => m.group(1)).toSet();
      expect(matches, {
        'photo_lightning_strike',
        'photo_rain_overlay',
        'photo_old_tv',
      });
    },
  );

  test('3 renk varyantı (a/b/c) ile eklenir', () {
    expect(
      sql,
      contains(
        "values ('a', null, null), ('b', '#00BFA5', '#1DE9B6'), ('c', '#FF7043', '#FFAB91')",
      ),
    );
  });

  test('ücretsiz elde edilemez, sadece satın alınabilir', () {
    expect(sql, contains('is_user_claimable = false'));
    expect(sql, contains('price_monthly,'));
    expect(sql, contains('price_yearly,'));
  });

  test('migration idempotenttir (on conflict do update)', () {
    expect('on conflict (code) do update set'.allMatches(sql).length, 1);
  });
}
