import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Admin > Dükkanlar sayfalı liste göçünün YAPISAL kararları.
///
/// Davranış canlı veritabanında `supabase/tests/manual/admin_shops_page_test.sql`
/// ile kanıtlanır (tüm dükkanlar için eski istemci hesabıyla birebir). Bu test
/// yanlışlıkla geri alınması güvenlik açığı ya da yavaşlık yaratacak kararları
/// sabitler: yalnız admin, boş search_path, sayfa sınırı, N+1'siz toplama.
void main() {
  const fileName = '20260927000002_admin_shops_page.sql';
  late String sql;
  late String fn;

  String read(File f) => f.readAsStringSync().replaceAll('\r\n', '\n');

  String stripComments(String s) => s
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('--'))
      .join('\n');

  setUpAll(() {
    sql = read(File('supabase/migrations/$fileName'));
    fn = RegExp(
      r'CREATE OR REPLACE FUNCTION public\.admin_shops_page\(.*?\$\$;',
      dotAll: true,
    ).firstMatch(sql)!.group(0)!;
  });

  test('göç tek işlemde çalışır ve PostgREST şemasını yeniler', () {
    final code = stripComments(sql);
    expect(RegExp(r'^begin;', multiLine: true, caseSensitive: false).hasMatch(code), isTrue);
    expect(RegExp(r'^commit;', multiLine: true, caseSensitive: false).hasMatch(code), isTrue);
    expect(code, contains("NOTIFY pgrst, 'reload schema';"));
  });

  test('yalnız admin: DEFINER içinde ilk iş admin kontrolü, değilse 42501', () {
    expect(fn, contains('SECURITY DEFINER'));
    expect(fn, contains("SET search_path = ''"));
    final body = fn.substring(fn.indexOf('BEGIN'));
    final check = body.indexOf('IF NOT private.current_user_is_admin() THEN');
    expect(check, greaterThanOrEqualTo(0));
    expect(body.indexOf("ERRCODE = '42501'"), greaterThan(check));
    // Kontrolden önce hiçbir tabloya dokunulmaz.
    expect(body.substring(0, check), isNot(contains('FROM public.')));
  });

  test('sayfa boyutu 1–100 aralığına sıkıştırılır, ofset negatif olamaz', () {
    expect(fn, contains('LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100)'));
    expect(fn, contains('GREATEST(COALESCE(p_offset, 0), 0)'));
    expect(fn, contains('LIMIT v_limit OFFSET v_offset'));
  });

  test('sipariş ve ürün sayıları dükkan başına ayrı sorguyla değil GROUP BY ile', () {
    expect(fn, contains('GROUP BY o.shop_id'));
    expect(fn, contains('GROUP BY p.shop_id'));
  });

  test('özet ve satırlar eski istemci hesaplarıyla aynı kuralları taşır', () {
    expect(fn, contains('COALESCE(s.commission_rate, 10) / 100'));
    expect(fn, contains('WHEN NOT COALESCE(s.has_own_courier, true)'));
    expect(fn, contains("v_fee := COALESCE(v_fee, 15);"));
    for (final key in [
      "'pending'", "'active'", "'passive'", "'pinned'", "'verified'",
      "'admin_courier'", "'overridden'", "'revenue'", "'commission'",
    ]) {
      expect(fn, contains(key), reason: 'özet anahtarı eksik: $key');
    }
  });

  test('yalnız authenticated çağırabilir (admin kontrolü içeride)', () {
    final code = stripComments(sql);
    const sig = 'public.admin_shops_page(text, text, text, integer, integer)';
    expect(
      RegExp('REVOKE ALL ON FUNCTION ${RegExp.escape(sig)}\\s+FROM PUBLIC, anon;').hasMatch(code),
      isTrue,
    );
    expect(
      RegExp('GRANT EXECUTE ON FUNCTION ${RegExp.escape(sig)}\\s+TO authenticated;').hasMatch(code),
      isTrue,
    );
  });
}
