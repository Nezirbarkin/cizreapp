import 'dart:io';

import 'package:cizreapp/features/admin/services/admin_live_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Canlı yayın bildirimi, abonelik, geçmiş ve ana sayfa kartı göçü
/// (20260928000021) sözleşmesi. Davranış canlıda
/// `supabase/tests/manual/live_notifications_history_test.sql` ile doğrulanır.
String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _fn(String sql, String header, String tag) {
  final start = sql.indexOf(header);
  expect(start, isNonNegative, reason: header);
  final end = sql.indexOf('$tag;', start);
  return sql.substring(start, end + tag.length + 1);
}

void main() {
  final sql = _read('supabase/migrations/20260928000021_live_notifications_history.sql');

  test('start_live_session: 4.3 tanımı + yalnız bildirim bloğu ve dönüş satırı', () {
    final previous = _fn(
      _read('supabase/migrations/20260928000016_admin_live_stream_controls.sql'),
      'CREATE OR REPLACE FUNCTION public.start_live_session(',
      r'$fn$',
    );
    final current = _fn(sql, 'CREATE OR REPLACE FUNCTION public.start_live_session(', r'$fn$');
    const notifyBlock =
        '  -- Hazırlıktan canlıya ilk geçiş: "yayın başladı" bildirimi. Hata yayını\n'
        '  -- engellemez (alt işlem geri alınır, yayın başlar).\n'
        "  IF v.status = 'scheduled' THEN\n"
        '    BEGIN\n'
        '      v_notified := private.live_notify_started(p_session_id);\n'
        '    EXCEPTION WHEN OTHERS THEN\n'
        "      RAISE WARNING 'live_notify_started(%): % (%)', p_session_id, SQLERRM, SQLSTATE;\n"
        '    END;\n'
        '  END IF;\n'
        '\n';
    expect(current, contains(notifyBlock), reason: 'bildirim yalnız ilk geçişte ve alt işlemde');
    final restored = current
        .replaceFirst('  v_notified integer;\n', '')
        .replaceFirst(notifyBlock, '')
        .replaceFirst(
          "  RETURN private.live_session_json(p_session_id) || jsonb_build_object('notified', v_notified);\n",
          '  RETURN private.live_session_json(p_session_id);\n',
        );
    expect(restored, previous);
    // Bildirim, yayın canlıya alındıktan SONRA ve izin kontrolünden sonra.
    expect(current.indexOf("SET status = 'live'"), lessThan(current.indexOf('private.live_notify_started')));
    expect(current.indexOf('private.live_assert_access'), lessThan(current.indexOf('private.live_notify_started')));
  });

  test('alıcı süzgeci: satıcı/yayıncı, bot, pasif hesap, engel ve tercih hariç; tek sefer; sınırlı', () {
    final body = _fn(sql, 'CREATE OR REPLACE FUNCTION private.live_notify_started(', r'$fn$');
    expect(body, contains('EXISTS (SELECT 1 FROM public.live_notify_log l WHERE l.session_id = p_session_id)'));
    expect(body, contains('r.user_id IS DISTINCT FROM v.owner_id'));
    expect(body, contains('r.user_id IS DISTINCT FROM v.host_user_id'));
    expect(body, contains('NOT COALESCE(p.is_bot, false)'));
    expect(body, contains("p.status::text = 'active'"));
    expect(body, contains('np.live_streams_enabled = false'));
    expect(body, contains('public.blocked_users'));
    expect(body, contains('LIMIT v_max'));
    expect(body, contains("'live_started'"));
    expect(body, contains("'route', '/live/' || v.id::text"));
    // Bekleme süresi yalnız GÖNDERİLMİŞ bildirime bakar (atlananlar saymaz).
    expect(body, contains('l.shop_id = v.shop_id AND l.skipped IS NULL'));
  });

  test('tablolar: abonelik yalnız kendi satırı okunur, yazma RPC; günlük istemciye kapalı', () {
    expect(sql, contains('ALTER TABLE public.live_subscriptions ENABLE ROW LEVEL SECURITY;'));
    expect(sql, contains('REVOKE ALL ON public.live_subscriptions FROM PUBLIC, anon, authenticated;'));
    expect(sql, contains('GRANT SELECT ON public.live_subscriptions TO authenticated;'));
    expect(sql, contains('USING (user_id = (SELECT auth.uid()));'));
    expect(RegExp(r'ON public\.live_subscriptions\s+FOR (INSERT|UPDATE|DELETE|ALL)').hasMatch(sql), isFalse);
    expect(sql, contains('ALTER TABLE public.live_notify_log ENABLE ROW LEVEL SECURITY;'));
    expect(sql, contains('REVOKE ALL ON public.live_notify_log FROM PUBLIC, anon, authenticated;'));
    expect(RegExp(r'POLICY \w+ ON public\.live_notify_log').hasMatch(sql), isFalse);
  });

  test('RPC\'ler: DEFINER, boş search_path; yönetici kontrolü; yetkiler', () {
    for (final name in [
      'live_shop_subscription(',
      'live_set_subscription(',
      'live_history(',
      'live_session_detail(',
      'live_home_card(',
      'admin_live_options(',
      'admin_set_live_options(',
    ]) {
      final body = _fn(sql, 'CREATE OR REPLACE FUNCTION public.$name', r'$fn$');
      expect(body, contains('SECURITY DEFINER'), reason: name);
      expect(body, contains("SET search_path = ''"), reason: name);
    }
    for (final name in ['admin_live_options(', 'admin_set_live_options(']) {
      expect(
        _fn(sql, 'CREATE OR REPLACE FUNCTION public.$name', r'$fn$'),
        contains('IF NOT public.auth_is_admin() THEN'),
        reason: name,
      );
    }
    expect(
      _fn(sql, 'CREATE OR REPLACE FUNCTION public.live_set_subscription(', r'$fn$'),
      contains("HINT = 'AUTH_REQUIRED'"),
    );
    expect(sql, contains('REVOKE ALL ON FUNCTION public.live_set_subscription(uuid, boolean) FROM PUBLIC, anon;'));
    expect(sql, contains('REVOKE ALL ON FUNCTION public.admin_live_options() FROM PUBLIC, anon;'));
    expect(sql, contains('REVOKE ALL ON FUNCTION public.admin_set_live_options(jsonb) FROM PUBLIC, anon;'));
    expect(sql, contains('GRANT EXECUTE ON FUNCTION public.live_history(integer, integer, uuid) TO anon, authenticated;'));
    expect(sql, contains('GRANT EXECUTE ON FUNCTION public.live_home_card() TO anon, authenticated;'));
  });

  test('geçmiş: sayfa kesimi ile sıra aynı ifade; yalnız aktif+onaylı mağazalar', () {
    final body = _fn(sql, 'CREATE OR REPLACE FUNCTION public.live_history(', r'$fn$');
    expect(body, contains('row_number() OVER (ORDER BY f.ended_at DESC, f.id) AS rn'));
    expect(body, contains('ORDER BY p.rn'));
    expect(body, contains('COALESCE(s.is_active, false)'));
    expect(body, contains('COALESCE(s.is_approved, false)'));
    expect(body, contains('make_interval(days => v_days)'));
  });

  test('yönetici ayarları: anahtarlar ve sınırlar istemciyle aynı', () {
    final setter = _fn(sql, 'CREATE OR REPLACE FUNCTION public.admin_set_live_options(', r'$fn$');
    final service = _read('lib/features/admin/services/admin_live_service.dart');
    for (final key in [
      'notify_enabled',
      'notify_cooldown_hours',
      'notify_followers',
      'notify_product_fans',
      'notify_customers',
      'notify_max_recipients',
      'home_card_enabled',
      'history_days',
    ]) {
      expect(setter, contains("WHEN '$key' THEN 'live_$key'"), reason: key);
      expect(service, contains("json['$key']"), reason: key);
    }
    const cooldown = AdminLiveOptions.cooldownRange;
    const recipients = AdminLiveOptions.maxRecipientsRange;
    const days = AdminLiveOptions.historyDaysRange;
    expect(setter, contains('LEAST(GREATEST(v_num, ${cooldown.min}), ${cooldown.max})'));
    expect(setter, contains('LEAST(GREATEST(v_num, ${recipients.min}), ${recipients.max})'));
    expect(setter, contains('LEAST(GREATEST(v_num, ${days.min}), ${days.max})'));
    expect(sql, contains("private.live_setting_int('live_notify_cooldown_hours', 3, ${cooldown.min}, ${cooldown.max})"));
    expect(sql, contains("private.live_setting_int('live_notify_max_recipients', 2000, ${recipients.min}, ${recipients.max})"));
    expect(sql, contains("private.live_setting_int('live_history_days', 30, ${days.min}, ${days.max})"));
    // app_settings istemci biçimiyle (düz metin) yazılır.
    expect(setter, contains('to_jsonb(v_text)'));
  });

  test('istemci bağlantıları: bildirim türü, rota, tercih, ana sayfa kartı', () {
    expect(sql, contains('ADD COLUMN IF NOT EXISTS live_streams_enabled boolean NOT NULL DEFAULT true;'));
    expect(_read('lib/core/models/notification_preferences_model.dart'), contains("json['live_streams_enabled']"));
    expect(_read('lib/core/services/notification_preferences_service.dart'), contains("case 'live_started':"));
    expect(_read('lib/features/profile/screens/notification_settings_screen.dart'), contains('liveStreamsEnabled'));
    expect(_read('lib/core/models/notification_model.dart'), contains("case 'live_started':"));
    expect(_read('lib/features/market/screens/notifications_screen.dart'), contains("case 'live_started':"));
    expect(_read('lib/core/services/push_notification_service.dart'), contains("'/live/\$entityId'"));
    final main = _read('lib/main.dart');
    expect(main, contains("routeName.startsWith('/live/')"));
    expect(main, contains('LiveSessionRouteScreen(sessionId: sessionId)'));
    final stories = _read('lib/core/widgets/story_card.dart');
    expect(stories, contains('return const LiveHomeStoryCard();'));
    expect(stories, contains('LiveHomeStoryCard(compact: false, width: cardWidth)'));
    final live = _read('lib/features/market/services/live_shopping_service.dart');
    for (final rpc in ['live_history', 'live_home_card', 'live_shop_subscription', 'live_set_subscription']) {
      expect(live, contains("'$rpc'"), reason: rpc);
    }
  });

  test('canlı test tüm kontrolleri içerir', () {
    final live = _read('supabase/tests/manual/live_notifications_history_test.sql');
    for (var i = 1; i <= 13; i++) {
      expect(live, contains('[$i]'), reason: '[$i]');
    }
  });
}
