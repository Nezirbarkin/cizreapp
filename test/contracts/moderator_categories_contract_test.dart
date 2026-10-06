import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Moderatör kategorileri göçü (20260928000022) sözleşmesi. Davranış canlıda
/// `supabase/tests/manual/moderator_categories_test.sql` ile doğrulanır.
String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _fn(String sql, String header, String tag) {
  final start = sql.indexOf(header);
  expect(start, isNonNegative, reason: header);
  final end = sql.indexOf('$tag;', start);
  return sql.substring(start, end + tag.length + 1);
}

/// Her parçanın tam [count] kez geçtiğini doğrulayıp değiştirir.
String _undo(String body, List<(String, String, int)> edits) {
  var out = body;
  for (final (from, to, count) in edits) {
    expect(out.split(from).length - 1, count, reason: from);
    out = out.replaceAll(from, to);
  }
  return out;
}

void main() {
  final sql = _read('supabase/migrations/20260928000022_moderator_categories.sql');
  final previous = _read('supabase/migrations/20260928000019_moderator_roles.sql');

  String pair(String header, List<(String, String, int)> edits) {
    final old = _fn(previous, header, r'$fn$');
    final restored = _undo(_fn(sql, header, r'$fn$'), edits);
    expect(restored, old, reason: header);
    return old;
  }

  test('şema: iki kategori dizisi, NULL = hepsi, boyut sınırlı', () {
    expect(sql, contains('ADD COLUMN IF NOT EXISTS ilan_category_ids uuid[]'));
    expect(sql, contains('ADD COLUMN IF NOT EXISTS shop_category_ids uuid[]'));
    expect(sql, contains('(ilan_category_ids IS NULL OR cardinality(ilan_category_ids) BETWEEN 1 AND 100)'));
    expect(sql, contains('(shop_category_ids IS NULL OR cardinality(shop_category_ids) BETWEEN 1 AND 100)'));
    // Tablo yazma yetkisi değişmedi (istemci yalnız kendi satırını okur).
    expect(RegExp(r'ON public\.moderators\s+FOR (INSERT|UPDATE|DELETE|ALL)').hasMatch(sql), isFalse);
  });

  test('sınır yardımcısı: yöneticiye sınır yok; yalnız oturumdaki kişinin satırı', () {
    final body = _fn(sql, 'CREATE OR REPLACE FUNCTION private.moderator_category_ids(', r'$fn$');
    expect(body.indexOf('private.current_user_is_admin()'), lessThan(body.indexOf('FROM public.moderators m')));
    expect(body, contains('WHERE m.user_id = (SELECT auth.uid());'));
    expect(sql, contains('REVOKE ALL ON FUNCTION private.moderator_category_ids(text) FROM PUBLIC;'));
  });

  test('ilan listesi ve kararı: 4.6 tanımı + yalnız kategori satırları', () {
    pair('CREATE OR REPLACE FUNCTION public.mod_pending_ilanlar(', [
      ("  -- Kategori sınırı (NULL = hepsi).\n  v_cats uuid[] := private.moderator_category_ids('ilan');\n", '', 1),
      (
        "    'total', (SELECT count(*) FROM public.ilanlar i\n"
            "               WHERE i.status = 'pending' AND (v_cats IS NULL OR i.category_id = ANY (v_cats))),\n",
        "    'total', (SELECT count(*) FROM public.ilanlar WHERE status = 'pending'),\n",
        1,
      ),
      ("               'category_id', x.category_id,\n", '', 1),
      (
        "        FROM (SELECT i.* FROM public.ilanlar i\n"
            "               WHERE i.status = 'pending' AND (v_cats IS NULL OR i.category_id = ANY (v_cats))\n",
        "        FROM (SELECT i.* FROM public.ilanlar i WHERE i.status = 'pending'\n",
        1,
      ),
    ]);
    pair('CREATE OR REPLACE FUNCTION public.mod_review_ilan(', [
      ("  v_cats uuid[] := private.moderator_category_ids('ilan');\n", '', 1),
      ('i.title, i.category_id INTO v', 'i.title INTO v', 1),
      (
        '  -- Kategori sınırı: moderatör yalnız kendi kategorilerindeki ilanı karara bağlar.\n'
            '  IF v_cats IS NOT NULL AND NOT COALESCE(v.category_id = ANY (v_cats), false) THEN\n'
            "    RAISE EXCEPTION 'Bu ilanın kategorisi moderasyon alanınızda değil' USING ERRCODE = '42501', HINT = 'MOD_CATEGORY_FORBIDDEN';\n"
            '  END IF;\n',
        '',
        1,
      ),
    ]);
    // Kategori kontrolü kapsam kontrolünden sonra, karardan önce.
    final review = _fn(sql, 'CREATE OR REPLACE FUNCTION public.mod_review_ilan(', r'$fn$');
    expect(review.indexOf("auth_is_moderator('ilanlar')"), lessThan(review.indexOf('MOD_CATEGORY_FORBIDDEN')));
    expect(review.indexOf('MOD_CATEGORY_FORBIDDEN'), lessThan(review.indexOf("set_config('cizre.ilan_moderation', 'on', true)")));
  });

  test('canlı yayın listesi ve kapatma: 4.6 tanımı + yalnız mağaza kategorisi süzgeci', () {
    pair('CREATE OR REPLACE FUNCTION public.admin_live_sessions(', [
      (
        '  -- Kategori sınırı (NULL = hepsi) ve ona giren mağazalar.\n'
            "  v_cats uuid[] := private.moderator_category_ids('shop');\n"
            '  v_shops uuid[];\n',
        '',
        1,
      ),
      (
        '  IF v_cats IS NOT NULL THEN\n'
            '    v_shops := ARRAY(SELECT s.id FROM public.shops s WHERE s.category_id = ANY (v_cats));\n'
            '  END IF;\n',
        '',
        1,
      ),
      ('     WHERE (v_shops IS NULL OR ls.shop_id = ANY (v_shops))\n       AND CASE v_status', '     WHERE CASE v_status', 1),
    ].followedBy(_summaryFilters(_fn(sql, 'CREATE OR REPLACE FUNCTION public.admin_live_sessions(', r'$fn$'))).toList());
    pair('CREATE OR REPLACE FUNCTION public.admin_end_live_session(', [
      ("  v_cats uuid[] := private.moderator_category_ids('shop');\n  v_shop_category uuid;\n", '', 1),
      (
        '  SELECT ls.status, s.category_id INTO v_status, v_shop_category\n'
            '    FROM public.live_sessions ls\n'
            '    JOIN public.shops s ON s.id = ls.shop_id\n'
            '   WHERE ls.id = p_session_id\n'
            '     FOR UPDATE OF ls;\n',
        '  SELECT status INTO v_status FROM public.live_sessions WHERE id = p_session_id FOR UPDATE;\n',
        1,
      ),
      (
        '  -- Kategori sınırı: moderatör yalnız kendi kategorilerindeki mağazanın yayınını kapatır.\n'
            '  IF v_cats IS NOT NULL AND NOT COALESCE(v_shop_category = ANY (v_cats), false) THEN\n'
            "    RAISE EXCEPTION 'Bu mağazanın kategorisi moderasyon alanınızda değil' USING ERRCODE = '42501', HINT = 'MOD_CATEGORY_FORBIDDEN';\n"
            '  END IF;\n',
        '',
        1,
      ),
    ]);
  });

  test('moderatör listesi: 4.6 tanımı + iki kategori alanı', () {
    pair('CREATE OR REPLACE FUNCTION public.admin_moderators_list(', [
      ("      'ilan_categories', private.moderator_category_list('ilan', m.ilan_category_ids),\n", '', 1),
      ("      'shop_categories', private.moderator_category_list('shop', m.shop_category_ids),\n", '', 1),
    ]);
  });

  test('my_moderation: askıdaki moderatörün yetkisi yok; yönetici sınırsız', () {
    final body = _fn(sql, 'CREATE OR REPLACE FUNCTION public.my_moderation(', r'$fn$');
    expect(body, contains("JOIN public.profiles p ON p.id = m.user_id AND p.status::text = 'active'"));
    expect(body, contains("'ilan_categories', NULL,\n      'shop_categories', NULL)"));
    expect(body, contains('SECURITY DEFINER'));
    expect(body, contains("SET search_path = ''"));
  });

  test('atama: eski imza kalktı; NULL = değiştirme, boş = tümü; doğrulama; kapsamsız sınır yok', () {
    expect(sql, contains('DROP FUNCTION IF EXISTS public.admin_set_moderator(uuid, text[], text);'));
    final body = _fn(sql, 'CREATE OR REPLACE FUNCTION public.admin_set_moderator(', r'$fn$');
    expect(body, contains('p_ilan_category_ids uuid[] DEFAULT NULL'));
    expect(body, contains('p_shop_category_ids uuid[] DEFAULT NULL'));
    expect(body, contains("WHEN NOT ('ilanlar' = ANY (v_scopes)) THEN NULL"));
    expect(body, contains('WHEN p_ilan_category_ids IS NULL THEN v_old_ilan'));
    expect(body, contains("WHEN NOT ('live' = ANY (v_scopes)) THEN NULL"));
    expect(body, contains('WHEN p_shop_category_ids IS NULL THEN v_old_shop'));
    expect(body, contains("'{}'::uuid[])"), reason: 'boş dizi NULL (tümü) olur');
    expect('MOD_CATEGORY_INVALID'.allMatches(body), hasLength(2));
    expect(body, contains('IF NOT public.auth_is_admin() THEN'));
    expect(body, contains('admin_audit_log'));
    expect(sql, contains('REVOKE ALL ON FUNCTION public.admin_set_moderator(uuid, text[], text, uuid[], uuid[]) FROM PUBLIC, anon;'));
    expect(sql, contains('REVOKE ALL ON FUNCTION public.admin_moderation_categories() FROM PUBLIC, anon;'));
    expect(_fn(sql, 'CREATE OR REPLACE FUNCTION public.admin_moderation_categories(', r'$fn$'), contains('IF NOT public.auth_is_admin() THEN'));
  });

  test('istemci bağlantıları', () {
    final service = _read('lib/features/admin/services/admin_moderators_service.dart');
    expect(service, contains("'p_ilan_category_ids': ilanCategoryIds,"));
    expect(service, contains("'p_shop_category_ids': shopCategoryIds,"));
    expect(service, contains("'admin_moderation_categories'"));
    expect(service, contains("case 'MOD_CATEGORY_INVALID':"));
    expect(_read('lib/features/moderation/services/moderation_service.dart'), contains("case 'MOD_CATEGORY_FORBIDDEN':"));
    expect(_read('lib/features/admin/services/admin_live_service.dart'), contains("case 'MOD_CATEGORY_FORBIDDEN':"));
    final models = _read('lib/features/moderation/models/moderation_models.dart');
    expect(models, contains("json['ilan_categories']"));
    expect(models, contains("json['shop_categories']"));
  });

  test('canlı test tüm kontrolleri içerir', () {
    final live = _read('supabase/tests/manual/moderator_categories_test.sql');
    for (var i = 1; i <= 12; i++) {
      expect(live, contains('[$i]'), reason: '[$i]');
    }
  });
}

/// admin_live_sessions özet sayaçlarına eklenen süzgeç satırları (5 adet).
List<(String, String, int)> _summaryFilters(String body) {
  final matches = RegExp(r'\n +AND \(v_shops IS NULL OR shop_id = ANY \(v_shops\)\)').allMatches(body).toList();
  expect(matches, hasLength(5), reason: 'live_now, preparing, today, minutes_7d, admin_closed_30d');
  return [for (final m in {for (final m in matches) m.group(0)!}) (m, '', RegExp(RegExp.escape(m)).allMatches(body).length)];
}
