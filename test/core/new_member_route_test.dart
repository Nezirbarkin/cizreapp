import 'package:cizreapp/core/services/admin_new_member_series_service.dart';
import 'package:cizreapp/core/utils/new_member_route.dart';
import 'package:flutter_test/flutter_test.dart';

/// Karşılama serisi: sunucudaki `action_route` / `condition` değerleri ile
/// istemci eşlemesi aynı kalmalı (20261024000001_new_member_messages).
void main() {
  test('NewMemberRoute.tryParse sunucu anahtarlarını tanır', () {
    expect(NewMemberRoute.tryParse('edit_profile'), NewMemberRoute.editProfile);
    expect(NewMemberRoute.tryParse('create_post'), NewMemberRoute.createPost);
    expect(NewMemberRoute.tryParse(' market '), NewMemberRoute.market);
    expect(NewMemberRoute.tryParse('okey'), NewMemberRoute.okey);
    expect(NewMemberRoute.tryParse(''), isNull);
    expect(NewMemberRoute.tryParse(null), isNull);
    expect(NewMemberRoute.tryParse(42), isNull);
    expect(NewMemberRoute.tryParse('wallet'), isNull);
  });

  test('admin ekranındaki rota ve koşul listeleri göçle aynı', () {
    expect(
      kNewMemberRoutes.keys.where((k) => k.isNotEmpty).toSet(),
      NewMemberRoute.values.map((r) => r.key).toSet(),
    );
    expect(
      kNewMemberConditions.keys.toSet(),
      {'always', 'no_avatar', 'no_post', 'no_order'},
    );
  });

  test('newMemberDelayLabel', () {
    expect(newMemberDelayLabel(0), 'Hemen');
    expect(newMemberDelayLabel(1), '1 dk');
    expect(newMemberDelayLabel(60), '1 sa');
    expect(newMemberDelayLabel(1440), '1 gün');
    expect(newMemberDelayLabel(1440 + 185), '1 gün 3 sa 5 dk');
  });

  test('NewMemberSeries.fromJson sayaçları ve okunma oranını okur', () {
    final s = NewMemberSeries.fromJson({
      'enabled': true,
      'steps': [
        {
          'id': 'a',
          'step_key': 'welcome',
          'sort_order': 1,
          'delay_minutes': 1,
          'title': 'Hoş geldin {ad}',
          'body': 'Metin',
          'icon': 'gift',
          'condition': 'always',
          'is_active': true,
          'respect_quiet_hours': false,
          'sent': 8,
          'read': 6,
          'skipped': 1,
          'failed': 0,
          'last_sent_at': '2026-10-24T10:00:00Z',
        },
      ],
    });
    expect(s.enabled, isTrue);
    expect(s.steps.single.readPercent, 75);
    expect(s.steps.single.respectQuietHours, isFalse);
    expect(s.steps.single.lastSentAt, isNotNull);
    expect(NewMemberSeries.fromJson(const {}).steps, isEmpty);
  });
}
