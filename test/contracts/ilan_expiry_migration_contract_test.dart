import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Görev 3.9 — ilan süresi hatırlatma + uzatma. Davranış canlıda
/// `supabase/tests/manual/ilan_expiry_reminders_test.sql` (6 kontrol) ile
/// kanıtlanır; burada yapısal kararlar.
void main() {
  String read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');
  String stripComments(String s) => s.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

  late String sql;
  setUpAll(() {
    sql = stripComments(read('supabase/migrations/20260928000011_ilan_expiry_reminders_and_extend.sql'));
  });

  test('HATA DÜZELTMESİ: cron artık doğrulayıcıya takılmaz (yalnız sistem işaretiyle, yalnız UPDATE)', () {
    expect(sql, contains("IF TG_OP = 'UPDATE' AND current_setting('cizre.ilan_system_write', true) = 'on' THEN"));
    final expire = RegExp(r'CREATE OR REPLACE FUNCTION public\.expire_stale_ilanlar\(\).*?\$fn\$;', dotAll: true)
        .firstMatch(sql)!
        .group(0)!;
    expect(expire, contains("set_config('cizre.ilan_system_write', 'on', true)"));
    expect(expire, contains("set_config('cizre.ilan_system_write', 'off', true)"));
    expect(expire, contains("interval '3 days'"));
    expect(expire, contains("interval '1 day'"));
    expect(expire, contains("v.expires_at >= now() - interval '7 days'"), reason: 'eski dolanlara toplu bildirim yok');
  });

  test('hatırlatma: ilan × aşama × bitiş başına bir kez; günlük istemciye kapalı', () {
    expect(sql, contains('PRIMARY KEY (ilan_id, stage, expires_at)'));
    expect(sql, contains('REVOKE ALL ON public.ilan_expiry_notices FROM PUBLIC, anon, authenticated;'));
    expect(sql, contains("'ilan_expiring'"));
    expect(sql, contains("'ilan_expired'"));
  });

  test('uzatma: yalnız sahibi; son 7 gün; etkin ilan sınırı; eski hatırlatmalar silinir', () {
    final extend = RegExp(r'CREATE OR REPLACE FUNCTION public\.extend_my_ilan\(.*?\$fn\$;', dotAll: true)
        .firstMatch(sql)!
        .group(0)!;
    expect(extend, contains('SECURITY DEFINER'));
    expect(extend, contains('v.owner_id IS DISTINCT FROM v_me'));
    expect(extend, contains("HINT = 'ILAN_TOO_EARLY'"));
    expect(extend, contains("HINT = 'ILAN_ACTIVE_LIMIT'"));
    expect(extend, contains("n.type IN ('ilan_expiring', 'ilan_expired')"));
    expect(sql, contains('REVOKE ALL ON FUNCTION public.extend_my_ilan(uuid) FROM PUBLIC, anon;'));
  });

  test('istemci: bildirim dokunuşu ilanı açar (liste + push + /ilan/<id> rotası)', () {
    expect(read('lib/main.dart'), contains("if (routeName.startsWith('/ilan/')) {"));
    final push = read('lib/core/services/push_notification_service.dart');
    expect(push, contains("case 'ilan_expiring':"));
    expect(push, contains(r"_navigateToRoute(context, '/ilan/$entityId');"));
    final screen = read('lib/features/market/screens/notifications_screen.dart');
    expect(screen, contains('IlanDetailScreen(ilanId: ilanId)'));
    expect(read('lib/ilanlar/screens/my_ilanlar_screen.dart'), contains('onExtend: _extend,'));
    expect(read('lib/ilanlar/screens/ilan_detail_screen.dart'), contains('IlanExpiryPanel('));
  });

  test('canlı doğrulama betiği repoda ve her grubu kapsar', () {
    final live = read('supabase/tests/manual/ilan_expiry_reminders_test.sql');
    for (var i = 1; i <= 6; i++) {
      expect(live, contains('[$i]'), reason: 'canlı testte [$i] yok');
    }
    expect(live, contains('TESTS_PASSED'));
  });
}
