import 'package:cizreapp/core/models/notification_model.dart';
import 'package:cizreapp/features/market/screens/notifications_screen.dart';
import 'package:flutter_test/flutter_test.dart';

NotificationModel _n(String id, {Map<String, dynamic>? meta}) => NotificationModel(
      id: id,
      userId: 'u1',
      type: 'admin_broadcast',
      metadata: meta,
      isRead: false,
      createdAt: DateTime.utc(2026, 10, 22),
    );

void main() {
  test('kişisel satırı olan duyuru kimlikleri toplanır (kart tekrar göstermez)', () {
    final ids = adminBroadcastIdsIn([
      _n('1', meta: {'broadcast_id': 'b-1', 'campaign_id': 'b-1'}),
      _n('2', meta: {'campaign_id': 'personal-only'}),
      _n('3'),
      _n('4', meta: {'broadcast_id': 'b-2'}),
    ]);
    expect(ids, {'b-1', 'b-2'});
  });

  test('bildirim yoksa boş küme', () {
    expect(adminBroadcastIdsIn(const []), isEmpty);
  });
}
