import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const path =
      'supabase/migrations/20260812000004_fix_admin_admob_app_ids_overview.sql';

  late String sql;

  setUpAll(() => sql = File(path).readAsStringSync());

  test(
    'admin overview kaydedilen Android ve iOS App ID alanlarını döndürür',
    () {
      expect(
        sql,
        contains("'admob_app_id_android', v_settings.admob_app_id_android"),
      );
      expect(sql, contains("'admob_app_id_ios', v_settings.admob_app_id_ios"));
    },
  );

  test(
    'overview doğrulanmış JWT subject ve iki admin sözleşmesini kullanır',
    () {
      expect(sql, contains("current_setting('request.jwt.claims', true)"));
      expect(sql, contains("p.role::text = 'admin'"));
      expect(sql, contains('COALESCE(p.is_admin, false)'));
      expect(sql, contains("RAISE EXCEPTION 'ADMIN_REQUIRED'"));
    },
  );

  test('constrained owner gerekli satırları RLS altında okuyabilir', () {
    expect(sql, contains('CREATE POLICY reward_points_owner_profiles_select'));
    expect(
      sql,
      contains('CREATE POLICY reward_points_owner_ad_settings_select'),
    );
    expect(sql, contains('TO reward_points_owner'));
    expect(sql, contains('USING (true)'));
  });

  test('overview yalnız authenticated admin istemcilerine açıktır', () {
    expect(sql, contains("SET search_path = ''"));
    expect(sql, contains('OWNER TO reward_points_owner'));
    expect(sql, contains('FROM PUBLIC, anon, service_role'));
    expect(sql, contains('TO authenticated'));
    expect(sql, contains("NOTIFY pgrst, 'reload schema'"));
  });
}
