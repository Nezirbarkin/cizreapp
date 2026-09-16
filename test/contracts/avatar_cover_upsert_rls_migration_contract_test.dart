import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Avatar/kapak yükleme düzeltmesinin sözleşmesi.
///
/// `ProfileService` tüm yüklemeleri `FileOptions(upsert: true)` ile yapıyor;
/// storage-api'nin upsert yolu `INSERT ... ON CONFLICT ... RETURNING` kullandığı
/// için dönen satırın SELECT politikalarından da geçmesi gerekiyor. `avatars` /
/// `covers` bucket'larında hiç SELECT politikası olmadığından her upsert
/// 403 "new row violates row-level security policy" alıyordu.
///
/// Davranış testleri:
/// `supabase/tests/database/016_avatar_cover_storage_upsert.test.sql`
void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/20260913100001_fix_avatar_cover_upsert_rls.sql',
    ).readAsStringSync();
  });

  test('iki bucket için de SELECT politikası oluşturulur', () {
    expect(sql, contains('CREATE POLICY avatars_select_public ON storage.objects'));
    expect(sql, contains('CREATE POLICY covers_select_public ON storage.objects'));

    expect(
      RegExp(r'FOR SELECT').allMatches(sql).length,
      2,
      reason: 'yalnızca iki SELECT politikası eklenmeli',
    );
    expect(sql, contains("USING (bucket_id = 'avatars')"));
    expect(sql, contains("USING (bucket_id = 'covers')"));
  });

  test('migration tekrar çalıştırılabilir (idempotent)', () {
    expect(
      sql,
      contains('DROP POLICY IF EXISTS avatars_select_public ON storage.objects'),
    );
    expect(
      sql,
      contains('DROP POLICY IF EXISTS covers_select_public ON storage.objects'),
    );
  });

  test('mevcut yazma politikalarına ve RLS durumuna dokunmaz', () {
    final lower = sql.toLowerCase();
    expect(lower, isNot(contains('for insert')));
    expect(lower, isNot(contains('for update')));
    expect(lower, isNot(contains('for delete')));
    expect(lower, isNot(contains('for all')));
    expect(lower, isNot(contains('disable row level security')));
    expect(lower, isNot(contains('drop policy if exists avatars_insert')));
    expect(lower, isNot(contains('update storage.buckets')));
  });

  test('istemci tarafı upsert:true kullanmaya devam ediyor (fix bunun içindi)', () {
    final service = File(
      'lib/features/profile/services/profile_service.dart',
    ).readAsStringSync();
    expect(service, contains('upsert: true'));
    expect(service, contains("from('avatars')"));
    expect(service, contains("from('covers')"));
  });
}
