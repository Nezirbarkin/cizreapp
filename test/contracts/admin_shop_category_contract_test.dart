import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Görev 4.5 — ana kategori kontrolü sözleşmesi: kilit istemciden yazılamaz,
/// koruma INVOKER, yönetici RPC'si kilitli; Admin > Dükkanlar listesi 1.3
/// kararlarını korur (yalnız kategori alanları eklendi).
String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _shopsPage(String sql) => RegExp(
  r'CREATE OR REPLACE FUNCTION public\.admin_shops_page\(.*?\$\$;',
  dotAll: true,
).firstMatch(sql)!.group(0)!;

void main() {
  final sql = _read('supabase/migrations/20260928000018_admin_shop_category_control.sql');

  test('kilit tablosu: satıcı yalnız okur, kimse doğrudan yazamaz', () {
    expect(sql, contains('ALTER TABLE public.shop_category_locks ENABLE ROW LEVEL SECURITY;'));
    expect(sql, contains('REVOKE ALL ON public.shop_category_locks FROM PUBLIC, anon, authenticated;'));
    expect(sql, contains('GRANT SELECT ON public.shop_category_locks TO authenticated;'));
    expect(RegExp(r'CREATE POLICY \w+ ON public\.shop_category_locks\s+FOR SELECT').allMatches(sql).length, 1);
    expect(RegExp(r'ON public\.shop_category_locks\s+FOR (INSERT|UPDATE|DELETE|ALL)').hasMatch(sql), isFalse);
  });

  test('koruma tetikleyicisi INVOKER, yalnız category_id değişiminde', () {
    final start = sql.indexOf('CREATE OR REPLACE FUNCTION private.guard_shop_category_lock()');
    final body = sql.substring(start, sql.indexOf(r'$fn$;', start));
    expect(body, contains('SECURITY INVOKER'));
    expect(body, isNot(contains('SECURITY DEFINER')));
    expect(body, contains('IF NEW.category_id IS NOT DISTINCT FROM OLD.category_id THEN'));
    expect(body, contains("HINT = 'SHOP_CATEGORY_LOCKED'"));
    expect(sql, contains('BEFORE UPDATE OF category_id ON public.shops'));
  });

  test('yönetici RPC\'si: DEFINER, yönetici kontrolü, pasif kategori yok, denetim ve bildirim', () {
    final start = sql.indexOf('CREATE OR REPLACE FUNCTION public.admin_set_shop_category(');
    final body = sql.substring(start, sql.indexOf(r'$fn$;', start));
    expect(body, contains('SECURITY DEFINER'));
    expect(body, contains("SET search_path = ''"));
    expect(body, contains('IF NOT public.auth_is_admin() THEN'));
    expect(body, contains("HINT = 'CATEGORY_INACTIVE'"));
    expect(body, contains('INSERT INTO public.admin_audit_log'));
    expect(body, contains("'admin_notification'"));
    expect(sql, contains('REVOKE ALL ON FUNCTION public.admin_set_shop_category(uuid, uuid, boolean, text) FROM PUBLIC, anon;'));
    expect(sql, contains('GRANT EXECUTE ON FUNCTION public.admin_set_shop_category(uuid, uuid, boolean, text) TO authenticated;'));
  });

  test('admin_shops_page: 1.3 tanımı + yalnız kategori alanları', () {
    final previous = _shopsPage(_read('supabase/migrations/20260927000002_admin_shops_page.sql'));
    final current = _shopsPage(sql);
    final stripped = current
        .replaceFirst(
          '           -- Görev 4.5: ana kategori adı/ikonu ve yönetici kilidi\n'
          '           c.name AS category_name,\n'
          '           c.icon AS category_icon,\n'
          '           (cl.shop_id IS NOT NULL) AS category_locked,\n'
          '           cl.note AS category_lock_note,\n',
          '',
        )
        .replaceFirst(
          '      LEFT JOIN public.categories c ON c.id = s.category_id\n'
          '      LEFT JOIN public.shop_category_locks cl ON cl.shop_id = s.id\n',
          '',
        )
        .replaceFirst("\n            OR r.category_name ILIKE '%' || v_q || '%')", ')');
    expect(stripped, previous, reason: '1.3 kararları (yönetici, search_path, sınır, N+1\'siz) aynen korunmalı');
  });

  test('istemci: kart menüsü, pencere ve satıcı kilidi bağlı', () {
    final shops = _read('lib/features/admin/screens/admin_dashboard_parts/_part_shops.dart');
    expect(shops, contains("case 'category':"));
    expect(shops, contains('_showShopCategoryDialog(shop);'));
    expect(shops, contains('AdminShopCategoryDialog.show('));
    expect(shops, contains("shop['category_locked'] == true"));
    expect(
      _read('lib/features/admin/screens/admin_dashboard_screen.dart'),
      contains("import '../widgets/admin_shop_category_dialog.dart';"),
    );
    final seller = _read('lib/features/seller/screens/shop_settings_screen.dart');
    expect(seller, contains(".from('shop_category_locks')"));
    expect(seller, contains("e.hint == 'SHOP_CATEGORY_LOCKED'"));
    expect(seller, contains('onChanged: _categoryLocked'));
  });

  test('canlı test tüm kontrolleri içerir', () {
    final live = _read('supabase/tests/manual/admin_shop_category_control_test.sql');
    for (var i = 1; i <= 8; i++) {
      expect(live, contains('[$i]'), reason: '[$i]');
    }
  });
}
