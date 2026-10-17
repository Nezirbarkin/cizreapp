import 'package:cizreapp/core/models/order_model.dart';
import 'package:cizreapp/core/widgets/commission_info_widget.dart';
import 'package:cizreapp/core/widgets/order_return_badge.dart';
import 'package:cizreapp/features/seller/widgets/dashboard/seller_returns_summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sipariş satırı DB'deki calculate_order_commission çıktısıyla aynı alanlar
/// (bkz. supabase/tests/manual/order_money_flow_simulation.sql).
Order _order({
  required bool ownCourier,
  required double deliveryFee,
  required double adminDeliveryFee,
  required double sellerCharge,
  required double net,
  double coupon = 0,
}) =>
    Order.fromJson({
      'id': 'o1',
      'status': 'delivered',
      'payment_method': 'balance',
      'subtotal': 100,
      'delivery_fee': deliveryFee,
      'discount': coupon,
      'total': 100 + deliveryFee - coupon,
      'admin_commission': 10,
      'admin_delivery_fee': adminDeliveryFee,
      'seller_delivery_charge': sellerCharge,
      'seller_net_amount': net,
      'seller_has_own_courier': ownCourier,
      'created_at': '2026-10-16T09:00:00Z',
      'updated_at': '2026-10-16T09:00:00Z',
    });

Future<void> _pump(WidgetTester tester, Order order, {bool isAdmin = false}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CommissionInfoWidget(order: order, isAdmin: isAdmin),
        ),
      ),
    ));

void main() {
  testWidgets('kuryesiz, müşteri teslimatı ödedi: satıcıdan teslimat kesilmez', (tester) async {
    final order = _order(
        ownCourier: false, deliveryFee: 50, adminDeliveryFee: 50, sellerCharge: 0, net: 90);
    expect(order.hasOwnCourier, isFalse);
    expect(order.sellerTotalDeductions, 10);
    await _pump(tester, order);
    expect(find.text('-₺10.00'), findsOneWidget);
    expect(find.text('-₺50.00'), findsNothing);
    expect(find.text('₺90.00'), findsOneWidget);
  });

  testWidgets('kuryesiz, satıcı ücretsiz teslimat verdi: 50 ₺ bedel kesilir', (tester) async {
    final order = _order(
        ownCourier: false, deliveryFee: 0, adminDeliveryFee: 50, sellerCharge: 50, net: 40);
    await _pump(tester, order);
    expect(find.text('Ücretsiz Teslimat Bedeli'), findsOneWidget);
    expect(find.text('-₺50.00'), findsOneWidget);
    expect(find.text('₺40.00'), findsOneWidget);
  });

  testWidgets('kuryesiz, 10 ₺ kupon: kupon satıcının netinden düşer', (tester) async {
    final order = _order(
        ownCourier: false,
        deliveryFee: 50,
        adminDeliveryFee: 50,
        sellerCharge: 0,
        net: 80,
        coupon: 10);
    await _pump(tester, order);
    expect(find.text('Kupon İndirimi'), findsOneWidget);
    expect(find.text('-₺10.00'), findsNWidgets(2)); // komisyon + kupon
    expect(find.text('₺80.00'), findsOneWidget);
  });

  testWidgets('iade durumu: tamamı iade edilen sipariş "İade edildi" rozeti alır', (tester) async {
    final order = Order.fromJson({
      'id': 'o2',
      'status': 'delivered',
      'payment_method': 'balance',
      'subtotal': 8,
      'total': 8,
      'return_status': 'returned',
      'returned_amount': 8,
      'created_at': '2026-10-16T09:00:00Z',
      'updated_at': '2026-10-16T09:00:00Z',
    });
    expect(order.status, OrderStatus.delivered);
    expect(order.isFullyReturned, isTrue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          OrderReturnBadge(returnStatus: order.returnStatus, returnedAmount: order.returnedAmount),
          const OrderReturnBadge(returnStatus: 'approved'),
          const OrderReturnBadge(returnStatus: null),
        ]),
      ),
    ));
    expect(find.text('İade edildi · ₺8.00'), findsOneWidget);
    expect(find.text('İade onaylandı · ürün teslim bekleniyor'), findsOneWidget);
  });

  testWidgets('satıcı Genel Bakış iade kartı sayıları ve tutarları gösterir', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SellerReturnsSummaryCard(
          summaryLoader: () async => {
            'pending': 1,
            'awaiting_receipt': 2,
            'completed': 3,
            'refunded_total': 63,
            'seller_debit_total': 56,
          },
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('İade Edilen Ürünler'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('₺63.00'), findsOneWidget);
    expect(find.text('₺56.00'), findsOneWidget);
    expect(find.textContaining('2 iadede ürünleri teslim alınca'), findsOneWidget);
  });

  testWidgets('kuryeli: teslimat ücreti satıcıya kalır', (tester) async {
    final order = _order(
        ownCourier: true, deliveryFee: 50, adminDeliveryFee: 0, sellerCharge: 0, net: 140);
    await _pump(tester, order);
    expect(find.text('Teslimat Ücreti (size kalır)'), findsOneWidget);
    expect(find.text('+₺50.00'), findsOneWidget);
    expect(find.text('₺140.00'), findsOneWidget);
  });
}
