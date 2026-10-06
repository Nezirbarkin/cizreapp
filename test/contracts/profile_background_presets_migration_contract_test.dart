import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Hazır profil arka planları göçünün (Görev 2.7) YAPISAL kararları. Davranış
/// canlıda `supabase/tests/manual/profile_background_presets_test.sql` (13
/// kontrol) ile kanıtlanır.
void main() {
  late String sql;

  setUpAll(() {
    sql = File('supabase/migrations/20260928000001_profile_background_presets.sql')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
  });

  test('tek işlem, şema yenilenir', () {
    expect(sql, contains('\nBEGIN;\n'));
    expect(sql, contains('\nCOMMIT;\n'));
    expect(sql, contains("NOTIFY pgrst, 'reload schema';"));
  });

  test('kova herkese açık okunur; yazma yalnız admin', () {
    expect(sql, contains("VALUES ('profile-backgrounds', 'profile-backgrounds', true, 2097152,"));
    final writePolicies = RegExp(
      r"ON storage\.objects FOR (INSERT|UPDATE|DELETE)\nTO authenticated\n[^;]*auth_is_admin\(\)",
    ).allMatches(sql).length;
    expect(writePolicies, 3);
  });

  test('tablo RLS\'li: herkes yalnız aktifleri okur, yazma admin politikasıyla', () {
    expect(sql, contains('ALTER TABLE public.profile_background_presets ENABLE ROW LEVEL SECURITY;'));
    expect(sql, contains('TO anon, authenticated\n  USING (is_active);'));
    expect(sql, contains('USING (public.auth_is_admin())\n  WITH CHECK (public.auth_is_admin());'));
    expect(sql, contains('REVOKE ALL ON public.profile_background_presets FROM anon;'));
  });

  test('50 hazır arka plan; kod = dosya adı; sıra artan (append-only)', () {
    final rows = RegExp(r"\('(bg_\d+)', '[^']+', '[^']+', 'presets/(bg_\d+)\.jpg', 'thumbs/(bg_\d+)\.jpg', (\d+)\)")
        .allMatches(sql)
        .toList();
    expect(rows, hasLength(50));
    var previous = 0;
    for (var i = 0; i < rows.length; i++) {
      final m = rows[i];
      expect(m.group(1), 'bg_${(i + 1).toString().padLeft(2, '0')}');
      expect(m.group(2), m.group(1));
      expect(m.group(3), m.group(1));
      final order = int.parse(m.group(4)!);
      expect(order, greaterThan(previous));
      previous = order;
    }
    expect(sql, contains('ON CONFLICT (code) DO NOTHING;'));
  });
}
