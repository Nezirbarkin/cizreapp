// EKRAN ÖNİZLEMELERİ — Liderler Tablosu'nun PNG'sini üretir.
//
//   flutter test test/leaderboard/leaderboard_ui_preview_test.dart --update-goldens
//
// KARŞILAŞTIRMA YAPMAZ, YALNIZCA ÜRETİR (music_ui_preview_test.dart ile aynı
// gerekçe): golden karşılaştırması yazı tipi/GPU farklarına duyarlıdır.
// Veriler canlı veritabanından alınan gerçek panolardır (2026-09-21).
@Tags(['preview'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:cizreapp/features/admin/widgets/leaderboard_management_content.dart';
import 'package:cizreapp/features/leaderboard/leaderboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

LeaderboardEntry _u(
  int rank,
  String name,
  String handle,
  double? metric, {
  DateTime? at,
  bool me = false,
  double? extra,
}) => LeaderboardEntry(
  rank: rank,
  type: LeaderboardEntityType.user,
  id: 'u$rank',
  name: name,
  handle: handle,
  metric: metric,
  extra: extra,
  at: at,
  isMe: me,
);

LeaderboardEntry _shop(int rank, String name, double metric, {double? extra}) =>
    LeaderboardEntry(
      rank: rank,
      type: LeaderboardEntityType.shop,
      id: 's$rank',
      name: name,
      metric: metric,
      extra: extra,
    );

LeaderboardEntry _post(int rank, String text, String handle, double metric) =>
    LeaderboardEntry(
      rank: rank,
      type: LeaderboardEntityType.post,
      id: 'p$rank',
      name: text,
      handle: handle,
      metric: metric,
      ownerId: 'o$rank',
    );

final _now = DateTime.now();

/// Canlı verilerden (2026-09-21). Sıra: admin'in belirlediği kart sırası.
final Map<LeaderboardBoard, List<LeaderboardEntry>> _data = {
  LeaderboardBoard.newMembers: [
    _u(
      1,
      'burak bolat',
      '@bareking',
      null,
      at: _now.subtract(const Duration(hours: 5)),
    ),
    _u(
      2,
      'Mahsun Sarıca',
      '@mahsun73.',
      null,
      at: _now.subtract(const Duration(days: 2)),
    ),
    _u(
      3,
      'ibrahim',
      '@salipazari',
      null,
      at: _now.subtract(const Duration(days: 3)),
    ),
    _u(
      4,
      'Ensar Müldür',
      '@ensar',
      null,
      at: _now.subtract(const Duration(days: 4)),
    ),
    _u(
      5,
      'Nezir Barkın',
      '@cizre',
      null,
      at: _now.subtract(const Duration(days: 5)),
    ),
  ],
  LeaderboardBoard.topFollowed: [
    _u(1, 'Nezir Barkın', '@test', 19),
    _u(2, 'CizreApp', '@cizreapp', 19),
    _u(3, 'Eyüp bilgin barkın', '@bilginbarkın', 15),
    _u(4, 'Zeynepp', '@zeynepp', 14),
    _u(5, 'Elif Barkın', '@eliff', 12),
    _u(9, 'Sen', '@sen', 7, me: true),
  ],
  LeaderboardBoard.topLikedPosts: [
    _post(
      1,
      'o sırada uygulamanın ne işe yaradığını anlamayan ben',
      '@sahinmbrz',
      9,
    ),
    _post(2, 'Cizre’de bugün hava çok güzel, herkese günaydın', '@zeynepp', 7),
    _post(3, 'Fotoğraflı gönderi', '@ruzgarsuaritma', 6),
  ],
  LeaderboardBoard.topViewedStories: const [],
  LeaderboardBoard.topSellers: [
    _shop(1, 'CizreApp', 13),
    _shop(2, 'GOLD MEDYA', 9),
    _shop(3, 'Asır Kuruyemiş & Aktar', 3),
  ],
  LeaderboardBoard.topRatedShops: [
    _shop(1, 'CizreApp', 5.0, extra: 7),
    _shop(2, 'GOLD MEDYA', 5.0, extra: 2),
    _shop(3, 'Asır Kuruyemiş & Aktar', 4.0, extra: 1),
  ],
  LeaderboardBoard.topProductSellers: [
    _shop(1, 'Asır Kuruyemiş & Aktar', 59),
    _shop(2, 'CİZRE Züccaciye', 16),
  ],
  LeaderboardBoard.topLogins: [_u(1, 'Nezir Barkın', '@test', 8)],
  // 101 Okey (canlı: okey_stats / okey_wallets)
  LeaderboardBoard.okeyMostWins: [
    _u(1, 'Nezir Barkın', '@test', 55),
    _u(2, 'CizreApp', '@cizreapp', 5),
    _u(3, 'Ahmet', '@hesap', 2),
    _u(4, 'test1', '@test1', 2),
  ],
  LeaderboardBoard.okeyWinRate: [
    _u(1, 'CizreApp', '@cizreapp', 71.4, extra: 7),
    _u(2, 'Nezir Barkın', '@test', 36.4, extra: 151),
    _u(3, 'test1', '@test1', 33.3, extra: 6),
  ],
  LeaderboardBoard.okeyRichest: [
    _u(1, 'Nezir Barkın', '@test', 9610),
    _u(2, 'CizreApp', '@cizreapp', 2710),
    _u(3, 'Fatma', '@fatmabrk', 1100),
    _u(4, 'Hüseyin', '@hess', 1000),
    _u(5, 'Mslm', '@mslm', 700),
    _u(8, 'Sen', '@sen', 650, me: true),
  ],
  LeaderboardBoard.okeyBestScore: [
    _u(1, 'Nezir Barkın', '@test', -303),
    _u(2, 'CizreApp', '@cizreapp', -98),
    _u(3, 'test1', '@test1', 4),
  ],
};

// Canlı (2026-09-21): üye 153 = 160 - 7 misafir.
const _stats = {
  'members': 153,
  'guests': 7,
  'ghosts': 4,
  'orders': 23,
  'shops': 7,
  'products': 110,
  'posts': 57,
  'okey_matches': 219,
  'visitors_today': 8,
  'active_today': 8,
  'guests_today': 0,
  'online_now': 1,
  'new_today': 0,
  'posts_today': 1,
  'orders_today': 0,
};

LeaderboardSnapshot _snapshot({int limit = 5}) {
  const order = [
    LeaderboardBoard.stats,
    LeaderboardBoard.statsToday,
    LeaderboardBoard.topFollowed,
    LeaderboardBoard.newMembers,
    LeaderboardBoard.topLikedPosts,
    LeaderboardBoard.topViewedStories,
    LeaderboardBoard.topSellers,
    LeaderboardBoard.topProductSellers,
    LeaderboardBoard.topRatedShops,
    LeaderboardBoard.topLogins,
    LeaderboardBoard.okeyMostWins,
    LeaderboardBoard.okeyWinRate,
    LeaderboardBoard.okeyRichest,
    LeaderboardBoard.okeyBestScore,
  ];
  return LeaderboardSnapshot(
    settings: LeaderboardSettings(
      enabled: true,
      period: LeaderboardPeriod.month,
      limit: limit,
      boards: {
        for (final b in LeaderboardBoard.values) b.key: order.contains(b),
      },
      order: [for (final b in order) b.key],
      stats: {for (final k in _stats.keys) k: true},
    ),
    boards: {for (final e in _data.entries) e.key.key: e.value},
    stats: _stats,
  );
}

Map<String, dynamic> _entryJson(LeaderboardEntry e) => {
  'r_rank': e.rank,
  'r_type': e.type.name,
  'r_id': e.id,
  'r_name': e.name,
  'r_handle': e.handle,
  'r_avatar': null,
  'r_metric': e.metric,
  'r_extra': e.extra,
  'r_at': e.at?.toIso8601String(),
  'r_owner': e.ownerId,
  'r_me': e.isMe,
};

MockClient _mock() {
  final snapshot = _snapshot();
  final settings = snapshot.settings;
  return MockClient((req) async {
    final path = req.url.path;
    Object body = [];
    if (path.endsWith('/rpc/leaderboard_settings')) {
      body = {
        'enabled': settings.enabled,
        'period': settings.period.key,
        'limit': settings.limit,
        'order': settings.order,
        'boards': settings.boards,
        'stats': settings.stats,
      };
    } else if (path.endsWith('/rpc/get_leaderboards')) {
      body = {
        'settings': {
          'enabled': settings.enabled,
          'period': settings.period.key,
          'limit': settings.limit,
          'order': settings.order,
          'boards': settings.boards,
          'stats': settings.stats,
        },
        'boards': {
          for (final e in _data.entries)
            e.key.key: [for (final r in e.value) _entryJson(r)],
        },
        'stats': _stats,
      };
    } else if (path.endsWith('/rpc/admin_leaderboard_hidden_users')) {
      body = [
        {'h_user_id': 'x1', 'h_self': true, 'h_admin': false},
        {'h_user_id': 'x2', 'h_self': false, 'h_admin': true},
      ];
    } else if (path.endsWith('/rest/v1/profiles')) {
      body = [
        {
          'id': 'x1',
          'full_name': 'Mahsun Sarıca',
          'username': 'mahsun73',
          'avatar_url': null,
        },
        {
          'id': 'x2',
          'full_name': 'Test Kullanıcı',
          'username': 'testuser',
          'avatar_url': null,
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
}

ThemeData get _theme => ThemeData(
  useMaterial3: true,
  fontFamily: 'Roboto',
  scaffoldBackgroundColor: const Color(0xFFF7F7FA),
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFD91A73)),
);

Future<void> _open(WidgetTester tester, Widget body, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme,
      home: Scaffold(body: body),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _section() => SingleChildScrollView(
  child: HomeLeaderboardSection(
    snapshotLoader: () async => _snapshot(),
    onOpenEntry: (_, __) {},
  ),
);

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

  testWidgets('ana sayfa — sayaç kartı', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    await _open(tester, _section(), const Size(390, 520));
    await _shot('preview_home_sayilar.png');
  });

  testWidgets('ana sayfa — bugün cizre’de kartı', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    await _open(tester, _section(), const Size(390, 500));
    await tester.tap(
      find.byKey(const ValueKey('leaderboard-chip-stats_today')),
    );
    await tester.pumpAndSettle();
    await _shot('preview_home_bugun.png');
  });

  testWidgets('ana sayfa — takipçi kartı ve senin sıran', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    await _open(tester, _section(), const Size(390, 640));
    await tester.tap(
      find.byKey(const ValueKey('leaderboard-chip-top_followed')),
    );
    await tester.pumpAndSettle();
    await _shot('preview_home_takipci.png');
  });

  testWidgets('ana sayfa — kaydırırken iki kart', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    await _open(tester, _section(), const Size(390, 640));
    // Yarım kaydır: iki kartın yan yana göründüğü an.
    await tester.drag(find.byType(PageView), const Offset(-150, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await _shot('preview_home_kaydirma.png');
    await tester.pumpAndSettle();
  });

  testWidgets('ana sayfa — gönderi kartı', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    await _open(tester, _section(), const Size(390, 480));
    final chip = find.byKey(const ValueKey('leaderboard-chip-top_liked_posts'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await _shot('preview_home_gonderi.png');
  });

  Future<void> okeyShot(
    WidgetTester tester,
    String chipKey,
    String file,
    double height,
  ) async {
    await _open(tester, _section(), Size(390, height));
    final chip = find.byKey(ValueKey('leaderboard-chip-$chipKey'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await _shot(file);
  }

  testWidgets('ana sayfa — okey kazanma oranı', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    await okeyShot(tester, 'okey_win_rate', 'preview_okey_oran.png', 420);
  });

  testWidgets('ana sayfa — okey en çok puan (senin sıran)', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    await okeyShot(tester, 'okey_richest', 'preview_okey_puan.png', 640);
  });

  testWidgets('ana sayfa — okey en iyi skor', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    await okeyShot(tester, 'okey_best_score', 'preview_okey_skor.png', 420);
  });

  testWidgets('ana sayfa — boş hikaye kartı', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    await _open(tester, _section(), const Size(390, 400));
    final chip = find.byKey(
      const ValueKey('leaderboard-chip-top_viewed_stories'),
    );
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await _shot('preview_home_hikaye_bos.png');
  });

  testWidgets('admin — liderler tablosu', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    await _open(
      tester,
      const LeaderboardManagementContent(),
      const Size(390, 3100),
    );
    await _shot('preview_admin_liderler.png');
  });

  testWidgets('hesap ayarı — kendini gizle', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    await _open(
      tester,
      Padding(
        padding: const EdgeInsets.all(16),
        child: LeaderboardVisibilityTile(
          loader: () async =>
              const LeaderboardVisibility(selfHidden: true, adminHidden: true),
          saver: (h) async => LeaderboardVisibility(selfHidden: h),
        ),
      ),
      const Size(390, 260),
    );
    await _shot('preview_hesap_gizle.png');
  });
}
