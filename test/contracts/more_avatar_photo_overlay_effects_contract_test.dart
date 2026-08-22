import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/20260817000032_more_avatar_photo_overlay_effects.sql',
    ).readAsStringSync();
  });

  test('bu migration şema değiştirmez, sadece katalog satırı ekler', () {
    expect(sql, isNot(contains('alter table')));
    expect(sql, isNot(contains('alter type')));
  });

  const expectedRendererKeys = [
    'photo_snow_overlay',
    'photo_fog_overlay',
    'photo_heat_wave',
    'photo_neon_glitch',
    'photo_vhs_static',
    'photo_film_grain',
    'photo_sun_flare',
    'photo_bokeh_lights',
    'photo_ice_frost',
    'photo_confetti_burst',
    'photo_bubble_overlay',
    'photo_crack_glass',
    'photo_smoke_drift',
    'photo_flame_overlay',
  ];

  test('14 yeni fotoğraf-üstü efekt avatar_effect kind ile eklenir', () {
    for (final rendererKey in expectedRendererKeys) {
      expect(sql, contains("'$rendererKey'"));
    }
    expect(sql, contains("'avatar_effect',"));
    expect(sql, isNot(contains("'cover_effect',")));
  });

  test('tümü photo_ öneki taşır (Flutter dispatch mekanizmasıyla eşleşir)', () {
    final matches = RegExp(
      r"\('(photo_[a-z_]+)',",
    ).allMatches(sql).map((m) => m.group(1)).toSet();
    expect(matches, expectedRendererKeys.toSet());
  });

  test('2 renk varyantı (a/b) ile eklenir', () {
    expect(
      sql,
      contains("values ('a', null, null), ('b', '#00BFA5', '#1DE9B6')"),
    );
  });

  test('ücretsiz elde edilemez, sadece satın alınabilir', () {
    expect(sql, contains('is_user_claimable = false'));
  });

  test('migration idempotenttir (on conflict do update)', () {
    expect('on conflict (code) do update set'.allMatches(sql).length, 1);
  });

  test(
    'tüm satırlar aynı desende: purchase_avatar_ + renderer_key + suffix',
    () {
      expect(
        sql,
        contains("'purchase_avatar_' || o.renderer_key || '_' || v.suffix"),
      );
    },
  );
}
