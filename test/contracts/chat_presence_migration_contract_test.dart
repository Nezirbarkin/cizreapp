import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Sohbet durumu (son görülme / çevrimiçi / yazıyor) göçünün GÜVENLİK ŞEKLİ.
///
/// Davranış canlı veritabanında `supabase/tests/manual/chat_presence_and_typing_test.sql`
/// ile kanıtlanır; bu test, yanlışlıkla geri alınması sessizce gizlilik sızıntısı
/// yaratacak yapısal kararları sabitler:
///
///  * iki profil görünümü ve `get_online_users` MASKELİ kalır (sonradan gelen bir
///    göç eski, maskesiz gövdeyi kopyalayıp `last_seen`'i herkese açamaz);
///  * çözümleyiciye ayar geçirilemez (yoksa istemci yönetici kurallarını atlatırdı);
///  * iç yardımcılar ve gizli anahtar tablosu istemciye kapalı;
///  * yönetici RPC'leri yetki denetler; anahtar beyaz listesi tohumlarla aynı.
void main() {
  const fileName = '20260921000008_chat_presence_and_typing.sql';
  late String sql;
  late List<File> migrations;

  /// `presence_resolve`'ı SON tanımlayan göç (000009 performans için gövdeyi
  /// PL/pgSQL'e taşıdı); kural denetimleri her zaman EN GÜNCEL tanıma bakar.
  late String presenceFile;
  late String presenceSql;

  setUpAll(() {
    sql = File('supabase/migrations/$fileName').readAsStringSync();
    migrations =
        Directory('supabase/migrations')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.sql'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final definers = migrations.where(
      (f) => f.readAsStringSync().contains(
        'CREATE OR REPLACE FUNCTION public.presence_resolve(',
      ),
    );
    expect(definers, isNotEmpty);
    presenceFile = definers.last.uri.pathSegments.last;
    presenceSql = definers.last.readAsStringSync();
  });

  String stripComments(String s) => s
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('--'))
      .join('\n');

  test('göç tek işlemde çalışır ve PostgREST şemasını yeniler', () {
    final code = stripComments(sql);
    expect(RegExp(r'^begin;', multiLine: true, caseSensitive: false).hasMatch(code), isTrue);
    expect(RegExp(r'^commit;', multiLine: true, caseSensitive: false).hasMatch(code), isTrue);
    expect(code, contains("NOTIFY pgrst, 'reload schema';"));
  });

  group('maskeleme', () {
    test('iki görünüm security_invoker ile ve presence_resolve üzerinden yeniden kurulur', () {
      for (final view in ['public_profiles_chat', 'public_profiles_safe']) {
        final match = RegExp(
          'CREATE OR REPLACE VIEW public\\.$view\\s+WITH \\(security_invoker = true\\) AS(.*?);',
          dotAll: true,
        ).firstMatch(sql);
        expect(match, isNotNull, reason: '$view security_invoker=true ile tanımlanmalı');
        expect(
          match!.group(1),
          contains('public.presence_resolve(p.id,'),
          reason: '$view is_online/last_seen değerlerini çözümleyiciden almalı',
        );
      }
    });

    test('görünümler ham last_seen / is_online sütununu doğrudan seçmez', () {
      for (final view in ['public_profiles_chat', 'public_profiles_safe']) {
        final body = RegExp(
          'CREATE OR REPLACE VIEW public\\.$view.*?;',
          dotAll: true,
        ).firstMatch(sql)!.group(0)!;
        // last_seen yalnız CASE içinde (çevrimiçiyse taze nabız) kullanılabilir.
        final rawLastSeen = RegExp(r'^\s*p\.last_seen\s*,', multiLine: true);
        final rawOnline = RegExp(r'^\s*p\.is_online\s*,', multiLine: true);
        expect(rawLastSeen.hasMatch(body), isFalse, reason: '$view ham last_seen döndürüyor');
        expect(rawOnline.hasMatch(body), isFalse, reason: '$view ham is_online döndürüyor');
      }
    });

    test('get_online_users çözümleyiciyle süzülür', () {
      final body = RegExp(
        r'CREATE OR REPLACE FUNCTION public\.get_online_users.*?\$function\$;',
        dotAll: true,
      ).firstMatch(sql)!.group(0)!;
      expect(body, contains('public.presence_resolve(p.id,'));
      expect(body, contains('WHERE pr.online'));
    });

    test('bu üç nesneyi SON tanımlayan göç bu dosyadır (maskesiz eski gövde geri gelmez)', () {
      String? latestDefiner(RegExp pattern) {
        final definers = migrations.where((f) => pattern.hasMatch(f.readAsStringSync()));
        return definers.isEmpty ? null : definers.last.uri.pathSegments.last;
      }

      expect(
        latestDefiner(RegExp(r'CREATE (OR REPLACE )?VIEW public\.public_profiles_chat')),
        fileName,
        reason: 'public_profiles_chat sonradan maskesiz yeniden tanımlanmış',
      );
      expect(
        latestDefiner(RegExp(r'CREATE (OR REPLACE )?VIEW public\.public_profiles_safe')),
        fileName,
        reason: 'public_profiles_safe sonradan maskesiz yeniden tanımlanmış',
      );
      expect(
        latestDefiner(RegExp(r'FUNCTION public\.get_online_users\(')),
        fileName,
        reason: 'get_online_users sonradan maskesiz yeniden tanımlanmış',
      );
    });
  });

  group('çözümleyici', () {
    late String signature;
    setUpAll(() {
      signature = RegExp(
        r'CREATE OR REPLACE FUNCTION public\.presence_resolve\((.*?)\)\s*RETURNS TABLE',
        dotAll: true,
      ).firstMatch(presenceSql)!.group(1)!;
    });

    test('yalnız (hedef, bağlam) alır: ayar/yapılandırma parametresi YOK', () {
      expect(signature, contains('p_target'));
      expect(signature, contains('p_context'));
      expect(
        signature.toLowerCase(),
        isNot(anyOf(contains('jsonb'), contains('cfg'), contains('setting'))),
        reason: 'anon/authenticated çağırabildiği için parametreyle kurallar atlatılabilir',
      );
      expect(RegExp(r'\bp_\w+').allMatches(signature).length, 2);
    });

    String latestBody() => RegExp(
      r'CREATE OR REPLACE FUNCTION public\.presence_resolve.*?\$fn\$;',
      dotAll: true,
    ).firstMatch(presenceSql)!.group(0)!;

    test('görünümler için anon ve authenticated çalıştırabilir', () {
      // CREATE OR REPLACE mevcut yetkileri korur; yine de son tanım niyeti yazar.
      expect(
        presenceSql,
        matches(RegExp(
          r'GRANT EXECUTE ON FUNCTION public\.presence_resolve\(uuid, text\)\s+TO anon, authenticated',
        )),
        reason: '$presenceFile anon/authenticated EXECUTE\'ini yazmıyor',
      );
    });

    test('SECURITY DEFINER ve boş search_path', () {
      final body = latestBody();
      expect(body, contains('SECURITY DEFINER'));
      expect(body, contains("SET search_path = ''"));
    });

    test('gövde PL/pgSQL: yavaş SQL sürümüne (çağrı başına ~5 ms) geri dönülmez', () {
      expect(
        latestBody(),
        contains('LANGUAGE plpgsql'),
        reason:
            'LANGUAGE sql + SECURITY DEFINER her çağrıda yeniden planlanır; 173 satırlık '
            'görünüm 415 ms sürüyordu ($presenceFile bunu ~28 ms\'ye indirdi)',
      );
    });

    test('kural kapıları çözümleyicide bulunur', () {
      final body = latestBody();
      for (final gate in [
        'is_ghost_mode', // hayalet modu
        'is_online_enabled', // çevrimiçi görünme tercihi
        'show_last_seen', // son görülme tercihi
        'last_seen_friends_only', // yalnız arkadaşlar
        'profile_is_public', // gizli hesap
        'blocked_users', // engel
        'public.follows', // takip / arkadaşlık
        "interval '3 minutes'", // nabız tazeliği = PrivacyService.activeThreshold
      ]) {
        expect(body, contains(gate), reason: 'çözümleyicide "$gate" kapısı yok');
      }
      // yönetici süre sınırı (SQL sürümünde cfg->>, PL/pgSQL'de v_cfg ->>)
      expect(
        RegExp(r"cfg\s*->>\s*'last_seen_max_days'").hasMatch(body),
        isTrue,
        reason: 'yönetici süre sınırı uygulanmıyor',
      );
    });
  });

  group('erişim', () {
    test('iç yardımcı chat_presence_cfg dışarıya kapalı', () {
      expect(
        sql,
        matches(RegExp(
          r'REVOKE ALL ON FUNCTION public\.chat_presence_cfg\(\) FROM PUBLIC, anon, authenticated;',
        )),
      );
      expect(
        RegExp(r'GRANT EXECUTE ON FUNCTION public\.chat_presence_cfg\(\)[^;]*authenticated')
            .hasMatch(sql),
        isFalse,
      );
    });

    test('istemci RPC\'leri anon\'a kapalı', () {
      for (final fn in [
        r'get_chat_presence_settings\(\)',
        r'get_user_presence\(uuid\[\], text\)',
        r'get_typing_channel\(uuid\)',
        r'get_group_typing_channel\(uuid\)',
        r'update_my_chat_privacy\(boolean, boolean, boolean\)',
        r'admin_set_chat_presence_setting\(text, text\)',
        r'admin_chat_presence_stats\(\)',
      ]) {
        expect(
          RegExp('REVOKE ALL ON FUNCTION public\\.$fn FROM PUBLIC, anon;').hasMatch(sql),
          isTrue,
          reason: '$fn anon\'dan geri alınmalı',
        );
      }
    });

    test('gizli anahtar tablosu istemciye kapalı ve RLS açık', () {
      expect(sql, contains('ALTER TABLE public.chat_typing_secret ENABLE ROW LEVEL SECURITY;'));
      expect(
        sql,
        contains('REVOKE ALL ON public.chat_typing_secret FROM PUBLIC, anon, authenticated;'),
      );
      // Tabloyu okuyabilecek bir politika tanımlanmamalı.
      expect(
        RegExp(r'CREATE POLICY[^;]*chat_typing_secret').hasMatch(sql),
        isFalse,
      );
    });

    test('yazıyor kanalı adı sunucu sırrıyla HMAC\'lenir, çiftin kimliği sıralıdır', () {
      expect(sql, contains('extensions.hmac('));
      expect(sql, contains('least(v_me::text, p_peer::text)'));
      expect(sql, contains('greatest(v_me::text, p_peer::text)'));
      expect(sql, contains("'sha256'"));
    });

    test('kanal kapıları: engel, admin anahtarı, grup üyeliği', () {
      final direct = RegExp(
        r'CREATE OR REPLACE FUNCTION public\.get_typing_channel.*?\$fn\$;',
        dotAll: true,
      ).firstMatch(sql)!.group(0)!;
      expect(direct, contains('public.social_block_exists(p_peer)'));
      expect(direct, contains("->> 'typing'"));

      final group = RegExp(
        r'CREATE OR REPLACE FUNCTION public\.get_group_typing_channel.*?\$fn\$;',
        dotAll: true,
      ).firstMatch(sql)!.group(0)!;
      expect(group, contains('public.is_group_member(p_group_id, v_me)'));
      expect(group, contains("->> 'typing_in_groups'"));
    });
  });

  group('yönetici', () {
    test('yönetici RPC\'leri auth_is_admin() denetler', () {
      for (final fn in ['admin_set_chat_presence_setting', 'admin_chat_presence_stats']) {
        final body = RegExp(
          'CREATE OR REPLACE FUNCTION public\\.$fn.*?\\\$fn\\\$;',
          dotAll: true,
        ).firstMatch(sql)!.group(0)!;
        expect(body, contains('NOT public.auth_is_admin()'), reason: '$fn yetki denetlemiyor');
      }
    });

    test('yazım beyaz listesi tohumlanan anahtarlarla birebir aynı', () {
      final seeded = RegExp(r"\('(chat_presence_\w+)',\s*'")
          .allMatches(sql.substring(sql.indexOf('INSERT INTO public.app_settings')))
          .map((m) => m.group(1)!)
          .toSet();
      expect(seeded.length, 7);

      final adminBody = RegExp(
        r'CREATE OR REPLACE FUNCTION public\.admin_set_chat_presence_setting.*?\$fn\$;',
        dotAll: true,
      ).firstMatch(sql)!.group(0)!;
      final whitelisted = RegExp(r"'(chat_presence_\w+)'")
          .allMatches(adminBody)
          .map((m) => m.group(1)!)
          .toSet();
      expect(whitelisted, seeded, reason: 'beyaz liste ile tohumlar ayrışmış');
    });

    test('varsayılanlar: özellikler AÇIK, süre sınırı 7 gün', () {
      final seedBlock = sql.substring(sql.indexOf('INSERT INTO public.app_settings'));
      expect(seedBlock, contains("'chat_presence_last_seen_max_days', '\"7\"'"));
      for (final key in [
        'last_seen_enabled',
        'last_seen_in_chat',
        'last_seen_in_profile',
        'online_enabled',
        'typing_enabled',
        'typing_in_groups',
      ]) {
        expect(seedBlock, contains("'chat_presence_$key', '\"true\"'"), reason: key);
      }
      // Okuyucudaki varsayılan da 7 (eksik/bozuk ayar özelliği kapatmaz)
      expect(sql, contains('FROM kv k WHERE k.key = \'chat_presence_last_seen_max_days\'), 7)'));
    });

    test('gün aralığı 1-365 hem okuyucuda hem yazıcıda', () {
      expect(sql, contains('BETWEEN 1 AND 365'));
      expect(RegExp(r'BETWEEN 1 AND 365').allMatches(sql).length, greaterThanOrEqualTo(2));
    });
  });

  test('kullanıcı tercih sütunları güvenli varsayılanla eklenir', () {
    expect(sql, contains('ADD COLUMN IF NOT EXISTS last_seen_friends_only boolean NOT NULL DEFAULT false'));
    expect(sql, contains('ADD COLUMN IF NOT EXISTS show_typing_indicator  boolean NOT NULL DEFAULT true'));
  });

  test('göçün canlı doğrulama betiği repoda ve her kural grubunu kapsar', () {
    final live = File('supabase/tests/manual/chat_presence_and_typing_test.sql').readAsStringSync();
    for (final tag in [
      'T0', 'T3', 'T5', 'T6', 'T7', 'T8', 'T9', 'T10', 'T11', 'T13', 'T14', 'T16', 'T17', 'T18', 'T19',
    ]) {
      expect(live, contains('[$tag'), reason: 'canlı testte $tag grubu yok');
    }
    expect(live, contains('TESTS_PASSED'));
  });
}
