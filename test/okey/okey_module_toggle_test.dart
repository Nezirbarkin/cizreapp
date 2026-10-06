import 'dart:convert';
import 'dart:io';

import 'package:cizreapp/okey/admin/okey_module_toggle_bar.dart';
import 'package:cizreapp/okey/services/okey_module_service.dart';
import 'package:cizreapp/okey/widgets/okey_module_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/test_fonts.dart';

/// Görev 4.1 — 101 Okey modül anahtarı: kapı (kullanıcı/yönetici), yönetici
/// anahtar şeridi, istemci girişlerinin kapıya bağlanması.

bool _serverEnabled = true;
bool _serverAdmin = false;
final List<http.Request> _requests = [];

void main() {
  setUpAll(() async {
    await loadTestFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-key',
      httpClient: MockClient((req) async {
        _requests.add(req);
        final name = req.url.pathSegments.last;
        final Object? body = switch (name) {
          'okey_module_enabled' => _serverEnabled,
          'auth_is_admin' => _serverAdmin,
          _ => null,
        };
        return http.Response(jsonEncode(body), 200, request: req, headers: {'content-type': 'application/json'});
      }),
      authOptions: const FlutterAuthClientOptions(localStorage: EmptyLocalStorage(), autoRefreshToken: false),
    );
  });

  setUp(() {
    _requests.clear();
    _serverEnabled = true;
    _serverAdmin = false;
    OkeyModuleService.setCacheForTesting(null);
  });

  Future<void> pumpGate(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: OkeyModuleGate(child: Scaffold(body: Text('LOBİ')))),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  testWidgets('açıkken lobi açılır', (tester) async {
    await pumpGate(tester);
    expect(find.text('LOBİ'), findsOneWidget);
    expect(OkeyModuleService.cachedEnabled, isTrue);
  });

  testWidgets('kapalıyken kullanıcıya "şu anda kapalı"; yönetici girer', (tester) async {
    _serverEnabled = false;
    await pumpGate(tester);
    expect(find.text('101 Okey şu anda kapalı'), findsOneWidget);
    expect(find.text('LOBİ'), findsNothing);
    expect(OkeyModuleService.cachedEnabled, isFalse);

    _serverAdmin = true;
    await tester.pumpWidget(const SizedBox());
    await pumpGate(tester);
    expect(find.text('LOBİ'), findsOneWidget, reason: 'yönetici kapalıyken de test edebilir');
  });

  testWidgets('yönetici şeridi: kapatmadan önce onay, kaydeder ve durumu gösterir', (tester) async {
    final saved = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OkeyModuleToggleBar(load: () async => true, save: (v) async => saved.add(v)),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Açık — kullanıcılar oynayabilir'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('101 Okey kapatılsın mı?'), findsOneWidget);
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();
    expect(saved, [false]);
    expect(find.text('Kapalı — girişler gizli, yeni oyun açılamaz'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(saved, [false, true], reason: 'açmak onay istemez');
  });

  test('istemci girişleri kapıdan geçer; liderler tablosu Okey panolarını süzer', () {
    String read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');
    expect(read('lib/main.dart'), contains("'/okey': (context) => const OkeyModuleGate(child: OkeyLobbyScreen()),"));
    final sidebar = read('lib/core/widgets/settings_sidebar.dart');
    expect(sidebar, contains('if (!_hide101OkeyButton && _okeyModuleEnabled)'));
    expect(sidebar, contains('const OkeyModuleGate('));
    final notifications = read('lib/features/market/screens/notifications_screen.dart');
    expect(RegExp('OkeyModuleGate\\(').allMatches(notifications).length, 2);
    expect(read('lib/features/leaderboard/widgets/home_leaderboard_section.dart'),
        contains("if (okeyOn || !board.key.startsWith('okey_')) board,"));
    expect(read('lib/okey/admin/okey_admin_settings_tab.dart'), contains('const OkeyModuleToggleBar(),'));
  });

  test('göç: dört tabloda ekleme koruması, yönetici/sistem serbest', () {
    final sql = File('supabase/migrations/20260928000013_okey_module_toggle.sql')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    for (final table in ['okey_rooms', 'okey_room_players', 'okey_room_spectators', 'okey_room_invites']) {
      expect(sql, contains('BEFORE INSERT ON public.$table'));
    }
    expect(sql, contains('IF public.okey_module_enabled() OR auth.uid() IS NULL OR public.auth_is_admin() THEN'));
    expect(sql, contains("HINT = 'OKEY_DISABLED'"));
    expect(sql, contains('GRANT EXECUTE ON FUNCTION public.okey_module_enabled() TO anon, authenticated;'));
    final live = File('supabase/tests/manual/okey_module_toggle_test.sql').readAsStringSync();
    for (var i = 1; i <= 4; i++) {
      expect(live, contains('[$i]'));
    }
  });
}
