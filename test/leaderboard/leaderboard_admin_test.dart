import 'dart:convert';

import 'package:cizreapp/features/admin/widgets/leaderboard_management_content.dart';
import 'package:cizreapp/features/leaderboard/leaderboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sahte sunucu: `app_settings` yazımlarını kaydeder ve sıra anahtarını sonraki
/// okumalara yansıtır (gerçek `leaderboard_settings()` gibi).
class _FakeServer {
  final writes = <Map<String, dynamic>>[];
  String orderSetting = '';
  bool failWrites = false;

  List<String> get order => orderSetting.isEmpty
      ? []
      : orderSetting.split(',').where((e) => e.isNotEmpty).toList();

  Map<String, dynamic> settingsJson() => {
    'enabled': true,
    'period': 'all',
    'limit': 5,
    'order': order,
    'boards': {for (final b in LeaderboardBoard.values) b.key: true},
    'stats': {for (final s in LeaderboardStat.values) s.key: true},
  };

  MockClient client() => MockClient((req) async {
    final path = req.url.path;
    Object body = [];
    var status = 200;

    if (path.endsWith('/rpc/leaderboard_settings')) {
      body = settingsJson();
    } else if (path.endsWith('/rpc/get_leaderboards')) {
      body = {'settings': settingsJson(), 'boards': {}, 'stats': {}};
    } else if (path.endsWith('/rest/v1/app_settings') && req.method == 'POST') {
      if (failWrites) {
        return http.Response(
          jsonEncode({'message': 'yetkisiz', 'code': '42501'}),
          403,
          request: req,
          headers: {'content-type': 'application/json'},
        );
      }
      final decoded = jsonDecode(req.body);
      final rows = decoded is List ? decoded : [decoded];
      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        writes.add(map);
        if (map['key'] == 'leaderboard_order') {
          orderSetting = map['value'] as String;
        }
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
}

late _FakeServer _server;

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: LeaderboardManagementContent())),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

/// Kart satırlarının ekrandaki sırası (yukarıdan aşağı).
List<String> _visibleOrder(WidgetTester tester) {
  final tiles = <(double, String)>[];
  for (final board in LeaderboardBoard.values) {
    final finder = find.byKey(ValueKey('lb-card-${board.key}'));
    if (finder.evaluate().isEmpty) continue;
    tiles.add((tester.getTopLeft(finder).dy, board.key));
  }
  tiles.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final t in tiles) t.$2];
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    _server = _FakeServer();
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: _server.client(),
    );
  });

  setUp(() {
    _server
      ..writes.clear()
      ..orderSetting = ''
      ..failWrites = false;
  });

  testWidgets('kartlar varsayılan sırayla, sıra numaralarıyla listelenir', (
    tester,
  ) async {
    await _open(tester);
    expect(_visibleOrder(tester).first, 'stats');
    expect(find.text('1. Rakamlarla Cizre'), findsOneWidget);
    expect(find.text('2. Bugün Cizre’de'), findsOneWidget);
    expect(find.text('3. Yeni Üyeler'), findsOneWidget);
    // Liste tembel kurulur (yalnız ekrana yakın kartlar); görünenlerin hepsinde
    // sürükleme tutamacı var.
    expect(
      find.byIcon(Icons.drag_indicator_rounded),
      findsNWidgets(_visibleOrder(tester).length),
    );
    expect(_visibleOrder(tester).length, greaterThan(3));
  });

  testWidgets('bir kartı sürükleyip bırakınca yeni sıra DÜZ metinle kaydedilir', (
    tester,
  ) async {
    await _open(tester);
    final before = _visibleOrder(tester);

    // İlk kartın tutamacını iki satırdan fazla aşağı sürükle (test yazı tipinde
    // satırlar ~130 px; bir sonrakinin ortasını geçmesi gerekir).
    await tester.drag(
      find.byIcon(Icons.drag_indicator_rounded).first,
      const Offset(0, 330),
    );
    await tester.pumpAndSettle();

    final orderWrites = _server.writes
        .where((w) => w['key'] == 'leaderboard_order')
        .toList();
    expect(orderWrites, hasLength(1));

    final saved = orderWrites.single['value'] as String;
    // Düz metin: tırnaklı ('"a,b"') olsaydı jsonb'de tırnak kalıp sunucu okuyucuları
    // bozulurdu (bkz. reference_app_settings_jsonb_write_format).
    expect(saved.startsWith('"'), isFalse);
    final keys = saved.split(',');
    expect(keys.toSet(), LeaderboardBoard.values.map((b) => b.key).toSet());
    expect(keys.length, LeaderboardBoard.values.length);
    expect(keys.first, isNot('stats'), reason: 'ilk kart aşağı taşındı');

    // Ekran da yeni sırayı gösterir ve kaydedilenle aynıdır.
    final after = _visibleOrder(tester);
    expect(after, isNot(before));
    // Liste tembel kurulduğu için yalnız görünen baş kısım karşılaştırılır.
    expect(after, keys.take(after.length).toList());
  });

  testWidgets('kaydedilemezse eski sıraya döner ve uyarır', (tester) async {
    await _open(tester);
    final before = _visibleOrder(tester);
    _server.failWrites = true;

    await tester.drag(
      find.byIcon(Icons.drag_indicator_rounded).first,
      const Offset(0, 330),
    );
    await tester.pumpAndSettle();

    expect(_visibleOrder(tester), before);
    expect(find.textContaining('Sıra kaydedilemedi'), findsOneWidget);
  });

  testWidgets('kart anahtarı düz "true"/"false" yazar', (tester) async {
    await _open(tester);
    // Sayaç kartının anahtarı (ilk kart satırındaki Switch).
    final firstCardSwitch = find.descendant(
      of: find.byKey(const ValueKey('lb-card-stats')),
      matching: find.byType(Switch),
    );
    await tester.tap(firstCardSwitch);
    await tester.pumpAndSettle();

    final write = _server.writes.singleWhere(
      (w) => w['key'] == 'leaderboard_board_stats',
    );
    expect(write['value'], 'false');
  });
}
