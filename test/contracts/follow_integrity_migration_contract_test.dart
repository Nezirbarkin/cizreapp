import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Takip bütünlüğü + önerilen kişiler (Görev 3.5) YAPISAL kararları. Davranış
/// canlıda `supabase/tests/manual/follow_integrity_and_suggestions_test.sql`
/// (8 kontrol) ile kanıtlanır.
void main() {
  String read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');
  String stripComments(String s) => s.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

  late String sql;
  setUpAll(() {
    sql = stripComments(read('supabase/migrations/20260928000009_follow_integrity_and_suggestions.sql'));
  });

  String fn(String name) => RegExp(
    'CREATE OR REPLACE FUNCTION ${RegExp.escape(name)}\\(.*?\\\$fn\\\$;',
    dotAll: true,
  ).firstMatch(sql)!.group(0)!;

  test('tek işlem; şema yenilenir', () {
    expect(sql, contains('\nBEGIN;\n'));
    expect(sql, contains('\nCOMMIT;\n'));
    expect(sql, contains("NOTIFY pgrst, 'reload schema';"));
  });

  group('gizlilik açığı', () {
    test('doğrudan takip yalnız açık + engelsiz hesaba', () {
      final policy = RegExp(r'CREATE POLICY follows_insert_self.*?\);', dotAll: true).firstMatch(sql)!.group(0)!;
      expect(policy, contains('public.social_can_follow_directly(following_id)'));
      final helper = fn('public.social_can_follow_directly');
      expect(helper, contains('pr.profile_is_public'));
      expect(helper, contains('NOT public.social_block_exists(p_target)'));
      expect(helper, contains('SECURITY DEFINER'));
    });

    test('istek yalnız "bekliyor" olarak açılır', () {
      final policy = RegExp(r'CREATE POLICY "Users can create follow requests".*?\);', dotAll: true).firstMatch(sql)!.group(0)!;
      expect(policy, contains("status = 'pending'"));
      expect(policy, contains('NOT public.social_block_exists(following_id)'));
    });

    test('upsert_follow_request DEFINER ve çağıran doğrulamalı; anon çalıştıramaz', () {
      final def = fn('public.upsert_follow_request');
      expect(def, contains('SECURITY DEFINER'));
      expect(def, contains('p_follower_id IS DISTINCT FROM v_me'));
      expect(sql, contains('REVOKE ALL ON FUNCTION public.upsert_follow_request(uuid, uuid) FROM PUBLIC, anon;'));
    });
  });

  group('takip RPC\'si', () {
    test('gizli hesaba istek, açığa takip, engelliye ret; bırakınca istek de gider', () {
      final def = fn('public.social_follow');
      expect(def, contains("HINT = 'FOLLOW_BLOCKED'"));
      expect(def, contains('INSERT INTO public.follows (follower_id, following_id)'));
      expect(def, contains("VALUES (v_me, p_user_id, 'pending');"));
      expect(def, contains("r.status = 'pending';"));
      expect(sql, contains('GRANT EXECUTE ON FUNCTION public.social_follow(uuid, boolean) TO authenticated;'));
    });
  });

  group('öneriler', () {
    test('süzgeçler: bot, admin, takip edilen, bekleyen, engelli, 60 gün içinde kaldırılan', () {
      final def = fn('public.suggested_follows');
      expect(def, contains('NOT COALESCE(p.is_bot, false)'));
      expect(def, contains('NOT COALESCE(p.is_admin, false)'));
      expect(def, contains("p.role::text <> 'admin'"));
      expect(def, contains('NOT EXISTS (SELECT 1 FROM my_following mf WHERE mf.id = p.id)'));
      expect(def, contains("r.status = 'pending'"));
      expect(def, contains('public.blocked_users'));
      expect(def, contains("d.created_at > now() - interval '60 days'"));
      expect(def, contains('IF v_me IS NULL THEN\n    RETURN \'[]\'::jsonb;'));
    });

    test('kaldırma tablosu istemciye kapalı', () {
      expect(sql, contains('REVOKE ALL ON public.follow_suggestion_dismissals FROM PUBLIC, anon, authenticated;'));
      expect(sql, contains('PRIMARY KEY (user_id, dismissed_user_id)'));
    });
  });

  test('istemci tabloya doğrudan takip yazmaz (sohbet üyeleri, gönderi servisi)', () {
    final members = read('lib/features/chat/screens/members_screen.dart');
    expect(members, isNot(contains(".from('follows').insert(")));
    expect(members, contains('_followService.follow(userId)'));
    final posts = read('lib/features/social/services/post_service.dart');
    expect(posts, isNot(contains(".from('follows').insert(")));
    expect(posts, contains("rpc('social_follow'"));
  });

  test('ana sayfada "En Son Gönderiler"in altında', () {
    final home = read('lib/features/market/screens/market_screen.dart');
    final recent = home.indexOf("'En Son Gönderiler'");
    final section = home.indexOf('HomeFollowSuggestionsSection(refreshTick: _recentPostsVersion)');
    final ilan = home.indexOf('const SliverToBoxAdapter(child: HomeIlanSection())');
    expect(recent, greaterThan(0));
    expect(section, greaterThan(recent));
    expect(ilan, greaterThan(section));
  });

  test('canlı doğrulama betiği repoda ve her grubu kapsar', () {
    final live = read('supabase/tests/manual/follow_integrity_and_suggestions_test.sql');
    for (var i = 1; i <= 8; i++) {
      expect(live, contains('[$i]'), reason: 'canlı testte [$i] yok');
    }
    expect(live, contains('TESTS_PASSED'));
  });
}
