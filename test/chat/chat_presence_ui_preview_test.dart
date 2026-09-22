// EKRAN ÖNİZLEMELERİ — Sohbet durumu (son görülme / çevrimiçi / yazıyor) ekranlarının
// PNG'sini üretir.
//
//   flutter test test/chat/chat_presence_ui_preview_test.dart --update-goldens
//
// KARŞILAŞTIRMA YAPMAZ, YALNIZCA ÜRETİR (leaderboard_ui_preview_test.dart ile aynı
// gerekçe): golden karşılaştırması yazı tipi/GPU farklarına duyarlıdır. Bayrak
// verilmezse hiçbir şey yapmaz.
@Tags(['preview'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:cizreapp/core/providers/theme_provider.dart';
import 'package:cizreapp/features/admin/widgets/chat_presence_settings_content.dart';
import 'package:cizreapp/features/chat/models/chat_presence.dart';
import 'package:cizreapp/features/chat/screens/chat_detail_screen.dart';
import 'package:cizreapp/features/chat/screens/chat_privacy_settings_screen.dart';
import 'package:cizreapp/features/chat/services/user_presence_service.dart';
import 'package:cizreapp/features/chat/widgets/presence_status_line.dart';
import 'package:cizreapp/features/profile/widgets/profile_shared_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> _loadFonts() async {
  const base = 'C:/flutter/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final file = File('$base/$f');
      if (!file.existsSync()) continue;
      loader.addFont(file.readAsBytes().then((b) => ByteData.view(b.buffer)));
    }
    await loader.load();
  }

  await load('Roboto', [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
  ]);
  await load('MaterialIcons', ['materialicons-regular.otf']);
}

// --- sahte sunucu ------------------------------------------------------------

String _presenceMode = 'online'; // online | seen | hidden
Map<String, dynamic> _cfg = {
  'last_seen': true,
  'last_seen_in_chat': true,
  'last_seen_in_profile': true,
  'last_seen_max_days': 7,
  'online': true,
  'typing': true,
  'typing_in_groups': true,
};
Map<String, dynamic> _profile = {
  'show_last_seen': true,
  'last_seen_friends_only': false,
  'show_typing_indicator': true,
  'is_online_enabled': true,
  'is_ghost_mode': false,
};

MockClient _mock() => MockClient((req) async {
  final name = req.url.pathSegments.last;
  Object body = [];
  switch (name) {
    case 'get_chat_presence_settings':
      body = _cfg;
    case 'admin_chat_presence_stats':
      body = {
        'total': 173,
        'online_now': 4,
        'last_seen_hidden': 12,
        'last_seen_friends': 7,
        'typing_off': 3,
        'ghost': 2,
        'online_off': 5,
      };
    case 'get_my_profile':
      body = _profile;
    case 'get_typing_channel':
      body = {'topic': null, 'send': false};
    case 'get_user_presence':
      final ids = (jsonDecode(req.body)['p_user_ids'] as List).cast<String>();
      body = [
        for (final id in ids)
          switch (_presenceMode) {
            'online' => {
              'user_id': id,
              'can_see_online': true,
              'online': true,
              'last_seen': DateTime.now().toUtc().toIso8601String(),
            },
            'seen' => {
              'user_id': id,
              'can_see_online': true,
              'online': false,
              'last_seen': DateTime.now()
                  .toUtc()
                  .subtract(const Duration(days: 1, hours: 2))
                  .toIso8601String(),
            },
            _ => {
              'user_id': id,
              'can_see_online': false,
              'online': false,
              'last_seen': null,
            },
          },
      ];
  }
  return http.Response(
    jsonEncode(body),
    200,
    request: req,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
});

ThemeData get _theme => ThemeData(
  useMaterial3: true,
  fontFamily: 'Roboto',
  scaffoldBackgroundColor: const Color(0xFFF7F7FA),
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFD91A73)),
);

Future<void> _open(WidgetTester tester, Widget home, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme,
        home: home,
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _shot(String file) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile(file));

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: _mock(),
    );
  });

  setUp(() {
    UserPresenceService.instance.reset();
    _presenceMode = 'online';
  });

  ChatDetailScreen chat() => const ChatDetailScreen(
    conversationId: 'c1',
    otherUserId: 'peer',
    otherUserName: 'Ayşe Yılmaz',
  );

  testWidgets('sohbet ekranı — çevrimiçi', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    _presenceMode = 'online';
    await _open(tester, chat(), const Size(390, 300));
    await _shot('preview_presence_chat_online.png');
  });

  testWidgets('sohbet ekranı — son görülme', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    _presenceMode = 'seen';
    await _open(tester, chat(), const Size(390, 300));
    await _shot('preview_presence_chat_seen.png');
  });

  testWidgets('sohbet ekranı — gizli (hiçbir şey gösterilmez)', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    _presenceMode = 'hidden';
    await _open(tester, chat(), const Size(390, 300));
    await _shot('preview_presence_chat_hidden.png');
  });

  testWidgets('sohbet başlığı — yazıyor (yakın çekim)', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    final typing = ValueNotifier<bool>(true);
    await _open(
      tester,
      Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFFD91A73),
          foregroundColor: Colors.white,
          title: Row(
            children: [
              const CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white24,
                child: Text('A', style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ayşe Yılmaz',
                      style: TextStyle(fontSize: 18, height: 1.15),
                    ),
                    PresenceStatusLine(userId: 'peer', typing: typing),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const Size(390, 120),
    );
    await _shot('preview_presence_chat_typing.png');
  });

  testWidgets('profil — çevrimiçi ve son görülme', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    Widget header(String mode) => ProfileIdentityHeader(
      userId: 'peer-$mode',
      username: 'ayse',
      fullName: 'Ayşe Yılmaz',
      avatarUrl: null,
      bio: 'Cizre\'de yaşıyorum. Kitap ve kahve.',
      hasStories: false,
      postsCount: 12,
      followersCount: 340,
      followingCount: 180,
      friendsCount: 96,
      onAvatarTap: () {},
      onFollowersTap: () {},
      onFollowingTap: () {},
      onFriendsTap: () {},
      presenceLine: PresenceStatusLine(
        userId: 'peer-$mode',
        presenceContext: PresenceContext.profile,
        style: PresenceLineStyle.onLight,
        fontSize: 12.5,
        showClockIcon: true,
      ),
    );

    _presenceMode = 'online';
    await _open(tester, Scaffold(body: header('online')), const Size(390, 130));
    await _shot('preview_presence_profile_online.png');

    UserPresenceService.instance.reset();
    _presenceMode = 'seen';
    await _open(tester, Scaffold(body: header('seen')), const Size(390, 130));
    await _shot('preview_presence_profile_seen.png');
  });

  testWidgets('kullanıcı gizlilik ekranı', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    _profile = {..._profile, 'last_seen_friends_only': true};
    await _open(tester, const ChatPrivacySettingsScreen(), const Size(390, 1150));
    await _shot('preview_presence_user_privacy.png');
  });

  testWidgets('kullanıcı gizlilik ekranı — yönetici kapattı', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    _cfg = {..._cfg, 'last_seen': false, 'typing': false};
    await _open(tester, const ChatPrivacySettingsScreen(), const Size(390, 1250));
    await _shot('preview_presence_user_privacy_admin_off.png');
    _cfg = {..._cfg, 'last_seen': true, 'typing': true};
  });

  testWidgets('admin — sohbet durumu', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    await _open(
      tester,
      const Scaffold(body: ChatPresenceSettingsContent()),
      const Size(390, 1900),
    );
    await _shot('preview_presence_admin.png');
  });

  testWidgets('admin — 9 gün önce senaryosu (7 günlük sınırda gizli)', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    await _open(
      tester,
      const Scaffold(body: ChatPresenceSettingsContent()),
      const Size(390, 640),
    );
    await tester.tap(find.text('9 gün önce'));
    await tester.pumpAndSettle();
    await _shot('preview_presence_admin_old.png');
  });
}
