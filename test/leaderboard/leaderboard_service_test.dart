import 'dart:convert';

import 'package:cizreapp/features/leaderboard/leaderboard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

var _snapshotCalls = 0;
var _writes = 0;

MockClient _client() => MockClient((req) async {
  final path = req.url.path;
  Object body = [];
  var status = 200;
  if (path.endsWith('/rpc/get_leaderboards')) {
    _snapshotCalls++;
    body = {
      'settings': {
        'enabled': true,
        'period': 'all',
        'limit': 5,
        'order': <String>[],
        'boards': {'top_followed': true},
        'stats': <String, dynamic>{},
      },
      'boards': {
        'top_followed': [
          {
            'r_rank': 1,
            'r_type': 'user',
            'r_id': 'u1',
            'r_name': 'Ayse',
            'r_metric': 19,
          },
        ],
      },
      'stats': <String, dynamic>{},
    };
  } else if (path.endsWith('/rest/v1/app_settings') && req.method == 'POST') {
    _writes++;
    status = 201;
  } else if (path.endsWith('/rpc/leaderboard_set_self_hidden')) {
    body = {'self_hidden': true, 'admin_hidden': false};
  } else if (path.endsWith('/rpc/admin_leaderboard_set_hidden')) {
    body = {};
  }
  return http.Response(
    jsonEncode(body),
    status,
    request: req,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
});

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: _client(),
    );
  });

  setUp(() {
    _snapshotCalls = 0;
    _writes = 0;
    LeaderboardService.invalidateCache();
  });

  test('ardışık çağrılar önbellekten döner (tek sunucu çağrısı)', () async {
    final a = await LeaderboardService.fetchSnapshot();
    final b = await LeaderboardService.fetchSnapshot();
    expect(_snapshotCalls, 1);
    expect(identical(a, b), isTrue);
    expect(a.topEntries(LeaderboardBoard.topFollowed).single.name, 'Ayse');
  });

  test('forceRefresh önbelleği atlar', () async {
    await LeaderboardService.fetchSnapshot();
    await LeaderboardService.fetchSnapshot(forceRefresh: true);
    expect(_snapshotCalls, 2);
  });

  test('admin yazımı önbelleği atar', () async {
    await LeaderboardService.fetchSnapshot();
    await LeaderboardService.setEnabled(false);
    expect(_writes, 1);
    await LeaderboardService.fetchSnapshot();
    expect(_snapshotCalls, 2);
  });

  test('kendini gizleme ve admin gizlemesi önbelleği atar', () async {
    await LeaderboardService.fetchSnapshot();
    final visibility = await LeaderboardService.setSelfHidden(true);
    expect(visibility.selfHidden, isTrue);
    await LeaderboardService.fetchSnapshot();
    expect(_snapshotCalls, 2);

    await LeaderboardService.adminSetHidden('u1', true);
    await LeaderboardService.fetchSnapshot();
    expect(_snapshotCalls, 3);
  });
}
