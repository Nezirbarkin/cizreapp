import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Sohbette fotoğraf/konum göçünün (Görev 3.1) YAPISAL kararları. Davranış
/// canlıda `supabase/tests/manual/chat_media_messages_test.sql` (12 kontrol)
/// ile kanıtlanır; bu test, yanlışlıkla geri alınması sessizce güvenlik açığı
/// yaratacak kararları sabitler.
void main() {
  late String sql;
  late String code;

  String stripComments(String s) =>
      s.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

  setUpAll(() {
    sql = File('supabase/migrations/20260928000004_chat_media_messages.sql')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    code = stripComments(sql);
  });

  String rpc() => RegExp(
    r'CREATE OR REPLACE FUNCTION public\.send_message_with_recipient\(.*?\$function\$;',
    dotAll: true,
  ).firstMatch(code)!.group(0)!;

  test('tek işlem; şema yenilenir', () {
    expect(code, contains('\nBEGIN;\n'));
    expect(code, contains('\nCOMMIT;\n'));
    expect(code, contains("NOTIFY pgrst, 'reload schema';"));
  });

  group('tablo', () {
    test('tür sütunu varsayılan metin; ek jsonb', () {
      expect(code, contains("ADD COLUMN IF NOT EXISTS message_type text NOT NULL DEFAULT 'text';"));
      expect(code, contains('ADD COLUMN IF NOT EXISTS attachment jsonb;'));
      expect(code, contains("CHECK (message_type IN ('text', 'image', 'location'))"));
    });

    test('tür/ek CHECK\'i NULL\'a düşemez (NULL CHECK\'i geçerdi)', () {
      final shape = RegExp(
        r'ADD CONSTRAINT messages_attachment_shape_check\s+CHECK \((.*?)\n  \);',
        dotAll: true,
      ).firstMatch(code)!.group(1)!;
      expect(shape.trimLeft(), startsWith('COALESCE('));
      expect(shape.trimRight(), endsWith('false\n    )'));
      expect(shape, contains("WHEN 'text' THEN attachment IS NULL"));
      expect(shape, contains(r"~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}[.](jpg|png|webp|gif)$'"));
      expect(shape, contains("jsonb_typeof(attachment -> 'lat') = 'number'"));
      expect(shape, contains('BETWEEN -90 AND 90'));
      expect(shape, contains('BETWEEN -180 AND 180'));
    });

    test('ek veri 2 KB ile sınırlı', () {
      expect(code, contains('CHECK (attachment IS NULL OR octet_length(attachment::text) <= 2048)'));
    });
  });

  group('gönderim RPC\'si', () {
    test('eski 6 parametreli imza kaldırılır (PostgREST belirsizliği olmasın)', () {
      expect(
        code,
        contains('DROP FUNCTION IF EXISTS public.send_message_with_recipient(uuid, text, uuid, uuid, text, text);'),
      );
      final def = rpc();
      expect(def, contains("p_message_type text DEFAULT 'text'::text"));
      expect(def, contains('p_attachment jsonb DEFAULT NULL::jsonb'));
    });

    test('"gönderen = çağıran" denetimi ve DEFINER korunur', () {
      final def = rpc();
      expect(def, contains('SECURITY DEFINER'));
      expect(def, contains('p_sender_id IS DISTINCT FROM auth.uid()'));
      expect(def, contains("ERRCODE = '42501'"));
      expect(def, contains('IF v_conv_user_id != p_sender_id THEN'));
    });

    test('fotoğraf yolu gönderen/alıcı klasöründe ve dosya gerçekten yüklenmiş olmalı', () {
      final def = rpc();
      expect(def, contains("split_part(v_attachment ->> 'path', '/', 1), '') <> p_sender_id::text"));
      expect(def, contains("split_part(v_attachment ->> 'path', '/', 2), '') <> v_recipient_id::text"));
      expect(def, contains("FROM storage.objects o"));
      expect(def, contains("o.bucket_id = 'chat_attachments'"));
      expect(def, contains("ERRCODE = '22023'"));
    });

    test('metin mesajında ek düşer; medya önizleme metni boş kalamaz', () {
      final def = rpc();
      expect(def, contains("IF v_type = 'text' THEN\n        v_attachment := NULL;"));
      expect(def, contains("'📷 Fotoğraf'"));
      expect(def, contains("'📍 Konum'"));
    });

    test('iki kopya da türü ve eki taşır', () {
      final def = rpc();
      expect(RegExp(r'message_type, attachment\)').allMatches(def).length, 2);
      expect(RegExp(r'v_type, v_attachment\)').allMatches(def).length, 2);
    });

    test('dönüş şekli: eskisi + message_type, attachment', () {
      final returns = RegExp(r'RETURNS TABLE\((.*?)\)\s*LANGUAGE', dotAll: true)
          .firstMatch(rpc())!
          .group(1)!
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      expect(
        returns,
        'message_id uuid, sender_id uuid, recipient_id uuid, recipient_message_id uuid, '
        'content text, conversation_id uuid, created_at timestamp with time zone, '
        'updated_at timestamp with time zone, is_read boolean, reply_to_id uuid, '
        'reply_to_content text, reply_to_sender_name text, message_type text, attachment jsonb',
      );
    });

    test('yalnız authenticated (ve service_role) çağırabilir', () {
      const sig = 'public.send_message_with_recipient(uuid, text, uuid, uuid, text, text, text, jsonb)';
      expect(code, contains('REVOKE ALL ON FUNCTION $sig\n  FROM PUBLIC, anon;'));
      expect(code, contains('GRANT EXECUTE ON FUNCTION $sig\n  TO authenticated, service_role;'));
    });
  });

  group('depo', () {
    test('kova ÖZEL, 10 MB, yalnız görsel', () {
      expect(code, contains("'chat_attachments', 'chat_attachments', false, 10485760,"));
      expect(code, contains("ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']"));
      expect(code, contains('SET public = EXCLUDED.public,'));
    });

    test('yükleme yalnız kendi klasörüne, iki derinlikte', () {
      final insert = RegExp(
        r'CREATE POLICY "chat_attachments_insert_own_folder".*?;',
        dotAll: true,
      ).firstMatch(code)!.group(0)!;
      expect(insert, contains('FOR INSERT TO authenticated'));
      expect(insert, contains('(storage.foldername(name))[1] = (SELECT auth.uid())::text'));
      expect(insert, contains('array_length(storage.foldername(name), 1) = 2'));
    });

    test('okuma yalnız iki taraf; silme yalnız gönderen; güncelleme ve anon yok', () {
      final select = RegExp(
        r'CREATE POLICY "chat_attachments_select_participants".*?;',
        dotAll: true,
      ).firstMatch(code)!.group(0)!;
      expect(select, contains('FOR SELECT TO authenticated'));
      expect(select, contains('(storage.foldername(name))[1],'));
      expect(select, contains('(storage.foldername(name))[2]'));

      final delete = RegExp(
        r'CREATE POLICY "chat_attachments_delete_own".*?;',
        dotAll: true,
      ).firstMatch(code)!.group(0)!;
      expect(delete, contains('FOR DELETE TO authenticated'));
      expect(delete, contains('(storage.foldername(name))[1] = (SELECT auth.uid())::text'));

      final policies = RegExp(r'CREATE POLICY "chat_attachments_[a-z_]+"').allMatches(code).length;
      expect(policies, 3);
      expect(code, isNot(contains('FOR UPDATE TO authenticated')));
      expect(RegExp(r'"chat_attachments_[a-z_]+"[^;]*TO (anon|public)').hasMatch(code), isFalse);
    });
  });

  test('canlı doğrulama betiği repoda ve her grubu kapsar', () {
    final live = File('supabase/tests/manual/chat_media_messages_test.sql').readAsStringSync();
    for (var i = 1; i <= 12; i++) {
      expect(live, contains('[$i]'), reason: 'canlı testte [$i] yok');
    }
    expect(live, contains('TESTS_PASSED'));
  });
}
