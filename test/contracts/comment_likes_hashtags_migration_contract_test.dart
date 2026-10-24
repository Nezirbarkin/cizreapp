import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Yorum beğenisi + #etiket göçü (20261024000003) sözleşmesi. Davranış canlıda
/// `supabase/tests/manual/comment_likes_hashtags_test.sql` ile doğrulanır.
String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final sql = _read('supabase/migrations/20261024000003_comment_likes_and_hashtags.sql');

  test('yorum sayacı istemciden yazılamaz (yorum sahibi UPDATE yapabiliyor)', () {
    expect(sql, contains('create trigger a_post_comments_guard_client_write'));
    expect(sql, contains('NEW.likes_count       := OLD.likes_count;'));
    expect(sql, contains("if current_user not in ('authenticated', 'anon') or public.social_is_admin() then"));
  });

  test('beğeni: kendi adına, görünür yorum, engel yok', () {
    expect(sql, contains('user_id = (select auth.uid())'));
    expect(sql, contains('not public.social_block_exists(c.user_id)'));
  });

  test('bildirim tercihe ve 24 saat kuralına uyar, beğeniyi engellemez', () {
    expect(sql, contains('np.likes_enabled = false'));
    expect(sql, contains("n.created_at > now() - interval '24 hours'"));
    expect(sql, contains("raise warning 'notify_comment_like(%)"));
  });

  test('etiket RPC\'leri INVOKER, jsonb döner (görünüm tipine bağımlılık yok), etiket doğrulanır', () {
    expect(sql, isNot(contains('returns setof public.posts_with_profiles')));
    expect(sql, contains("v_tag !~ '^[0-9a-zçğıöşü_]{2,40}\$'"));
    expect('security invoker'.allMatches(sql).length, 2);
    expect(sql, contains("translate(coalesce(p, ''), 'IİıÇĞÖŞÜ', 'iiiçğöşü')"));
  });
}
