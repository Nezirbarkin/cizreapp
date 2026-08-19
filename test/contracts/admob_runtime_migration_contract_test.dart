import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const migrationPath =
      'supabase/migrations/20260810000002_restore_admin_admob_runtime_contract.sql';

  late String migration;

  setUpAll(() {
    migration = File(migrationPath).readAsStringSync();
  });

  test('kanonik admin RPC tam 19 parametreli AdMob sözleşmesini kurar', () {
    expect(migration, contains('p_admob_app_id_android text DEFAULT NULL'));
    expect(migration, contains('p_admob_app_id_ios text DEFAULT NULL'));
    expect(
      migration,
      contains('p_admob_rewarded_unit_id_android text DEFAULT NULL'),
    );
    expect(
      migration,
      contains('p_admob_rewarded_unit_id_ios text DEFAULT NULL'),
    );
    expect(
      migration,
      contains('integer, integer, integer, boolean, text, text, text, text'),
    );
  });

  test('eski RPC overloadlarını kaldırıp PostgREST belirsizliğini önler', () {
    final dropCount = RegExp(
      r'DROP FUNCTION IF EXISTS public\.admin_update_reward_points_config\(',
    ).allMatches(migration).length;

    expect(dropCount, 3);
    expect(migration, contains("NOTIFY pgrst, 'reload schema'"));
  });

  test('public config yalnız runtime unit kimliklerini yayınlar', () {
    final viewStart = migration.indexOf(
      'CREATE OR REPLACE VIEW public.reward_points_public_config',
    );
    final viewEnd = migration.indexOf(
      'REVOKE ALL ON public.reward_points_public_config',
      viewStart,
    );
    expect(viewStart, greaterThanOrEqualTo(0));
    expect(viewEnd, greaterThan(viewStart));

    final viewDefinition = migration.substring(viewStart, viewEnd);
    expect(viewDefinition, contains('admob_rewarded_unit_id_android'));
    expect(viewDefinition, contains('admob_rewarded_unit_id_ios'));
    expect(viewDefinition, isNot(contains('admob_app_id_android')));
    expect(viewDefinition, isNot(contains('admob_app_id_ios')));
  });

  test('istemci rollerine yazma veya secret yüzeyi açmaz', () {
    expect(
      migration,
      contains('REVOKE ALL ON public.ad_settings FROM anon, authenticated'),
    );
    expect(
      migration,
      isNot(contains('GRANT UPDATE ON public.ad_settings TO authenticated')),
    );
    expect(migration, isNot(contains('ADMOB_SSV_HASH_SECRET')));
    expect(migration, isNot(contains('SUPABASE_SERVICE_ROLE_KEY')));
  });
}
