import 'package:cizreapp/core/models/digital_order_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('server composition snapshot kaynak bazında parse edilir', () {
    final order = DigitalOrder.fromJson({
      'id': 'order-1',
      'user_id': 'user-1',
      'product_id': 'product-1',
      'provider_id': 'provider-1',
      'target_url': 'https://example.com',
      'quantity': 100,
      'unit_price': 0.1,
      'total_price': 10,
      'gross_total_try': 10,
      'points_spent': 250,
      'points_per_try_snapshot': 100,
      'points_discount_try': 2.5,
      'cash_balance_paid_try': 7.5,
      'payment_composition_version': 1,
      'refund_points_total': 50,
      'refund_cash_total_try': 1.5,
      'refund_gross_total_try': 2,
      'reconciliation_status': 'settled',
      'status': 'partial',
      'created_at': '2026-07-30T00:00:00Z',
    });

    expect(order.paymentCompositionLabel, '250 puan + 7.50 TL');
    expect(order.refundCompositionLabel, '50 puan + 1.50 TL');
    expect(order.hasRefund, true);
  });

  test('reconciliation pending iade sayılmaz', () {
    final order = DigitalOrder.fromJson({
      'id': 'order-2',
      'user_id': 'user-1',
      'product_id': 'product-1',
      'provider_id': 'provider-1',
      'target_url': 'https://example.com',
      'quantity': 100,
      'unit_price': 0.1,
      'total_price': 10,
      'gross_total_try': 10,
      'cash_balance_paid_try': 10,
      'reconciliation_status': 'reconciliation_pending',
      'status': 'pending',
      'created_at': '2026-07-30T00:00:00Z',
    });

    expect(order.reconciliationPending, true);
    expect(order.hasRefund, false);
  });
}
