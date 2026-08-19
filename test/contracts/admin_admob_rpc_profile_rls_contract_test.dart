import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const path =
      'supabase/migrations/20260810000009_fix_admin_admob_rpc_profile_rls.sql';

  late String sql;

  setUpAll(() => sql = File(path).readAsStringSync());

  test(
    'constrained RPC sahibi admin profil satırını RLS altında görebilir',
    () {
      expect(
        sql,
        contains('CREATE POLICY reward_points_owner_profiles_select'),
      );
      expect(sql, contains('TO reward_points_owner'));
      expect(sql, contains('FOR SELECT'));
      expect(sql, contains('USING (true)'));
    },
  );

  test('admin sözleşmesi hem role hem legacy is_admin alanını destekler', () {
    expect(sql, contains("p.role::text = 'admin'"));
    expect(sql, contains('COALESCE(p.is_admin, false)'));
    expect(sql, contains("RAISE EXCEPTION 'ADMIN_REQUIRED'"));
  });

  test('JWT subject ve least privilege sözleşmesi korunur', () {
    expect(sql, contains("current_setting('request.jwt.claims', true)"));
    expect(sql, contains("SET search_path = ''"));
    expect(sql, contains('OWNER TO reward_points_owner'));
    expect(sql, contains('TO authenticated'));
    expect(sql, contains('FROM PUBLIC, anon, service_role'));
  });
}
