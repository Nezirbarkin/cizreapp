import 'dart:io';

import 'package:cizreapp/features/leaderboard/leaderboard.dart';
import 'package:flutter_test/flutter_test.dart';

/// Görev 4.4 — kart/sayaç/rekor anahtarları istemci enum'larıyla sunucuda
/// AYNI sırada; kişisel sayılar yalnız çağırana, yardımcılar istemciye kapalı.
String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

List<String> _array(String sql, String function) {
  final start = sql.indexOf('CREATE OR REPLACE FUNCTION public.$function()');
  expect(start, isNonNegative, reason: function);
  final open = sql.indexOf('ARRAY[', start);
  final close = sql.indexOf('];', open);
  return RegExp(r"'([a-z_]+)'").allMatches(sql.substring(open, close)).map((m) => m.group(1)!).toList();
}

void main() {
  final sql = _read('supabase/migrations/20260928000017_leaderboard_personal_and_records.sql');

  test('kart anahtarları enum sırasıyla aynı', () {
    expect(_array(sql, 'leaderboard_card_keys'), [for (final b in LeaderboardBoard.values) b.key]);
  });

  test('kişisel sayaç ve rekor anahtarları enum\'larla aynı', () {
    expect(_array(sql, 'leaderboard_personal_stat_keys'), [
      for (final s in LeaderboardStat.values)
        if (s.group == LeaderboardStatGroup.personal) s.key,
    ]);
    expect(_array(sql, 'leaderboard_record_keys'), [for (final r in LeaderboardRecord.values) r.key]);
    for (final record in LeaderboardRecord.values) {
      expect(sql, contains("public.leaderboard_flag('${record.settingKey}', true)"), reason: record.key);
      expect(sql, contains("('${record.settingKey}', '\"true\"'"), reason: 'varsayılan satır');
    }
    for (final stat in LeaderboardStat.values.where((s) => s.group == LeaderboardStatGroup.personal)) {
      expect(sql, contains("public.leaderboard_flag('${stat.settingKey}', true)"), reason: stat.key);
    }
  });

  test('kişisel sayılar yalnız çağırana; misafire dönmez', () {
    final start = sql.indexOf('CREATE OR REPLACE FUNCTION public.leaderboard_my_stats()');
    final body = sql.substring(start, sql.indexOf(r'$fn$;', start));
    expect(body, contains('v_uid uuid := (SELECT auth.uid());'));
    expect(body, contains('a.is_anonymous'));
    expect(RegExp(r'p_user|p_id').hasMatch(body), isFalse, reason: 'başka kullanıcı parametresi yok');
  });

  test('get_leaderboards kişisel sayıları stats\'a, rekorları records\'a koyar', () {
    final start = sql.indexOf('CREATE OR REPLACE FUNCTION public.get_leaderboards()');
    final body = sql.substring(start, sql.indexOf(r'$fn$;', start));
    expect(body, contains("CONTINUE WHEN v_key IN ('stats', 'stats_today', 'my_stats', 'records');"));
    expect(body, contains('v_stats := v_stats || public.leaderboard_my_stats();'));
    expect(body, contains('v_records := public.leaderboard_records();'));
    expect(body, contains("'records', v_records"));
  });

  test('yardımcılar istemciye kapalı; giriş noktaları açık', () {
    for (final fn in [
      'leaderboard_my_stats()',
      'leaderboard_records()',
      'leaderboard_personal_stat_keys()',
      'leaderboard_record_keys()',
    ]) {
      expect(sql, contains('REVOKE ALL ON FUNCTION public.$fn FROM PUBLIC, anon, authenticated;'), reason: fn);
    }
    expect(sql, contains('GRANT EXECUTE ON FUNCTION public.get_leaderboards() TO authenticated, service_role;'));
    expect(sql, contains('GRANT EXECUTE ON FUNCTION public.leaderboard_settings() TO authenticated, service_role;'));
  });

  test('en eski üye rekoru yönetici hesaplarını atlar; kişi rekorları uygunluk kurallarını kullanır', () {
    final start = sql.indexOf('CREATE OR REPLACE FUNCTION public.leaderboard_records()');
    final body = sql.substring(start, sql.indexOf(r'$fn$;', start));
    expect(body, contains("p.role::text <> 'admin' AND NOT COALESCE(p.is_admin, false)"));
    expect(RegExp(r'leaderboard_eligible_users\(\)').allMatches(body).length, 3);
  });

  test('canlı test tüm kontrolleri içerir', () {
    final live = _read('supabase/tests/manual/leaderboard_personal_and_records_test.sql');
    for (var i = 1; i <= 7; i++) {
      expect(live, contains('[$i]'), reason: '[$i]');
    }
  });
}
