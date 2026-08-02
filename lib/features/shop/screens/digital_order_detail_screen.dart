import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/models/digital_order_model.dart';

class DigitalOrderDetailScreen extends StatelessWidget {
  final DigitalOrder order;

  const DigitalOrderDetailScreen({super.key, required this.order});

  Color _statusColor(DigitalOrderStatus status) {
    switch (status) {
      case DigitalOrderStatus.completed:
        return Colors.green;
      case DigitalOrderStatus.inProgress:
      case DigitalOrderStatus.pending:
        return Colors.orange;
      case DigitalOrderStatus.partial:
        return Colors.amber;
      case DigitalOrderStatus.canceled:
      case DigitalOrderStatus.failed:
        return Colors.red;
      case DigitalOrderStatus.refunded:
        return Colors.blueGrey;
    }
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(order.status);
    final showRefund = order.hasRefund;

    return Scaffold(
      appBar: AppBar(title: const Text('Sipariş Detayı')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          order.productName ?? 'Dijital Ürün',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          // ignore: deprecated_member_use
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          order.status.label,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  _row('Link', order.targetUrl),
                  _row('Miktar', order.quantity.toString()),
                  _row('Birim Fiyat', '₺${order.unitPrice.toStringAsFixed(4)}'),
                  _row(
                    'Brüt Tutar',
                    '${order.grossTotalTry.toStringAsFixed(2)} TL',
                  ),
                  _row('Kullanılan Puan', '${order.pointsSpent} puan'),
                  _row(
                    'Puan İndirimi',
                    '${order.pointsDiscountTry.toStringAsFixed(2)} TL',
                  ),
                  _row(
                    'TL Bakiye Ödemesi',
                    '${order.cashBalancePaidTry.toStringAsFixed(2)} TL',
                  ),
                  if (order.externalOrderId != null)
                    _row('Sağlayıcı Sipariş No', order.externalOrderId!),
                  if (order.startCount != null)
                    _row('Başlangıç Sayısı', order.startCount.toString()),
                  if (order.remains != null)
                    _row('Kalan', order.remains.toString()),
                  _row(
                    'Oluşturulma',
                    DateFormat(
                      'dd.MM.yyyy HH:mm',
                    ).format(order.createdAt.toLocal()),
                  ),
                  if (order.lastCheckedAt != null)
                    _row(
                      'Son Kontrol',
                      DateFormat(
                        'dd.MM.yyyy HH:mm',
                      ).format(order.lastCheckedAt!.toLocal()),
                    ),
                  if (order.errorMessage != null)
                    _row('Hata', order.errorMessage!),
                ],
              ),
            ),
          ),
          if (order.reconciliationPending) ...[
            const SizedBox(height: 12),
            Card(
              color: Colors.orange.shade50,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Sağlayıcı sonucu mutabakat bekliyor. Bu durum iade anlamına gelmez; kesin sonuç alınmadan puan veya TL iadesi varsayılmaz.',
                ),
              ),
            ),
          ],
          if (showRefund) ...[
            const SizedBox(height: 12),
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${order.refundCompositionLabel} kendi ödeme kaynağına iade edildi. Puan TL’ye dönüştürülmedi.',
                        style: TextStyle(
                          color: Colors.blue.shade900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
