import 'package:cizreapp/features/leaderboard/leaderboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LeaderboardEntry _user(
  int rank,
  String name,
  double metric, {
  bool me = false,
}) => LeaderboardEntry(
  rank: rank,
  type: LeaderboardEntityType.user,
  id: 'u$rank',
  name: name,
  handle: '@${name.toLowerCase()}',
  metric: metric,
  isMe: me,
);

LeaderboardSnapshot _snapshot({
  bool enabled = true,
  int limit = 5,
  LeaderboardPeriod period = LeaderboardPeriod.all,
  List<LeaderboardBoard> order = const [],
  required Map<LeaderboardBoard, List<LeaderboardEntry>> boards,
  Map<String, int> stats = const {},
}) {
  final on = {for (final b in boards.keys) b.key};
  // Sayaç kartları kendi gruplarındaki sayaçlar gelince açılır.
  for (final stat in LeaderboardStat.values) {
    if (!stats.containsKey(stat.key)) continue;
    on.add(
      stat.group == LeaderboardStatGroup.today
          ? LeaderboardBoard.statsToday.key
          : LeaderboardBoard.stats.key,
    );
  }
  return LeaderboardSnapshot(
    settings: LeaderboardSettings(
      enabled: enabled,
      period: period,
      limit: limit,
      boards: {
        for (final b in LeaderboardBoard.values) b.key: on.contains(b.key),
      },
      order: [for (final b in order) b.key],
      stats: {for (final k in stats.keys) k: true},
    ),
    boards: {for (final e in boards.entries) e.key.key: e.value},
    stats: stats,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required LeaderboardSnapshotLoader loader,
  LeaderboardEntryOpener? onOpen,
}) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: HomeLeaderboardSection(
            snapshotLoader: loader,
            onOpenEntry: onOpen ?? (_, __) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Finder _chip(LeaderboardBoard b) =>
    find.byKey(ValueKey('leaderboard-chip-${b.key}'));
Finder _card(LeaderboardBoard b) =>
    find.byKey(ValueKey('leaderboard-card-${b.key}'));

void main() {
  testWidgets('ana anahtar kapalıysa hiçbir şey çizmez', (tester) async {
    await _pump(
      tester,
      loader: () async => _snapshot(
        enabled: false,
        boards: {
          LeaderboardBoard.topFollowed: [_user(1, 'Ayse', 19)],
        },
      ),
    );
    expect(find.text('Liderler Tablosu'), findsNothing);
    expect(find.byType(PageView), findsNothing);
  });

  testWidgets('hiçbir kart açık değilse bölüm görünmez', (tester) async {
    await _pump(tester, loader: () async => _snapshot(boards: {}));
    expect(find.text('Liderler Tablosu'), findsNothing);
  });

  testWidgets('sayaç kartı sayaç yoksa çizilmez', (tester) async {
    await _pump(
      tester,
      loader: () async => _snapshot(
        boards: {
          LeaderboardBoard.topFollowed: [_user(1, 'Ayse', 19)],
        },
      ),
    );
    expect(_chip(LeaderboardBoard.stats), findsNothing);
    expect(_chip(LeaderboardBoard.topFollowed), findsOneWidget);
  });

  testWidgets('yükleme sürerken yer tutucu çizmez', (tester) async {
    Future<LeaderboardSnapshot> loader() => Future<LeaderboardSnapshot>.delayed(
      const Duration(seconds: 1),
      () => _snapshot(boards: {}),
    );
    await _pump(tester, loader: loader);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Liderler Tablosu'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('hata olunca Yenile ile yeniden dener', (tester) async {
    var calls = 0;
    await _pump(
      tester,
      loader: () async {
        calls++;
        if (calls == 1) throw StateError('ağ yok');
        return _snapshot(
          boards: {
            LeaderboardBoard.topFollowed: [_user(1, 'Ayse', 19)],
          },
        );
      },
    );
    expect(find.text('Liderler tablosu şu anda yüklenemedi.'), findsOneWidget);

    await tester.tap(find.text('Yenile'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(calls, 2);
    expect(find.text('Ayse'), findsOneWidget);
  });

  testWidgets('tek çağrı: kartlar gezilirken yeniden veri çekilmez', (
    tester,
  ) async {
    var calls = 0;
    await _pump(
      tester,
      loader: () async {
        calls++;
        return _snapshot(
          boards: {
            LeaderboardBoard.topFollowed: [_user(1, 'Ayse', 19)],
            LeaderboardBoard.topPosters: [_user(1, 'Ceren', 21)],
          },
        );
      },
    );
    await tester.tap(_chip(LeaderboardBoard.topPosters));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('sekmeler admin sırasındadır', (tester) async {
    await _pump(
      tester,
      loader: () async => _snapshot(
        order: [
          LeaderboardBoard.mostLiked,
          LeaderboardBoard.topFollowed,
          LeaderboardBoard.newMembers,
        ],
        boards: {
          LeaderboardBoard.newMembers: [_user(1, 'A', 0)],
          LeaderboardBoard.topFollowed: [_user(1, 'B', 1)],
          LeaderboardBoard.mostLiked: [_user(1, 'C', 2)],
        },
      ),
    );
    final xs = [
      tester.getTopLeft(_chip(LeaderboardBoard.mostLiked)).dx,
      tester.getTopLeft(_chip(LeaderboardBoard.topFollowed)).dx,
      tester.getTopLeft(_chip(LeaderboardBoard.newMembers)).dx,
    ];
    expect(xs[0], lessThan(xs[1]));
    expect(xs[1], lessThan(xs[2]));
    // İlk kart admin sırasındaki ilk kart.
    expect(find.text('En Çok Beğeni Alanlar'), findsOneWidget);
  });

  testWidgets('parmakla sola kaydırınca sonraki kart gelir', (tester) async {
    await _pump(
      tester,
      loader: () async => _snapshot(
        order: [LeaderboardBoard.topFollowed, LeaderboardBoard.topPosters],
        boards: {
          LeaderboardBoard.topFollowed: [_user(1, 'Ayse', 19)],
          LeaderboardBoard.topPosters: [_user(1, 'Ceren', 21)],
        },
      ),
    );
    final before = tester.getTopLeft(_card(LeaderboardBoard.topPosters)).dx;
    expect(
      before,
      greaterThan(300),
    ); // ikinci kart sağda, yalnız kenarı görünür

    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();

    final after = tester.getTopLeft(_card(LeaderboardBoard.topPosters)).dx;
    expect(after, lessThan(40));
    expect(find.text('Ceren'), findsOneWidget);
    expect(find.text('21 gönderi'), findsOneWidget);

    // Geri kaydırınca ilk kart döner.
    await tester.drag(find.byType(PageView), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(_card(LeaderboardBoard.topFollowed)).dx,
      lessThan(40),
    );
  });

  testWidgets('sekmeye dokunmak kartı kaydırır', (tester) async {
    await _pump(
      tester,
      loader: () async => _snapshot(
        order: [
          LeaderboardBoard.topFollowed,
          LeaderboardBoard.topPosters,
          LeaderboardBoard.mostLiked,
        ],
        boards: {
          LeaderboardBoard.topFollowed: [_user(1, 'Ayse', 19)],
          LeaderboardBoard.topPosters: [_user(1, 'Ceren', 21)],
          LeaderboardBoard.mostLiked: [_user(1, 'Deniz', 46)],
        },
      ),
    );
    // Üçüncü sekme ekranın dışında kalır; sekme çubuğu kaydırılabilir.
    await tester.ensureVisible(_chip(LeaderboardBoard.mostLiked));
    await tester.pumpAndSettle();
    await tester.tap(_chip(LeaderboardBoard.mostLiked));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(_card(LeaderboardBoard.mostLiked)).dx,
      lessThan(40),
    );
    expect(find.text('46 beğeni'), findsOneWidget);
  });

  testWidgets('kart yüksekliği satır sayısına göre hesaplanır ve taşmaz', (
    tester,
  ) async {
    // 5 satır: 26 (kenar) + 44 (başlık) + 5 * 64.
    await _pump(
      tester,
      loader: () async => _snapshot(
        limit: 5,
        order: [LeaderboardBoard.topFollowed],
        boards: {
          LeaderboardBoard.topFollowed: [
            for (var i = 1; i <= 5; i++) _user(i, 'Kisi$i', 20.0 - i),
          ],
        },
      ),
    );
    expect(tester.getSize(find.byType(PageView)).height, 26 + 44 + 5 * 64);
    expect(tester.takeException(), isNull);
  });

  testWidgets('yandan görünen komşu kart daha uzunsa taşma olmaz', (
    tester,
  ) async {
    // Kısa kart (sayaç) önce, uzun kart (10 satır + senin sıran) sonra: viewport
    // ilk kartın yüksekliğindeyken komşu kart kendi yüksekliğinde çizilmeli.
    await _pump(
      tester,
      loader: () async => _snapshot(
        limit: 5,
        order: [LeaderboardBoard.stats, LeaderboardBoard.topFollowed],
        boards: {
          LeaderboardBoard.topFollowed: [
            for (var i = 1; i <= 5; i++) _user(i, 'Kisi$i', 30.0 - i),
            _user(9, 'Ben', 3, me: true),
          ],
        },
        stats: {'members': 160, 'orders': 23},
      ),
    );
    expect(tester.takeException(), isNull);
    // Başlangıç yüksekliği sayaç kartınındır (1 satır sayaç).
    expect(tester.getSize(find.byType(PageView)).height, 26 + 44 + 84);

    // Kaydırma sırasında yükseklik iki kart arasında geçiş yapar, taşmaz.
    await tester.drag(find.byType(PageView), const Offset(-120, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
    final mid = tester.getSize(find.byType(PageView)).height;
    expect(mid, greaterThan(26 + 44 + 84));
    expect(mid, lessThan(26 + 44 + 5 * 64 + 92));

    // Kısa sürükleme eşiği aşmaz: ilk karta geri döner.
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(PageView)).height, 26 + 44 + 84);

    // Yeterince kaydırınca uzun karta geçer ve yükseklik ona uyar.
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(PageView)).height, 26 + 44 + 5 * 64 + 92);
    expect(tester.takeException(), isNull);
  });

  testWidgets('kısa listede altta boşluk kalmaz (yükseklik satıra uyar)', (
    tester,
  ) async {
    await _pump(
      tester,
      loader: () async => _snapshot(
        limit: 5,
        order: [LeaderboardBoard.topFollowed],
        boards: {
          LeaderboardBoard.topFollowed: [_user(1, 'A', 3), _user(2, 'B', 2)],
        },
      ),
    );
    expect(tester.getSize(find.byType(PageView)).height, 26 + 44 + 2 * 64);
  });

  testWidgets('senin sıran: ilk N dışındaysa ayrı satır ve "Sen" rozeti', (
    tester,
  ) async {
    await _pump(
      tester,
      loader: () async => _snapshot(
        limit: 3,
        order: [LeaderboardBoard.topFollowed],
        boards: {
          LeaderboardBoard.topFollowed: [
            _user(1, 'A', 19),
            _user(2, 'B', 15),
            _user(3, 'C', 12),
            _user(7, 'Ben', 4, me: true),
          ],
        },
      ),
    );
    expect(find.text('Senin sıran'), findsOneWidget);
    expect(find.text('Sen'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    // 3 satır + "senin sıran" bloğu (92).
    expect(tester.getSize(find.byType(PageView)).height, 26 + 44 + 3 * 64 + 92);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ilk N içindeyken "Senin sıran" bloğu yok, yalnız rozet var', (
    tester,
  ) async {
    await _pump(
      tester,
      loader: () async => _snapshot(
        limit: 3,
        order: [LeaderboardBoard.topFollowed],
        boards: {
          LeaderboardBoard.topFollowed: [
            _user(1, 'A', 19),
            _user(2, 'Ben', 15, me: true),
            _user(3, 'C', 12),
          ],
        },
      ),
    );
    expect(find.text('Senin sıran'), findsNothing);
    expect(find.text('Sen'), findsOneWidget);
  });

  testWidgets('sayaç kartı yalnız açık sayaçları binlik ayraçlı gösterir', (
    tester,
  ) async {
    await _pump(
      tester,
      loader: () async => _snapshot(
        order: [LeaderboardBoard.stats],
        boards: {},
        stats: {'members': 1234, 'orders': 23, 'shops': 7},
      ),
    );
    expect(find.text('Rakamlarla Cizre'), findsOneWidget);
    expect(find.text('1.234'), findsOneWidget);
    expect(find.text('Toplam üye'), findsOneWidget);
    expect(find.text('23'), findsOneWidget);
    expect(find.text('Tamamlanan sipariş'), findsOneWidget);
    expect(find.text('Aktif dükkan'), findsOneWidget);
    // Kapalı sayaç yok.
    expect(find.text('Toplam ürün'), findsNothing);
    // 3 sayaç = 2 satır: 26 + 44 + 2*84 + 10.
    expect(tester.getSize(find.byType(PageView)).height, 26 + 44 + 2 * 84 + 10);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Bugün Cizre’de" kartı yalnız günlük sayaçları gösterir', (
    tester,
  ) async {
    await _pump(
      tester,
      loader: () async => _snapshot(
        order: [LeaderboardBoard.statsToday],
        boards: {},
        stats: {
          'visitors_today': 8,
          'active_today': 5,
          'guests_today': 3,
          'online_now': 1,
        },
      ),
    );
    expect(find.text('Bugün Cizre’de'), findsOneWidget);
    expect(find.text('Bugün ziyaretçi'), findsOneWidget);
    expect(find.text('Bugün aktif üye'), findsOneWidget);
    expect(find.text('Bugün üyesiz ziyaretçi'), findsOneWidget);
    expect(find.text('Şu an çevrimiçi'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    // Genel sayaçlar bu kartta yok.
    expect(find.text('Toplam üye'), findsNothing);
    // 4 sayaç = 2 satır.
    expect(tester.getSize(find.byType(PageView)).height, 26 + 44 + 2 * 84 + 10);
    expect(tester.takeException(), isNull);
  });

  testWidgets('genel kartta üyesiz ve hayalet kullanıcı sayaçları görünür', (
    tester,
  ) async {
    await _pump(
      tester,
      loader: () async => _snapshot(
        order: [LeaderboardBoard.stats],
        boards: {},
        stats: {'members': 153, 'guests': 7, 'ghosts': 4},
      ),
    );
    expect(find.text('Toplam üye'), findsOneWidget);
    expect(find.text('Üyesiz kullanıcı'), findsOneWidget);
    expect(find.text('Hayalet kullanıcı'), findsOneWidget);
    expect(find.text('153'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('iki sayaç kartı ayrı ayrı çizilir ve kendi grubunu gösterir', (
    tester,
  ) async {
    await _pump(
      tester,
      loader: () async => _snapshot(
        order: [LeaderboardBoard.stats, LeaderboardBoard.statsToday],
        boards: {},
        stats: {'members': 153, 'visitors_today': 8},
      ),
    );
    expect(
      find.byKey(const ValueKey('leaderboard-chip-stats')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('leaderboard-chip-stats_today')),
      findsOneWidget,
    );
  });

  testWidgets('günlük sayaç gelmezse "Bugün Cizre’de" kartı çizilmez', (
    tester,
  ) async {
    await _pump(
      tester,
      loader: () async => _snapshot(
        order: [LeaderboardBoard.stats, LeaderboardBoard.statsToday],
        boards: {},
        stats: {'members': 153},
      ),
    );
    expect(
      find.byKey(const ValueKey('leaderboard-chip-stats')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('leaderboard-chip-stats_today')),
      findsNothing,
    );
  });

  testWidgets('dönem notu döneme duyarlı kartta görünür', (tester) async {
    await _pump(
      tester,
      loader: () async => _snapshot(
        period: LeaderboardPeriod.week,
        order: [LeaderboardBoard.topSellers],
        boards: {
          LeaderboardBoard.topSellers: [
            const LeaderboardEntry(
              rank: 1,
              type: LeaderboardEntityType.shop,
              id: 's1',
              name: 'CizreApp',
              metric: 13,
            ),
          ],
        },
      ),
    );
    expect(find.text('Son 7 gün'), findsOneWidget);
    expect(find.text('13 sipariş'), findsOneWidget);
  });

  testWidgets('veri yoksa boş durum; hikaye kartının kendi metni var', (
    tester,
  ) async {
    await _pump(
      tester,
      loader: () async => _snapshot(
        order: [
          LeaderboardBoard.topCouriers,
          LeaderboardBoard.topViewedStories,
        ],
        boards: {
          LeaderboardBoard.topCouriers: const [],
          LeaderboardBoard.topViewedStories: const [],
        },
      ),
    );
    expect(find.text('Bu pano için henüz yeterli veri yok.'), findsOneWidget);

    await tester.tap(_chip(LeaderboardBoard.topViewedStories));
    await tester.pumpAndSettle();
    expect(find.text('Şu an yayında izlenen hikaye yok.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('satıra dokunmak doğru varlığı açar (gönderi ve dükkan)', (
    tester,
  ) async {
    LeaderboardEntry? opened;
    await _pump(
      tester,
      loader: () async => _snapshot(
        order: [LeaderboardBoard.topLikedPosts],
        boards: {
          LeaderboardBoard.topLikedPosts: [
            const LeaderboardEntry(
              rank: 1,
              type: LeaderboardEntityType.post,
              id: 'post-9',
              name: 'Merhaba Cizre',
              handle: '@ayse',
              metric: 9,
              ownerId: 'author-1',
            ),
          ],
        },
      ),
      onOpen: (_, entry) => opened = entry,
    );

    expect(find.text('Merhaba Cizre'), findsOneWidget);
    expect(find.text('9 beğeni'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('leaderboard-row-top_liked_posts-1')),
    );
    expect(opened?.id, 'post-9');
    expect(opened?.type, LeaderboardEntityType.post);
  });

  testWidgets(
    'Okey: kazanma oranı yüzde ve maç sayısıyla, en iyi skor eksi işaretiyle',
    (tester) async {
      await _pump(
        tester,
        loader: () async => _snapshot(
          order: [LeaderboardBoard.okeyWinRate, LeaderboardBoard.okeyBestScore],
          boards: {
            LeaderboardBoard.okeyWinRate: [
              const LeaderboardEntry(
                rank: 1,
                type: LeaderboardEntityType.user,
                id: 'u1',
                name: 'Ayse',
                handle: '@ayse',
                metric: 71.4,
                extra: 7,
              ),
            ],
            LeaderboardBoard.okeyBestScore: [
              const LeaderboardEntry(
                rank: 1,
                type: LeaderboardEntityType.user,
                id: 'u2',
                name: 'Veli',
                handle: '@veli',
                metric: -303,
              ),
            ],
          },
        ),
      );
      expect(find.text('Okey: En Yüksek Kazanma Oranı'), findsOneWidget);
      expect(find.text('%71'), findsOneWidget);
      expect(find.text('7 maç'), findsOneWidget);

      await tester.tap(_chip(LeaderboardBoard.okeyBestScore));
      await tester.pumpAndSettle();
      expect(find.text('-303'), findsOneWidget);
      expect(find.text('En düşük (en iyi) maç skoru'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('sayaç kartında Okey maçı sayacı görünür', (tester) async {
    await _pump(
      tester,
      loader: () async => _snapshot(
        order: [LeaderboardBoard.stats],
        boards: {},
        stats: {'members': 160, 'okey_matches': 1219},
      ),
    );
    expect(find.text('Oynanan Okey maçı'), findsOneWidget);
    expect(find.text('1.219'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('değer yoksa boş rozet çizilmez', (tester) async {
    await _pump(
      tester,
      loader: () async => _snapshot(
        order: [LeaderboardBoard.newMembers],
        // `at` gelmedi: rozet metni boş olurdu.
        boards: {
          LeaderboardBoard.newMembers: [
            const LeaderboardEntry(
              rank: 1,
              type: LeaderboardEntityType.user,
              id: 'u1',
              name: 'Ayse',
            ),
          ],
        },
      ),
    );
    expect(find.text('Ayse'), findsOneWidget);
    expect(find.text(''), findsNothing);
  });
}
