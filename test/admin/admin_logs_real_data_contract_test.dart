import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin log ekranı merkezi Supabase RPC verisini kullanır', () {
    final loader = File(
      'lib/features/admin/screens/admin_dashboard_parts/_part_data_loaders.dart',
    ).readAsStringSync();
    final analytics = File(
      'lib/core/services/analytics_service.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260817000017_admin_logs_real_data.sql',
    ).readAsStringSync();

    expect(loader, contains("'admin_logs_data'"));
    expect(loader, isNot(contains('_analyticsService.getErrors(limit: 20)')));
    expect(analytics, contains("from('app_analytics_events').insert"));
    expect(migration, contains('SECURITY DEFINER'));
    expect(migration, contains('private.current_user_is_admin()'));
    expect(
      migration,
      contains('CREATE POLICY "Users can insert own analytics events"'),
    );
    expect(migration, contains('user_id = (SELECT auth.uid())'));
  });
}
