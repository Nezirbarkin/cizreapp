import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Gönderi fotoğraf çerçevesi göçlerinin (Görev 2.8) YAPISAL kararları.
/// Davranış canlıda `supabase/tests/manual/post_image_aspect_ratio_test.sql`
/// (8 kontrol) ile kanıtlanır.
void main() {
  late String schema;
  late String backfill;

  String read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

  setUpAll(() {
    schema = read('supabase/migrations/20260928000002_post_image_aspect_ratio.sql');
    backfill = read('supabase/migrations/20260928000003_backfill_post_image_aspect_ratio.sql');
  });

  group('şema', () {
    test('tek işlem; şema yenilenir', () {
      expect(schema, contains('\nBEGIN;\n'));
      expect(schema, contains('\nCOMMIT;\n'));
      expect(schema, contains("NOTIFY pgrst, 'reload schema';"));
    });

    test('kolon real, NULL serbest, akla yatkın aralıkla sınırlı', () {
      expect(schema, contains('ADD COLUMN IF NOT EXISTS image_aspect_ratio real;'));
      expect(schema, contains('CHECK (image_aspect_ratio IS NULL OR image_aspect_ratio BETWEEN 0.5 AND 2.0)'));
    });

    test('posts_with_profiles yeniden yaratılır (p.* genişlesin), güvenlik aynen', () {
      expect(schema, contains('DROP VIEW IF EXISTS public.posts_with_profiles;'));
      expect(schema, contains('WITH (security_invoker = true) AS\nSELECT\n  p.*,'));
      // profiles'tan yalnız güvenli sütunlar; rol/admin kasıtlı NULL.
      expect(schema, contains('NULL::TEXT    AS author_role,'));
      expect(schema, contains('NULL::BOOLEAN AS author_is_admin,'));
      expect(schema, contains('WHERE p.is_active = true;'));
      expect(schema, contains('GRANT SELECT ON public.posts_with_profiles TO authenticated, anon;'));
    });

    test('misafir akışı kolonu döndürür; güvenlik sözleşmesi korunur', () {
      expect(schema, contains('DROP FUNCTION IF EXISTS public.public_explore_feed(integer, integer);'));
      expect(schema, contains('  image_aspect_ratio real,\n'));
      expect(schema, contains('po.images, po.image_aspect_ratio,'));
      expect(schema, contains('SECURITY DEFINER\nSET search_path = \'\''));
      expect(schema, contains("s.key = 'explore_public_access'"));
      expect(schema, contains('AND COALESCE(pr.profile_is_public, true) = true'));
      expect(schema, contains('AND COALESCE(pr.is_ghost_mode, false) = false'));
      expect(schema, contains("<> 'deleted'::public.user_status"));
      expect(schema, contains('CASE WHEN v_music THEN po.music ELSE NULL::jsonb END'));
      expect(schema, contains('REVOKE ALL ON FUNCTION public.public_explore_feed(integer, integer) FROM PUBLIC;'));
      expect(schema, contains('TO anon, authenticated, service_role;'));
    });
  });

  group('geri doldurma', () {
    test('yalnız boş olanlar; updated_at tetikleyicisi işlem boyunca kapalı', () {
      expect(backfill, contains('\nBEGIN;\n'));
      expect(backfill, contains('\nCOMMIT;\n'));
      expect(backfill, contains('AND p.image_aspect_ratio IS NULL;'));
      final disable = backfill.indexOf('DISABLE TRIGGER update_posts_updated_at;');
      final update = backfill.indexOf('UPDATE public.posts AS p');
      final enable = backfill.indexOf('ENABLE TRIGGER update_posts_updated_at;');
      expect(disable, greaterThan(0));
      expect(update, greaterThan(disable));
      expect(enable, greaterThan(update));
    });

    test('90 ölçülmüş gönderi; oranlar akış aralığında [0.8, 1.91]', () {
      final rows = RegExp(r"\('([0-9a-f-]{36})'::uuid, (\d+\.\d{4})::real\)").allMatches(backfill).toList();
      expect(rows, hasLength(90));
      expect(rows.map((m) => m.group(1)).toSet(), hasLength(90));
      for (final m in rows) {
        final ratio = double.parse(m.group(2)!);
        expect(ratio, inInclusiveRange(0.8, 1.91), reason: m.group(1));
      }
    });
  });
}
