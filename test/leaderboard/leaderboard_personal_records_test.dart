import 'package:cizreapp/features/leaderboard/leaderboard.dart';
import 'package:cizreapp/okey/services/okey_module_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Görev 4.4 — "Rakamlarla Sen" (kişisel sayılar) ve "Rekor Skorlar".

Map<String, dynamic> _json({
  Map<String, int> stats = const {},
  Map<String, Object?> records = const {},
  List<String> boardsOn = const ['my_stats', 'records'],
}) => {
  'settings': {
    'enabled': true,
    'period': 'all',
    'limit': 5,
    'order': <String>[],
    'boards': {for (final b in LeaderboardBoard.values) b.key: boardsOn.contains(b.key)},
    'stats': {for (final k in stats.keys) k: true},
    'records': {for (final k in records.keys) k: true},
  },
  'boards': <String, Object?>{},
  'stats': stats,
  'records': records,
};

const _personal = {
  'my_days': 326,
  'my_posts': 12,
  'my_likes': 1234,
  'my_followers': 45,
  'my_okey_matches': 30,
  'my_okey_wins': 11,
};

final _records = <String, Object?>{
  'busiest_day': {'value': 87, 'at': '2026-09-21', 'type': 'day'},
  'oldest_member': {
    'value': 430,
    'at': '2025-07-24T10:00:00+00:00',
    'type': 'user',
    'id': 'u-old',
    'name': 'Ahmet Yılmaz',
    'handle': '@ahmet',
  },
  'top_post_likes': {
    'value': 1540,
    'at': '2026-09-01T10:00:00+00:00',
    'type': 'post',
    'id': 'p-top',
    'name': 'Cizre köprüsünde gün batımı',
    'handle': '@ayse',
    'owner': 'u-ayse',
  },
  'live_peak': {
    'value': 31,
    'at': '2026-09-20T18:00:00+00:00',
    'type': 'shop',
    'id': 'shop-1',
    'name': 'Çay Evi',
    'detail': 'Yeni sezon çaydanlıklar',
  },
  'first_post': {
    'at': '2025-11-06T09:00:00+00:00',
    'type': 'post',
    'id': 'p-first',
    'name': 'Merhaba Cizre',
    'handle': '@kurucu',
  },
  'bilinmeyen_rekor': {'value': 1, 'type': 'day'},
};

Future<void> _pump(
  WidgetTester tester,
  LeaderboardSnapshot snapshot, {
  List<LeaderboardEntry>? opened,
}) async {
  tester.view.physicalSize = const Size(390, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: HomeLeaderboardSection(
            snapshotLoader: () async => snapshot,
            onOpenEntry: (_, entry) => opened?.add(entry),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _openChip(WidgetTester tester, LeaderboardBoard board) async {
  await tester.tap(find.byKey(ValueKey('leaderboard-chip-${board.key}')));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => OkeyModuleService.setCacheForTesting(null));

  group('modeller', () {
    test('rekorlar okunur; bilinmeyen anahtar atlanır; enum sırasıyla listelenir', () {
      final snapshot = LeaderboardSnapshot.fromJson(_json(records: _records));
      expect(snapshot.records.keys, isNot(contains('bilinmeyen_rekor')));
      expect(snapshot.recordsFor().map((r) => r.record), [
        LeaderboardRecord.busiestDay,
        LeaderboardRecord.oldestMember,
        LeaderboardRecord.topPostLikes,
        LeaderboardRecord.livePeak,
        LeaderboardRecord.firstPost,
      ]);
      expect(snapshot.settings.isRecordEnabled(LeaderboardRecord.busiestDay), isTrue);
      expect(snapshot.settings.isRecordEnabled(LeaderboardRecord.signupDay), isFalse);
    });

    test('değer ve alt satır metinleri; dokunma hedefi', () {
      final snapshot = LeaderboardSnapshot.fromJson(_json(records: _records));
      LeaderboardRecordValue of(LeaderboardRecord r) => snapshot.records[r.key]!;

      final day = of(LeaderboardRecord.busiestDay);
      expect(day.valueLabel, '87 kişi');
      expect(day.subtitle, '21 Eylül 2026');
      expect(day.toEntry(), isNull, reason: 'gün rekorunun açılacak sayfası yok');

      final oldest = of(LeaderboardRecord.oldestMember);
      expect(oldest.valueLabel, '1 yıl 2 aydır üye');
      expect(oldest.subtitle, 'Ahmet Yılmaz · @ahmet');
      expect(oldest.toEntry()!.type, LeaderboardEntityType.user);
      expect(oldest.toEntry()!.id, 'u-old');

      final post = of(LeaderboardRecord.topPostLikes);
      expect(post.valueLabel, '1.540 beğeni');
      expect(post.subtitle, '@ayse · Cizre köprüsünde gün batımı');
      expect(post.toEntry()!.type, LeaderboardEntityType.post);
      expect(post.toEntry()!.ownerId, 'u-ayse');

      final live = of(LeaderboardRecord.livePeak);
      expect(live.valueLabel, '31 izleyici');
      expect(live.subtitle, 'Çay Evi · Yeni sezon çaydanlıklar');
      expect(live.toEntry()!.type, LeaderboardEntityType.shop);

      final first = of(LeaderboardRecord.firstPost);
      expect(first.valueLabel, formatTrDate(DateTime.parse('2025-11-06T09:00:00+00:00')));
    });

    test('üyelik süresi ve Türkçe tarih', () {
      expect(memberForLabel(12), '12 gündür üye');
      expect(memberForLabel(300), '10 aydır üye');
      expect(memberForLabel(360), '1 yıldır üye');
      expect(memberForLabel(800), '2 yıl 2 aydır üye');
      expect(formatTrDate(DateTime(2026, 2, 3)), '3 Şubat 2026');
    });

    test('kartlar: sayaç/rekor yoksa kart yok; Okey süzgeci', () {
      final empty = LeaderboardSnapshot.fromJson(_json());
      expect(empty.cards, isEmpty);

      final full = LeaderboardSnapshot.fromJson(_json(stats: _personal, records: _records));
      expect(full.cards, [LeaderboardBoard.myStats, LeaderboardBoard.records]);
      expect(full.statsFor(LeaderboardBoard.myStats).map((s) => s.key), [
        'my_days',
        'my_posts',
        'my_likes',
        'my_followers',
        'my_okey_matches',
        'my_okey_wins',
      ]);
      expect(full.statsFor(LeaderboardBoard.stats), isEmpty, reason: 'kişisel sayılar genel kartta çıkmaz');

      final noOkey = full.withoutOkey();
      expect(noOkey.statsFor(LeaderboardBoard.myStats).map((s) => s.key), [
        'my_days',
        'my_posts',
        'my_likes',
        'my_followers',
      ]);
      expect(noOkey.records.length, full.records.length);
    });
  });

  group('ana sayfa', () {
    testWidgets('"Rakamlarla Sen": yalnız gelen kişisel sayılar', (tester) async {
      await _pump(tester, LeaderboardSnapshot.fromJson(_json(stats: _personal, records: _records)));

      expect(find.byKey(const ValueKey('leaderboard-chip-my_stats')), findsOneWidget);
      expect(find.text('Rakamlarla Sen'), findsOneWidget);
      expect(find.byKey(const ValueKey('leaderboard-stat-my_likes')), findsOneWidget);
      expect(find.text('1.234'), findsOneWidget);
      expect(find.text('Aldığın beğeni'), findsOneWidget);
      expect(find.byKey(const ValueKey('leaderboard-stat-my_orders')), findsNothing);
    });

    testWidgets('"Rekor Skorlar": satırlar; kişi/gönderi/dükkân açılır, gün açılmaz', (tester) async {
      final opened = <LeaderboardEntry>[];
      await _pump(
        tester,
        LeaderboardSnapshot.fromJson(_json(stats: _personal, records: _records)),
        opened: opened,
      );
      await _openChip(tester, LeaderboardBoard.records);

      expect(find.text('Rekor Skorlar'), findsOneWidget);
      expect(find.text('En kalabalık gün'), findsOneWidget);
      expect(find.text('87 kişi'), findsOneWidget);
      expect(find.text('21 Eylül 2026'), findsOneWidget);
      expect(find.text('1 yıl 2 aydır üye'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('leaderboard-record-busiest_day')));
      await tester.pump();
      expect(opened, isEmpty);

      await tester.tap(find.byKey(const ValueKey('leaderboard-record-top_post_likes')));
      await tester.pump();
      expect(opened.single.type, LeaderboardEntityType.post);
      expect(opened.single.id, 'p-top');

      await tester.tap(find.byKey(const ValueKey('leaderboard-record-oldest_member')));
      await tester.pump();
      expect(opened.last.type, LeaderboardEntityType.user);
    });

    testWidgets('101 Okey kapalıyken kişisel Okey sayıları gizlenir', (tester) async {
      OkeyModuleService.setCacheForTesting(false);
      await _pump(tester, LeaderboardSnapshot.fromJson(_json(stats: _personal)));

      expect(find.byKey(const ValueKey('leaderboard-stat-my_posts')), findsOneWidget);
      expect(find.byKey(const ValueKey('leaderboard-stat-my_okey_matches')), findsNothing);
      expect(find.byKey(const ValueKey('leaderboard-stat-my_okey_wins')), findsNothing);
    });

    testWidgets('dar ekran + büyük yazı: rekor satırları taşmaz', (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: HomeLeaderboardSection(
                snapshotLoader: () async => LeaderboardSnapshot.fromJson(_json(stats: _personal, records: _records)),
                onOpenEntry: (_, __) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await _openChip(tester, LeaderboardBoard.records);
      expect(tester.takeException(), isNull);
    });
  });
}
