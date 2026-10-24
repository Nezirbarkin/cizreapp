import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Yeni üye karşılama serisi göçü (20261024000001) sözleşmesi. Davranış canlıda
/// `supabase/tests/manual/new_member_messages_test.sql` ile doğrulanır.
String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final sql = _read('supabase/migrations/20261024000001_new_member_messages.sql');
  final lower = sql.toLowerCase();

  test('kayıt akışına tetikleyici eklenmez (handle_new_user hataları yutar)', () {
    expect(lower, isNot(contains('create trigger')));
    expect(lower, isNot(contains('create or replace function public.handle_new_user')));
  });

  test('her dakika çalışan cron işi ve tek sefer garantisi', () {
    expect(sql, contains("'new-member-messages'"));
    expect(sql, contains("'* * * * *'"));
    expect(sql, contains('primary key (user_id, step_id)'));
    expect(sql, contains('pg_try_advisory_xact_lock'));
  });

  test('geriye dönük toplu gönderim yok, bot / misafir hariç', () {
    expect(sql, contains('s.activated_at,'));
    expect(sql, contains('v_enabled_at,'));
    expect(sql, contains("interval '3 days'"));
    expect(sql, contains('coalesce(p.is_bot, false) = false'));
    expect(sql, contains('coalesce(au.is_anonymous, false) = false'));
  });

  test('bildirim mevcut admin ikonu kalıbıyla yazılır (dedup muaf, Dinle düğmesi)', () {
    expect(sql, contains("'new_member'"));
    expect(sql, contains("'admin_icon:' || s.icon"));
    expect(sql, contains("jsonb_build_object('voice_text', s.voice_text)"));
    expect(sql, contains("jsonb_build_object('route', s.action_route)"));
  });

  test('hata kullanıcı başına yakalanır ve kaydedilir', () {
    expect(sql, contains('exception when others then'));
    expect(sql, contains("'new_member_messages', SQLSTATE"));
  });

  test('istemci sahte karşılama yazamaz', () {
    expect(sql, contains('|courier_document|new_member|product_review_reply)'));
  });

  test('tablolar istemciye kapalı; admin RPC\'leri guard ile', () {
    expect(sql, contains('revoke all on public.new_member_message_steps from public, anon, authenticated;'));
    expect(sql, contains('revoke all on public.new_member_message_deliveries from public, anon, authenticated;'));
    for (final fn in [
      'admin_new_member_steps',
      'admin_upsert_new_member_step',
      'admin_set_new_member_step_active',
      'admin_delete_new_member_step',
      'admin_send_new_member_step_test',
      'admin_set_new_member_messages_enabled',
    ]) {
      final start = sql.indexOf('create or replace function public.$fn(');
      expect(start, isNonNegative, reason: fn);
      final body = sql.substring(start, sql.indexOf(r'$fn$;', start));
      expect(body, contains('private.admin_notification_guard()'), reason: fn);
    }
  });
}
