import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Görev 4.2 — Admin öne çıkarma yönetimi sözleşmesi: yetki, iade, sayfa
/// sırası, yönetici bildirimi ve panel bağlantısı birbirinden kopmasın.
String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _function(String sql, String signatureStart) {
  final start = sql.indexOf(signatureStart);
  expect(start, isNonNegative, reason: '$signatureStart bulunamadı');
  final end = sql.indexOf(r'$fn$;', start);
  expect(end, greaterThan(start));
  return sql.substring(start, end);
}

void main() {
  final management = _read('supabase/migrations/20260928000014_admin_sponsorship_management.sql');
  final notify = _read('supabase/migrations/20260928000015_sponsorship_pending_admin_notify.sql');

  test('üç RPC: DEFINER, boş search_path, yönetici kontrolü ve yetkiler', () {
    for (final name in ['admin_sponsorships_list(', 'admin_review_sponsorship(', 'admin_cancel_sponsorship(']) {
      final body = _function(management, 'CREATE OR REPLACE FUNCTION public.$name');
      expect(body, contains('SECURITY DEFINER'), reason: name);
      expect(body, contains("SET search_path = ''"), reason: name);
      expect(body, contains('IF NOT public.auth_is_admin() THEN'), reason: name);
      expect(body, contains("ERRCODE = '42501'"), reason: name);
    }
    for (final signature in [
      'public.admin_sponsorships_list(text, integer, integer)',
      'public.admin_review_sponsorship(uuid, boolean, text)',
      'public.admin_cancel_sponsorship(uuid, boolean, text)',
    ]) {
      expect(management, contains('REVOKE ALL ON FUNCTION $signature FROM PUBLIC, anon;'));
      expect(management, contains('GRANT EXECUTE ON FUNCTION $signature TO authenticated;'));
    }
  });

  test('ret ücretin tamamını iade eder; onay zinciri kilitle kurar', () {
    final review = _function(management, 'CREATE OR REPLACE FUNCTION public.admin_review_sponsorship(');
    expect(review, contains("HINT = 'SPONSORSHIP_NOT_PENDING'"));
    expect(review, contains('PERFORM 1 FROM public.shops WHERE id = v.shop_id FOR UPDATE;'));
    expect(review, contains('PERFORM private.refresh_sponsored_until(v.shop_id, v.product_id, v.placement);'));
    expect(review, contains('v_refund := private.sponsorship_refund(v, v.price_paid,'));
  });

  test('iptal: başlamadıysa tamamı, sürüyorsa kalan oranı; zincir yeniden kurulur', () {
    final cancel = _function(management, 'CREATE OR REPLACE FUNCTION public.admin_cancel_sponsorship(');
    expect(cancel, contains("HINT = 'SPONSORSHIP_NOT_ACTIVE'"));
    expect(cancel, contains('v_amount := v.price_paid;'));
    expect(cancel, contains('v.price_paid * v_left_secs / v_total_secs'));
    expect(cancel, contains('PERFORM private.sponsorship_rechain(v.shop_id, v.product_id, v.placement);'));
  });

  test('sayfa kesimi ile sayfa içi sıra aynı ifade (bekleyenler en eskiden)', () {
    final list = _function(management, 'CREATE OR REPLACE FUNCTION public.admin_sponsorships_list(');
    expect(
      list,
      contains("ORDER BY CASE WHEN status = 'pending' THEN created_at END ASC, created_at DESC, id"),
    );
    expect(list, contains("CASE WHEN f.status = 'pending' THEN f.created_at END ASC,\n             f.created_at DESC, f.id"));
    expect(list, isNot(contains('FROM (SELECT * FROM filtered ORDER BY created_at DESC LIMIT')));
  });

  test('bekleyen başvuru yöneticilere bildirim olarak düşer (satın alan hariç)', () {
    expect(notify, contains('AFTER INSERT ON public.shop_sponsorships'));
    expect(notify, contains("WHEN (NEW.status = 'pending')"));
    expect(notify, contains('SECURITY DEFINER'));
    expect(notify, contains("SET search_path = ''"));
    expect(notify, contains("'admin_notification'"));
    expect(notify, contains('AND p.id IS DISTINCT FROM NEW.created_by'));
    expect(
      notify,
      contains('REVOKE ALL ON FUNCTION private.notify_admins_sponsorship_pending() FROM PUBLIC, anon, authenticated;'),
    );
  });

  test('panel bağlantısı: menü adı bildirimdeki admin_section ile aynı', () {
    final section = RegExp(r"'admin_section', '([^']+)'").firstMatch(notify)!.group(1)!;
    expect(section, 'Öne Çıkarma');
    final drawer = _read('lib/features/admin/screens/admin_dashboard_parts/_part_drawer.dart');
    expect(drawer, contains("title: '$section',"));
    expect(drawer, contains("setState(() => _selectedMenu = '$section');"));
    final content = _read('lib/features/admin/screens/admin_dashboard_parts/_part_misc_remaining.dart');
    expect(content, contains("case '$section':"));
    expect(content, contains('return const AdminSponsorshipsContent();'));
    expect(
      _read('lib/features/admin/screens/admin_dashboard_screen.dart'),
      contains("import '../widgets/admin_sponsorships_content.dart';"),
    );
  });

  test('paket formu sınırları tablo CHECK\'leriyle aynı', () {
    final table = _read('supabase/migrations/20260928000006_seller_sponsorships.sql');
    expect(table, contains('CHECK (length(btrim(name)) BETWEEN 1 AND 40)'));
    expect(table, contains('CHECK (duration_days BETWEEN 1 AND 90)'));
    expect(table, contains('price         numeric(10,2) NOT NULL CHECK (price >= 0)'));
    expect(table, contains('UNIQUE (placement, duration_days)'));
    final ui = _read('lib/features/admin/widgets/admin_sponsorships_content.dart');
    expect(ui, contains('maxLength: 40,'));
    expect(ui, contains('if (days == null || days < 1 || days > 90)'));
    expect(ui, contains(r"RegExp(r'^\d{1,7}(\.\d{1,2})?$')"));
  });

  test('canlı testler tüm kontrolleri içerir', () {
    final live = _read('supabase/tests/manual/admin_sponsorship_management_test.sql');
    for (var i = 1; i <= 8; i++) {
      expect(live, contains('[$i]'), reason: 'yönetim testi [$i]');
    }
    final liveNotify = _read('supabase/tests/manual/sponsorship_pending_admin_notify_test.sql');
    for (var i = 1; i <= 3; i++) {
      expect(liveNotify, contains('[$i]'), reason: 'bildirim testi [$i]');
    }
  });
}
