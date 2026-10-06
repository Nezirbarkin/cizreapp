import 'dart:io';

import 'package:cizreapp/features/admin/services/bot_comment_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Görev 4.7 — bot yorumları sözleşmesi.
String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _fn(String sql, String header) {
  final start = sql.indexOf(header);
  expect(start, isNonNegative, reason: header);
  final end = sql.indexOf(r'$fn$;', start);
  return sql.substring(start, end);
}

void main() {
  final sql = _read('supabase/migrations/20260928000020_bot_comments.sql');

  test('tablolar istemciye kapalı; yalnız yönetici RPC\'leri', () {
    for (final table in ['bot_comment_library', 'bot_comment_jobs', 'bot_comment_seen_posts']) {
      expect(sql, contains('ALTER TABLE public.$table ENABLE ROW LEVEL SECURITY;'), reason: table);
      expect(sql, contains('REVOKE ALL ON TABLE public.$table FROM PUBLIC, anon, authenticated;'), reason: table);
    }
    for (final name in [
      'admin_bot_comment(',
      'admin_bot_comment_jobs(',
      'admin_bot_comment_cancel(',
      'admin_bot_comment_library(',
      'admin_bot_comment_library_upsert(',
      'admin_bot_comment_library_delete(',
      'admin_bot_recent_posts(',
      'admin_bot_run_comment_queue(',
    ]) {
      final body = _fn(sql, 'CREATE OR REPLACE FUNCTION public.$name');
      expect(body, contains('SECURITY DEFINER'), reason: name);
      expect(body, contains("SET search_path = ''"), reason: name);
      expect(body, contains('IF NOT private.current_user_is_admin() THEN'), reason: name);
    }
    expect(sql, contains('REVOKE ALL ON FUNCTION public.schedule_bot_comments(integer) FROM PUBLIC, anon, authenticated;'));
    expect(sql, contains('REVOKE ALL ON FUNCTION public.process_bot_comment_jobs(integer) FROM PUBLIC, anon, authenticated;'));
  });

  test('otomatik yorum varsayılan kapalı; gönderi bir kez değerlendirilir; bot bir kez yorumlar', () {
    expect(sql, contains("('bot_auto_comment_enabled', '\"false\"',"));
    final schedule = _fn(sql, 'CREATE OR REPLACE FUNCTION public.schedule_bot_comments(');
    expect(schedule, contains("private.bot_setting_bool('bot_auto_comment_enabled', false)"));
    expect(schedule, contains('NOT EXISTS (SELECT 1 FROM public.bot_comment_seen_posts s WHERE s.post_id = po.id)'));
    expect(schedule, contains('INSERT INTO public.bot_comment_seen_posts'));
    expect(schedule, contains('AND p.id <> v_post.user_id'), reason: 'yazar kendi gönderisine yorum yapmaz');
    expect(sql, contains("ON public.bot_comment_jobs (bot_id, post_id) WHERE source = 'auto';"));
  });

  test('işleyici gizli gönderiye / pasif bota yazmaz', () {
    final execute = _fn(sql, 'CREATE OR REPLACE FUNCTION private.bot_comment_execute(');
    expect(execute, contains('po.is_active IS NOT FALSE'));
    expect(execute, contains('NOT private.bot_is_active(v_job.bot_id)'));
    expect(execute, contains('INSERT INTO public.post_comments (post_id, user_id, content)'));
  });

  test('bot sahibine yorum bildirimi yazılmaz; gerçek kullanıcıya yazılır', () {
    final start = sql.indexOf('CREATE OR REPLACE FUNCTION public.notify_post_comment()');
    final body = sql.substring(start, sql.indexOf(r'$function$;', start));
    final skip = body.indexOf('COALESCE(is_bot, false)');
    final insert = body.indexOf('INSERT INTO public.notifications');
    expect(skip, isNonNegative);
    expect(insert, greaterThan(skip));
    expect(body, contains("'post_comment'"));
  });

  test('tonlar istemciyle aynı; pg_cron işi kurulu', () {
    final check = RegExp(r"tone IN \(([^)]+)\)").firstMatch(sql)!.group(1)!;
    final keys = RegExp(r"'([a-z]+)'").allMatches(check).map((m) => m.group(1)).toList();
    expect(keys, BotCommentService.tones);
    expect(sql, contains("'bot_comment_tick',"));
  });

  test('Bot Hesapları ekranında Yorumlar sekmesi', () {
    final ui = _read('lib/features/admin/widgets/bot_management_content.dart');
    expect(ui, contains('TabController(length: 5, vsync: this)'));
    expect(ui, contains("Tab(icon: Icon(Icons.mode_comment_outlined), text: 'Yorumlar'),"));
    expect(ui, contains('BotCommentsTab(bots: _bots),'));
  });

  test('canlı test tüm kontrolleri içerir', () {
    final live = _read('supabase/tests/manual/bot_comments_test.sql');
    for (var i = 1; i <= 9; i++) {
      expect(live, contains('[$i]'), reason: '[$i]');
    }
  });
}
