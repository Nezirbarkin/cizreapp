import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ana sayfada biten yayın 24 saat (hikâye gibi) + "Yayınlarım" göçü
/// (20261004000003) sözleşmesi. Davranış canlıda
/// `supabase/tests/manual/live_home_story_window_test.sql` ile doğrulanır.
String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _fn(String sql, String header, String tag) {
  final start = sql.indexOf(header);
  expect(start, isNonNegative, reason: header);
  final end = sql.indexOf('$tag;', start);
  return sql.substring(start, end + tag.length + 1);
}

/// Fonksiyonu en son (dosya adı sırasıyla) yeniden tanımlayan göç.
String _latestDefinition(String header) {
  final files = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  String? latest;
  for (final file in files) {
    final sql = _read(file.path);
    if (sql.contains(header)) latest = _fn(sql, header, r'$fn$');
  }
  expect(latest, isNotNull, reason: header);
  return latest!;
}

const _homeHeader = 'CREATE OR REPLACE FUNCTION public.live_home_card()';
const _window =
    '     -- Hikâye gibi: biten yayın ana sayfada 24 saat kalır (sahibi "Yayınlarım"da görür).\n'
    "     AND ls.ended_at > now() - interval '24 hours'\n";

void main() {
  final sql = _read('supabase/migrations/20261004000003_live_home_story_window_and_my_history.sql');

  test('ana sayfa kartı: kullanıcı yayını tanımı + yalnız 24 saat satırı', () {
    final previous = _fn(_read('supabase/migrations/20261004000001_user_live_streams.sql'), _homeHeader, r'$fn$');
    final current = _fn(sql, _homeHeader, r'$fn$');
    expect(current, contains(_window));
    final restored = current.replaceFirst(
      _window,
      '     AND ls.ended_at > now() - make_interval(days => private.live_history_days())\n',
    );
    expect(restored, previous);
    // Canlı yayın seçimi ve görünürlük süzgeci aynen duruyor.
    expect(current, contains('private.live_session_listable(ls.shop_id, ls.host_user_id, v_uid)'));
  });

  test('sonraki göçler 24 saat kuralını geri almamalı (en son tanım)', () {
    final latest = _latestDefinition(_homeHeader);
    expect(latest, contains("AND ls.ended_at > now() - interval '24 hours'"));
    expect(latest, isNot(contains('make_interval(days => private.live_history_days())')));
  });

  test('Yayınlarım: oturum şart, yalnız kendi biten yayınları, süre sınırı yok', () {
    final body = _latestDefinition('CREATE OR REPLACE FUNCTION public.live_my_history(');
    expect(body, contains('SECURITY DEFINER'));
    expect(body, contains("SET search_path = ''"));
    expect(body, contains("HINT = 'AUTH_REQUIRED'"));
    expect(body.indexOf('AUTH_REQUIRED'), lessThan(body.indexOf('FROM public.live_sessions ls')));
    expect(body, contains('WHERE ls.host_user_id = v_uid'));
    expect(body, contains("AND ls.status = 'ended'"));
    expect(body, contains('AND ls.started_at IS NOT NULL'));
    expect(body, isNot(contains('ended_at > now()')), reason: 'süre sınırı yok');
    expect(body, isNot(contains('live_session_listable')), reason: 'sahibi gizli/pasif kendi yayınını da görür');
    // Sayfa kesimi ile sayfa içi sıra aynı ifade.
    expect(body, contains('row_number() OVER (ORDER BY f.ended_at DESC, f.id) AS rn'));
    expect(body, contains('ORDER BY p.rn'));
    expect(body, contains('LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50)'));
  });

  test('yetkiler: Yayınlarım misafire kapalı; kart herkese açık', () {
    expect(sql, contains('REVOKE ALL ON FUNCTION public.live_my_history(integer, integer) FROM PUBLIC, anon;'));
    expect(sql, contains('GRANT EXECUTE ON FUNCTION public.live_my_history(integer, integer) TO authenticated;'));
    expect(sql, contains('GRANT EXECUTE ON FUNCTION public.live_home_card() TO anon, authenticated;'));
  });

  test('bildirim değişmedi: kullanıcı yayınında yalnız takipçi dalı dolu', () {
    expect(sql, isNot(contains('live_notify_started')), reason: 'bu göç bildirime dokunmaz');
    final notify = _latestDefinition('CREATE OR REPLACE FUNCTION private.live_notify_started(');
    // Mağazasız yayında shop_id NULL: abone/ürün/müşteri dalları eşleşmez.
    expect(notify, contains('WHERE sub.shop_id = v.shop_id'));
    expect(notify, contains('WHERE v_fans AND pr.shop_id = v.shop_id'));
    expect(notify, contains('WHERE v_customers AND o.shop_id = v.shop_id'));
    expect(notify, contains('WHERE v_followers AND f.following_id = v.owner_id'));
    expect(notify, contains('COALESCE(s.owner_id, ls.host_user_id) AS owner_id'));
  });

  test('istemci bağlantıları', () {
    expect(_read('lib/features/market/services/live_shopping_service.dart'), contains("'live_my_history'"));
    final sessions = _read('lib/features/market/screens/live_sessions_screen.dart');
    expect(sessions, contains("tooltip: 'Yayınlarım'"));
    expect(sessions, contains('if (_service.currentUserId != null)'));
    expect(sessions, contains('MyLiveStreamsScreen(service: widget.service)'));
    expect(_read('lib/features/market/screens/my_live_streams_screen.dart'), contains('fetchMyHistory('));
  });

  test('canlı test tüm kontrolleri içerir', () {
    final live = _read('supabase/tests/manual/live_home_story_window_test.sql');
    for (var i = 1; i <= 10; i++) {
      expect(live, contains('[$i]'), reason: '[$i]');
    }
  });
}
