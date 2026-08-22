import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const migrationPath =
      'supabase/migrations/20260810000006_fix_reward_points_owner_auth_acl.sql';

  late String migration;

  setUpAll(() {
    migration = File(migrationPath).readAsStringSync();
  });

  test(
    'reward owner auth.uid çağrısı için gereken minimum ACL değerlerini alır',
    () {
      expect(
        migration,
        contains('GRANT USAGE ON SCHEMA auth TO reward_points_owner'),
      );
      expect(
        migration,
        contains('GRANT EXECUTE ON FUNCTION auth.uid() TO reward_points_owner'),
      );
    },
  );

  test(
    'auth tablolarına veya auth şemasında create yetkisine erişim açmaz',
    () {
      expect(migration, isNot(contains('GRANT SELECT ON auth.')));
      expect(migration, isNot(contains('GRANT INSERT ON auth.')));
      expect(migration, isNot(contains('GRANT UPDATE ON auth.')));
      expect(migration, isNot(contains('GRANT DELETE ON auth.')));
      expect(migration, isNot(contains('GRANT CREATE ON SCHEMA auth')));
    },
  );

  test('PostgREST şema önbelleğini yeniler', () {
    expect(migration, contains("NOTIFY pgrst, 'reload schema'"));
  });
}
