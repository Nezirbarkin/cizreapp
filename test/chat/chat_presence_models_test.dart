import 'package:cizreapp/features/chat/models/chat_presence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PresenceLabels.lastSeenAgo', () {
    // 2026-09-21 Pazartesi, 15:00 Türkiye saati (12:00 UTC).
    final now = DateTime.utc(2026, 9, 21, 12, 0, 0);

    String ago(DateTime seen) => PresenceLabels.lastSeenAgo(seen, now: now);

    test('bir dakikadan yeni: "az önce"', () {
      expect(ago(now), 'az önce');
      expect(ago(now.subtract(const Duration(seconds: 59))), 'az önce');
    });

    test('bir saatten yeni: dakika cinsinden', () {
      expect(ago(now.subtract(const Duration(seconds: 60))), '1 dk önce');
      expect(ago(now.subtract(const Duration(minutes: 12))), '12 dk önce');
      expect(ago(now.subtract(const Duration(minutes: 59))), '59 dk önce');
    });

    test('aynı gün: "bugün SS:dd" Türkiye saatiyle', () {
      // 10:30 UTC = 13:30 TR
      expect(ago(DateTime.utc(2026, 9, 21, 10, 30)), 'bugün 13:30');
    });

    test('gün sınırı UTC ile değil TÜRKİYE saatiyle hesaplanır', () {
      // Şimdi: 22 Eylül 01:30 TR (21 Eylül 22:30 UTC). Görülme: 21 Eylül 23:30 TR
      // (20:30 UTC) — yalnız 2 saat önce ama TAKVİM günü dün.
      final lateNow = DateTime.utc(2026, 9, 21, 22, 30);
      final seen = DateTime.utc(2026, 9, 21, 20, 30);
      expect(PresenceLabels.lastSeenAgo(seen, now: lateNow), 'dün 23:30');
    });

    test('dün', () {
      // 20 Eylül 21:10 TR = 18:10 UTC
      expect(ago(DateTime.utc(2026, 9, 20, 18, 10)), 'dün 21:10');
    });

    test('2-6 gün önce: gün adı', () {
      // 19 Eylül Cumartesi 12:00 TR
      expect(ago(DateTime.utc(2026, 9, 19, 9, 0)), 'Cumartesi 12:00');
      // 15 Eylül Salı — tam 6 takvim günü önce
      expect(ago(DateTime.utc(2026, 9, 15, 9, 0)), 'Salı 12:00');
    });

    test('7 gün ve daha eskisi: tarih (yalnız yönetici sınırı genişletirse görünür)', () {
      expect(ago(DateTime.utc(2026, 9, 14, 9, 0)), '14.09.2026');
      expect(ago(DateTime.utc(2025, 12, 31, 21, 30)), '01.01.2026');
    });

    test('gelecekteki zaman (saat kayması) "az önce" sayılır', () {
      expect(ago(now.add(const Duration(minutes: 5))), 'az önce');
    });

    test('yerel/ofsetli DateTime aynı ana işaret eder', () {
      expect(ago(DateTime.parse('2026-09-20T21:10:00+03:00')), 'dün 21:10');
    });

    test('lastSeen öneki ekler', () {
      expect(
        PresenceLabels.lastSeen(
          now.subtract(const Duration(minutes: 5)),
          now: now,
        ),
        'son görülme 5 dk önce',
      );
    });

    test('gün adları Pazartesi..Pazar doğru eşlenir', () {
      // 21 Eylül 2026 Pazartesi'den geriye 2..6 gün
      const expected = {
        2: 'Cumartesi', // 19
        3: 'Cuma', // 18
        4: 'Perşembe', // 17
        5: 'Çarşamba', // 16
        6: 'Salı', // 15
      };
      expected.forEach((days, name) {
        final seen = DateTime.utc(2026, 9, 21 - days, 9, 0);
        expect(ago(seen), '$name 12:00', reason: '$days gün önce');
      });
    });
  });

  group('PresenceLabels.typingNames', () {
    test('kişi sayısına göre metin', () {
      expect(PresenceLabels.typingNames(const []), 'yazıyor');
      expect(PresenceLabels.typingNames(const ['Ali']), 'Ali yazıyor');
      expect(
        PresenceLabels.typingNames(const ['Ali', 'Ayşe']),
        'Ali ve Ayşe yazıyor',
      );
      expect(
        PresenceLabels.typingNames(const ['Ali', 'Ayşe', 'Can']),
        '3 kişi yazıyor',
      );
    });

    test('boş adlar sayılmaz', () {
      expect(PresenceLabels.typingNames(const ['', '  ', 'Ali']), 'Ali yazıyor');
      expect(PresenceLabels.typingNames(const ['', '  ']), 'yazıyor');
    });
  });

  group('ChatPresenceSettings', () {
    test('sunucu cevabı okunur', () {
      final s = ChatPresenceSettings.fromJson({
        'last_seen': false,
        'last_seen_in_chat': true,
        'last_seen_in_profile': false,
        'last_seen_max_days': 14,
        'online': false,
        'typing': true,
        'typing_in_groups': false,
      });
      expect(s.lastSeen, isFalse);
      expect(s.lastSeenInChat, isTrue);
      expect(s.lastSeenInProfile, isFalse);
      expect(s.lastSeenMaxDays, 14);
      expect(s.online, isFalse);
      expect(s.typing, isTrue);
      expect(s.typingInGroups, isFalse);
    });

    test('eksik ya da bozuk alan varsayılana (açık, 7 gün) düşer', () {
      final s = ChatPresenceSettings.fromJson({
        'last_seen': 'evet', // bool değil
        'last_seen_max_days': '7', // sayı değil
        'online': null,
      });
      expect(s, const ChatPresenceSettings());
      expect(s.lastSeenMaxDays, 7);
    });

    test('gün aralığı dışı (0, 366, negatif) 7 olur; ondalık sayı tamsayıya çevrilir', () {
      for (final bad in [0, 366, -3, 100000]) {
        expect(
          ChatPresenceSettings.fromJson({'last_seen_max_days': bad}).lastSeenMaxDays,
          7,
          reason: '$bad',
        );
      }
      expect(
        ChatPresenceSettings.fromJson({'last_seen_max_days': 30.0}).lastSeenMaxDays,
        30,
      );
      expect(
        ChatPresenceSettings.fromJson({'last_seen_max_days': 1}).lastSeenMaxDays,
        1,
      );
      expect(
        ChatPresenceSettings.fromJson({'last_seen_max_days': 365}).lastSeenMaxDays,
        365,
      );
    });

    test('showsLastSeen ana anahtarı ve bağlamı birlikte değerlendirir', () {
      const on = ChatPresenceSettings();
      expect(on.showsLastSeen(PresenceContext.chat), isTrue);
      expect(on.showsLastSeen(PresenceContext.profile), isTrue);
      expect(on.showsLastSeen(PresenceContext.list), isTrue);

      final masterOff = on.copyWith(lastSeen: false);
      for (final c in PresenceContext.values) {
        expect(masterOff.showsLastSeen(c), isFalse, reason: 'ana anahtar kapalı: $c');
      }

      final noChat = on.copyWith(lastSeenInChat: false);
      expect(noChat.showsLastSeen(PresenceContext.chat), isFalse);
      // liste sohbet gibi davranır (sunucuyla aynı)
      expect(noChat.showsLastSeen(PresenceContext.list), isFalse);
      expect(noChat.showsLastSeen(PresenceContext.profile), isTrue);

      final noProfile = on.copyWith(lastSeenInProfile: false);
      expect(noProfile.showsLastSeen(PresenceContext.profile), isFalse);
      expect(noProfile.showsLastSeen(PresenceContext.chat), isTrue);
    });

    test('showsAnyPresence: çevrimiçi ya da son görülmeden biri açıksa true', () {
      const on = ChatPresenceSettings();
      expect(on.copyWith(online: false).showsAnyPresence(PresenceContext.chat), isTrue);
      expect(on.copyWith(lastSeen: false).showsAnyPresence(PresenceContext.chat), isTrue);
      expect(
        on.copyWith(online: false, lastSeen: false).showsAnyPresence(PresenceContext.chat),
        isFalse,
      );
      // yalnız profil kapalıysa profil bağlamında da çevrimiçi hâlâ gösterilebilir
      expect(
        on
            .copyWith(online: false, lastSeenInProfile: false)
            .showsAnyPresence(PresenceContext.profile),
        isFalse,
      );
    });

    test('yazıyor: grup, ana anahtara bağlıdır', () {
      const on = ChatPresenceSettings();
      expect(on.typingEnabled, isTrue);
      expect(on.groupTypingEnabled, isTrue);
      expect(on.copyWith(typingInGroups: false).groupTypingEnabled, isFalse);
      expect(on.copyWith(typingInGroups: false).typingEnabled, isTrue);
      final off = on.copyWith(typing: false);
      expect(off.typingEnabled, isFalse);
      expect(off.groupTypingEnabled, isFalse, reason: 'ana anahtar kapalıyken alt anahtar etkisiz');
    });

    test('eşitlik ve hashCode alanlara bakar', () {
      expect(const ChatPresenceSettings(), const ChatPresenceSettings());
      expect(
        const ChatPresenceSettings().hashCode,
        const ChatPresenceSettings().hashCode,
      );
      expect(
        const ChatPresenceSettings(),
        isNot(const ChatPresenceSettings(lastSeenMaxDays: 8)),
      );
    });
  });

  group('UserPresence', () {
    test('sunucu satırı okunur', () {
      final p = UserPresence.fromJson({
        'user_id': 'u1',
        'can_see_online': true,
        'online': false,
        'last_seen': '2026-09-20T18:10:00+00:00',
      });
      expect(p.userId, 'u1');
      expect(p.canSeeOnline, isTrue);
      expect(p.online, isFalse);
      expect(p.lastSeen, DateTime.utc(2026, 9, 20, 18, 10));
    });

    test('last_seen null ya da bozuksa null olur; bayraklar varsayılan false', () {
      expect(UserPresence.fromJson({'user_id': 'u', 'last_seen': null}).lastSeen, isNull);
      expect(UserPresence.fromJson({'user_id': 'u', 'last_seen': 'dün'}).lastSeen, isNull);
      final p = UserPresence.fromJson({'user_id': 'u'});
      expect(p.canSeeOnline, isFalse);
      expect(p.online, isFalse);
    });

    test('hidden hiçbir şey göstermez', () {
      const p = UserPresence.hidden('u');
      expect(p.canSeeOnline, isFalse);
      expect(p.online, isFalse);
      expect(p.lastSeen, isNull);
    });
  });

  group('LastSeenAudience ve ChatPrivacyPrefs', () {
    test('üçlü seçim iki sütuna eşlenir', () {
      expect(LastSeenAudience.everyone.showLastSeen, isTrue);
      expect(LastSeenAudience.everyone.friendsOnly, isFalse);
      expect(LastSeenAudience.friends.showLastSeen, isTrue);
      expect(LastSeenAudience.friends.friendsOnly, isTrue);
      expect(LastSeenAudience.nobody.showLastSeen, isFalse);
      // "hiç kimse"de arkadaş bayrağı anlamsız: null → RPC önceki değeri korur
      expect(LastSeenAudience.nobody.friendsOnly, isNull);
    });

    test('iki sütundan seçim geri çıkarılır (eski istemci uyumu dahil)', () {
      LastSeenAudience of(bool show, bool friends) =>
          LastSeenAudience.fromColumns(showLastSeen: show, friendsOnly: friends);
      expect(of(true, false), LastSeenAudience.everyone);
      expect(of(true, true), LastSeenAudience.friends);
      expect(of(false, false), LastSeenAudience.nobody);
      // eski istemci show_last_seen'i kapatırsa arkadaş bayrağı ne olursa olsun "hiç kimse"
      expect(of(false, true), LastSeenAudience.nobody);
    });

    test('profil satırından tercihler okunur, eksikse varsayılan', () {
      final prefs = ChatPrivacyPrefs.fromProfile({
        'show_last_seen': true,
        'last_seen_friends_only': true,
        'show_typing_indicator': false,
      });
      expect(prefs.lastSeenAudience, LastSeenAudience.friends);
      expect(prefs.showTypingIndicator, isFalse);

      final defaults = ChatPrivacyPrefs.fromProfile(const {});
      expect(defaults.lastSeenAudience, LastSeenAudience.everyone);
      expect(defaults.showTypingIndicator, isTrue);
    });

    test('copyWith yalnız verilen alanı değiştirir', () {
      const base = ChatPrivacyPrefs(
        lastSeenAudience: LastSeenAudience.friends,
        showTypingIndicator: false,
      );
      expect(
        base.copyWith(showTypingIndicator: true).lastSeenAudience,
        LastSeenAudience.friends,
      );
      expect(
        base.copyWith(lastSeenAudience: LastSeenAudience.nobody).showTypingIndicator,
        isFalse,
      );
    });
  });
}
