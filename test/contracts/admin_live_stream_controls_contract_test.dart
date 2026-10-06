import 'dart:io';

import 'package:cizreapp/core/models/live_shopping_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Görev 4.3 — admin canlı yayın kontrolü sözleşmesi: izin kontrolü üç
/// kapıda, yönetim RPC'leri kilitli, istemci kodları sunucu HINT'leriyle aynı.
String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _function(String sql, String signatureStart) {
  final start = sql.indexOf(signatureStart);
  expect(start, isNonNegative, reason: '$signatureStart bulunamadı');
  final end = sql.indexOf(r'$fn$;', start);
  expect(end, greaterThan(start));
  return sql.substring(start, end);
}

void main() {
  final sql = _read('supabase/migrations/20260928000016_admin_live_stream_controls.sql');

  test('izin tablosu istemciye tamamen kapalı', () {
    expect(sql, contains('ALTER TABLE public.shop_live_permissions ENABLE ROW LEVEL SECURITY;'));
    expect(sql, contains('REVOKE ALL ON public.shop_live_permissions FROM PUBLIC, anon, authenticated;'));
    expect(sql, isNot(contains('CREATE POLICY')), reason: 'politika yok = istemci okuyamaz/yazamaz');
    expect(sql, isNot(contains('GRANT SELECT ON public.shop_live_permissions')));
  });

  test('izin kontrolü: yeni/hazırlıktaki yayında üç kapı; süren yayın sürdürülür', () {
    final create = _function(sql, 'CREATE OR REPLACE FUNCTION public.live_create_session(');
    final resume = create.indexOf("jsonb_build_object('resumed', true)");
    final assertAccess = create.indexOf('PERFORM private.live_assert_access(p_shop_id);');
    final insert = create.indexOf('INSERT INTO public.live_sessions');
    expect(resume, isNonNegative);
    expect(assertAccess, greaterThan(resume), reason: 'süren yayın izin kontrolünden önce sürdürülür');
    expect(insert, greaterThan(assertAccess));

    final start = _function(sql, 'CREATE OR REPLACE FUNCTION public.start_live_session(');
    expect(start, contains("IF v.status = 'scheduled' THEN\n    PERFORM private.live_assert_access(v.shop_id);"));

    final grant = _function(sql, 'CREATE OR REPLACE FUNCTION public.live_token_grant(');
    expect(grant, contains("IF v.status = 'scheduled' THEN\n      v_access := private.live_shop_access(v.shop_id);"));
    expect(grant, contains("RETURN jsonb_build_object('ok', false, 'error', v_access);"));
    expect(sql, contains('GRANT EXECUTE ON FUNCTION public.live_token_grant(uuid, text, uuid) TO service_role;'));
  });

  test('erişim kodları: sunucu HINT\'leri istemcide karşılıklı', () {
    final access = _function(sql, 'CREATE OR REPLACE FUNCTION private.live_shop_access(');
    for (final code in ['LIVE_DISABLED', 'LIVE_REVOKED', 'LIVE_NOT_PERMITTED']) {
      expect(access, contains("'$code'"));
      expect(LiveFailure.fromCode(code), isNot(LiveFailure.unknown), reason: code);
    }
    final assertAccess = _function(sql, 'CREATE OR REPLACE FUNCTION private.live_assert_access(');
    expect(assertAccess, contains('HINT = v_access'));
    expect(assertAccess, contains("DETAIL = COALESCE(v_note, '')"));
    // live-token grant hatasını olduğu gibi geçirir (yeniden dağıtım gerekmez)
    expect(_read('supabase/functions/_shared/live_token.ts'), contains('return json({ ok: false, error: grant.error ?? "FORBIDDEN" });'));
  });

  test('yönetim RPC\'leri: DEFINER, boş search_path, yönetici kontrolü, yetkiler', () {
    for (final name in [
      'admin_live_sessions(',
      'admin_live_shops(',
      'admin_end_live_session(',
      'admin_set_shop_live_permission(',
      'admin_set_live_settings(',
    ]) {
      final body = _function(sql, 'CREATE OR REPLACE FUNCTION public.$name');
      expect(body, contains('SECURITY DEFINER'), reason: name);
      expect(body, contains("SET search_path = ''"), reason: name);
      expect(body, contains('IF NOT public.auth_is_admin() THEN'), reason: name);
    }
    for (final signature in [
      'public.admin_live_sessions(text, integer, integer)',
      'public.admin_live_shops(text, text, integer, integer)',
      'public.admin_end_live_session(uuid, text)',
      'public.admin_set_shop_live_permission(uuid, text, text)',
      'public.admin_set_live_settings(boolean, text, boolean)',
    ]) {
      expect(sql, contains('REVOKE ALL ON FUNCTION $signature FROM PUBLIC, anon;'));
      expect(sql, contains('GRANT EXECUTE ON FUNCTION $signature TO authenticated;'));
    }
  });

  test('yönetici kapatması 3.4 kancasını kullanır; izin kalkınca açık yayın kapanır', () {
    final close = _function(sql, 'CREATE OR REPLACE FUNCTION private.live_admin_close(');
    expect(close, contains("private.live_close_session(p_session_id, 'admin')"));
    expect(close, contains('ended_by = auth.uid(), ended_note = p_note'));
    final permission = _function(sql, 'CREATE OR REPLACE FUNCTION public.admin_set_shop_live_permission(');
    expect(permission, contains("IF v_after <> 'ok' THEN"));
    expect(permission, contains('PERFORM private.live_admin_close(v_session, v_note);'));
    // İzleyici/satıcı ekranı 'admin' nedenini gösterir (3.4)
    expect(_read('lib/features/market/widgets/live_stream_widgets.dart'), contains("case 'admin':"));
  });

  test('sayfalı listelerde kesim ve sıra aynı ifade', () {
    final sessions = _function(sql, 'CREATE OR REPLACE FUNCTION public.admin_live_sessions(');
    expect(sessions, contains('row_number() OVER (ORDER BY'));
    expect(sessions, contains('ORDER BY p.rn'));
    final shops = _function(sql, 'CREATE OR REPLACE FUNCTION public.admin_live_shops(');
    expect(shops, contains('row_number() OVER (ORDER BY'));
    expect(shops, contains('ORDER BY p.rn'));
  });

  test('akış modülün açık olup olmadığını söyler', () {
    final feed = _function(sql, 'CREATE OR REPLACE FUNCTION public.live_sessions_feed(');
    expect(feed, contains("'enabled', private.live_module_enabled()"));
    expect(sql, contains('GRANT EXECUTE ON FUNCTION public.live_sessions_feed(integer) TO anon, authenticated;'));
  });

  test('panel bağlantısı', () {
    final drawer = _read('lib/features/admin/screens/admin_dashboard_parts/_part_drawer.dart');
    expect(drawer, contains("title: 'Canlı Yayınlar',"));
    expect(drawer, contains("setState(() => _selectedMenu = 'Canlı Yayınlar');"));
    final content = _read('lib/features/admin/screens/admin_dashboard_parts/_part_misc_remaining.dart');
    expect(content, contains("case 'Canlı Yayınlar':"));
    expect(content, contains('return const AdminLiveContent();'));
    expect(
      _read('lib/features/admin/screens/admin_dashboard_screen.dart'),
      contains("import '../widgets/admin_live_content.dart';"),
    );
  });

  test('canlı test tüm kontrolleri içerir', () {
    final live = _read('supabase/tests/manual/admin_live_stream_controls_test.sql');
    for (var i = 1; i <= 10; i++) {
      expect(live, contains('[$i]'), reason: '[$i]');
    }
  });
}
