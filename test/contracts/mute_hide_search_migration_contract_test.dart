import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Sessize alma + gizleme + gönderi araması göçü (20261024000004) sözleşmesi.
/// Davranış canlıda `supabase/tests/manual/mute_hide_search_test.sql` ile doğrulanır.
String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final sql = _read('supabase/migrations/20261024000004_mute_hide_search.sql');

  test('akış sunucuda süzülür (istemci süzmesi sayfalamayı bozardı)', () {
    expect(sql, contains('create view public.feed_posts_with_profiles'));
    expect(sql, contains('with (security_invoker = true)'));
    expect(sql, contains('m.muter_id = (select auth.uid()) and m.muted_id = p.user_id'));
    expect(sql, contains('h.user_id = (select auth.uid()) and h.post_id = p.id'));
  });

  test('kayıtlar yalnız sahibine; misafire kapalı', () {
    expect(sql, contains('muted_users_insert_own'));
    expect(sql, contains('hidden_posts_insert_own'));
    expect(sql, contains('check (muter_id <> muted_id)'));
    expect(sql, contains('grant select on public.feed_posts_with_profiles to authenticated;'));
    expect(sql, contains('revoke all on function public.search_posts(text, integer) from public, anon;'));
  });

  test('arama joker karakterleri kaçışlanır, Türkçe katlanır', () {
    expect(sql, contains(r"replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_')"));
    expect(sql, contains('public.social_fold_tr(p.content) like'));
  });
}
