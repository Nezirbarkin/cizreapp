import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Sohbet hızlı yolları + gönderen doğrulaması göçünün YAPISAL kararları.
///
/// Davranış canlı veritabanında
/// `supabase/tests/manual/chat_fast_paths_test.sql` ile kanıtlanır; bu test,
/// yanlışlıkla geri alınması sessizce güvenlik açığı ya da yavaşlık yaratacak
/// kararları sabitler:
///
///  * iki okuma RPC'si SECURITY INVOKER kalır (RLS atlanmaz) ve boş
///    search_path ile çalışır; anon çağıramaz;
///  * sayfa boyutu sunucuda sınırlanır (istemci tüm geçmişi isteyemez);
///  * send_message_with_recipient'i SON tanımlayan göç "gönderen = çağıran"
///    kontrolünü içerir (sonradan kopyalanan eski gövde açığı geri getiremez);
///  * mark_sender_messages_read istemciye yeniden açılmaz.
void main() {
  const fileName = '20260927000001_chat_fast_paths.sql';
  late String sql;
  late List<File> migrations;

  // Çalışma ağacı CRLF de olabilir; karşılaştırmalar LF üzerinden yapılır.
  String read(File f) => f.readAsStringSync().replaceAll('\r\n', '\n');

  setUpAll(() {
    sql = read(File('supabase/migrations/$fileName'));
    migrations =
        Directory('supabase/migrations')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.sql'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
  });

  String stripComments(String s) => s
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('--'))
      .join('\n');

  /// `CREATE OR REPLACE FUNCTION public.<name>(` ile başlayıp gövdenin
  /// kapanışına (`$$;` ya da `$function$;`) kadar olan tanım.
  String functionDef(String source, String name) {
    final match = RegExp(
      'CREATE OR REPLACE FUNCTION public\\.$name\\(.*?(\\\$\\\$|\\\$function\\\$);',
      dotAll: true,
    ).firstMatch(source);
    expect(match, isNotNull, reason: '$name tanımı bulunamadı');
    return match!.group(0)!;
  }

  test('göç tek işlemde çalışır ve PostgREST şemasını yeniler', () {
    final code = stripComments(sql);
    expect(RegExp(r'^begin;', multiLine: true, caseSensitive: false).hasMatch(code), isTrue);
    expect(RegExp(r'^commit;', multiLine: true, caseSensitive: false).hasMatch(code), isTrue);
    expect(code, contains("NOTIFY pgrst, 'reload schema';"));
  });

  group('okuma RPC\'leri', () {
    for (final name in ['get_my_conversations', 'get_conversation_messages']) {
      test('$name SECURITY INVOKER, STABLE ve boş search_path', () {
        final def = functionDef(sql, name);
        expect(def, contains('SECURITY INVOKER'));
        expect(def, isNot(contains('SECURITY DEFINER')));
        expect(def, contains('STABLE'));
        expect(def, contains("SET search_path = ''"));
        expect(def, contains('auth.uid()'));
      });
    }

    test('liste profili maskeli görünümden okur, ham profiles tablosundan değil', () {
      final def = functionDef(sql, 'get_my_conversations');
      expect(def, contains('public.public_profiles_chat'));
      expect(def, isNot(contains('public.profiles ')));
    });

    test('sayfa boyutu sunucuda 1–100 aralığına sıkıştırılır', () {
      final def = functionDef(sql, 'get_conversation_messages');
      expect(def, contains('LEAST(GREATEST(COALESCE(p_limit, 40), 1), 100)'));
      expect(def, contains('LIMIT v_limit'));
    });

    test('mesaj satırları to_jsonb ile döner, yardımcı alanlar ayıklanır', () {
      final def = functionDef(sql, 'get_conversation_messages');
      expect(def, contains('RETURNS SETOF jsonb'));
      expect(def, contains("to_jsonb(b) - 'is_my_copy' - 'my_read' - 'partner_read'"));
    });

    test('yalnız authenticated çağırabilir', () {
      final code = stripComments(sql);
      for (final sig in [
        'public.get_my_conversations()',
        'public.get_conversation_messages(uuid, timestamptz, integer)',
      ]) {
        expect(
          RegExp('REVOKE ALL ON FUNCTION ${RegExp.escape(sig)}\\s+FROM PUBLIC, anon;')
              .hasMatch(code),
          isTrue,
          reason: '$sig PUBLIC/anon yetkisi kaldırılmalı',
        );
        expect(
          RegExp('GRANT EXECUTE ON FUNCTION ${RegExp.escape(sig)}\\s+TO authenticated;')
              .hasMatch(code),
          isTrue,
          reason: '$sig authenticated\'a açılmalı',
        );
      }
    });

    test('sayfalı okuma için bileşik indeks', () {
      expect(
        stripComments(sql),
        contains('ON public.messages (conversation_id, created_at DESC)'),
      );
    });
  });

  group('gönderen doğrulaması', () {
    test('send_message_with_recipient\'i SON tanımlayan göç kontrolü içerir', () {
      final definers = migrations.where(
        (f) => read(f).contains(
          'CREATE OR REPLACE FUNCTION public.send_message_with_recipient(',
        ),
      );
      expect(definers, isNotEmpty);
      // Fonksiyonu sonradan yeniden tanımlayan göç (ör. 20260928000004 fotoğraf/
      // konum mesajları) bu kontrolü KORUMALI: eski, kontrolsüz gövde geri
      // gelemez. Denetim her zaman EN SON tanıma bakar.
      final latest = definers.last;
      final def = functionDef(read(latest), 'send_message_with_recipient');
      expect(def, contains('p_sender_id IS DISTINCT FROM auth.uid()'));
      expect(def, contains("ERRCODE = '42501'"));
      expect(def, contains('SECURITY DEFINER'));
    });

    test('dönüş şekli uygulamanın beklediğiyle aynı kalır', () {
      final def = functionDef(sql, 'send_message_with_recipient');
      final returns = RegExp(r'RETURNS TABLE\((.*?)\)\s*LANGUAGE', dotAll: true)
          .firstMatch(def)!
          .group(1)!
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      expect(
        returns,
        'message_id uuid, sender_id uuid, recipient_id uuid, recipient_message_id uuid, '
        'content text, conversation_id uuid, created_at timestamp with time zone, '
        'updated_at timestamp with time zone, is_read boolean, reply_to_id uuid, '
        'reply_to_content text, reply_to_sender_name text',
      );
    });

    test('mark_sender_messages_read istemciye kapalı ve yeniden açılmıyor', () {
      expect(
        stripComments(sql),
        contains(
          'REVOKE ALL ON FUNCTION public.mark_sender_messages_read(uuid, uuid)\n'
          '  FROM PUBLIC, anon, authenticated;',
        ),
      );
      final later = migrations.where(
        (f) => f.uri.pathSegments.last.compareTo(fileName) > 0,
      );
      for (final f in later) {
        expect(
          RegExp(r'GRANT[^;]*mark_sender_messages_read', dotAll: true)
              .hasMatch(read(f)),
          isFalse,
          reason: '${f.uri.pathSegments.last} mark_sender_messages_read yetkisini geri veriyor',
        );
      }
    });
  });
}
