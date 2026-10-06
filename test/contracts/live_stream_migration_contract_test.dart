import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Canlı yayın tamamlama (Görev 3.4) YAPISAL kararları. Davranış canlıda
/// `supabase/tests/manual/live_stream_completion_test.sql` (11 kontrol),
/// anahtar üretimi `supabase/functions/_shared/agora_token_test.ts` (resmi
/// paketle bayt bayt) ve `live_token_test.ts` ile kanıtlanır.
void main() {
  String read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');
  String stripComments(String s) => s.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

  late String sql;
  setUpAll(() {
    sql = stripComments(read('supabase/migrations/20260928000008_live_stream_completion.sql'));
  });

  String fn(String name) => RegExp(
    'CREATE OR REPLACE FUNCTION ${RegExp.escape(name)}\\(.*?\\\$fn\\\$;',
    dotAll: true,
  ).firstMatch(sql)!.group(0)!;

  test('tek işlem; şema yenilenir', () {
    expect(sql, contains('\nBEGIN;\n'));
    expect(sql, contains('\nCOMMIT;\n'));
    expect(sql, contains("NOTIFY pgrst, 'reload schema';"));
  });

  group('yazmalar yalnız RPC\'lerden', () {
    test('doğrudan yayın/sabitleme yazma politikaları ve yetkileri kaldırılır', () {
      for (final policy in [
        'live_sessions_insert_host',
        'live_sessions_update_host',
        'live_pin_insert_host',
        'live_pin_update_host',
        'live_pin_delete_host',
      ]) {
        expect(sql, contains('DROP POLICY IF EXISTS "$policy"'));
        expect(sql, isNot(contains('CREATE POLICY "$policy"')));
      }
      expect(sql, contains('REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.live_sessions FROM anon, authenticated;'));
      expect(sql, contains('REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.live_pinned_products FROM anon, authenticated;'));
      expect(sql, contains('REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.live_messages FROM anon;'));
    });

    test('mağaza başına tek açık yayın', () {
      expect(sql, contains('CREATE UNIQUE INDEX IF NOT EXISTS live_sessions_one_open_per_shop'));
      expect(sql, contains("WHERE status IN ('scheduled', 'live');"));
    });

    test('satıcı RPC\'leri DEFINER, arama yolu boş, anon çalıştıramaz', () {
      for (final name in [
        'public.live_create_session',
        'public.start_live_session',
        'public.end_live_session',
        'public.live_session_heartbeat',
        'public.live_pin_product',
        'public.live_unpin_product',
      ]) {
        final def = fn(name);
        expect(def, contains('SECURITY DEFINER'), reason: name);
        expect(def, contains("SET search_path = ''"), reason: name);
        expect(def, contains('auth.uid()'), reason: name);
      }
      expect(sql, contains('REVOKE ALL ON FUNCTION public.live_create_session(uuid, text, text) FROM PUBLIC, anon;'));
      expect(sql, contains('GRANT EXECUTE ON FUNCTION public.live_session_heartbeat(uuid, integer) TO authenticated;'));
    });

    test('sabitlenen ürün yayının mağazasına ait ve satışta olmalı', () {
      final def = fn('public.live_pin_product');
      expect(def, contains('p.shop_id = v.shop_id'));
      expect(def, contains('COALESCE(p.is_available, false)'));
      expect(def, contains("HINT = 'LIVE_PRODUCT_INVALID'"));
    });
  });

  group('mesajlar', () {
    test('satıcı bayrağı, ad ve zaman sunucuda; canlı değilse/boş/uzun/hızlı reddedilir', () {
      final def = fn('private.live_messages_before_insert');
      expect(def, contains('NEW.is_host := (NEW.user_id = v_session.host_user_id);'));
      expect(def, contains('NEW.created_at := now();'));
      expect(def, contains("HINT = 'LIVE_NOT_LIVE'"));
      expect(def, contains('char_length(v_text) > 300'));
      expect(def, contains("interval '10 seconds'"));
      expect(def, contains('IF v_recent >= 5 THEN'));
      expect(sql, contains('BEFORE INSERT ON public.live_messages'));
    });

    test('moderasyon: satıcı kendi yayınındaki her mesajı siler', () {
      final policy = RegExp(r'CREATE POLICY "live_messages_delete_host".*?\);', dotAll: true).firstMatch(sql)!.group(0)!;
      expect(policy, isNot(contains('is_host')));
      expect(policy, contains('ls.host_user_id = (SELECT auth.uid())'));
    });
  });

  group('Agora anahtarı', () {
    test('yetki kararı yalnız service_role; satıcı uid 1; izleyici yalnız taze canlı yayına', () {
      final def = fn('public.live_token_grant');
      expect(def, contains("'host_uid', 1"));
      expect(def, contains("v.last_heartbeat_at < now() - interval '2 minutes'"));
      expect(sql, contains('REVOKE ALL ON FUNCTION public.live_token_grant(uuid, text, uuid) FROM PUBLIC, anon, authenticated;'));
      expect(sql, contains('GRANT EXECUTE ON FUNCTION public.live_token_grant(uuid, text, uuid) TO service_role;'));
    });

    test('Edge Function: sertifika sunucuda kalır; ayar yoksa LIVE_NOT_CONFIGURED; bağımlılıksız imza', () {
      final index = read('supabase/functions/live-token/index.ts');
      expect(index, contains('"live_token_grant"'));
      expect(index, contains('Deno.env.get("AGORA_APP_CERTIFICATE")'));
      final handler = read('supabase/functions/_shared/live_token.ts');
      expect(handler, contains('LIVE_NOT_CONFIGURED'));
      expect(handler, contains('app_id: appId'));
      final response = RegExp(r'return json\(\{\s*ok: true,.*?\}\);', dotAll: true).firstMatch(handler)!.group(0)!;
      expect(response, contains('token,'));
      expect(response, isNot(contains('ertificate')), reason: 'sertifika yanıta girmez');
      final token = read('supabase/functions/_shared/agora_token.ts');
      expect(token, isNot(contains('npm:')));
      expect(token, contains('crypto.subtle'));
      expect(token, contains('new CompressionStream("deflate")'));
    });
  });

  test('bayat yayın temizliği her dakika', () {
    expect(sql, contains("'live-reap-stale-sessions',\n      '* * * * *',"));
    expect(fn('private.live_reap_stale_sessions'), contains("< now() - interval '2 minutes'"));
  });

  group('istemci', () {
    test('artık olmayan public.users gömmesi yok; App ID .env\'den okunmaz', () {
      final service = read('lib/features/market/services/live_shopping_service.dart');
      expect(service, isNot(contains('users!host_user_id')));
      expect(service, isNot(contains('users(')));
      expect(service, contains("_client.functions.invoke(\n      'live-token'"));
      final agora = read('lib/features/market/services/agora_service.dart');
      expect(agora, isNot(contains('AGORA_APP_ID')));
      expect(agora, isNot(contains('dotenv')));
    });

    test('yayın sırasında ekran kararmaz: yerel kanal Android ve iOS\'ta', () {
      final android = read('android/app/src/main/kotlin/com/cizreapp/com/MainActivity.kt');
      expect(android, contains('"cizreapp/screen_awake"'));
      expect(android, contains('FLAG_KEEP_SCREEN_ON'));
      final ios = read('ios/Runner/AppDelegate.swift');
      expect(ios, contains('"cizreapp/screen_awake"'));
      expect(ios, contains('isIdleTimerDisabled'));
      expect(read('lib/core/services/screen_awake_service.dart'), contains("MethodChannel('cizreapp/screen_awake')"));
    });

    test('iOS izin metinleri canlı yayını söyler', () {
      final plist = read('ios/Runner/Info.plist');
      expect(plist, contains('mağazanız için canlı yayın yapabilirsiniz'));
      expect(plist, contains('canlı yayında konuşabilir'));
    });
  });

  test('canlı doğrulama betiği repoda ve her grubu kapsar', () {
    final live = read('supabase/tests/manual/live_stream_completion_test.sql');
    for (var i = 1; i <= 11; i++) {
      expect(live, contains('[$i]'), reason: 'canlı testte [$i] yok');
    }
    expect(live, contains('TESTS_PASSED'));
  });
}
