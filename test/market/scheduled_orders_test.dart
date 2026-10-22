import 'package:cizreapp/core/models/order_model.dart';
import 'package:cizreapp/core/models/shop_model.dart';
import 'package:cizreapp/core/utils/schedule_format.dart';
import 'package:cizreapp/core/widgets/scheduled_order_badge.dart';
import 'package:cizreapp/features/market/services/scheduled_order_service.dart';
import 'package:cizreapp/features/market/widgets/scheduled_slot_picker.dart';
import 'package:cizreapp/features/seller/widgets/seller_scheduled_orders_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeScheduledService extends ScheduledOrderService {
  _FakeScheduledService(this.items);

  final List<DateTime> items;

  @override
  Future<List<DateTime>> slots(String shopId) async => items;

  @override
  Future<bool> globallyEnabled({bool forceRefresh = false}) async => true;

  @override
  Future<String?> validate(String shopId, DateTime at) async => null;
}

// Türkiye saatiyle 22 Eki 2026 Per 10:00 (UTC 07:00).
final _now = DateTime.utc(2026, 10, 22, 7);

DateTime _trUtc(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 10, day, hour - 3, minute);

void main() {
  group('ScheduleFormat (Türkiye saati)', () {
    test('saat ve gün etiketleri', () {
      final t = _trUtc(22, 14);
      expect(ScheduleFormat.time(t), '14:00');
      expect(ScheduleFormat.dayLabel(t, now: _now), 'Bugün');
      expect(ScheduleFormat.dayLabel(_trUtc(23, 9, 30), now: _now), 'Yarın');
      expect(ScheduleFormat.full(_trUtc(24, 9, 30), now: _now), '24 Eki Cmt 09:30');
    });

    test('gece yarısından sonrası ertesi güne yazılır', () {
      // TR 23 Eki 01:00 = UTC 22 Eki 22:00
      final t = DateTime.utc(2026, 10, 22, 22);
      expect(ScheduleFormat.full(t, now: _now), 'Yarın 01:00');
    });
  });

  group('modeller', () {
    test('Order.scheduled_for okunur ve yazılır', () {
      final o = Order.fromJson({
        'id': 'o1',
        'user_id': 'u1',
        'shop_id': 's1',
        'status': 'pending',
        'payment_method': 'cash',
        'subtotal': 10,
        'total': 10,
        'created_at': '2026-10-22T07:00:00Z',
        'updated_at': '2026-10-22T07:00:00Z',
        'scheduled_for': '2026-10-22T11:00:00+00:00',
      });
      expect(o.isScheduled, isTrue);
      expect(o.scheduledFor!.toUtc(), DateTime.utc(2026, 10, 22, 11));
      expect(o.toJson()['scheduled_for'], '2026-10-22T11:00:00.000Z');
      final plain = Order.fromJson({
        'id': 'o2',
        'user_id': 'u1',
        'shop_id': 's1',
        'status': 'pending',
        'payment_method': 'cash',
        'subtotal': 10,
        'total': 10,
        'created_at': '2026-10-22T07:00:00Z',
        'updated_at': '2026-10-22T07:00:00Z',
      });
      expect(plain.isScheduled, isFalse);
    });

    test('Shop randevu alanları ve admin engeli', () {
      final base = {
        'id': 's1',
        'owner_id': 'u1',
        'name': 'Dükkan',
        'scheduled_orders_enabled': true,
        'scheduled_slot_minutes': 30,
        'scheduled_max_days': 5,
        'scheduled_min_lead_minutes': 90,
      };
      final s = Shop.fromJson(base);
      expect(s.acceptsScheduledOrders, isTrue);
      expect(s.scheduledSlotMinutes, 30);
      expect(s.scheduledMaxDays, 5);
      expect(s.scheduledMinLeadMinutes, 90);
      expect(Shop.fromJson({...base, 'scheduled_orders_admin_blocked': true}).acceptsScheduledOrders,
          isFalse);
      final plain = Shop.fromJson({'id': 's2', 'owner_id': 'u1', 'name': 'X'});
      expect(plain.acceptsScheduledOrders, isFalse);
      expect(plain.scheduledSlotMinutes, 60);
    });
  });

  group('saat seçici', () {
    Future<DateTime?> openPicker(WidgetTester t, List<DateTime> slots) async {
      DateTime? result;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showModalBottomSheet<DateTime>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ScheduledSlotPickerSheet(
                      shopId: 's1',
                      shopName: 'Test Dükkan',
                      service: _FakeScheduledService(slots),
                      now: _now,
                    ),
                  );
                },
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('aç'));
      await t.pumpAndSettle();
      return result;
    }

    testWidgets('günler ve saatler listelenir, seçilen saat döner', (t) async {
      DateTime? picked;
      final slots = [_trUtc(22, 14), _trUtc(22, 15), _trUtc(23, 9)];
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  picked = await showModalBottomSheet<DateTime>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ScheduledSlotPickerSheet(
                      shopId: 's1',
                      service: _FakeScheduledService(slots),
                      now: _now,
                    ),
                  );
                },
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('aç'));
      await t.pumpAndSettle();

      expect(find.text('Bugün'), findsOneWidget);
      expect(find.text('Yarın'), findsOneWidget);
      expect(find.text('14:00'), findsOneWidget);
      expect(find.text('09:00'), findsNothing); // yarının saati, gün seçilmedi
      expect(find.text('Saat seçin'), findsOneWidget);

      await t.tap(find.text('Yarın'));
      await t.pumpAndSettle();
      await t.tap(find.text('09:00'));
      await t.pumpAndSettle();
      await t.tap(find.text('Yarın 09:00 — Onayla'));
      await t.pumpAndSettle();
      expect(picked, _trUtc(23, 9));
    });

    testWidgets('uygun saat yoksa bilgi verir', (t) async {
      await openPicker(t, const []);
      expect(find.text('Bu dükkan için şu an uygun randevu saati yok.'), findsOneWidget);
    });
  });

  testWidgets('teslimat zamanı kartı: Hemen seçilince randevu kalkar', (t) async {
    DateTime? value = _trUtc(23, 9);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => ScheduledDeliveryCard(
            shopId: 's1',
            value: value,
            service: _FakeScheduledService(const []),
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      ),
    ));
    expect(find.textContaining('Randevu: '), findsOneWidget);
    expect(find.text('Değiştir'), findsOneWidget);
    await t.tap(find.text('Hemen (en kısa sürede)'));
    await t.pumpAndSettle();
    expect(value, isNull);
    expect(find.text('İleri bir saate randevu al'), findsOneWidget);
  });

  testWidgets('rozet Gel Al siparişinde "Teslim alma" yazar', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScheduledOrderBadge(scheduledFor: _trUtc(22, 14), isPickup: true),
      ),
    ));
    expect(find.textContaining('Teslim alma: '), findsOneWidget);
    expect(find.textContaining('14:00'), findsOneWidget);
  });

  group('satıcı randevu ayarları', () {
    testWidgets('admin engellediyse kilitli ve açıklamalı', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SellerScheduledOrdersSection(
              shopData: const {
                'id': 's1',
                'scheduled_orders_enabled': true,
                'scheduled_orders_admin_blocked': true,
              },
              globalEnabledLoader: () async => true,
              onSave: ({
                required bool enabled,
                required int slotMinutes,
                required int maxDays,
                required int minLeadMinutes,
              }) async {},
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text('Yönetim bu mağaza için randevulu siparişi kapattı.'), findsOneWidget);
      final sw = t.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(sw.onChanged, isNull);
    });

    testWidgets('açıp kaydetmek seçilen değerleri gönderir', (t) async {
      Map<String, Object>? saved;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SellerScheduledOrdersSection(
              shopData: const {
                'id': 's1',
                'scheduled_orders_enabled': false,
                'scheduled_slot_minutes': 45, // seçeneklere yuvarlanır
              },
              globalEnabledLoader: () async => true,
              onSave: ({
                required bool enabled,
                required int slotMinutes,
                required int maxDays,
                required int minLeadMinutes,
              }) async {
                saved = {
                  'enabled': enabled,
                  'slot': slotMinutes,
                  'days': maxDays,
                  'lead': minLeadMinutes,
                };
              },
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      expect(find.text('Saat aralığı'), findsOneWidget);
      await t.tap(find.text('Randevu Ayarlarını Kaydet'));
      await t.pumpAndSettle();
      expect(saved, {'enabled': true, 'slot': 30, 'days': 3, 'lead': 60});
    });
  });
}
