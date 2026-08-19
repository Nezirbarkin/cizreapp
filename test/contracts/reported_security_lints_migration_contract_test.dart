import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const path =
      'supabase/migrations/20260810000008_fix_reported_security_lints.sql';

  late String sql;

  setUpAll(() => sql = File(path).readAsStringSync());

  test('deprecated push fonksiyonunun search path ve REST erişimi kapanır', () {
    expect(sql, contains('send_push_on_notification_deprecated()'));
    expect(sql, contains('SET search_path = public, extensions, pg_temp'));
    expect(sql, contains('FROM PUBLIC, anon, authenticated'));
  });

  test('trigger ve internal fonksiyonlar katalogdan topluca korunur', () {
    expect(sql, contains('FROM pg_catalog.pg_trigger AS t'));
    expect(sql, contains('t.tgfoid = p.oid'));
    expect(sql, contains('enqueue_notification_outbox_trigger'));
    expect(sql, contains('handle_new_user'));
  });

  test('AdMob sunucu RPC fonksiyonları yalnız service role için bırakılır', () {
    expect(sql, contains('create_ad_reward_session(uuid,text,text,text,text)'));
    expect(sql, contains('grant_verified_ad_points(uuid,text,text,text,text,'));
    expect(sql, contains('TO service_role'));
  });

  test('public bucket listeleme politikaları kaldırılır', () {
    expect(sql, contains('DROP POLICY IF EXISTS "avatar_select_policy"'));
    expect(sql, contains('DROP POLICY IF EXISTS "cover_select_policy"'));
    expect(sql, contains('DROP POLICY IF EXISTS "News media public read"'));
    expect(sql, isNot(contains('CREATE POLICY "avatar_select_policy"')));
  });

  test('pgTAP public şemasından extensions şemasına taşınır', () {
    expect(sql, contains('ALTER EXTENSION pgtap SET SCHEMA extensions'));
    expect(sql, contains('CREATE SCHEMA IF NOT EXISTS extensions'));
  });

  test('istemciye gerekli AdMob admin RPC yetkisine dokunulmaz', () {
    expect(sql, isNot(contains('admin_update_reward_points_config(')));
    expect(sql, contains("NOTIFY pgrst, 'reload schema'"));
  });

  test('RLS helper ve aktif uygulama RPC erişimleri korunur', () {
    expect(sql, contains('GRANT EXECUTE ON FUNCTION %s TO authenticated'));
    expect(sql, contains('public.add_product(uuid,text,text,numeric'));
    expect(
      sql,
      contains('lookup_email_by_username(text) intentionally remains'),
    );
    expect(sql, isNot(contains("'apply_campaign_rewards_for_order',")));
  });
}
