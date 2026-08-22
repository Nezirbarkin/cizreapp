import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const path =
      'supabase/migrations/20260810000007_fix_admin_admob_rpc_jwt_context.sql';

  late String sql;

  setUpAll(() => sql = File(path).readAsStringSync());

  test(
    'admin RPC doğrulanmış JWT subject bilgisini auth şeması olmadan okur',
    () {
      expect(sql, contains("current_setting('request.jwt.claims', true)"));
      expect(sql, contains("->> 'sub'"));
      expect(sql, isNot(contains('auth.uid()')));
    },
  );

  test('RPC security definer, sabit search path ve sınırlı grant kullanır', () {
    expect(sql, contains('SECURITY DEFINER'));
    expect(sql, contains("SET search_path = ''"));
    expect(sql, contains('OWNER TO reward_points_owner'));
    expect(sql, contains('TO authenticated'));
    expect(sql, contains('FROM PUBLIC, anon, service_role'));
  });

  test('admin denetimi ve audit kaydı korunur', () {
    expect(sql, contains("p.role = 'admin'"));
    expect(sql, contains('reward_points_config_audit'));
    expect(sql, contains('v_admin'));
  });
}
