import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Canlı yayın tekrar izleme göçü (20261016000040) sözleşmesi. Davranış
/// canlıda `supabase/tests/manual/live_replays_test.sql` ile doğrulanır.
String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _fn(String sql, String header) {
  final start = sql.indexOf(header);
  expect(start, isNonNegative, reason: header);
  final end = sql.indexOf(r'$fn$;', start);
  return sql.substring(start, end + 5);
}

void main() {
  final sql = _read('supabase/migrations/20261016000040_live_replays.sql');

  test('live_session_json: 20261004000001 tanımı + yalnız replay satırı', () {
    const header = 'CREATE OR REPLACE FUNCTION private.live_session_json(';
    final previous = _fn(_read('supabase/migrations/20261004000001_user_live_streams.sql'), header);
    final current = _fn(sql, header);
    const line = "    'replay', private.live_replay_json(ls),\n";
    expect(current, contains(line));
    expect(current.replaceFirst(line, ''), previous);
  });

  test('yönetici ayarları: 20260928000021 tanımları + yalnız kayıt anahtarları', () {
    final old = _read('supabase/migrations/20260928000021_live_notifications_history.sql');
    const optionsHeader = 'CREATE OR REPLACE FUNCTION public.admin_live_options(';
    final options = _fn(sql, optionsHeader)
        .replaceFirst(
          "    'replay_enabled', private.live_setting_bool('live_replay_enabled', true),\n"
              "    'replay_days', private.live_replay_days(),\n",
          '',
        )
        .replaceFirst(
          "                              WHERE skipped = 'cooldown' AND notified_at > now() - interval '30 days'),\n"
              "      'replays', (SELECT count(*) FROM public.live_sessions\n"
              "                   WHERE replay_state IN ('recording', 'ready') AND replay_parts > 0),\n"
              "      'replay_size_bytes', (SELECT COALESCE(sum(replay_size_bytes), 0) FROM public.live_sessions\n"
              "                             WHERE replay_state IN ('recording', 'ready', 'failed'))\n",
          "                              WHERE skipped = 'cooldown' AND notified_at > now() - interval '30 days')\n",
        );
    expect(options, _fn(old, optionsHeader));

    const setHeader = 'CREATE OR REPLACE FUNCTION public.admin_set_live_options(';
    final setter = _fn(sql, setHeader);
    expect(setter, contains("WHEN 'replay_days' THEN LEAST(GREATEST(v_num, 1), 365)"));
    final restored = setter
        .replaceFirst("      WHEN 'replay_enabled' THEN 'live_replay_enabled'\n", '')
        .replaceFirst("      WHEN 'replay_days' THEN 'live_replay_days'\n", '')
        .replaceFirst(
          "    IF v_key IN ('notify_enabled', 'notify_followers', 'notify_product_fans', 'notify_customers',\n"
              "                 'home_card_enabled', 'replay_enabled') THEN\n",
          "    IF v_key IN ('notify_enabled', 'notify_followers', 'notify_product_fans', 'notify_customers', 'home_card_enabled') THEN\n",
        )
        .replaceFirst("        WHEN 'replay_days' THEN LEAST(GREATEST(v_num, 1), 365)\n", '');
    expect(restored, _fn(old, setHeader));
  });

  test('kova özel, yalnız MP4, parça başına 50 MB', () {
    expect(sql, contains("VALUES ('live-replays', 'live-replays', false, 52428800, ARRAY['video/mp4'])"));
    expect(sql, contains('SET public = false'));
  });

  test('depo politikaları: okuma görünürlük kuralıyla, yazma yalnız yayıncıya, silme yayıncı/yönetici', () {
    expect(
      sql,
      contains(
        'FOR SELECT TO anon, authenticated\n'
        "  USING (bucket_id = 'live-replays' AND public.live_replay_object_visible(name));",
      ),
    );
    expect(
      sql,
      contains(
        'FOR INSERT TO authenticated\n'
        "  WITH CHECK (bucket_id = 'live-replays' AND public.live_replay_upload_allowed(name));",
      ),
    );
    expect(sql, contains('FOR UPDATE TO authenticated'));
    expect(
      sql,
      contains(
        'FOR DELETE TO authenticated\n'
        "  USING (bucket_id = 'live-replays' AND public.live_replay_delete_allowed(name));",
      ),
    );

    final upload = _fn(sql, 'CREATE OR REPLACE FUNCTION public.live_replay_upload_allowed(');
    expect(upload, contains('ls.host_user_id = v_uid'));
    expect(upload, contains("ls.replay_state = 'recording'"));
    expect(upload, contains("ls.ended_at > now() - interval '7 days'"));
    expect(upload, contains('v_part < 1 OR v_part > 999'));

    final visible = _fn(sql, 'CREATE OR REPLACE FUNCTION private.live_replay_visible(');
    expect(visible, contains("v.replay_state = 'deleted'"));
    expect(visible, contains("v.status <> 'ended'"), reason: 'canlıyken izleyici kaydı görmez');
    expect(visible, contains('private.live_replay_days()'), reason: 'saklama süresi dolunca kapanır');
    expect(
      visible,
      contains('private.live_session_listable(v.shop_id, v.host_user_id, p_viewer)'),
      reason: 'gizli hesap / engel kuralı canlı yayınla aynı',
    );
  });

  test('parça tablosu istemciye kapalı; yazmalar DEFINER RPC, boş search_path', () {
    expect(sql, contains('ALTER TABLE public.live_replay_parts ENABLE ROW LEVEL SECURITY;'));
    expect(sql, contains('REVOKE ALL ON TABLE public.live_replay_parts FROM PUBLIC, anon, authenticated;'));
    for (final name in [
      'live_replay_begin(',
      'live_replay_add_part(',
      'live_replay_finish(',
      'live_replay_parts(',
      'live_replay_delete(',
      'live_replay_cleanup_batch(',
      'live_replay_object_visible(',
      'live_replay_upload_allowed(',
      'live_replay_delete_allowed(',
    ]) {
      final body = _fn(sql, 'CREATE OR REPLACE FUNCTION public.$name');
      expect(body, contains('SECURITY DEFINER'), reason: name);
      expect(body, contains("SET search_path = ''"), reason: name);
    }
    final add = _fn(sql, 'CREATE OR REPLACE FUNCTION public.live_replay_add_part(');
    expect(add, contains("o.bucket_id = 'live-replays' AND o.name = v_path"), reason: 'dosya depoda olmalı');
    expect(add, contains("HINT = 'LIVE_REPLAY_CLOSED'"));
    final delete = _fn(sql, 'CREATE OR REPLACE FUNCTION public.live_replay_delete(');
    expect(delete, contains('v.host_user_id <> v_uid AND NOT public.auth_is_admin()'));
    final begin = _fn(sql, 'CREATE OR REPLACE FUNCTION public.live_replay_begin(');
    expect(begin, contains("private.live_setting_bool('live_replay_enabled', true)"));
  });

  test('yetkiler: yazmalar misafire kapalı, temizlik yalnız service_role', () {
    for (final sig in [
      'public.live_replay_begin(uuid)',
      'public.live_replay_add_part(uuid, integer, integer)',
      'public.live_replay_finish(uuid)',
      'public.live_replay_delete(uuid)',
    ]) {
      expect(sql, contains('REVOKE ALL ON FUNCTION $sig FROM PUBLIC, anon;'), reason: sig);
      expect(sql, contains('GRANT EXECUTE ON FUNCTION $sig TO authenticated;'), reason: sig);
    }
    expect(sql, contains('GRANT EXECUTE ON FUNCTION public.live_replay_parts(uuid) TO anon, authenticated;'));
    expect(
      sql,
      contains('REVOKE ALL ON FUNCTION public.live_replay_cleanup_batch(integer) FROM PUBLIC, anon, authenticated;'),
    );
    expect(sql, contains('GRANT EXECUTE ON FUNCTION public.live_replay_cleanup_batch(integer) TO service_role;'));
  });

  test('saatlik temizlik cron\'u ve Edge Function cron sırrıyla korunur', () {
    expect(
      sql,
      contains(
        "'live-replay-cleanup-hourly',\n    '23 * * * *',\n"
        "    replace(v_cmd, 'smm-order-status-check', 'live-replay-cleanup')",
      ),
    );
    final fn = _read('supabase/functions/live-replay-cleanup/index.ts');
    expect(fn, contains('isCronAuthorized(req.headers.get("x-cron-secret"), Deno.env.get("CRON_SECRET"))'));
    expect(fn, contains('live_replay_cleanup_batch'));
    expect(_read('supabase/config.toml'), contains('[functions.live-replay-cleanup]\nverify_jwt = false'));
    expect(File('supabase/functions/_shared/live_replay_cleanup_test.ts').existsSync(), isTrue);
  });

  test('canlı doğrulama betiği repoda ve her grubu kapsar', () {
    final live = _read('supabase/tests/manual/live_replays_test.sql');
    for (var i = 1; i <= 13; i++) {
      expect(live, contains('-- [$i] '), reason: 'kontrol $i');
    }
    expect(live, contains("RAISE EXCEPTION 'TESTS_PASSED live_replays %/13', v_checks;"));
  });
}
