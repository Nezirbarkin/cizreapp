import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/20260817000030_more_purchasable_profile_decorations.sql',
    ).readAsStringSync();
  });

  test('bu migration şema değiştirmez, sadece katalog satırı ekler', () {
    // kind kısıtlaması ve fiyat kolonları zaten 20260817000027'de eklendi;
    // burada tekrar ALTER TABLE olmamalı (additive-only migration deseni).
    expect(sql, isNot(contains('alter table')));
    expect(sql, isNot(contains('alter type')));
  });

  test('5 yeni avatar çerçevesi/yaratığı avatar_effect olarak eklenir', () {
    for (final rendererKey in [
      'royal_gold_frame',
      'koi_swim',
      'owl_perch',
      'dragon_wisp',
      'star_confetti_frame',
    ]) {
      expect(sql, contains("'$rendererKey'"));
    }
    expect(sql, contains("'purchase_avatar_' || c.renderer_key"));
    expect(sql, contains("'avatar_effect',"));
  });

  test('5 yeni kapak sahnesi cover_effect olarak eklenir', () {
    for (final rendererKey in [
      'starry_night_cover',
      'snowfall_cover',
      'golden_hour_cover',
      'ocean_wave_cover',
      'firework_burst_cover',
    ]) {
      expect(sql, contains("'$rendererKey'"));
    }
    expect(sql, contains("'purchase_cover_' || s.renderer_key"));
    expect(sql, contains("'cover_effect',"));
  });

  test('5 yeni tüm-profil halesi effect olarak eklenir', () {
    for (final rendererKey in [
      'royal_aura',
      'galaxy_swirl',
      'phoenix_flame',
      'crystal_shimmer',
      'thunder_storm',
    ]) {
      expect(sql, contains("'$rendererKey'"));
    }
    expect(sql, contains("'purchase_profile_' || a.renderer_key"));
    expect(sql, contains("'effect',"));
  });

  test('üç kategori de 3 renk varyantı (a/b/c) ile eklenir', () {
    expect(
      sql,
      contains(
        "values ('a', null, null), ('b', '#00BFA5', '#1DE9B6'), ('c', '#FF7043', '#FFAB91')",
      ),
    );
    expect(
      sql,
      contains(
        "values ('a', null, null), ('b', '#FF7043', '#FFCCBC'), ('c', '#7E57C2', '#D1C4E9')",
      ),
    );
    expect(
      sql,
      contains(
        "values ('a', null, null), ('b', '#F9A825', '#FFF176'), ('c', '#5C6BC0', '#9FA8DA')",
      ),
    );
  });

  test('tüm yeni satırlar ücretsiz elde edilemez, sadece satın alınabilir', () {
    expect(
      sql.split('is_user_claimable = false').length - 1,
      greaterThanOrEqualTo(3),
    );
    // Katalog insert'lerinde is_user_claimable sabit false geçilir.
    final insertCount = 'insert into public.profile_feature_catalog'
        .allMatches(sql)
        .length;
    expect(insertCount, 3);
  });

  test('migration idempotenttir (on conflict do update)', () {
    expect('on conflict (code) do update set'.allMatches(sql).length, 3);
  });
}
