import 'dart:io';

import 'package:cizreapp/okey/models/okey_models.dart';
import 'package:cizreapp/okey/providers/okey_room_provider.dart';
import 'package:cizreapp/okey/services/okey_points_service.dart';
import 'package:cizreapp/okey/services/okey_sound_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 101 OKEY — İKİ KULLANICI İSTEĞİ (2026-09-08)
///
///  1. "botlarında skorları göster" — skor tablosu yalnızca `okey_stats`'ı
///     okuyordu; botlar ekonominin dışında olduğu için o tabloda satırları
///     yok ve canlı projede listede iki isim görünüyordu.
///  2. "oyuncu katılırken ses çıkartın" — bekleme odası sessizce yoklanıyor,
///     masa oyuncu ekrana bakmıyorken doluyordu.
void main() {
  group('Skor tablosu satırı (istemci)', () {
    test('BOT satırında user_id yoktur, kart bot_profile_id ile açılır', () {
      final e = OkeyLeaderboardEntry.fromMap(const {
        'user_id': null,
        'bot_profile_id': 'bot-1',
        'display_name': 'Ferhat Polat',
        'avatar_url': 'https://x/y.png',
        'points': 9535,
        'matches_played': 375,
        'matches_won': 221,
        'hands_won': 1125,
        'best_match_score': -136,
      });

      expect(e.userId, isNull);
      expect(e.botProfileId, 'bot-1');
      expect(e.displayName, 'Ferhat Polat');
      expect(e.matchesWon, 221);
    });

    test('GERÇEK oyuncu satırında bot_profile_id yoktur', () {
      final e = OkeyLeaderboardEntry.fromMap(const {
        'user_id': 'user-1',
        'bot_profile_id': null,
        'display_name': 'Nezir',
        'points': 1200,
        'matches_played': 4,
        'matches_won': 1,
        'hands_won': 6,
      });

      expect(e.userId, 'user-1');
      expect(e.botProfileId, isNull);
      expect(e.bestMatchScore, isNull);
    });

    test('eksik alanlar satırı düşürmez (eski sunucu sürümü)', () {
      // Sunucu henüz güncellenmemişse `bot_profile_id` hiç gelmez; tablo yine
      // de çizilmeli, çökmemeli.
      final e = OkeyLeaderboardEntry.fromMap(const {
        'user_id': 'user-1',
        'display_name': 'Nezir',
      });

      expect(e.botProfileId, isNull);
      expect(e.points, 0);
      expect(e.matchesPlayed, 0);
    });
  });

  // SQL sunucuda yaşıyor, Dart'ta çalıştırılamıyor: sözleşme METİNDEN
  // doğrulanır (bkz. okey_bot_stake_payout_contract_test.dart — aynı yöntem).
  group('okey_leaderboard göçü', () {
    const path =
        'supabase/migrations/20260908200001_okey_leaderboard_includes_bots.sql';
    late String sql;

    setUpAll(() => sql = File(path).readAsStringSync());

    test('tablo bot kimliklerini de döndürür', () {
      expect(sql, contains('bot_profile_id uuid'));
      expect(sql, contains('FROM public.okey_bot_profiles AS b'));
      expect(sql, contains('UNION ALL'));
    });

    test('yalnız ETKİN botlar listelenir', () {
      expect(sql, contains('WHERE b.is_active'));
    });

    test('bot sayıları TEK kaynaktan gelir — tablo ve kart ayrışamaz', () {
      // Formül iki yere kopyalanırsa tablo ile profil kartı farklı sayılar
      // gösterir ve bu, botu ele veren en açık işaret olurdu.
      expect(sql, contains('CREATE OR REPLACE FUNCTION '
          'public.okey_bot_public_stats(p_bot_profile_id uuid)'));
      expect(
        'public.okey_bot_public_stats(b.id)'.allMatches(sql).length,
        2,
        reason: 'hem okey_leaderboard hem okey_profile_card çağırmalı',
      );
    });

    test('bot istatistikleri SABİTTİR (id tohumu, random değil)', () {
      expect(sql, contains('hashtext(p_bot_profile_id::text)'));
      // Açıklama satırları `random()`'dan NEDEN kaçınıldığını anlatıyor;
      // aranan şey kodun kendisi, o yüzden yorumlar atılır.
      final code = sql
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('--'))
          .join('\n');
      expect(code, isNot(contains('random()')));
    });

    test('bot hesapları gerçek oyuncu dalında sayılmaz', () {
      expect(sql, contains('WHERE NOT COALESCE(p.is_bot, false)'));
    });

    test('yetkiler korunur — anon skor tablosunu okuyamaz', () {
      expect(
        sql,
        contains('REVOKE ALL ON FUNCTION public.okey_leaderboard(int) '
            'FROM PUBLIC, anon;'),
      );
      expect(
        sql,
        contains('GRANT EXECUTE ON FUNCTION public.okey_leaderboard(int) '
            'TO authenticated;'),
      );
    });

    test('oturumsuz çağrı boş döner', () {
      expect(sql, contains('WHERE (SELECT auth.uid()) IS NOT NULL'));
    });
  });

  group('Katılım sesi', () {
    OkeyRoomSeat seat(int no, {String? userId, String? botProfileId}) =>
        OkeyRoomSeat(
          roomId: 'r',
          seatNo: no,
          isReady: false,
          isBot: botProfileId != null,
          userId: userId,
          botProfileId: botProfileId,
        );

    OkeyRoomSeat empty(int no) =>
        OkeyRoomSeat(roomId: 'r', seatNo: no, isReady: false);

    test('boş koltuk dolunca katılım sayılır', () {
      expect(
        OkeyRoomProvider.seatJoined(
          before: [seat(0, userId: 'a'), empty(1)],
          after: [seat(0, userId: 'a'), seat(1, userId: 'b')],
        ),
        isTrue,
      );
    });

    test('BOT oturunca da çalar — sessizlik botu ele verirdi', () {
      expect(
        OkeyRoomProvider.seatJoined(
          before: [seat(0, userId: 'a'), empty(1)],
          after: [seat(0, userId: 'a'), seat(1, botProfileId: 'bot-1')],
        ),
        isTrue,
      );
    });

    test('hiçbir şey değişmediyse ses yok', () {
      expect(
        OkeyRoomProvider.seatJoined(
          before: [seat(0, userId: 'a'), seat(1, botProfileId: 'bot-1')],
          after: [seat(0, userId: 'a'), seat(1, botProfileId: 'bot-1')],
        ),
        isFalse,
      );
    });

    test('oyuncu ÇIKINCA ses yok', () {
      expect(
        OkeyRoomProvider.seatJoined(
          before: [seat(0, userId: 'a'), seat(1, userId: 'b')],
          after: [seat(0, userId: 'a'), empty(1)],
        ),
        isFalse,
      );
    });

    test('aynı koltuğa BAŞKASI oturursa katılım sayılır', () {
      expect(
        OkeyRoomProvider.seatJoined(
          before: [seat(1, userId: 'b')],
          after: [seat(1, userId: 'c')],
        ),
        isTrue,
      );
    });

    test('hazır durumu değişmesi katılım DEĞİLDİR', () {
      expect(
        OkeyRoomProvider.seatJoined(
          before: [seat(0, userId: 'a')],
          after: [
            OkeyRoomSeat(roomId: 'r', seatNo: 0, isReady: true, userId: 'a'),
          ],
        ),
        isFalse,
      );
    });

    test('iki koltuk birden dolsa bile tek karar döner', () {
      // Sağlayıcı bu karara göre sesi BİR kez çalar; iki ses üst üste binerdi.
      expect(
        OkeyRoomProvider.seatJoined(
          before: [seat(0, userId: 'a'), empty(1), empty(2)],
          after: [
            seat(0, userId: 'a'),
            seat(1, botProfileId: 'bot-1'),
            seat(2, botProfileId: 'bot-2'),
          ],
        ),
        isTrue,
      );
    });

    test('katılım sesinin örnek dosyası depoda var', () {
      final file = File('assets/${OkeySound.playerJoin.assetPath}');
      expect(file.existsSync(), isTrue, reason: file.path);
      expect(file.lengthSync(), greaterThan(1000));
    });
  });
}
