import 'package:cizreapp/features/leaderboard/leaderboard.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row(
  int rank, {
  String type = 'user',
  String? name,
  Object? metric,
  bool me = false,
  Map<String, dynamic> extra = const {},
}) => {
  'r_rank': rank,
  'r_type': type,
  'r_id': 'id$rank',
  'r_name': name ?? 'Kişi $rank',
  'r_metric': metric ?? 10 - rank,
  'r_me': me,
  ...extra,
};

Map<String, dynamic> _settingsJson({
  bool enabled = true,
  int limit = 5,
  List<String> order = const [],
  Set<String>? on,
  Set<String> stats = const {'members', 'orders'},
}) {
  final enabledKeys = on ?? LeaderboardBoard.values.map((b) => b.key).toSet();
  return {
    'enabled': enabled,
    'period': 'month',
    'limit': limit,
    'order': order,
    'boards': {
      for (final b in LeaderboardBoard.values)
        b.key: enabledKeys.contains(b.key),
    },
    'stats': {
      for (final s in LeaderboardStat.values) s.key: stats.contains(s.key),
    },
  };
}

void main() {
  group('LeaderboardEntry.fromJson', () {
    test('kullanıcı satırını okur', () {
      final entry = LeaderboardEntry.fromJson({
        'r_rank': 1,
        'r_type': 'user',
        'r_id': 'u1',
        'r_name': '  Zeynep  ',
        'r_handle': '@zeynepp',
        'r_avatar': 'https://example.invalid/a.png',
        'r_metric': 14,
        'r_extra': null,
        'r_at': null,
      });
      expect(entry.rank, 1);
      expect(entry.type, LeaderboardEntityType.user);
      expect(entry.name, 'Zeynep');
      expect(entry.handle, '@zeynepp');
      expect(entry.metric, 14);
      expect(entry.at, isNull);
      expect(entry.isMe, isFalse);
      expect(entry.ownerId, isNull);
    });

    test('numeric sütunu metin olarak gelse de okunur', () {
      final entry = LeaderboardEntry.fromJson({
        'r_rank': 2,
        'r_type': 'shop',
        'r_id': 's1',
        'r_name': 'CizreApp',
        'r_metric': '4.5',
        'r_extra': '7',
      });
      expect(entry.type, LeaderboardEntityType.shop);
      expect(entry.metric, 4.5);
      expect(entry.extra, 7);
    });

    test('gönderi ve hikaye türleri ile yazar kimliği okunur', () {
      final post = LeaderboardEntry.fromJson(
        _row(1, type: 'post', extra: {'r_owner': 'author-1'}),
      );
      final story = LeaderboardEntry.fromJson(_row(1, type: 'story'));
      expect(post.type, LeaderboardEntityType.post);
      expect(post.ownerId, 'author-1');
      expect(story.type, LeaderboardEntityType.story);
    });

    test('bilinmeyen tür kullanıcı sayılır', () {
      final entry = LeaderboardEntry.fromJson(_row(1, type: 'gelecekte'));
      expect(entry.type, LeaderboardEntityType.user);
    });

    test('boş handle/avatar null olur, r_me okunur', () {
      final entry = LeaderboardEntry.fromJson({
        'r_rank': 1,
        'r_type': 'user',
        'r_id': 'u1',
        'r_name': 'A',
        'r_handle': '  ',
        'r_avatar': '',
        'r_me': true,
      });
      expect(entry.handle, isNull);
      expect(entry.avatarUrl, isNull);
      expect(entry.isMe, isTrue);
    });
  });

  group('LeaderboardSettings', () {
    test('ana anahtar kapalıysa hiçbir kart görünmez', () {
      final settings = LeaderboardSettings.fromJson(
        _settingsJson(enabled: false),
      );
      expect(settings.visibleBoards, isEmpty);
    });

    test('yalnız açık kartlar görünür', () {
      final settings = LeaderboardSettings.fromJson(
        _settingsJson(on: {'most_liked', 'top_followed', 'new_members'}),
      );
      expect(settings.visibleBoards, [
        LeaderboardBoard.newMembers,
        LeaderboardBoard.topFollowed,
        LeaderboardBoard.mostLiked,
      ]);
    });

    test('admin sırası uygulanır', () {
      final settings = LeaderboardSettings.fromJson(
        _settingsJson(
          order: ['most_liked', 'stats', 'top_followed'],
          on: {'most_liked', 'top_followed', 'stats', 'new_members'},
        ),
      );
      expect(settings.visibleBoards, [
        LeaderboardBoard.mostLiked,
        LeaderboardBoard.stats,
        LeaderboardBoard.topFollowed,
        LeaderboardBoard
            .newMembers, // kayıtlı sırada yok → varsayılan sırayla sona
      ]);
    });

    test(
      'sıradaki bilinmeyen ve tekrarlı anahtarlar atılır, eksikler eklenir',
      () {
        final settings = LeaderboardSettings.fromJson(
          _settingsJson(
            order: ['top_followed', 'yok', 'top_followed', 'stats'],
          ),
        );
        final ordered = settings.orderedBoards;
        expect(ordered.take(2), [
          LeaderboardBoard.topFollowed,
          LeaderboardBoard.stats,
        ]);
        // Her kart tam bir kez.
        expect(ordered.toSet().length, LeaderboardBoard.values.length);
        expect(ordered.length, LeaderboardBoard.values.length);
      },
    );

    test('withOrder yalnız sırayı değiştirir', () {
      final settings = LeaderboardSettings.fromJson(_settingsJson());
      final swapped = settings.withOrder([
        LeaderboardBoard.mostLiked,
        LeaderboardBoard.stats,
      ]);
      expect(swapped.orderedBoards.first, LeaderboardBoard.mostLiked);
      expect(swapped.period, settings.period);
      expect(swapped.limit, settings.limit);
      expect(swapped.boards, settings.boards);
    });

    test('sayaç anahtarları: Okey maçı sayacı dahil, ayar anahtarı doğru', () {
      expect(LeaderboardStat.okeyMatches.key, 'okey_matches');
      expect(
        LeaderboardStat.okeyMatches.settingKey,
        'leaderboard_stat_okey_matches',
      );
      expect(LeaderboardStat.values.length, 15);
      // Her sayaç bir gruba aittir; "active_today" günlük grupta.
      expect(LeaderboardStat.activeToday.group, LeaderboardStatGroup.today);
      expect(LeaderboardStat.members.group, LeaderboardStatGroup.general);
      expect(
        LeaderboardStat.values
            .where((s) => s.group == LeaderboardStatGroup.today)
            .length,
        7,
      );
    });

    test('sayaç anahtarları okunur', () {
      final settings = LeaderboardSettings.fromJson(_settingsJson());
      expect(settings.isStatEnabled(LeaderboardStat.members), isTrue);
      expect(settings.isStatEnabled(LeaderboardStat.posts), isFalse);
    });

    test(
      'sunucunun bilmediği anahtar yok sayılır, eksik kart kapalı sayılır',
      () {
        final settings = LeaderboardSettings.fromJson({
          'enabled': true,
          'boards': {'top_followed': true, 'gelecekte_eklenen': true},
        });
        expect(settings.visibleBoards, [LeaderboardBoard.topFollowed]);
      },
    );

    test('limit 3-10 aralığına sıkıştırılır, bilinmeyen dönem "tümü" olur', () {
      final settings = LeaderboardSettings.fromJson({
        'enabled': true,
        'period': 'yarin',
        'limit': 99,
        'boards': <String, dynamic>{},
      });
      expect(settings.limit, 10);
      expect(settings.period, LeaderboardPeriod.all);
    });

    test('okunamayan ayar bölümü gizler', () {
      expect(LeaderboardSettings.fallback.visibleBoards, isEmpty);
    });
  });

  group('LeaderboardBoard', () {
    test('key kümesi sunucudaki leaderboard_card_keys() ile aynı', () {
      expect(
        [for (final b in LeaderboardBoard.values) b.key],
        [
          'stats',
          'stats_today',
          'new_members',
          'top_followed',
          'top_liked_posts',
          'top_viewed_posts',
          'top_viewed_stories',
          'top_sellers',
          'top_product_sellers',
          'top_customers',
          'top_rated_shops',
          'top_posters',
          'most_liked',
          'top_logins',
          'top_couriers',
          'okey_most_played',
          'okey_most_wins',
          'okey_most_losses',
          'okey_win_rate',
          'okey_richest',
          'okey_points_won',
          'okey_hands_won',
          'okey_best_score',
        ],
      );
      expect(
        LeaderboardBoard.topSellers.settingKey,
        'leaderboard_board_top_sellers',
      );
      expect(
        LeaderboardBoard.fromKey('top_posters'),
        LeaderboardBoard.topPosters,
      );
      expect(LeaderboardBoard.fromKey('yok'), isNull);
      expect(LeaderboardBoard.stats.isStats, isTrue);
      expect(LeaderboardBoard.statsToday.isStats, isTrue);
      expect(LeaderboardBoard.stats.statGroup, LeaderboardStatGroup.general);
      expect(LeaderboardBoard.statsToday.statGroup, LeaderboardStatGroup.today);
      expect(LeaderboardBoard.topFollowed.statGroup, isNull);
      expect(LeaderboardBoard.topFollowed.isStats, isFalse);
    });

    test('değer etiketleri', () {
      LeaderboardEntry e(double metric, {double? extra}) => LeaderboardEntry(
        rank: 1,
        type: LeaderboardEntityType.user,
        id: 'x',
        name: 'x',
        metric: metric,
        extra: extra,
      );
      expect(LeaderboardBoard.topFollowed.metricLabel(e(19)), '19 takipçi');
      expect(LeaderboardBoard.topSellers.metricLabel(e(13)), '13 sipariş');
      expect(LeaderboardBoard.topCustomers.metricLabel(e(2)), '2 sipariş');
      expect(LeaderboardBoard.topCouriers.metricLabel(e(2)), '2 teslimat');
      expect(LeaderboardBoard.topPosters.metricLabel(e(21)), '21 gönderi');
      expect(LeaderboardBoard.mostLiked.metricLabel(e(46)), '46 beğeni');
      expect(LeaderboardBoard.topLikedPosts.metricLabel(e(9)), '9 beğeni');
      expect(
        LeaderboardBoard.topViewedPosts.metricLabel(e(59)),
        '59 görüntülenme',
      );
      expect(
        LeaderboardBoard.topViewedStories.metricLabel(e(12)),
        '12 izlenme',
      );
      expect(LeaderboardBoard.topLogins.metricLabel(e(8)), '8 giriş');
      expect(LeaderboardBoard.topProductSellers.metricLabel(e(12)), '12 ürün');
      expect(LeaderboardBoard.topRatedShops.metricLabel(e(5)), '5.0');
      // 101 Okey
      expect(LeaderboardBoard.okeyMostPlayed.metricLabel(e(151)), '151 maç');
      expect(LeaderboardBoard.okeyMostWins.metricLabel(e(55)), '55 galibiyet');
      expect(
        LeaderboardBoard.okeyMostLosses.metricLabel(e(96)),
        '96 mağlubiyet',
      );
      expect(LeaderboardBoard.okeyWinRate.metricLabel(e(71.4)), '%71');
      expect(LeaderboardBoard.okeyRichest.metricLabel(e(9610)), '9.610 puan');
      expect(
        LeaderboardBoard.okeyPointsWon.metricLabel(e(19844)),
        '19.844 puan',
      );
      expect(LeaderboardBoard.okeyHandsWon.metricLabel(e(13)), '13 el');
      // En iyi skor düşük olandır ve NEGATİF olabilir: işaret korunur.
      expect(LeaderboardBoard.okeyBestScore.metricLabel(e(-303)), '-303');
      expect(LeaderboardBoard.okeyBestScore.metricLabel(e(12)), '12');
      expect(
        LeaderboardBoard.topRatedShops.metricSubLabel(e(5, extra: 7)),
        '7 yorum',
      );
      expect(
        LeaderboardBoard.topFollowed.metricSubLabel(e(5, extra: 7)),
        isNull,
      );
      // Kazanma oranının altında oynanan maç sayısı.
      expect(
        LeaderboardBoard.okeyWinRate.metricSubLabel(e(71.4, extra: 7)),
        '7 maç',
      );
      expect(LeaderboardBoard.okeyWinRate.metricSubLabel(e(71.4)), isNull);
    });

    test('Okey kartları döneme duyarsızdır (okey_stats birikimlidir)', () {
      final okey = LeaderboardBoard.values.where(
        (b) => b.key.startsWith('okey_'),
      );
      expect(okey.length, 8);
      for (final board in okey) {
        expect(board.periodAware, isFalse, reason: board.key);
        expect(board.caption(LeaderboardPeriod.week), board.description);
        expect(board.isStats, isFalse);
      }
    });

    test('dönem notu yalnız döneme duyarlı kartlarda görünür', () {
      expect(
        LeaderboardBoard.topSellers.caption(LeaderboardPeriod.month),
        'Son 30 gün',
      );
      expect(
        LeaderboardBoard.topFollowed.caption(LeaderboardPeriod.month),
        isNot(contains('Son 30 gün')),
      );
      // Hikaye kartı yalnız yayındakileri sıralar; dönem ona uygulanmaz.
      expect(LeaderboardBoard.topViewedStories.periodAware, isFalse);
    });
  });

  group('LeaderboardSnapshot', () {
    Map<String, dynamic> json({
      Map<String, dynamic>? boards,
      Map<String, dynamic>? stats,
      Map<String, dynamic>? settings,
    }) => {
      'settings': settings ?? _settingsJson(limit: 3),
      'boards': boards ?? <String, dynamic>{},
      'stats': stats ?? <String, dynamic>{},
    };

    test(
      'kartlar, sıralı ve yalnız açık olanlar; sayaç yoksa sayaç kartı yok',
      () {
        final empty = LeaderboardSnapshot.fromJson(
          json(
            settings: _settingsJson(
              on: {'stats', 'top_followed'},
              order: ['stats', 'top_followed'],
            ),
          ),
        );
        expect(empty.cards, [LeaderboardBoard.topFollowed]);

        final withStats = LeaderboardSnapshot.fromJson(
          json(
            settings: _settingsJson(
              on: {'stats', 'top_followed'},
              order: ['stats', 'top_followed'],
            ),
            stats: {'members': 160, 'orders': 23},
          ),
        );
        expect(withStats.cards, [
          LeaderboardBoard.stats,
          LeaderboardBoard.topFollowed,
        ]);
        expect(withStats.statsFor(LeaderboardBoard.stats), [
          LeaderboardStat.members,
          LeaderboardStat.orders,
        ]);
        expect(withStats.stats['members'], 160);
      },
    );

    test(
      'sayaç kartları kendi grubunu gösterir; boş grubun kartı çizilmez',
      () {
        final snapshot = LeaderboardSnapshot.fromJson(
          json(
            settings: _settingsJson(
              on: {'stats', 'stats_today'},
              order: ['stats', 'stats_today'],
            ),
            stats: {
              'members': 153,
              'guests': 7,
              'visitors_today': 8,
              'online_now': 1,
            },
          ),
        );
        expect(snapshot.statsFor(LeaderboardBoard.stats), [
          LeaderboardStat.members,
          LeaderboardStat.guests,
        ]);
        expect(snapshot.statsFor(LeaderboardBoard.statsToday), [
          LeaderboardStat.visitorsToday,
          LeaderboardStat.onlineNow,
        ]);
        expect(snapshot.statsFor(LeaderboardBoard.topFollowed), isEmpty);
        expect(snapshot.cards, [
          LeaderboardBoard.stats,
          LeaderboardBoard.statsToday,
        ]);

        // Günlük sayaç yoksa günlük kart da yok.
        final onlyGeneral = LeaderboardSnapshot.fromJson(
          json(
            settings: _settingsJson(
              on: {'stats', 'stats_today'},
              order: ['stats', 'stats_today'],
            ),
            stats: {'members': 153},
          ),
        );
        expect(onlyGeneral.cards, [LeaderboardBoard.stats]);
      },
    );

    test('ilk N görünür, sırası N dışındaki kendi satırın ayrı gelir', () {
      final snapshot = LeaderboardSnapshot.fromJson(
        json(
          settings: _settingsJson(limit: 3),
          boards: {
            'top_followed': [
              _row(1),
              _row(2),
              _row(3),
              _row(7, me: true, name: 'Ben'),
            ],
          },
        ),
      );
      expect(
        snapshot.topEntries(LeaderboardBoard.topFollowed).map((e) => e.rank),
        [1, 2, 3],
      );
      final mine = snapshot.myEntryBeyondTop(LeaderboardBoard.topFollowed);
      expect(mine?.rank, 7);
      expect(mine?.name, 'Ben');
    });

    test('ilk N içindeki kendi satırın "beyond" sayılmaz', () {
      final snapshot = LeaderboardSnapshot.fromJson(
        json(
          settings: _settingsJson(limit: 3),
          boards: {
            'top_followed': [_row(1), _row(2, me: true), _row(3)],
          },
        ),
      );
      expect(snapshot.myEntryBeyondTop(LeaderboardBoard.topFollowed), isNull);
      expect(snapshot.topEntries(LeaderboardBoard.topFollowed).length, 3);
    });

    test('bozuk pano ve sayaç değerleri atlanır', () {
      final snapshot = LeaderboardSnapshot.fromJson(
        json(
          boards: {
            'top_followed': 'bozuk',
            'most_liked': [_row(1)],
          },
          stats: {'members': 'x', 'orders': 5},
        ),
      );
      expect(snapshot.boards.containsKey('top_followed'), isFalse);
      expect(snapshot.boards['most_liked']!.length, 1);
      expect(snapshot.stats, {'orders': 5});
    });

    test('boş anlık görüntü hiç kart göstermez', () {
      expect(LeaderboardSnapshot.empty.cards, isEmpty);
    });
  });

  group('LeaderboardVisibility', () {
    test('kim gizledi etiketi', () {
      expect(const LeaderboardVisibility().hidden, isFalse);
      expect(const LeaderboardVisibility().label, '');
      expect(
        const LeaderboardVisibility(selfHidden: true).label,
        contains('kendisi'),
      );
      expect(
        const LeaderboardVisibility(adminHidden: true).label,
        contains('admin'),
      );
      expect(
        const LeaderboardVisibility(selfHidden: true, adminHidden: true).label,
        contains('admin + kendisi'),
      );
      expect(const LeaderboardVisibility(adminHidden: true).hidden, isTrue);
    });

    test('fromJson', () {
      final v = LeaderboardVisibility.fromJson({
        'self_hidden': true,
        'admin_hidden': false,
      });
      expect(v.selfHidden, isTrue);
      expect(v.adminHidden, isFalse);
    });
  });

  group('formatCount', () {
    test('binlik ayraç', () {
      expect(formatCount(0), '0');
      expect(formatCount(999), '999');
      expect(formatCount(1000), '1.000');
      expect(formatCount(160), '160');
      expect(formatCount(1234567), '1.234.567');
    });
  });

  group('relativeJoinLabel', () {
    final now = DateTime(2026, 9, 21, 14, 0);

    test('bir saatten yeni: az önce', () {
      expect(
        relativeJoinLabel(now.subtract(const Duration(minutes: 20)), now: now),
        'Az önce',
      );
    });

    test('bugün: saat önce', () {
      expect(
        relativeJoinLabel(DateTime(2026, 9, 21, 9, 0), now: now),
        '5 saat önce',
      );
    });

    test('dün gece yarısından önceki katılım "Dün" der, saat saymaz', () {
      expect(relativeJoinLabel(DateTime(2026, 9, 20, 23, 30), now: now), 'Dün');
    });

    test('gün, ay ve yıl', () {
      expect(
        relativeJoinLabel(DateTime(2026, 9, 16, 15, 0), now: now),
        '5 gün önce',
      );
      expect(
        relativeJoinLabel(DateTime(2026, 6, 21, 15, 0), now: now),
        '3 ay önce',
      );
      expect(
        relativeJoinLabel(DateTime(2024, 9, 21, 15, 0), now: now),
        '2 yıl önce',
      );
    });
  });
}
