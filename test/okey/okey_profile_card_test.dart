import 'package:cizreapp/okey/services/okey_profile_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// PROFİL KARTI — türetilen sayılar
///
/// Kaybedilen maç ve kazanma oranı sunucudan AYRICA gelmez; oynanan ve
/// kazanılan maçtan türetilir. Ayrı sütunlar olsaydı "oynanan = kazanılan +
/// kaybedilen" değişmezini iki yerde korumak gerekirdi.

OkeyProfileCard _card({int played = 0, int won = 0}) => OkeyProfileCard(
  displayName: 'Oyuncu',
  points: 100,
  matchesPlayed: played,
  matchesWon: won,
  handsPlayed: 0,
  handsWon: 0,
  followersCount: 0,
  followingCount: 0,
  friendsCount: 0,
);

void main() {
  group('OkeyProfileCard', () {
    test('kaybedilen maç = oynanan − kazanılan', () {
      expect(_card(played: 214, won: 98).matchesLost, 116);
    });

    test('hiç maç yoksa oran 0, kaybedilen 0', () {
      final c = _card();
      expect(c.winRate, 0);
      expect(c.matchesLost, 0);
      expect(c.winRateLabel, '%0');
    });

    test('kazanma oranı ve etiketi', () {
      expect(_card(played: 200, won: 92).winRate, closeTo(0.46, 0.0001));
      expect(_card(played: 200, won: 92).winRateLabel, '%46');
      expect(_card(played: 3, won: 3).winRateLabel, '%100');
    });

    test('bozuk istatistik NEGATİF sayı göstermez', () {
      // Eski/bozuk bir okey_stats satırı kazanılanı oynanandan büyük
      // gösterebilir; kart "-4 kaybedilen" yazmamalı.
      expect(_card(played: 2, won: 6).matchesLost, 0);
    });

    test(
      'sunucu haritası okunur ve eksik alanlar güvenli varsayılana düşer',
      () {
        final c = OkeyProfileCard.fromMap({
          'user_id': 'u1',
          'display_name': 'Aleyna Ü.',
          'points': 4820,
          'matches_played': 214,
          'matches_won': 98,
          'followers_count': 128,
          'following_count': 96,
          'friends_count': 41,
          'is_following': true,
        });
        expect(c.userId, 'u1');
        expect(c.displayName, 'Aleyna Ü.');
        expect(c.points, 4820);
        expect(c.matchesLost, 116);
        expect(c.winRateLabel, '%46');
        expect(c.friendsCount, 41);
        expect(c.isFollowing, isTrue);
        // Gelmeyen alanlar çökmeye değil varsayılana düşer.
        expect(c.bestMatchScore, isNull);
        expect(c.handsWon, 0);
        expect(c.isSelf, isFalse);
      },
    );

    test('bot kartında user_id null olur (kart yine çizilir)', () {
      final c = OkeyProfileCard.fromMap({
        'display_name': 'Murat D.',
        'matches_played': 180,
        'matches_won': 84,
      });
      expect(c.userId, isNull);
      expect(c.displayName, 'Murat D.');
      expect(c.winRateLabel, '%47');
    });
  });
}
