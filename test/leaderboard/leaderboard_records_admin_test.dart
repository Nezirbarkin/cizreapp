import 'dart:convert';

import 'package:cizreapp/features/admin/widgets/admin_ui.dart';
import 'package:cizreapp/features/admin/widgets/leaderboard_management_content.dart';
import 'package:cizreapp/features/leaderboard/leaderboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Görev 4.4 — admin Liderler Tablosu ekranında "Rakamlarla Sen" sayaçları
/// ve "Rekor Skorlar" anahtarları.
final _writes = <Map<String, dynamic>>[];

Map<String, dynamic> _settings() => {
  'enabled': true,
  'period': 'all',
  'limit': 5,
  'order': <String>[],
  'boards': {for (final b in LeaderboardBoard.values) b.key: true},
  'stats': {for (final s in LeaderboardStat.values) s.key: true},
  'records': {for (final r in LeaderboardRecord.values) r.key: true},
};

MockClient _client() => MockClient((req) async {
  final path = req.url.path;
  Object body = [];
  var status = 200;
  if (path.endsWith('/rpc/leaderboard_settings')) {
    body = _settings();
  } else if (path.endsWith('/rpc/get_leaderboards')) {
    body = {'settings': _settings(), 'boards': {}, 'stats': {}, 'records': {}};
  } else if (path.endsWith('/rest/v1/app_settings') && req.method == 'POST') {
    final decoded = jsonDecode(req.body);
    for (final row in decoded is List ? decoded : [decoded]) {
      _writes.add(Map<String, dynamic>.from(row as Map));
    }
    status = 201;
  }
  return http.Response(
    jsonEncode(body),
    status,
    request: req,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
});

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LeaderboardManagementContent())));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 400, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

Finder _switchOf(String title) => find.descendant(
  of: find.ancestor(of: find.text(title), matching: find.byType(AdminCard)).first,
  matching: find.byType(Switch),
);

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

  setUp(_writes.clear);

  testWidgets('"Rakamlarla Sen" sayaçları kendi bölümünde; kapatınca düz metin yazılır', (tester) async {
    await _open(tester);
    await _scrollTo(tester, find.text('Rakamlarla Sen kartındaki sayılar'));
    expect(find.textContaining('yalnız KENDİ sayılarını görür'), findsOneWidget);

    await _scrollTo(tester, find.text('Aldığın beğeni'));
    await tester.tap(_switchOf('Aldığın beğeni'));
    await tester.pumpAndSettle();
    expect(_writes.last, {'key': 'leaderboard_stat_my_likes', 'value': 'false'});
  });

  testWidgets('"Rekor Skorlar" anahtarları: her rekor ayrı, düz metin', (tester) async {
    await _open(tester);
    await _scrollTo(tester, find.text('Rekor Skorlar kartındaki rekorlar'));

    for (final record in LeaderboardRecord.values) {
      await _scrollTo(tester, find.text(record.label));
      expect(find.text(record.label), findsOneWidget, reason: record.key);
    }

    await _scrollTo(tester, find.text('En kalabalık gün'));
    await tester.tap(_switchOf('En kalabalık gün'));
    await tester.pumpAndSettle();
    expect(_writes.last, {'key': 'leaderboard_record_busiest_day', 'value': 'false'});
  });
}
