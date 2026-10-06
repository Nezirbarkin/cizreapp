import 'dart:io';

import 'package:cizreapp/features/moderation/models/moderation_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Görev 4.6 — moderatör rolü ve RLS altyapısı sözleşmesi.
String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _fn(String sql, String header, String tag) {
  final start = sql.indexOf(header);
  expect(start, isNonNegative, reason: header);
  final end = sql.indexOf('$tag;', start);
  return sql.substring(start, end + tag.length + 1);
}

void main() {
  final sql = _read('supabase/migrations/20260928000019_moderator_roles.sql');

  test('rol enum\'u değişmedi; yetki ayrı tabloda, istemciye salt okunur', () {
    expect(sql, isNot(contains('ALTER TYPE')), reason: 'moderatörlük asıl rolden bağımsız');
    expect(sql, contains('ALTER TABLE public.moderators ENABLE ROW LEVEL SECURITY;'));
    expect(sql, contains('REVOKE ALL ON public.moderators FROM PUBLIC, anon, authenticated;'));
    expect(sql, contains('GRANT SELECT ON public.moderators TO authenticated;'));
    expect(RegExp(r'ON public\.moderators\s+FOR (INSERT|UPDATE|DELETE|ALL)').hasMatch(sql), isFalse);
  });

  test('kapsam anahtarları istemci enum\'uyla aynı (CHECK ve atama)', () {
    final keys = [for (final s in ModerationScope.values) s.key]..sort();
    final check = RegExp(r"scopes <@ ARRAY\[([^\]]+)\]").firstMatch(sql)!.group(1)!;
    final sqlKeys = RegExp(r"'([a-z]+)'").allMatches(check).map((m) => m.group(1)!).toList()..sort();
    expect(sqlKeys, keys);
  });

  test('auth_is_moderator: yönetici ya da AKTİF moderatör; kapsamlı', () {
    final body = _fn(sql, 'CREATE OR REPLACE FUNCTION public.auth_is_moderator(', r'$fn$');
    expect(body, contains('SECURITY DEFINER'));
    expect(body, contains("SET search_path = ''"));
    expect(body, contains('private.current_user_is_admin()'));
    expect(body, contains("p.status::text = 'active'"));
    expect(body, contains('p_scope = ANY (m.scopes)'));
  });

  test('şikayet açıkları kapandı; yönetici kontrolü JWT rolüne bakmıyor', () {
    expect(sql, contains('DROP POLICY IF EXISTS post_reports_select_anon ON public.post_reports;'));
    expect(
      sql,
      contains("ALTER POLICY user_reports_select_unified ON public.user_reports\n"
          "  USING (reporter_id = (SELECT auth.uid()) OR (SELECT public.auth_is_moderator('reports')));"),
    );
    expect(
      sql,
      contains("ALTER POLICY post_reports_update_admin ON public.post_reports\n"
          "  USING ((SELECT public.auth_is_moderator('reports')))"),
    );
    final policySection = sql.substring(sql.indexOf('-- 4) RLS'), sql.indexOf('-- 5) Moderasyon'));
    expect(policySection, isNot(contains("auth.jwt()")));
  });

  test('moderasyon RPC\'leri: DEFINER, kapsam kontrolü, denetim', () {
    final expected = {
      'mod_set_post_active(': 'content',
      'mod_posts(': 'content',
      'mod_reports(': 'reports',
      'mod_resolve_report(': 'reports',
      'mod_pending_ilanlar(': 'ilanlar',
      'mod_review_ilan(': 'ilanlar',
    };
    for (final entry in expected.entries) {
      final body = _fn(sql, 'CREATE OR REPLACE FUNCTION public.${entry.key}', r'$fn$');
      expect(body, contains('SECURITY DEFINER'), reason: entry.key);
      expect(body, contains("SET search_path = ''"), reason: entry.key);
      expect(body, contains("IF NOT public.auth_is_moderator('${entry.value}') THEN"), reason: entry.key);
    }
    expect(_fn(sql, 'CREATE OR REPLACE FUNCTION private.mod_set_post_active(', r'$fn$'), contains('admin_audit_log'));
    expect(_fn(sql, 'CREATE OR REPLACE FUNCTION public.mod_resolve_report(', r'$fn$'), contains('admin_audit_log'));
    expect(_fn(sql, 'CREATE OR REPLACE FUNCTION public.mod_review_ilan(', r'$fn$'), contains('admin_audit_log'));
  });

  test('ilan doğrulayıcı: 3.9 tanımı + yalnız moderatör onayı satırı', () {
    final previous = _fn(
      _read('supabase/migrations/20260928000011_ilan_expiry_reminders_and_extend.sql'),
      'CREATE OR REPLACE FUNCTION public.validate_ilan_write()',
      r'$function$',
    );
    final current = _fn(sql, 'CREATE OR REPLACE FUNCTION public.validate_ilan_write()', r'$function$');
    final restored = current.replaceFirst(
      "  -- Görev 4.6: 'ilanlar' kapsamlı moderatörün onay/ret kararı (yalnız\n"
      "  -- mod_review_ilan'ın işlem-içi işaretiyle) yönetici kararı gibi işlenir:\n"
      "  -- onay alanları, retle ücret iadesi aynı kodla yürür.\n"
      "  v_is_admin boolean := public.ilan_is_admin()\n"
      "    OR (current_setting('cizre.ilan_moderation', true) = 'on'\n"
      "        AND public.auth_is_moderator('ilanlar'));\n",
      '  v_is_admin boolean := public.ilan_is_admin();\n',
    );
    expect(restored, previous);
    // İşaret yalnız kapsam doğrulandıktan sonra ve işlem-içi kurulur.
    final review = _fn(sql, 'CREATE OR REPLACE FUNCTION public.mod_review_ilan(', r'$fn$');
    expect(review.indexOf("auth_is_moderator('ilanlar')"), lessThan(review.indexOf("set_config('cizre.ilan_moderation', 'on', true)")));
  });

  test('canlı yayın listesi/kapatma: 4.3 tanımı + yalnız yetki satırı', () {
    final old = _read('supabase/migrations/20260928000016_admin_live_stream_controls.sql');
    for (final header in [
      'CREATE OR REPLACE FUNCTION public.admin_live_sessions(',
      'CREATE OR REPLACE FUNCTION public.admin_end_live_session(',
    ]) {
      final previous = _fn(old, header, r'$fn$');
      final current = _fn(sql, header, r'$fn$');
      final restored = current.replaceFirst(
        "  -- Görev 4.6: yönetici ya da 'live' kapsamlı moderatör.\n"
        "  IF NOT public.auth_is_moderator('live') THEN\n"
        "    RAISE EXCEPTION 'Yönetici ya da moderatör yetkisi gerekli' USING ERRCODE = '42501';\n",
        "  IF NOT public.auth_is_admin() THEN\n"
        "    RAISE EXCEPTION 'Yönetici yetkisi gerekli' USING ERRCODE = '42501';\n",
      );
      expect(restored, previous, reason: header);
    }
  });

  test('istemci bağlantıları', () {
    final drawer = _read('lib/features/admin/screens/admin_dashboard_parts/_part_drawer.dart');
    expect(drawer, contains("title: 'Moderatörler',"));
    final content = _read('lib/features/admin/screens/admin_dashboard_parts/_part_misc_remaining.dart');
    expect(content, contains("case 'Moderatörler':"));
    expect(content, contains('return const AdminModeratorsContent();'));
    final sidebar = _read('lib/core/widgets/settings_sidebar.dart');
    expect(sidebar, contains('if (_moderationAccess.hasAny &&'));
    expect(sidebar, contains('ModerationService.fetchMyAccess()'));
    // Önbellekteki yetki bayat olabilir: panel girmeden sunucudan taze yetkiyle açılır,
    // yetki yoksa açılmaz (2026-10-04 düzeltmesi).
    expect(sidebar, contains('if (!access.hasAny) {'));
    expect(sidebar, contains('ModerationPanelScreen(access: access)'));
    expect(
      sidebar.indexOf('await ModerationService.fetchMyAccess()'),
      lessThan(sidebar.indexOf('ModerationPanelScreen(access: access)')),
    );
    expect(
      _read('lib/features/moderation/screens/moderation_panel_screen.dart'),
      contains('const AdminLiveContent(moderatorMode: true)'),
    );
  });

  test('canlı test tüm kontrolleri içerir', () {
    final live = _read('supabase/tests/manual/moderator_roles_test.sql');
    for (var i = 1; i <= 10; i++) {
      expect(live, contains('[$i]'), reason: '[$i]');
    }
  });
}
