import 'dart:io';

import 'package:cizreapp/okey/services/okey_invite_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// ARKADAŞ DAVETİ — istemci modelleri ve sunucu sözleşmesi.
///
/// Davetin can alıcı noktaları sunucudadır (kim kimi davet edebilir, kabul
/// masaya oturmakla aynı işlem mi, bildirim kime gidiyor). Bu yüzden testin
/// bir yarısı göç dosyasının o kararları GERÇEKTEN kodladığını doğrular.
void main() {
  group('OkeyInviteCandidate', () {
    OkeyInviteCandidate candidate({
      bool inRoom = false,
      bool invited = false,
    }) => OkeyInviteCandidate(
      userId: 'u1',
      displayName: 'Aleyna Ü.',
      points: 4820,
      isFriend: true,
      inRoom: inRoom,
      invited: invited,
    );

    test('masada oturan ya da daveti bekleyen kişi tekrar davet edilemez', () {
      expect(candidate().canInvite, isTrue);
      expect(candidate(inRoom: true).canInvite, isFalse);
      expect(candidate(invited: true).canInvite, isFalse);
    });

    test('copyWith yalnız davet durumunu değiştirir', () {
      final before = candidate();
      final after = before.copyWith(invited: true);
      expect(after.invited, isTrue);
      expect(after.userId, before.userId);
      expect(after.displayName, before.displayName);
      expect(after.points, before.points);
      expect(after.isFriend, before.isFriend);
    });

    test('sunucu haritası okunur, eksik alanlar güvenli varsayılana düşer', () {
      final c = OkeyInviteCandidate.fromMap({
        'user_id': 'u9',
        'display_name': 'Barkın',
        'avatar_url': null,
        'points': 750,
        'is_friend': true,
        'in_room': false,
        'invited': false,
      });
      expect(c.userId, 'u9');
      expect(c.points, 750);
      expect(c.isFriend, isTrue);
      expect(c.canInvite, isTrue);

      // Eski/eksik bir satır çökertmez.
      final bare = OkeyInviteCandidate.fromMap({'user_id': 'u10'});
      expect(bare.displayName, 'Oyuncu');
      expect(bare.points, 0);
      expect(bare.isFriend, isFalse);
    });
  });

  group('OkeyRoomInvite', () {
    test('sunucu haritası okunur', () {
      final i = OkeyRoomInvite.fromMap({
        'invite_id': 'i1',
        'room_id': 'r1',
        'inviter_id': 'u1',
        'inviter_name': 'Aleyna Ü.',
        'inviter_avatar': null,
        'table_stake': 1500,
        'total_hands': 3,
        'game_mode': 'katlamali',
        'team_mode': 'esli',
        'assist_mode': 'yardimsiz',
        'seated_count': 2,
        'created_at': '2026-09-05T10:00:00.000Z',
      });
      expect(i.inviteId, 'i1');
      expect(i.roomId, 'r1');
      expect(i.tableStake, 1500);
      expect(i.seatedCount, 2);
      expect(i.teamMode, 'esli');
    });

    test('eksik alanlar güvenli varsayılana düşer', () {
      final i = OkeyRoomInvite.fromMap({
        'invite_id': 'i2',
        'room_id': 'r2',
        'inviter_id': 'u2',
        'created_at': '2026-09-05T10:00:00.000Z',
      });
      expect(i.inviterName, 'Bir oyuncu');
      expect(i.tableStake, 0);
      expect(i.totalHands, 3);
      expect(i.gameMode, 'katlamasiz');
    });
  });

  group('APP: hata kodları', () {
    test('sunucu kodları eyleme dönük Türkçe cümleye çevrilir', () {
      expect(
        OkeyInviteService.friendlyError(
          Exception('PostgrestException(message: APP:not_following)'),
        ),
        contains('takip ettiğin'),
      );
      expect(
        OkeyInviteService.friendlyError(Exception('APP:room_full')),
        contains('boş koltuk kalmadı'),
      );
      expect(
        OkeyInviteService.friendlyError(Exception('APP:invite_rate_limited')),
        contains('çok fazla davet'),
      );
    });

    test('tanınmayan hata HAM Postgres metnini ekrana sızdırmaz', () {
      final msg = OkeyInviteService.friendlyError(
        Exception('PostgrestException(message: 42P01 relation does not exist)'),
      );
      expect(msg, 'İşlem tamamlanamadı, tekrar dene.');
      expect(msg, isNot(contains('42P01')));
    });
  });

  group('sunucu sözleşmesi (20260905000002 göçü)', () {
    late String migration;

    setUpAll(() {
      migration = File(
        'supabase/migrations/20260905000002_okey_room_invites.sql',
      ).readAsStringSync();
    });

    test('davet tablosu istemciye YAZMA izni vermez', () {
      // Doğrulamanın tamamı RPC'lerde; tabloya doğrudan yazılabilseydi
      // takip kontrolü de hız sınırı da atlanabilirdi.
      expect(
        migration,
        contains(
          'ALTER TABLE public.okey_room_invites ENABLE ROW LEVEL SECURITY',
        ),
      );
      expect(
        migration,
        contains('GRANT SELECT ON public.okey_room_invites TO authenticated'),
      );
      expect(migration, isNot(contains('FOR INSERT TO authenticated')));
      expect(
        migration,
        isNot(contains('GRANT INSERT ON public.okey_room_invites')),
      );
      expect(
        migration,
        isNot(contains('GRANT UPDATE ON public.okey_room_invites')),
      );
    });

    test('yalnız takip edilen kişi davet edilebilir', () {
      expect(migration, contains("RAISE EXCEPTION 'APP:not_following'"));
      expect(
        migration,
        contains(
          'WHERE f.follower_id = v_uid AND f.following_id = p_invitee_id',
        ),
      );
    });

    test('misafir hesap ne listelenir ne davet edilir', () {
      expect(migration, contains('COALESCE(u.is_anonymous, false) = false'));
      expect(
        migration,
        contains("RAISE EXCEPTION 'APP:invitee_not_invitable'"),
      );
    });

    test('boş koltuk yoksa davet edilemez', () {
      expect(migration, contains("RAISE EXCEPTION 'APP:room_full'"));
      expect(migration, contains("v_room.status <> 'waiting'"));
    });

    test('davet spamı iki katmanla kesilir', () {
      expect(migration, contains("RAISE EXCEPTION 'APP:invite_already_sent'"));
      expect(migration, contains("RAISE EXCEPTION 'APP:invite_rate_limited'"));
    });

    test('KABUL = masaya oturmak; oturma başarısızsa kabul yazılmaz', () {
      final acceptStart = migration.indexOf(
        'CREATE FUNCTION public.okey_accept_room_invite',
      );
      final acceptEnd = migration.indexOf(
        'CREATE FUNCTION public.okey_decline_room_invite',
      );
      expect(acceptStart, greaterThan(-1));
      expect(acceptEnd, greaterThan(acceptStart));
      final accept = migration.substring(acceptStart, acceptEnd);

      // Oturma çağrısı, daveti 'accepted' yapan UPDATE'ten ÖNCE gelmeli.
      final join = accept.indexOf('public.join_okey_room(');
      final update = accept.indexOf("SET status = 'accepted'");
      expect(join, greaterThan(-1));
      expect(update, greaterThan(join));
    });

    test('davet EDENE bildirim gider (kabul ve ret)', () {
      expect(migration, contains("'okey_invite_accepted'"));
      expect(migration, contains("'okey_invite_declined'"));
      expect(migration, contains('v_invite.inviter_id,'));
    });

    test('kabul/ret bildiriminin entity_id\'si DAVET kimliğidir', () {
      // Oda kimliği kullanılsaydı dedup_notification (user_id, entity_id,
      // type) tekilliği yüzünden ikinci arkadaşın kabulü, birincinin
      // bildirimini SİLERDİ.
      expect(migration, contains("v_invite.id::text, 'okey_room_invite'"));
    });

    test('dedup_notification sabit search_path ile onarıldı', () {
      // Trigger, çağıranın search_path'iyle çalışır; sabitlenmemişken
      // `SET search_path = ''` olan her fonksiyonun notifications INSERT'i
      // "relation notifications does not exist" ile düşüyordu.
      expect(
        migration,
        contains('CREATE OR REPLACE FUNCTION public.dedup_notification()'),
      );
      expect(migration, contains('SET search_path = public, pg_temp'));
      expect(migration, contains('DELETE FROM public.notifications'));
    });

    test('RPC yetkileri anon\'a kapalı, authenticated\'a açık', () {
      for (final fn in const [
        'public.okey_invitable_friends(uuid, text, int)',
        'public.okey_invite_to_room(uuid, uuid)',
        'public.okey_my_room_invites()',
        'public.okey_accept_room_invite(uuid)',
        'public.okey_decline_room_invite(uuid)',
      ]) {
        expect(
          migration,
          contains('REVOKE ALL ON FUNCTION $fn FROM PUBLIC, anon'),
        );
        expect(
          migration,
          contains('GRANT EXECUTE ON FUNCTION $fn TO authenticated'),
        );
      }
      expect(migration, contains("NOTIFY pgrst, 'reload schema'"));
    });
  });
}
