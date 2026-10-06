import 'dart:convert';

import 'package:cizreapp/okey/admin/okey_admin_design_tab.dart';
import 'package:cizreapp/okey/screens/okey_lobby_screen.dart';
import 'package:cizreapp/okey/services/okey_guest_auth.dart';
import 'package:cizreapp/okey/theme/okey_design.dart';
import 'package:cizreapp/okey/widgets/okey_appearance_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// TASARIM SİSTEMİ v6 — DOLU lobi, her tasarım × her düzen.
///
/// okey_screens_overflow_test.dart lobiyi Supabase'siz, yani BOŞ çizer.
/// Arena ızgarası, canlı masa şeridi, kompakt liste, davet ve "devam et"
/// kartları ancak veriyle görünür; bu dosya sahte bir sunucuyla (MockClient)
/// lobiyi doldurur ve taşmayı en kötü içerikle (uzun ad, 6 haneli bedel,
/// büyük yazı) ölçer.

const _longName = 'ÇokUzunOyuncuAdıTaşmaTestiİçinYazıldı';

Map<String, dynamic> _room(
  int i, {
  String status = 'waiting',
  String team = 'essiz',
  String mode = 'katlamasiz',
  int fee = 50,
  int hands = 3,
  int seated = 1,
  int bots = 0,
  int spectators = 0,
  String? match,
}) => {
  'id': 'room-$i',
  'created_by': 'u$i',
  'status': status,
  'is_private': false,
  'join_code': null,
  'max_score': 1000,
  'turn_seconds': 30,
  'game_mode': mode,
  'team_mode': team,
  'assist_mode': i.isEven ? 'yardimli' : 'yardimsiz',
  'entry_fee': fee,
  'total_hands': hands,
  'current_match_id': match,
  'created_at': '2026-10-05T10:00:00Z',
  'seated_count': seated,
  'bot_count': bots,
  'creator_name': i == 0 ? _longName : 'Oyuncu $i',
  'creator_avatar': null,
  'spectator_count': spectators,
};

http.Response _json(http.Request req, Object? body) => http.Response(
  jsonEncode(body),
  200,
  request: req,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

MockClient _server() => MockClient((req) async {
  final name = req.url.pathSegments.last;
  switch (name) {
    case 'okey_list_open_rooms':
      return _json(req, [
        _room(0, fee: 25000, hands: 9),
        _room(1, team: 'esli', seated: 2),
        _room(2, mode: 'katlamali', seated: 3, bots: 0),
        _room(3, fee: 0),
        _room(4, team: 'esli', mode: 'katlamali', seated: 1, bots: 2),
      ]);
    case 'okey_list_live_rooms':
      return _json(req, [
        _room(
          10,
          status: 'in_progress',
          seated: 4,
          spectators: 12,
          match: 'm1',
        ),
        _room(11, status: 'in_progress', seated: 2, bots: 2, match: 'm2'),
        _room(12, status: 'in_progress', team: 'esli', seated: 4, match: 'm3'),
      ]);
    case 'okey_my_active_room':
      return _json(req, [
        _room(20, status: 'in_progress', seated: 4, match: 'm20'),
      ]);
    case 'okey_my_room_invites':
      return _json(req, [
        {
          'invite_id': 'inv-1',
          'room_id': 'room-1',
          'inviter_id': 'u9',
          'inviter_name': _longName,
          'inviter_avatar': null,
          'table_stake': 150000,
          'total_hands': 9,
          'seated_count': 3,
          'created_at': '2026-10-05T10:00:00Z',
        },
      ]);
    case 'okey_get_wallet':
      return _json(req, [
        {
          'points': 1234567,
          'can_claim_hourly': true,
          'seconds_until_next_gift': 0,
          'hourly_gift_points': 100,
          'ad_reward_points': 250,
        },
      ]);
    default:
      return _json(req, []);
  }
});

const _sizes = <String, Size>{
  '320x568': Size(320, 568),
  '360x640': Size(360, 640),
  '411x731': Size(411, 731),
  'yatay 731x411': Size(731, 411),
  'tablet 768x1024': Size(768, 1024),
};

Future<void> _pumpLobby(
  WidgetTester tester, {
  required Size size,
  required double textScale,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: OkeyLobbyScreen(),
      ),
    ),
  );
  // Sağlayıcılar ilk yüklemeyi mikro göreve erteler; sahte sunucu yanıtları
  // birkaç karede gelir. pumpAndSettle YOK: giriş animasyonları sürer.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _server(),
    );
  });

  setUp(() {
    OkeyGuestAuth.debugSessionOverride = true;
  });

  tearDown(() {
    OkeyGuestAuth.debugSessionOverride = null;
    OkeyDesignPrefs.instance.debugReset();
  });

  group('Dolu lobi hiçbir tasarım/düzen/boyutta taşmaz', () {
    for (final design in OkeyDesign.all) {
      for (final layout in OkeyLobbyLayout.values) {
        for (final entry in _sizes.entries) {
          for (final scale in const [1.0, 1.5]) {
            testWidgets(
              '${design.key} · ${layout.name} · ${entry.key} · ${scale}x',
              (tester) async {
                OkeyDesignPrefs.instance.debugReset(
                  admin: OkeyDesignConfig(
                    designKey: design.key,
                    layout: layout,
                  ),
                );
                await _pumpLobby(tester, size: entry.value, textScale: scale);
                expect(tester.takeException(), isNull);
                // Davet, devam et ve masa kartları gerçekten çizildi mi —
                // boş lobiyi ölçmek bu testin amacı değil.
                expect(find.textContaining('seni davet etti'), findsOneWidget);
                expect(
                  find.textContaining('kaldığın yerden devam et'),
                  findsOneWidget,
                );
                await tester.pumpWidget(const SizedBox());
              },
            );
          }
        }
      }
    }
  });

  group('Düzenlerin kendine özgü parçaları', () {
    Future<void> pumpWith(WidgetTester tester, OkeyLobbyLayout layout) async {
      OkeyDesignPrefs.instance.debugReset(
        admin: OkeyDesignConfig(designKey: 'salon', layout: layout),
      );
      await _pumpLobby(tester, size: const Size(411, 2400), textScale: 1);
    }

    testWidgets('Salon: "Hemen oyna" afişi ve tek liste', (tester) async {
      await pumpWith(tester, OkeyLobbyLayout.salon);
      expect(find.text('Hemen oyna'), findsOneWidget);
      expect(find.text('OTOMATİK EŞLEŞ'), findsOneWidget);
      // 3 canlı + 5 açık masa aynı listede.
      expect(find.text('İZLE'), findsNWidgets(3));
      expect(find.text('OTUR'), findsNWidgets(5));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Arena: istatistik afişi, hızlı kutular, canlı şerit, ızgara', (
      tester,
    ) async {
      await pumpWith(tester, OkeyLobbyLayout.arena);
      expect(find.text('HEMEN OYNA'), findsOneWidget);
      expect(find.text('1.234.567'), findsWidgets, reason: 'çip sayacı');
      expect(find.text('Kodla katıl'), findsOneWidget);
      expect(find.text('ŞU AN OYNANANLAR'), findsOneWidget);
      expect(find.text('AÇIK MASALAR'), findsOneWidget);
      expect(find.text('OTUR'), findsNWidgets(5));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Kompakt: sekmeler ve sabit alt çubuk', (tester) async {
      await pumpWith(tester, OkeyLobbyLayout.kompakt);
      expect(find.text('HEMEN OYNA'), findsOneWidget);
      expect(find.byTooltip('Masa kur'), findsOneWidget);
      expect(find.text('Açık masalar'), findsOneWidget);
      // Açık sekmede 5 satır; canlı sekmeye geçince 3.
      expect(find.textContaining('Oyuncu'), findsWidgets);
      await tester.tap(find.text('Canlı'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('CANLI'), findsNWidgets(3));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('cümle düzenli tasarımda düğmeler "Hemen oyna" yazar', (
      tester,
    ) async {
      OkeyDesignPrefs.instance.debugReset(
        admin: const OkeyDesignConfig(designKey: 'ege'),
      );
      await _pumpLobby(tester, size: const Size(411, 2400), textScale: 1);
      expect(find.text('Hemen oyna'), findsOneWidget);
      expect(find.text('HEMEN OYNA'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Görünüm sayfası', () {
    testWidgets('oyuncu tasarım seçince lobi yeni tasarımla kurulur', (
      tester,
    ) async {
      OkeyDesignPrefs.instance.debugReset();
      await _pumpLobby(tester, size: const Size(411, 900), textScale: 1);
      await tester.tap(find.byTooltip('Görünüm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(OkeyAppearanceSheet), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Yatay listenin görünür ikinci kartı (tembel liste: ekran dışındaki
      // kartlar henüz kurulmamıştır).
      await tester.tap(find.text('Zümrüt Kulüp'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(OkeyDesignPrefs.instance.current.value, OkeyDesign.zumrut);
      // Lobi arkada ARENA düzeniyle yeniden kuruldu.
      expect(find.text('Kodla katıl', skipOffstage: false), findsWidgets);
      expect(find.textContaining('Yöneticinin seçimine dön'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.textContaining('Yöneticinin seçimine dön'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(OkeyDesignPrefs.instance.current.value, OkeyDesign.salon);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('yönetici kilitliyse Görünüm düğmesi yok', (tester) async {
      OkeyDesignPrefs.instance.debugReset(
        admin: const OkeyDesignConfig(designKey: 'saray', userChoice: false),
      );
      await _pumpLobby(tester, size: const Size(411, 900), textScale: 1);
      expect(find.byTooltip('Görünüm'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Admin › Tasarım sekmesi', () {
    Future<List<OkeyDesignConfig>> pumpTab(
      WidgetTester tester, {
      Size size = const Size(411, 3000),
      double textScale = 1,
      OkeyDesignConfig initial = OkeyDesignConfig.defaults,
    }) async {
      final saved = <OkeyDesignConfig>[];
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: MaterialApp(
            home: Scaffold(
              body: OkeyAdminDesignTab(
                load: () async => initial,
                save: (c) async => saved.add(c),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      return saved;
    }

    for (final size in const [
      Size(320, 568),
      Size(411, 731),
      Size(1280, 800),
    ]) {
      for (final scale in const [1.0, 1.5]) {
        testWidgets(
          'taşmaz — ${size.width.toInt()}x${size.height.toInt()} · ${scale}x',
          (tester) async {
            await pumpTab(tester, size: size, textScale: scale);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('yedi tasarım kartı, aktif olan işaretli', (tester) async {
      await pumpTab(tester);
      for (final d in OkeyDesign.all) {
        expect(find.text(d.label), findsWidgets, reason: d.key);
      }
      expect(find.text('Aktif'), findsOneWidget);
      expect(find.text('Uygula'), findsNWidgets(OkeyDesign.all.length - 1));
    });

    testWidgets('tasarım uygulama onay ister ve kaydeder', (tester) async {
      final saved = await pumpTab(tester);
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Uygula').at(2),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Uygula').at(2));
      await tester.pumpAndSettle();
      expect(find.textContaining('uygulansın mı?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Uygula').last);
      await tester.pumpAndSettle();
      expect(saved.single.designKey, OkeyDesign.all[3].key);
      expect(saved.single.userChoice, isTrue);
    });

    testWidgets('düzen ve oyuncu seçimi anahtarı kaydedilir', (tester) async {
      final saved = await pumpTab(tester);
      await tester.tap(find.text('Arena'));
      await tester.pumpAndSettle();
      expect(saved.last.layout, OkeyLobbyLayout.arena);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(saved.last.userChoice, isFalse);
      expect(saved.last.layout, OkeyLobbyLayout.arena);
      await tester.tap(find.text('Tasarıma göre'));
      await tester.pumpAndSettle();
      expect(saved.last.layout, isNull);
    });
  });
}
