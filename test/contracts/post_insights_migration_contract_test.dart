import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Gönderi görüntülenme + düzenleme göçü (20261024000002) sözleşmesi. Davranış
/// canlıda `supabase/tests/manual/post_insights_and_edits_test.sql` ile doğrulanır.
String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final sql = _read('supabase/migrations/20261024000002_post_insights_and_edits.sql');

  test('sayaç posts\'ta değil ayrı tabloda (realtime / updated_at yükü yok)', () {
    expect(sql, isNot(contains('add column if not exists views_count')));
    expect(sql, contains('create table if not exists public.post_stats'));
    expect(sql, contains('primary key (post_id, viewer_id, day)'));
  });

  test('gösterim yalnız RPC ile, kendi gönderisi ve göremediği yazar hariç', () {
    expect(sql, contains('revoke all on public.post_impressions from public, anon, authenticated;'));
    expect(sql, contains('p.user_id is distinct from v_uid'));
    expect(sql, contains('public.can_view_social_author(p.user_id)'));
    expect(sql, contains('p_post_ids[1:50]'));
    expect(sql, contains('revoke all on function public.record_post_impressions(uuid[]) from public, anon;'));
  });

  test('istatistik yalnız sahibe / admine', () {
    expect(sql, contains('v_post.user_id is distinct from v_uid and not public.social_is_admin()'));
  });

  test('posts kolonu 4 yerde: görünüm sonu, iki misafir RPC, koruma', () {
    final view = sql.substring(sql.indexOf('CREATE OR REPLACE VIEW public.posts_with_profiles'));
    expect(
      view,
      contains('pr.id IS NOT NULL AS author_profile_exists,\n'
          '    COALESCE(ps.views_count, 0)::integer AS views_count,\n'
          '    p.edited_at\n'),
      reason: 'yeni sütunlar yalnız SONA eklenebilir',
    );
    expect(view, contains('WITH (security_invoker = true)'));
    expect(
      'author_profile_exists boolean, views_count integer, edited_at timestamp with time zone)'
          .allMatches(sql)
          .length,
      2,
    );
    expect(sql, contains('NEW.edited_at      := NULL;'));
    expect(sql, contains('NEW.edited_at      := OLD.edited_at;'));
    expect(sql, contains('before update of content on public.posts'));
  });

  test('ölü increment_post_view kaldırılır', () {
    expect(sql, contains('drop function if exists public.increment_post_view(uuid);'));
  });
}
